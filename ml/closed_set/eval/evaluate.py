from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import torch
from torch.utils.data import DataLoader

ML_ROOT = Path(__file__).resolve().parents[2]
if ML_ROOT.as_posix() not in sys.path:
    sys.path.insert(0, ML_ROOT.as_posix())
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate the M1 closed-set detector checkpoint.")
    parser.add_argument("--config", required=True, help="Path to the training YAML config.")
    parser.add_argument("--checkpoint", required=True, help="Path to the Lightning checkpoint.")
    parser.add_argument(
        "--split",
        choices=("val", "test"),
        default="val",
        help="Which grouped split to evaluate.",
    )
    parser.add_argument(
        "--device",
        default="auto",
        help="Torch device to use: auto, cpu, mps, or cuda.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=None,
        help="Optional batch size override for evaluation.",
    )
    parser.add_argument(
        "--output",
        default="outputs/closed_set/eval/report.json",
        help="Path to the evaluation report JSON.",
    )
    return parser.parse_args()

def resolve_device(device_name: str) -> torch.device:
    normalized = device_name.lower()
    if normalized == "auto":
        if torch.cuda.is_available():
            return torch.device("cuda")
        if torch.backends.mps.is_available():
            return torch.device("mps")
        return torch.device("cpu")
    return torch.device(normalized)

def load_split_samples(bundle: Any, split_name: str) -> list[Any]:
    if split_name == "val":
        return bundle.val_samples
    return bundle.test_samples

def main() -> None:
    args = parse_args()
    from closed_set.training.train import (
        ClosedSetDetectionDataset,
        LightningClosedSetDetector,
        build_dataset_bundle,
        collate_detection_batch,
        compute_detection_metrics,
        load_training_config,
        relative_to_ml_root,
        resolve_path,
    )

    config_path = resolve_path(args.config)
    checkpoint_path = resolve_path(args.checkpoint)
    output_path = resolve_path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    config = load_training_config(config_path)
    bundle = build_dataset_bundle(config, config_path)
    samples = load_split_samples(bundle, args.split)
    if not samples:
        raise ValueError(f"No samples available for split '{args.split}'.")

    dataset = ClosedSetDetectionDataset(
        samples=samples,
        image_size=config.trainer.image_size,
        label_to_index=bundle.label_to_index,
        is_training=False,
        augmentations=config.augmentations,
    )
    data_loader = DataLoader(
        dataset,
        batch_size=args.batch_size or config.trainer.batch_size,
        shuffle=False,
        num_workers=config.trainer.num_workers,
        pin_memory=torch.cuda.is_available(),
        collate_fn=collate_detection_batch,
    )

    device = resolve_device(args.device)
    model = LightningClosedSetDetector.load_from_checkpoint(
        checkpoint_path.as_posix(),
        config=config,
        label_names=bundle.label_names,
        map_location=device,
    )
    model.to(device)
    model.eval()

    predictions: list[dict[str, torch.Tensor]] = []
    targets: list[dict[str, torch.Tensor]] = []
    with torch.no_grad():
        for images, batch_targets in data_loader:
            device_images = [image.to(device) for image in images]
            batch_predictions = model.detector(device_images)
            predictions.extend(
                {
                    "boxes": prediction["boxes"].detach().cpu(),
                    "scores": prediction["scores"].detach().cpu(),
                    "labels": prediction["labels"].detach().cpu(),
                }
                for prediction in batch_predictions
            )
            targets.extend(
                {
                    "boxes": target["boxes"].detach().cpu(),
                    "labels": target["labels"].detach().cpu(),
                }
                for target in batch_targets
            )

    metrics = compute_detection_metrics(
        predictions=predictions,
        targets=targets,
        label_names=bundle.label_names,
        score_threshold=config.thresholds.score_threshold,
        iou_threshold=config.thresholds.iou_match_threshold,
    )
    report = {
        "model_track": "M1",
        "created_at": datetime.now(UTC).isoformat(),
        "config_source": relative_to_ml_root(config_path),
        "checkpoint_source": relative_to_ml_root(checkpoint_path),
        "evaluated_split": args.split,
        "metrics": {
            "map_at_50_macro": metrics["map_at_50_macro"],
            "map_at_50_per_class": metrics["map_at_50_per_class"],
            "recall_at_1_macro": metrics["recall_at_1_macro"],
            "recall_at_1_min": metrics["recall_at_1_min"],
            "recall_at_1_per_class": metrics["recall_at_1_per_class"],
            "fps_end_to_end": None,
        },
        "acceptance_gate": {
            "map_at_50_macro": 0.75,
            "per_class_recall_at_1_min": 0.80,
            "fps_end_to_end": 2.0,
        },
        "gate_status": {
            "map_at_50_pass": metrics["map_at_50_macro"] >= 0.75,
            "per_class_recall_at_1_pass": metrics["recall_at_1_min"] >= 0.80,
            "label_coverage_pass": set(metrics["classes_present_in_validation"])
            == set(bundle.label_names),
            "fps_end_to_end_pass": None,
        },
        "ground_truth_instances_per_class": metrics["ground_truth_instances_per_class"],
        "classes_present_in_split": metrics["classes_present_in_validation"],
        "notes": [
            "This report reuses the exact M1 training dataset loader and metric implementation.",
            "End-to-end iPhone FPS must be measured inside app integration and remains null here.",
        ],
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)

    print(f"Wrote M1 evaluation report to {relative_to_ml_root(output_path)}")

if __name__ == "__main__":
    main()
