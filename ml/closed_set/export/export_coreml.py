from __future__ import annotations

import argparse
import json
import sys
from collections import OrderedDict
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import torch
from torchvision.models.detection.image_list import ImageList

ML_ROOT = Path(__file__).resolve().parents[2]
if ML_ROOT.as_posix() not in sys.path:
    sys.path.insert(0, ML_ROOT.as_posix())

class CoreMLExportWrapper(torch.nn.Module):
    def __init__(self, detector: torch.nn.Module, image_size: int, top_k: int) -> None:
        super().__init__()
        self.backbone = detector.backbone
        self.rpn = detector.rpn
        self.roi_heads = detector.roi_heads
        self.image_size = float(image_size)
        self.top_k = top_k
        self.register_buffer(
            "image_mean",
            torch.tensor(detector.transform.image_mean, dtype=torch.float32).view(1, -1, 1, 1),
        )
        self.register_buffer(
            "image_std",
            torch.tensor(detector.transform.image_std, dtype=torch.float32).view(1, -1, 1, 1),
        )

    def forward(self, image: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        normalized = (image - self.image_mean) / self.image_std
        height = int(normalized.shape[-2])
        width = int(normalized.shape[-1])
        images = ImageList(normalized, [(height, width)])
        features = self.backbone(images.tensors)
        if isinstance(features, torch.Tensor):
            features = OrderedDict([("0", features)])
        proposals, _ = self.rpn(images, features, None)
        predictions, _ = self.roi_heads(features, proposals, images.image_sizes, None)
        predictions = predictions[0]
        scores = predictions["scores"][: self.top_k]
        labels = predictions["labels"][: self.top_k].to(torch.int32)
        boxes = predictions["boxes"][: self.top_k] / self.image_size

        padded_scores = torch.zeros(self.top_k, dtype=scores.dtype, device=scores.device)
        padded_labels = torch.zeros(self.top_k, dtype=labels.dtype, device=labels.device)
        padded_boxes = torch.zeros((self.top_k, 4), dtype=boxes.dtype, device=boxes.device)

        num_detections = scores.size(0)
        padded_scores[:num_detections] = scores
        padded_labels[:num_detections] = labels
        padded_boxes[:num_detections] = boxes
        return padded_scores, padded_labels, padded_boxes

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export the trained M1 checkpoint to Core ML.")
    parser.add_argument("--config", required=True, help="Path to the training YAML config.")
    parser.add_argument("--checkpoint", required=True, help="Path to the Lightning checkpoint.")
    parser.add_argument(
        "--output-dir",
        default="outputs/closed_set/export",
        help="Directory where the exported mlpackage and sidecars should be written.",
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=20,
        help="Maximum number of detections returned by the exported model.",
    )
    parser.add_argument(
        "--deployment-target",
        default="iOS17",
        help="Core ML deployment target, for example iOS17 or iOS18.",
    )
    return parser.parse_args()

def load_coremltools() -> Any:
    try:
        import coremltools as ct
    except ImportError as exc:
        raise RuntimeError(
            "coremltools is required for export. Run `uv sync --group export` first."
        ) from exc
    return ct

def resolve_precision(ct: Any, precision_name: str) -> Any:
    normalized = precision_name.lower()
    if normalized == "fp16":
        return ct.precision.FLOAT16
    if normalized in {"fp32", "float32"}:
        return ct.precision.FLOAT32
    raise ValueError(f"Unsupported Core ML precision setting: {precision_name}")

def resolve_deployment_target(ct: Any, target_name: str) -> Any:
    try:
        return getattr(ct.target, target_name)
    except AttributeError as exc:
        raise ValueError(f"Unsupported Core ML deployment target: {target_name}") from exc

def main() -> None:
    args = parse_args()
    from closed_set.training.train import (
        LightningClosedSetDetector,
        load_label_names,
        load_training_config,
        relative_to_ml_root,
        resolve_path,
    )

    ct = load_coremltools()

    config_path = resolve_path(args.config)
    checkpoint_path = resolve_path(args.checkpoint)
    output_dir = resolve_path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    config = load_training_config(config_path)
    labels_manifest_path = resolve_path(config.labels_manifest, config_path=config_path)
    label_names = load_label_names(labels_manifest_path)

    model = LightningClosedSetDetector.load_from_checkpoint(
        checkpoint_path.as_posix(),
        config=config,
        label_names=label_names,
        map_location="cpu",
    )
    model.eval()

    wrapper = CoreMLExportWrapper(
        detector=model.detector,
        image_size=config.trainer.image_size,
        top_k=args.top_k,
    ).cpu()
    wrapper.eval()

    example_input = torch.rand(1, 3, config.trainer.image_size, config.trainer.image_size)
    traced = torch.jit.trace(wrapper, example_input, strict=False)
    traced_path = output_dir / f"{config.model_id.replace('.', '_')}-{config.model_version}.pt"
    torch.jit.save(traced, traced_path.as_posix())

    try:
        coreml_model = ct.convert(
            traced,
            convert_to="mlprogram",
            inputs=[
                ct.ImageType(
                    name="image",
                    shape=example_input.shape,
                    scale=1.0 / 255.0,
                    bias=[0.0, 0.0, 0.0],
                    color_layout=ct.colorlayout.RGB,
                )
            ],
            outputs=[
                ct.TensorType(name="scores"),
                ct.TensorType(name="labels"),
                ct.TensorType(name="bbox_xyxy_norm"),
            ],
            minimum_deployment_target=resolve_deployment_target(ct, args.deployment_target),
            compute_precision=resolve_precision(ct, config.export.precision),
        )
    except Exception as exc:
        failure_report = {
            "model_track": "M1",
            "created_at": datetime.now(UTC).isoformat(),
            "source_checkpoint": relative_to_ml_root(checkpoint_path),
            "source_config": relative_to_ml_root(config_path),
            "traced_torchscript_path": relative_to_ml_root(traced_path),
            "coreml_conversion_status": "failed",
            "error_type": type(exc).__name__,
            "error_message": str(exc),
            "notes": [
                "Torchvision detection graphs may still fail Core ML conversion because of unsupported integer ops in the proposal or post-processing stack.",
                "Use the Create ML baseline for the guaranteed Apple-native artifact path, or switch M1 to a conversion-friendly detector family before export.",
                "Threshold configuration remains external to model weights and is preserved in the training config.",
            ],
        }
        failure_path = output_dir / f"{config.model_id.replace('.', '_')}-{config.model_version}-export-failure.json"
        with failure_path.open("w", encoding="utf-8") as handle:
            json.dump(failure_report, handle, indent=2)
        raise RuntimeError(
            f"Core ML export failed. Wrote failure report to {relative_to_ml_root(failure_path)}"
        ) from exc

    model_filename = f"{config.model_id.replace('.', '_')}-{config.model_version}.mlpackage"
    model_path = output_dir / model_filename
    coreml_model.short_description = "Closed-set M1 detector for on-device room search."
    coreml_model.author = config.owner
    coreml_model.version = config.model_version
    coreml_model.license = "Internal use only"
    coreml_model.user_defined_metadata.update(
        {
            "model_id": config.model_id,
            "model_version": config.model_version,
            "label_names": json.dumps(label_names),
            "score_threshold": str(config.thresholds.score_threshold),
            "nms_threshold": str(config.thresholds.nms_threshold),
            "top_k": str(args.top_k),
        }
    )
    coreml_model.save(model_path.as_posix())

    sidecar = {
        "model_track": "M1",
        "created_at": datetime.now(UTC).isoformat(),
        "source_checkpoint": relative_to_ml_root(checkpoint_path),
        "source_config": relative_to_ml_root(config_path),
        "traced_torchscript_path": relative_to_ml_root(traced_path),
        "coreml_model_path": relative_to_ml_root(model_path),
        "input_name": "image",
        "output_names": ["scores", "labels", "bbox_xyxy_norm"],
        "top_k": args.top_k,
        "label_names": label_names,
        "thresholds": {
            "score_threshold": config.thresholds.score_threshold,
            "nms_threshold": config.thresholds.nms_threshold,
        },
        "notes": [
            "Threshold config is intentionally preserved outside the model weights for deterministic app-side post-processing.",
            "The exported Core ML artifact returns fixed top-k tensors suitable for app-side decoding.",
        ],
    }
    sidecar_path = output_dir / f"{config.model_id.replace('.', '_')}-{config.model_version}.json"
    with sidecar_path.open("w", encoding="utf-8") as handle:
        json.dump(sidecar, handle, indent=2)

    print(f"Wrote Core ML artifact to {relative_to_ml_root(model_path)}")
    print(f"Wrote export metadata to {relative_to_ml_root(sidecar_path)}")

if __name__ == "__main__":
    main()
