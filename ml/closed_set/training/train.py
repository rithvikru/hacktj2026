from __future__ import annotations

import argparse
import json
import random
from collections import defaultdict
from dataclasses import asdict, dataclass, is_dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import lightning as L
import torch
import yaml
from lightning.pytorch.callbacks import LearningRateMonitor, ModelCheckpoint
from lightning.pytorch.loggers import CSVLogger
from PIL import Image, ImageFilter, ImageOps
from torch import Tensor, nn
from torch.utils.data import DataLoader, Dataset
from torchvision.models import MobileNet_V3_Large_Weights, ResNet50_Weights
from torchvision.models.detection import (
    FasterRCNN_MobileNet_V3_Large_FPN_Weights,
    FasterRCNN_ResNet50_FPN_V2_Weights,
    fasterrcnn_mobilenet_v3_large_fpn,
    fasterrcnn_resnet50_fpn_v2,
)
from torchvision.models.detection.faster_rcnn import FastRCNNPredictor
from torchvision.ops import box_iou
from torchvision.transforms import ColorJitter, RandomErasing
from torchvision.transforms.functional import pil_to_tensor

from hacktj2026_ml.contracts import ModelManifest
from hacktj2026_ml.paths import ML_ROOT
from hacktj2026_ml.schema_utils import validate_instance

VISIBLE_DETECTION_STATES = {"fully_visible", "partially_occluded"}

@dataclass(slots=True)
class DatasetConfig:
    frame_records: str
    detection_annotations: str
    image_root: str | None
    include_visibility_states: tuple[str, ...]
    allow_empty_frames: bool
    require_selected_for_training: bool
    require_selected_for_eval: bool

@dataclass(slots=True)
class ModelConfig:
    architecture: str
    weights: str | None
    weights_backbone: str | None
    trainable_backbone_layers: int | None

@dataclass(slots=True)
class OptimizerConfig:
    name: str
    learning_rate: float
    weight_decay: float
    momentum: float

@dataclass(slots=True)
class TrainerConfig:
    seed: int
    image_size: int
    batch_size: int
    num_workers: int
    epochs: int
    accelerator: str
    devices: int | str
    precision: str
    gradient_clip_val: float
    accumulate_grad_batches: int
    log_every_n_steps: int
    num_sanity_val_steps: int

@dataclass(slots=True)
class ScaleJitterConfig:
    enabled: bool
    min_scale: float
    max_scale: float

@dataclass(slots=True)
class AugmentationConfig:
    horizontal_flip_prob: float
    color_jitter_prob: float
    gaussian_blur_prob: float
    random_erasing_prob: float
    scale_jitter: ScaleJitterConfig

@dataclass(slots=True)
class ThresholdConfig:
    score_threshold: float
    nms_threshold: float
    iou_match_threshold: float

@dataclass(slots=True)
class ExportConfig:
    format: str
    precision: str

@dataclass(slots=True)
class TrainingConfig:
    run_name: str
    owner: str
    model_id: str
    model_version: str
    labels_manifest: str
    split_manifest: str
    dataset: DatasetConfig
    model: ModelConfig
    optimizer: OptimizerConfig
    trainer: TrainerConfig
    augmentations: AugmentationConfig
    thresholds: ThresholdConfig
    export: ExportConfig

@dataclass(slots=True)
class FrameSample:
    frame: dict[str, Any]
    annotations: list[dict[str, Any]]
    image_path: Path

@dataclass(slots=True)
class DatasetBundle:
    train_samples: list[FrameSample]
    val_samples: list[FrameSample]
    test_samples: list[FrameSample]
    label_names: list[str]
    label_to_index: dict[str, int]
    frame_source: Path
    annotation_source: Path
    split_source: Path
    labels_source: Path

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train the M1 closed-set detector.")
    parser.add_argument("--config", required=True, help="Path to the training YAML config.")
    parser.add_argument(
        "--output-dir",
        default="outputs/closed_set/train",
        help="Directory where run artifacts should be written.",
    )
    parser.add_argument(
        "--fast-dev-run",
        action="store_true",
        help="Run one train/val batch for smoke testing.",
    )
    parser.add_argument(
        "--limit-train-batches",
        type=float,
        default=1.0,
        help="Lightning limit_train_batches override.",
    )
    parser.add_argument(
        "--limit-val-batches",
        type=float,
        default=1.0,
        help="Lightning limit_val_batches override.",
    )
    return parser.parse_args()

def resolve_path(raw_path: str | Path, *, config_path: Path | None = None) -> Path:
    candidate = Path(raw_path)
    if candidate.is_absolute():
        return candidate
    if config_path is not None:
        config_relative = (config_path.parent / candidate).resolve()
        if config_relative.exists():
            return config_relative
    return (ML_ROOT / candidate).resolve()

