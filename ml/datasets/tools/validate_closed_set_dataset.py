from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

import yaml

from hacktj2026_ml.paths import ML_ROOT
from hacktj2026_ml.schema_utils import validate_instance


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate the closed-set M1 dataset inputs.")
    parser.add_argument("--frame-records", required=True, help="Path to frame-records json/jsonl.")
    parser.add_argument(
        "--annotations",
        required=True,
        help="Path to detection-annotations json/jsonl.",
    )
    parser.add_argument(
        "--labels-manifest",
        default="datasets/manifests/closed-set-labels.yaml",
        help="Path to the closed-set label manifest.",
    )
    parser.add_argument(
        "--split-manifest",
        default="datasets/manifests/dataset-splits.example.yaml",
        help="Path to the grouped split manifest.",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Optional path for a JSON validation summary.",
    )
    return parser.parse_args()


def resolve_path(raw_path: str | Path) -> Path:
    candidate = Path(raw_path)
    if candidate.is_absolute():
        return candidate
    return (ML_ROOT / candidate).resolve()


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


def validate_records(records: list[dict[str, Any]], schema_name: str, source: Path) -> None:
    errors: list[str] = []
    for index, record in enumerate(records, start=1):
        record_errors = validate_instance(record, schema_name)
        errors.extend(f"{source}:{index}: {error}" for error in record_errors)
    if errors:
        preview = "\n".join(errors[:20])
        raise ValueError(f"Schema validation failed for {source}:\n{preview}")


def load_label_names(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8") as handle:
        manifest = yaml.safe_load(handle) or {}
    labels = manifest.get("labels") or []
    return [item["canonical_label"] for item in labels]


def load_split_manifest(path: Path) -> dict[str, dict[str, set[str]]]:
    with path.open("r", encoding="utf-8") as handle:
        manifest = yaml.safe_load(handle) or {}
    splits = manifest.get("splits") or {}
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
    if split_filters["room_ids"] and frame["room_id"] not in split_filters["room_ids"]:
        return False
    if split_filters["session_ids"] and frame["session_id"] not in split_filters["session_ids"]:
        return False
    if split_filters["frame_ids"] and frame["frame_id"] not in split_filters["frame_ids"]:
        return False
    if split_filters["object_instance_ids"]:
        instance_ids = {annotation["object_instance_id"] for annotation in annotations}
        if not instance_ids.intersection(split_filters["object_instance_ids"]):
            return False
    return True


def main() -> None:
    args = parse_args()
    frame_records_path = resolve_path(args.frame_records)
    annotations_path = resolve_path(args.annotations)
    labels_manifest_path = resolve_path(args.labels_manifest)
    split_manifest_path = resolve_path(args.split_manifest)

    frame_records = load_records(frame_records_path)
    annotations = load_records(annotations_path)
    validate_records(frame_records, "frame-record.schema.json", frame_records_path)
    validate_records(annotations, "detection-annotation.schema.json", annotations_path)

    label_names = set(load_label_names(labels_manifest_path))
    split_manifest = load_split_manifest(split_manifest_path)
    annotations_by_frame: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for annotation in annotations:
        annotations_by_frame[annotation["frame_id"]].append(annotation)
        if annotation["canonical_label"] not in label_names:
            raise ValueError(f"Unknown canonical_label in annotations: {annotation['canonical_label']}")

    split_frames: dict[str, list[dict[str, Any]]] = defaultdict(list)
    duplicate_assignments: dict[str, list[str]] = {}
    for frame in frame_records:
        matching_splits: list[str] = []
        frame_annotations = annotations_by_frame.get(frame["frame_id"], [])
        for split_name, split_filters in split_manifest.items():
            if frame_matches_split(frame, frame_annotations, split_filters):
                matching_splits.append(split_name)
                split_frames[split_name].append(frame)
        if len(matching_splits) > 1:
            duplicate_assignments[frame["frame_id"]] = matching_splits

    if duplicate_assignments:
        raise ValueError(f"Frames assigned to multiple splits: {duplicate_assignments}")

    split_summary = {}
    for split_name in ("train", "val", "test"):
        frames = split_frames.get(split_name, [])
        split_summary[split_name] = {
            "frame_count": len(frames),
            "room_ids": sorted({frame["room_id"] for frame in frames}),
            "session_ids": sorted({frame["session_id"] for frame in frames}),
        }

    present_labels = sorted({annotation["canonical_label"] for annotation in annotations})
    summary = {
        "frame_records_source": frame_records_path.as_posix(),
        "annotations_source": annotations_path.as_posix(),
        "labels_manifest_source": labels_manifest_path.as_posix(),
        "split_manifest_source": split_manifest_path.as_posix(),
        "frame_count": len(frame_records),
        "annotation_count": len(annotations),
        "labels_present": present_labels,
        "labels_missing": sorted(label_names.difference(present_labels)),
        "split_summary": split_summary,
    }

    if args.output:
        output_path = resolve_path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", encoding="utf-8") as handle:
            json.dump(summary, handle, indent=2)
        print(f"Wrote dataset validation summary to {output_path}")
    else:
        print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