def relative_to_ml_root(path: Path) -> str:
    try:
        return path.resolve().relative_to(ML_ROOT.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()

def load_records(path: Path) -> list[dict[str, Any]]:
    if path.suffix in {".jsonl", ".ndjson"}:
        records: list[dict[str, Any]] = []
        with path.open("r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                payload = line.strip()
                if not payload:
                    continue
                try:
                    records.append(json.loads(payload))
                except json.JSONDecodeError as exc:
                    raise ValueError(f"Invalid JSON on line {line_number} in {path}") from exc
        return records

    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)

    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in ("records", "frames", "annotations", "items"):
            value = payload.get(key)
            if isinstance(value, list):
                return value

    raise ValueError(f"Expected list-like JSON payload in {path}")

def validate_records(records: list[dict[str, Any]], schema_name: str, source_path: Path) -> None:
    validation_errors: list[str] = []
    for index, record in enumerate(records, start=1):
        errors = validate_instance(record, schema_name)
        validation_errors.extend(
            f"{source_path}:{index}: {error}"
            for error in errors
        )
    if validation_errors:
        preview = "\n".join(validation_errors[:20])
        raise ValueError(f"Schema validation failed for {source_path}:\n{preview}")

def load_training_config(config_path: Path) -> TrainingConfig:
    with config_path.open("r", encoding="utf-8") as handle:
        raw = yaml.safe_load(handle) or {}

    dataset_raw = raw.get("dataset") or {}
    model_raw = raw.get("model") or {}
    optimizer_raw = raw.get("optimizer") or {}
    trainer_raw = raw.get("trainer") or {}
    augmentations_raw = raw.get("augmentations") or {}
    thresholds_raw = raw.get("thresholds") or {}
    export_raw = raw.get("export") or {}
    scale_jitter_raw = augmentations_raw.get("scale_jitter") or {}

    return TrainingConfig(
        run_name=raw.get("run_name", "m1_closed_set"),
        owner=raw.get("owner", "ai-ml-lead"),
        model_id=raw.get("model_id", "m1.closed_set.detector"),
        model_version=raw.get("model_version", "0.1.0"),
        labels_manifest=raw["labels_manifest"],
        split_manifest=raw["split_manifest"],
        dataset=DatasetConfig(
            frame_records=dataset_raw["frame_records"],
            detection_annotations=dataset_raw["detection_annotations"],
            image_root=dataset_raw.get("image_root"),
            include_visibility_states=tuple(
                dataset_raw.get(
                    "include_visibility_states",
                    sorted(VISIBLE_DETECTION_STATES),
                )
            ),
            allow_empty_frames=bool(dataset_raw.get("allow_empty_frames", True)),
            require_selected_for_training=bool(
                dataset_raw.get("require_selected_for_training", True)
            ),
            require_selected_for_eval=bool(dataset_raw.get("require_selected_for_eval", True)),
        ),
        model=ModelConfig(
            architecture=model_raw.get("architecture", "fasterrcnn_mobilenet_v3_large_fpn"),
            weights=model_raw.get("weights"),
            weights_backbone=model_raw.get("weights_backbone"),
            trainable_backbone_layers=model_raw.get("trainable_backbone_layers"),
        ),
        optimizer=OptimizerConfig(
            name=optimizer_raw.get("name", "adamw"),
            learning_rate=float(optimizer_raw.get("learning_rate", 1.0e-4)),
            weight_decay=float(optimizer_raw.get("weight_decay", 1.0e-4)),
            momentum=float(optimizer_raw.get("momentum", 0.9)),
        ),
        trainer=TrainerConfig(
            seed=int(trainer_raw.get("seed", 2026)),
            image_size=int(trainer_raw.get("image_size", 640)),
            batch_size=int(trainer_raw.get("batch_size", 4)),
            num_workers=int(trainer_raw.get("num_workers", 0)),
            epochs=int(trainer_raw.get("epochs", 20)),
            accelerator=str(trainer_raw.get("accelerator", "auto")),
            devices=trainer_raw.get("devices", 1),
            precision=str(trainer_raw.get("precision", "32-true")),
            gradient_clip_val=float(trainer_raw.get("gradient_clip_val", 1.0)),
            accumulate_grad_batches=int(trainer_raw.get("accumulate_grad_batches", 1)),
            log_every_n_steps=int(trainer_raw.get("log_every_n_steps", 5)),
            num_sanity_val_steps=int(trainer_raw.get("num_sanity_val_steps", 1)),
        ),
        augmentations=AugmentationConfig(
            horizontal_flip_prob=float(augmentations_raw.get("horizontal_flip_prob", 0.5)),
            color_jitter_prob=float(augmentations_raw.get("color_jitter_prob", 0.5)),
            gaussian_blur_prob=float(augmentations_raw.get("gaussian_blur_prob", 0.2)),
            random_erasing_prob=float(augmentations_raw.get("random_erasing_prob", 0.1)),
            scale_jitter=ScaleJitterConfig(
                enabled=bool(scale_jitter_raw.get("enabled", True)),
                min_scale=float(scale_jitter_raw.get("min_scale", 0.85)),
                max_scale=float(scale_jitter_raw.get("max_scale", 1.15)),
            ),
        ),
        thresholds=ThresholdConfig(
            score_threshold=float(thresholds_raw.get("score_threshold", 0.25)),
            nms_threshold=float(thresholds_raw.get("nms_threshold", 0.50)),
            iou_match_threshold=float(thresholds_raw.get("iou_match_threshold", 0.50)),
        ),
        export=ExportConfig(
            format=str(export_raw.get("format", "coreml")),
            precision=str(export_raw.get("precision", "fp16")),
        ),
    )

def load_label_names(labels_manifest_path: Path) -> list[str]:
    with labels_manifest_path.open("r", encoding="utf-8") as handle:
        manifest = yaml.safe_load(handle) or {}
    labels = manifest.get("labels") or []
    label_names = [label["canonical_label"] for label in labels]
    if not label_names:
        raise ValueError(f"No labels found in {labels_manifest_path}")
    return label_names

def load_split_manifest(split_manifest_path: Path) -> dict[str, dict[str, set[str]]]:
    with split_manifest_path.open("r", encoding="utf-8") as handle:
        manifest = yaml.safe_load(handle) or {}
    splits = manifest.get("splits") or {}
    if not splits:
        raise ValueError(f"No split definitions found in {split_manifest_path}")

    parsed: dict[str, dict[str, set[str]]] = {}
    for split_name, split_config in splits.items():
        parsed[split_name] = {
            "room_ids": set(split_config.get("room_ids", [])),
            "session_ids": set(split_config.get("session_ids", [])),
            "object_instance_ids": set(split_config.get("object_instance_ids", [])),
            "frame_ids": set(split_config.get("frame_ids", [])),
        }
    return parsed

def frame_matches_split(
    frame: dict[str, Any],
    annotations: list[dict[str, Any]],
    split_filters: dict[str, set[str]],
) -> bool:
    room_ids = split_filters["room_ids"]
    session_ids = split_filters["session_ids"]
    object_instance_ids = split_filters["object_instance_ids"]
    frame_ids = split_filters["frame_ids"]

    if room_ids and frame["room_id"] not in room_ids:
        return False
    if session_ids and frame["session_id"] not in session_ids:
        return False
    if frame_ids and frame["frame_id"] not in frame_ids:
        return False
    if object_instance_ids:
        annotation_instance_ids = {annotation["object_instance_id"] for annotation in annotations}
        if not annotation_instance_ids.intersection(object_instance_ids):
            return False
    return True

def resolve_image_path(
    image_path: str,
    *,
    image_root: Path | None,
    frame_source: Path,
) -> Path:
    raw_path = Path(image_path)
    if raw_path.is_absolute():
        return raw_path
    if image_root is not None:
        return (image_root / raw_path).resolve()
    source_relative = (frame_source.parent / raw_path).resolve()
    if source_relative.exists():
        return source_relative
    return (ML_ROOT / raw_path).resolve()

def filter_annotations(
    annotations: list[dict[str, Any]],
    *,
    label_to_index: dict[str, int],
    allowed_visibility_states: set[str],
) -> list[dict[str, Any]]:
    filtered: list[dict[str, Any]] = []
    for annotation in annotations:
        if annotation["canonical_label"] not in label_to_index:
            raise ValueError(f"Unknown label in annotation: {annotation['canonical_label']}")
        if annotation["visibility_state"] not in allowed_visibility_states:
            continue
        filtered.append(annotation)
    return filtered

def build_dataset_bundle(config: TrainingConfig, config_path: Path) -> DatasetBundle:
    labels_manifest_path = resolve_path(config.labels_manifest, config_path=config_path)
    split_manifest_path = resolve_path(config.split_manifest, config_path=config_path)
    frame_records_path = resolve_path(config.dataset.frame_records, config_path=config_path)
    detection_annotations_path = resolve_path(
        config.dataset.detection_annotations, config_path=config_path
    )
    image_root = (
        resolve_path(config.dataset.image_root, config_path=config_path)
        if config.dataset.image_root is not None
        else None
    )

    label_names = load_label_names(labels_manifest_path)
    label_to_index = {label_name: index + 1 for index, label_name in enumerate(label_names)}
    split_manifest = load_split_manifest(split_manifest_path)
    frame_records = load_records(frame_records_path)
    detection_annotations = load_records(detection_annotations_path)

    validate_records(frame_records, "frame-record.schema.json", frame_records_path)
    validate_records(
        detection_annotations,
        "detection-annotation.schema.json",
        detection_annotations_path,
    )

    annotations_by_frame: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for annotation in detection_annotations:
        annotations_by_frame[annotation["frame_id"]].append(annotation)

    allowed_visibility_states = set(config.dataset.include_visibility_states)
    split_samples: dict[str, list[FrameSample]] = {"train": [], "val": [], "test": []}

    for frame in frame_records:
        frame_annotations = filter_annotations(
            annotations_by_frame.get(frame["frame_id"], []),
            label_to_index=label_to_index,
            allowed_visibility_states=allowed_visibility_states,
        )
        frame_image_path = resolve_image_path(
            frame["image_path"],
            image_root=image_root,
            frame_source=frame_records_path,
        )
        if not frame_image_path.exists():
            raise FileNotFoundError(f"Image for frame {frame['frame_id']} not found: {frame_image_path}")

        for split_name in ("train", "val", "test"):
            split_filters = split_manifest.get(split_name)
            if not split_filters:
                continue
            if not frame_matches_split(frame, frame_annotations, split_filters):
                continue

            if split_name == "train":
                if config.dataset.require_selected_for_training and not frame["selected_for_training"]:
                    continue
            else:
                if config.dataset.require_selected_for_eval and not frame["selected_for_eval"]:
                    continue

            if not frame_annotations and not config.dataset.allow_empty_frames:
                continue

            split_samples[split_name].append(
                FrameSample(
                    frame=frame,
                    annotations=frame_annotations,
                    image_path=frame_image_path,
                )
            )
            break

    if not split_samples["train"]:
        raise ValueError("No training samples matched the configured dataset and split manifest.")
    if not split_samples["val"]:
        raise ValueError("No validation samples matched the configured dataset and split manifest.")

    return DatasetBundle(
        train_samples=split_samples["train"],
        val_samples=split_samples["val"],
        test_samples=split_samples["test"],
        label_names=label_names,
        label_to_index=label_to_index,
        frame_source=frame_records_path,
        annotation_source=detection_annotations_path,
        split_source=split_manifest_path,
        labels_source=labels_manifest_path,
    )

def clip_boxes(boxes: Tensor, image_size: int) -> Tensor:
    if boxes.numel() == 0:
        return boxes.reshape(0, 4)
    boxes[:, 0::2] = boxes[:, 0::2].clamp(0, image_size)
    boxes[:, 1::2] = boxes[:, 1::2].clamp(0, image_size)
    return boxes

def scale_jitter_image(
    image: Image.Image,
    boxes: Tensor,
    *,
    output_size: int,
    scale_cfg: ScaleJitterConfig,
    rng: random.Random,
) -> tuple[Image.Image, Tensor]:
    if not scale_cfg.enabled or boxes.numel() == 0:
        return image, boxes

    scale = rng.uniform(scale_cfg.min_scale, scale_cfg.max_scale)
    if abs(scale - 1.0) < 1.0e-3:
        return image, boxes

    scaled_size = max(8, int(round(output_size * scale)))
    resized = image.resize((scaled_size, scaled_size), Image.Resampling.BILINEAR)
    boxes = boxes.clone() * scale

    if scaled_size >= output_size:
        max_offset = scaled_size - output_size
        offset_x = rng.randint(0, max_offset) if max_offset else 0
        offset_y = rng.randint(0, max_offset) if max_offset else 0
        image = resized.crop((offset_x, offset_y, offset_x + output_size, offset_y + output_size))
        boxes[:, [0, 2]] -= offset_x
        boxes[:, [1, 3]] -= offset_y
    else:
        max_offset = output_size - scaled_size
        offset_x = rng.randint(0, max_offset) if max_offset else 0
        offset_y = rng.randint(0, max_offset) if max_offset else 0
        canvas = Image.new("RGB", (output_size, output_size), color=(0, 0, 0))
        canvas.paste(resized, (offset_x, offset_y))
        image = canvas
        boxes[:, [0, 2]] += offset_x
        boxes[:, [1, 3]] += offset_y

    return image, clip_boxes(boxes, output_size)

class ClosedSetDetectionDataset(Dataset[tuple[Tensor, dict[str, Tensor]]]):
    def __init__(
        self,
        *,
        samples: list[FrameSample],
        image_size: int,
        label_to_index: dict[str, int],
        is_training: bool,
        augmentations: AugmentationConfig,
    ) -> None:
        self.samples = samples
        self.image_size = image_size
        self.label_to_index = label_to_index
        self.is_training = is_training
        self.augmentations = augmentations
        self.color_jitter = ColorJitter(brightness=0.35, contrast=0.35, saturation=0.15, hue=0.03)
        self.random_erasing = RandomErasing(
            p=self.augmentations.random_erasing_prob,
            scale=(0.02, 0.12),
            ratio=(0.3, 3.3),
            value="random",
        )

    def __len__(self) -> int:
        return len(self.samples)

    def __getitem__(self, index: int) -> tuple[Tensor, dict[str, Tensor]]:
        sample = self.samples[index]
        rng = random
        image = Image.open(sample.image_path).convert("RGB")
        original_width, original_height = image.size
        image = image.resize(
            (self.image_size, self.image_size),
            resample=Image.Resampling.BILINEAR,
        )

        boxes: list[list[float]] = []
        labels: list[int] = []
        for annotation in sample.annotations:
            x0, y0, x1, y1 = annotation["bbox_xyxy_norm"]
            boxes.append(
                [
                    x0 * self.image_size,
                    y0 * self.image_size,
                    x1 * self.image_size,
                    y1 * self.image_size,
                ]
            )
            labels.append(self.label_to_index[annotation["canonical_label"]])

        boxes_tensor = (
            torch.tensor(boxes, dtype=torch.float32)
            if boxes
            else torch.zeros((0, 4), dtype=torch.float32)
        )
        labels_tensor = (
            torch.tensor(labels, dtype=torch.int64)
            if labels
            else torch.zeros((0,), dtype=torch.int64)
        )

        if self.is_training:
            image, boxes_tensor = scale_jitter_image(
                image,
                boxes_tensor,
                output_size=self.image_size,
                scale_cfg=self.augmentations.scale_jitter,
                rng=rng,
            )
            if rng.random() < self.augmentations.horizontal_flip_prob:
                image = ImageOps.mirror(image)
                if boxes_tensor.numel() > 0:
                    x0 = boxes_tensor[:, 0].clone()
                    x1 = boxes_tensor[:, 2].clone()
                    boxes_tensor[:, 0] = self.image_size - x1
                    boxes_tensor[:, 2] = self.image_size - x0
            if rng.random() < self.augmentations.color_jitter_prob:
                image = self.color_jitter(image)
            if rng.random() < self.augmentations.gaussian_blur_prob:
                image = image.filter(ImageFilter.GaussianBlur(radius=rng.uniform(0.5, 1.4)))

        boxes_tensor = clip_boxes(boxes_tensor, self.image_size)
        if boxes_tensor.numel() > 0:
            valid = (boxes_tensor[:, 2] > boxes_tensor[:, 0] + 1.0) & (
                boxes_tensor[:, 3] > boxes_tensor[:, 1] + 1.0
            )
            boxes_tensor = boxes_tensor[valid]
            labels_tensor = labels_tensor[valid]

        image_tensor = pil_to_tensor(image).float().div(255.0)
        if self.is_training:
            image_tensor = self.random_erasing(image_tensor)

        area = (
            (boxes_tensor[:, 2] - boxes_tensor[:, 0]) * (boxes_tensor[:, 3] - boxes_tensor[:, 1])
            if boxes_tensor.numel() > 0
            else torch.zeros((0,), dtype=torch.float32)
        )

        target = {
            "boxes": boxes_tensor,
            "labels": labels_tensor,
            "image_id": torch.tensor([index], dtype=torch.int64),
            "area": area,
            "iscrowd": torch.zeros((boxes_tensor.shape[0],), dtype=torch.int64),
            "orig_size": torch.tensor([original_height, original_width], dtype=torch.int64),
            "size": torch.tensor([self.image_size, self.image_size], dtype=torch.int64),
        }
        return image_tensor, target

def collate_detection_batch(
    batch: list[tuple[Tensor, dict[str, Tensor]]],
) -> tuple[list[Tensor], list[dict[str, Tensor]]]:
    images, targets = zip(*batch, strict=True)
    return list(images), list(targets)

class ClosedSetDataModule(L.LightningDataModule):
    def __init__(self, config: TrainingConfig, bundle: DatasetBundle) -> None:
        super().__init__()
        self.config = config
        self.bundle = bundle
        self.train_dataset: ClosedSetDetectionDataset | None = None
        self.val_dataset: ClosedSetDetectionDataset | None = None

    def setup(self, stage: str | None = None) -> None:
        if stage in (None, "fit"):
            self.train_dataset = ClosedSetDetectionDataset(
                samples=self.bundle.train_samples,
                image_size=self.config.trainer.image_size,
                label_to_index=self.bundle.label_to_index,
                is_training=True,
                augmentations=self.config.augmentations,
            )
            self.val_dataset = ClosedSetDetectionDataset(
                samples=self.bundle.val_samples,
                image_size=self.config.trainer.image_size,
                label_to_index=self.bundle.label_to_index,
                is_training=False,
                augmentations=self.config.augmentations,
            )

    def train_dataloader(self) -> DataLoader:
        if self.train_dataset is None:
            raise RuntimeError("DataModule.setup() must run before requesting train_dataloader().")
        return DataLoader(
            self.train_dataset,
            batch_size=self.config.trainer.batch_size,
            shuffle=True,
            num_workers=self.config.trainer.num_workers,
            pin_memory=torch.cuda.is_available(),
            collate_fn=collate_detection_batch,
        )

    def val_dataloader(self) -> DataLoader:
        if self.val_dataset is None:
            raise RuntimeError("DataModule.setup() must run before requesting val_dataloader().")
        return DataLoader(
            self.val_dataset,
            batch_size=self.config.trainer.batch_size,
            shuffle=False,
            num_workers=self.config.trainer.num_workers,
            pin_memory=torch.cuda.is_available(),
            collate_fn=collate_detection_batch,
        )

def build_detector(model_config: ModelConfig, num_classes: int) -> nn.Module:
    architecture = model_config.architecture
    resolved_weights = resolve_model_weights(architecture, model_config.weights)
    resolved_backbone_weights = resolve_backbone_weights(
        architecture,
        model_config.weights_backbone,
    )
    has_pretrained_weights = (
        resolved_weights is not None or resolved_backbone_weights is not None
    )
    kwargs: dict[str, Any] = {
        "weights": resolved_weights,
        "weights_backbone": resolved_backbone_weights,
    }
    if model_config.trainable_backbone_layers is not None and has_pretrained_weights:
        kwargs["trainable_backbone_layers"] = model_config.trainable_backbone_layers

    if architecture == "fasterrcnn_mobilenet_v3_large_fpn":
        model = fasterrcnn_mobilenet_v3_large_fpn(**kwargs)
    elif architecture == "fasterrcnn_resnet50_fpn_v2":
        model = fasterrcnn_resnet50_fpn_v2(**kwargs)
    else:
        raise ValueError(f"Unsupported M1 detector architecture: {architecture}")

    if not hasattr(model, "roi_heads") or not hasattr(model.roi_heads, "box_predictor"):
        raise TypeError(f"Model {architecture} does not expose a Faster R-CNN predictor head.")

    in_features = model.roi_heads.box_predictor.cls_score.in_features
    model.roi_heads.box_predictor = FastRCNNPredictor(in_features, num_classes)
    return model

def normalize_weight_name(raw_value: str | None) -> str | None:
    if raw_value is None:
        return None
    normalized = str(raw_value).strip()
    if normalized.lower() in {"", "none", "null"}:
        return None
    return normalized

def resolve_model_weights(architecture: str, raw_value: str | None) -> Any:
    normalized = normalize_weight_name(raw_value)
    if normalized is None:
        return None
    if architecture == "fasterrcnn_mobilenet_v3_large_fpn":
        if normalized.upper() == "DEFAULT":
            return FasterRCNN_MobileNet_V3_Large_FPN_Weights.DEFAULT
        return getattr(FasterRCNN_MobileNet_V3_Large_FPN_Weights, normalized)
    if architecture == "fasterrcnn_resnet50_fpn_v2":
        if normalized.upper() == "DEFAULT":
            return FasterRCNN_ResNet50_FPN_V2_Weights.DEFAULT
        return getattr(FasterRCNN_ResNet50_FPN_V2_Weights, normalized)
    return normalized

def resolve_backbone_weights(architecture: str, raw_value: str | None) -> Any:
    normalized = normalize_weight_name(raw_value)
    if normalized is None:
        return None
    if architecture == "fasterrcnn_mobilenet_v3_large_fpn":
        if normalized.upper() == "DEFAULT":
            return MobileNet_V3_Large_Weights.DEFAULT
        return getattr(MobileNet_V3_Large_Weights, normalized)
    if architecture == "fasterrcnn_resnet50_fpn_v2":
        if normalized.upper() == "DEFAULT":
            return ResNet50_Weights.DEFAULT
        return getattr(ResNet50_Weights, normalized)
    return normalized

def compute_average_precision(precision: Tensor, recall: Tensor) -> float:
    if precision.numel() == 0:
        return 0.0
    precision = torch.cat([torch.tensor([0.0]), precision, torch.tensor([0.0])])
    recall = torch.cat([torch.tensor([0.0]), recall, torch.tensor([1.0])])
    for index in range(precision.numel() - 1, 0, -1):
        precision[index - 1] = torch.maximum(precision[index - 1], precision[index])
    changing_points = torch.where(recall[1:] != recall[:-1])[0]
    ap = torch.sum((recall[changing_points + 1] - recall[changing_points]) * precision[changing_points + 1])
    return float(ap.item())

def compute_detection_metrics(
    *,
    predictions: list[dict[str, Tensor]],
    targets: list[dict[str, Tensor]],
    label_names: list[str],
    score_threshold: float,
    iou_threshold: float,
) -> dict[str, Any]:
    gt_by_class_image: dict[int, dict[int, Tensor]] = defaultdict(dict)
    pred_by_class: dict[int, list[dict[str, Tensor | int | float]]] = defaultdict(list)
    recall_hits: dict[int, int] = defaultdict(int)
    recall_denominators: dict[int, int] = defaultdict(int)
    gt_counts: dict[int, int] = defaultdict(int)

    for image_index, (prediction, target) in enumerate(zip(predictions, targets, strict=True)):
        pred_boxes = prediction["boxes"].detach().cpu()
        pred_scores = prediction["scores"].detach().cpu()
        pred_labels = prediction["labels"].detach().cpu()
        target_boxes = target["boxes"].detach().cpu()
        target_labels = target["labels"].detach().cpu()

        keep = pred_scores >= score_threshold
        pred_boxes = pred_boxes[keep]
        pred_scores = pred_scores[keep]
        pred_labels = pred_labels[keep]

        for class_id in range(1, len(label_names) + 1):
            gt_mask = target_labels == class_id
            class_gt_boxes = target_boxes[gt_mask]
            gt_by_class_image[class_id][image_index] = class_gt_boxes
            gt_counts[class_id] += int(class_gt_boxes.shape[0])
            if class_gt_boxes.shape[0] > 0:
                recall_denominators[class_id] += 1

            pred_mask = pred_labels == class_id
            class_pred_boxes = pred_boxes[pred_mask]
            class_pred_scores = pred_scores[pred_mask]
            for box, score in zip(class_pred_boxes, class_pred_scores, strict=True):
                pred_by_class[class_id].append(
                    {"image_index": image_index, "box": box, "score": float(score.item())}
                )

            if class_gt_boxes.shape[0] > 0 and class_pred_boxes.shape[0] > 0:
                top_index = int(torch.argmax(class_pred_scores).item())
                top_box = class_pred_boxes[top_index].unsqueeze(0)
                hit = box_iou(top_box, class_gt_boxes).max().item() >= iou_threshold
                recall_hits[class_id] += int(hit)

    map_per_class: dict[str, float] = {}
    recall_per_class: dict[str, float] = {}
    present_class_ids = [class_id for class_id, count in gt_counts.items() if count > 0]

    for class_id in range(1, len(label_names) + 1):
        class_name = label_names[class_id - 1]
        predictions_for_class = sorted(
            pred_by_class[class_id],
            key=lambda item: item["score"],
            reverse=True,
        )
        gt_images = gt_by_class_image[class_id]
        matched_by_image = {
            image_index: torch.zeros((boxes.shape[0],), dtype=torch.bool)
            for image_index, boxes in gt_images.items()
        }
        true_positives: list[float] = []
        false_positives: list[float] = []

        for prediction in predictions_for_class:
            image_index = int(prediction["image_index"])
            pred_box = prediction["box"]
            gt_boxes = gt_images.get(image_index)
            if gt_boxes is None or gt_boxes.shape[0] == 0:
                true_positives.append(0.0)
                false_positives.append(1.0)
                continue

            ious = box_iou(pred_box.unsqueeze(0), gt_boxes).squeeze(0)
            best_iou, best_index = torch.max(ious, dim=0)
            if best_iou.item() >= iou_threshold and not matched_by_image[image_index][best_index]:
                matched_by_image[image_index][best_index] = True
                true_positives.append(1.0)
                false_positives.append(0.0)
            else:
                true_positives.append(0.0)
                false_positives.append(1.0)

        if gt_counts[class_id] > 0 and true_positives:
            tp = torch.tensor(true_positives).cumsum(0)
            fp = torch.tensor(false_positives).cumsum(0)
            precision = tp / torch.clamp(tp + fp, min=1.0)
            recall = tp / gt_counts[class_id]
            map_per_class[class_name] = compute_average_precision(precision, recall)
        else:
            map_per_class[class_name] = 0.0

        denominator = recall_denominators[class_id]
        recall_per_class[class_name] = (
            recall_hits[class_id] / denominator if denominator > 0 else 0.0
        )

    macro_map50 = (
        sum(map_per_class[label_names[class_id - 1]] for class_id in present_class_ids) / len(present_class_ids)
        if present_class_ids
        else 0.0
    )
    macro_recall_at_1 = (
        sum(recall_per_class[label_names[class_id - 1]] for class_id in present_class_ids)
        / len(present_class_ids)
        if present_class_ids
        else 0.0
    )
    min_recall_at_1 = (
        min(recall_per_class[label_names[class_id - 1]] for class_id in present_class_ids)
        if present_class_ids
        else 0.0
    )

    return {
        "map_at_50_macro": macro_map50,
        "map_at_50_per_class": map_per_class,
        "recall_at_1_macro": macro_recall_at_1,
        "recall_at_1_min": min_recall_at_1,
        "recall_at_1_per_class": recall_per_class,
        "ground_truth_instances_per_class": {
            label_names[class_id - 1]: gt_counts[class_id]
            for class_id in range(1, len(label_names) + 1)
        },
        "classes_present_in_validation": [label_names[class_id - 1] for class_id in present_class_ids],
    }

class LightningClosedSetDetector(L.LightningModule):
    def __init__(
        self,
        *,
        config: TrainingConfig,
        label_names: list[str],
    ) -> None:
        super().__init__()
        self.config = config
        self.label_names = label_names
        self.detector = build_detector(config.model, num_classes=len(label_names) + 1)
        self.validation_predictions: list[dict[str, Tensor]] = []
        self.validation_targets: list[dict[str, Tensor]] = []
        self.latest_validation_metrics: dict[str, Any] = {}
        self.best_validation_metrics: dict[str, Any] = {}
        self.best_map50_macro = 0.0

    def training_step(self, batch: tuple[list[Tensor], list[dict[str, Tensor]]], batch_idx: int) -> Tensor:
        images, targets = batch
        loss_dict = self.detector(images, targets)
        total_loss = sum(loss_dict.values())
        self.log("train_loss", total_loss, prog_bar=True, on_step=True, on_epoch=True, batch_size=len(images))
        for name, value in loss_dict.items():
            self.log(name, value, on_step=True, on_epoch=True, batch_size=len(images))
        return total_loss

    def on_validation_epoch_start(self) -> None:
        self.validation_predictions = []
        self.validation_targets = []

    def validation_step(
        self,
        batch: tuple[list[Tensor], list[dict[str, Tensor]]],
        batch_idx: int,
    ) -> None:
        images, targets = batch
        predictions = self.detector(images)
        self.validation_predictions.extend(
            {
                "boxes": prediction["boxes"].detach().cpu(),
                "scores": prediction["scores"].detach().cpu(),
                "labels": prediction["labels"].detach().cpu(),
            }
            for prediction in predictions
        )
        self.validation_targets.extend(
            {
                "boxes": target["boxes"].detach().cpu(),
                "labels": target["labels"].detach().cpu(),
            }
            for target in targets
        )

    def on_validation_epoch_end(self) -> None:
        metrics = compute_detection_metrics(
            predictions=self.validation_predictions,
            targets=self.validation_targets,
            label_names=self.label_names,
            score_threshold=self.config.thresholds.score_threshold,
            iou_threshold=self.config.thresholds.iou_match_threshold,
        )
        self.latest_validation_metrics = metrics
        if metrics["map_at_50_macro"] >= self.best_map50_macro:
            self.best_map50_macro = metrics["map_at_50_macro"]
            self.best_validation_metrics = metrics

        self.log("val_map50_macro", metrics["map_at_50_macro"], prog_bar=True, sync_dist=False)
        self.log("val_recall_at_1_macro", metrics["recall_at_1_macro"], prog_bar=True, sync_dist=False)
        self.log("val_recall_at_1_min", metrics["recall_at_1_min"], prog_bar=False, sync_dist=False)

    def configure_optimizers(self) -> torch.optim.Optimizer:
        params = [parameter for parameter in self.parameters() if parameter.requires_grad]
        if self.config.optimizer.name.lower() == "sgd":
            return torch.optim.SGD(
                params,
                lr=self.config.optimizer.learning_rate,
                momentum=self.config.optimizer.momentum,
                weight_decay=self.config.optimizer.weight_decay,
            )
        return torch.optim.AdamW(
            params,
            lr=self.config.optimizer.learning_rate,
            weight_decay=self.config.optimizer.weight_decay,
        )

def summarize_samples(
    samples: list[FrameSample],
    *,
    label_names: list[str],
) -> dict[str, Any]:
    per_class_annotations = {label_name: 0 for label_name in label_names}
    room_ids: set[str] = set()
    session_ids: set[str] = set()
    for sample in samples:
        room_ids.add(sample.frame["room_id"])
        session_ids.add(sample.frame["session_id"])
        for annotation in sample.annotations:
            per_class_annotations[annotation["canonical_label"]] += 1
    return {
        "frame_count": len(samples),
        "room_count": len(room_ids),
        "session_count": len(session_ids),
        "empty_frame_count": sum(1 for sample in samples if not sample.annotations),
        "annotation_count": sum(per_class_annotations.values()),
        "annotations_per_class": per_class_annotations,
    }

def write_yaml(path: Path, payload: dict[str, Any]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        yaml.safe_dump(payload, handle, sort_keys=False)

def make_json_serializable(value: Any) -> Any:
    if is_dataclass(value):
        return make_json_serializable(asdict(value))
    if isinstance(value, Path):
        return value.as_posix()
    if isinstance(value, dict):
        return {key: make_json_serializable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [make_json_serializable(item) for item in value]
    if hasattr(value, "__dict__") and not isinstance(value, (str, bytes)):
        return {
            key: make_json_serializable(item)
            for key, item in value.__dict__.items()
        }
    return value

def write_run_artifacts(
    *,
    run_dir: Path,
    config: TrainingConfig,
    bundle: DatasetBundle,
    final_metrics: dict[str, Any],
    best_checkpoint_path: str,
    config_path: Path,
) -> None:
    resolved_config_path = run_dir / "resolved-config.yaml"
    training_manifest_path = run_dir / "training-data-manifest.json"
    eval_report_path = run_dir / "eval-report.json"
    summary_path = run_dir / "summary.json"
    model_manifest_path = run_dir / "model-manifest.yaml"

    write_yaml(
        resolved_config_path,
        make_json_serializable(
            {
                "source_config": relative_to_ml_root(config_path),
                "config": config,
            }
        ),
    )

    training_data_manifest = {
        "model_track": "M1",
        "frame_records_source": relative_to_ml_root(bundle.frame_source),
        "detection_annotations_source": relative_to_ml_root(bundle.annotation_source),
        "split_manifest_source": relative_to_ml_root(bundle.split_source),
        "labels_manifest_source": relative_to_ml_root(bundle.labels_source),
        "splits": {
            "train": summarize_samples(bundle.train_samples, label_names=bundle.label_names),
            "val": summarize_samples(bundle.val_samples, label_names=bundle.label_names),
            "test": summarize_samples(bundle.test_samples, label_names=bundle.label_names),
        },
        "labels": bundle.label_names,
        "visibility_states_used": list(config.dataset.include_visibility_states),
        "notes": [
            "Closed-set M1 training includes only visible annotations.",
            "Empty frames are preserved as hard negatives when configured.",
        ],
    }
    with training_manifest_path.open("w", encoding="utf-8") as handle:
        json.dump(training_data_manifest, handle, indent=2)

    eval_report = {
        "model_track": "M1",
        "created_at": datetime.now(UTC).isoformat(),
        "ground_truth_source": relative_to_ml_root(bundle.split_source),
        "metrics": {
            "map_at_50_macro": final_metrics["map_at_50_macro"],
            "map_at_50_per_class": final_metrics["map_at_50_per_class"],
            "recall_at_1_macro": final_metrics["recall_at_1_macro"],
            "recall_at_1_min": final_metrics["recall_at_1_min"],
            "recall_at_1_per_class": final_metrics["recall_at_1_per_class"],
            "fps_end_to_end": None,
        },
        "acceptance_gate": {
            "map_at_50_macro": 0.75,
            "per_class_recall_at_1_min": 0.80,
            "fps_end_to_end": 2.0,
        },
        "gate_status": {
            "map_at_50_pass": final_metrics["map_at_50_macro"] >= 0.75,
            "per_class_recall_at_1_pass": final_metrics["recall_at_1_min"] >= 0.80,
            "validation_label_coverage_pass": set(final_metrics["classes_present_in_validation"])
            == set(bundle.label_names),
            "fps_end_to_end_pass": None,
        },
        "notes": [
            "The training pipeline computes held-out validation mAP@50 and recall@1.",
            "Gate decisions are only trustworthy when every locked label is present in validation.",
            "End-to-end iPhone FPS must be measured in app integration and is intentionally left null here.",
        ],
    }
    with eval_report_path.open("w", encoding="utf-8") as handle:
        json.dump(eval_report, handle, indent=2)

    manifest = ModelManifest(
        model_id=config.model_id,
        model_family="closed_set_detector",
        version=config.model_version,
        training_data_manifest=relative_to_ml_root(training_manifest_path),
        eval_report_path=relative_to_ml_root(eval_report_path),
        input_contract={"image_size": config.trainer.image_size, "channels": 3},
        output_contract={
            "result_type": "detected",
            "fields": ["label", "score", "bbox_xyxy_norm"],
        },
        thresholds={
            "score_threshold": config.thresholds.score_threshold,
            "nms_threshold": config.thresholds.nms_threshold,
        },
        owner=config.owner,
        created_at=datetime.now(UTC).isoformat(),
    )
    write_yaml(model_manifest_path, manifest.model_dump(mode="json"))

    summary = {
        "run_name": config.run_name,
        "model_id": config.model_id,
        "model_version": config.model_version,
        "best_checkpoint_path": best_checkpoint_path,
        "final_metrics": final_metrics,
        "artifacts": {
            "resolved_config": relative_to_ml_root(resolved_config_path),
            "training_data_manifest": relative_to_ml_root(training_manifest_path),
            "eval_report": relative_to_ml_root(eval_report_path),
            "model_manifest": relative_to_ml_root(model_manifest_path),
        },
    }
    with summary_path.open("w", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2)

def main() -> None:
    args = parse_args()
    config_path = resolve_path(args.config)
    config = load_training_config(config_path)

    if not set(config.dataset.include_visibility_states).issubset(VISIBLE_DETECTION_STATES):
        raise ValueError(
            "M1 is a visible-object detector. include_visibility_states must stay within "
            f"{sorted(VISIBLE_DETECTION_STATES)}."
        )

    L.seed_everything(config.trainer.seed, workers=True)
    bundle = build_dataset_bundle(config, config_path)

    run_id = f"{config.run_name}-{datetime.now(UTC).strftime('%Y%m%dT%H%M%SZ')}"
    run_root = resolve_path(args.output_dir, config_path=config_path)
    run_dir = run_root / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    data_module = ClosedSetDataModule(config, bundle)
    model = LightningClosedSetDetector(config=config, label_names=bundle.label_names)

    checkpoints_dir = run_dir / "checkpoints"
    checkpoint_callback = ModelCheckpoint(
        dirpath=checkpoints_dir,
        filename="m1-{epoch:02d}-{val_map50_macro:.4f}",
        monitor="val_map50_macro",
        mode="max",
        save_top_k=1,
        save_last=True,
    )
    logger = CSVLogger(save_dir=run_dir.as_posix(), name="logs")

    trainer = L.Trainer(
        accelerator=config.trainer.accelerator,
        devices=config.trainer.devices,
        max_epochs=config.trainer.epochs,
        precision=config.trainer.precision,
        gradient_clip_val=config.trainer.gradient_clip_val,
        accumulate_grad_batches=config.trainer.accumulate_grad_batches,
        log_every_n_steps=config.trainer.log_every_n_steps,
        num_sanity_val_steps=config.trainer.num_sanity_val_steps,
        callbacks=[checkpoint_callback, LearningRateMonitor(logging_interval="epoch")],
        logger=logger,
        default_root_dir=run_dir.as_posix(),
        fast_dev_run=args.fast_dev_run,
        limit_train_batches=args.limit_train_batches,
        limit_val_batches=args.limit_val_batches,
    )

    trainer.fit(model=model, datamodule=data_module)
    validation_results = trainer.validate(
        model=model,
        datamodule=data_module,
        ckpt_path="best" if checkpoint_callback.best_model_path else None,
        verbose=False,
    )
    final_metrics = model.latest_validation_metrics or model.best_validation_metrics
    if validation_results:
        final_metrics = {
            **final_metrics,
            "map_at_50_macro": float(validation_results[0]["val_map50_macro"]),
            "recall_at_1_macro": float(validation_results[0]["val_recall_at_1_macro"]),
            "recall_at_1_min": float(validation_results[0]["val_recall_at_1_min"]),
        }

    write_run_artifacts(
        run_dir=run_dir,
        config=config,
        bundle=bundle,
        final_metrics=final_metrics,
        best_checkpoint_path=checkpoint_callback.best_model_path,
        config_path=config_path,
    )

    print(f"Completed M1 training run at {relative_to_ml_root(run_dir)}")
    print(f"Best checkpoint: {checkpoint_callback.best_model_path or 'none'}")
    print(f"Validation mAP@50: {final_metrics['map_at_50_macro']:.4f}")
    print(f"Validation recall@1 macro: {final_metrics['recall_at_1_macro']:.4f}")
    print(f"Validation recall@1 min: {final_metrics['recall_at_1_min']:.4f}")

if __name__ == "__main__":
    main()
