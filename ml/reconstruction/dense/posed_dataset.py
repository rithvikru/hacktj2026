from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

from reconstruction.da3.run_pipeline import MAX_RECONSTRUCTION_FRAMES, select_reconstruction_frames


@dataclass(frozen=True)
class DenseDatasetExport:
    dataset_dir: Path
    images_dir: Path
    transforms_json_path: Path
    manifest_path: Path
    selected_frame_ids: list[str]
    frame_count: int


def export_dense_dataset(
    room_id: str,
    frame_dir: Path,
    frames: list[dict],
    reconstruction_dir: Path,
    frame_manifest: dict | None = None,
    max_frames: int | None = None,
) -> DenseDatasetExport:
    """Export a posed-image dense dataset for external splat trainers.

    The output layout is intentionally simple and compatible with common posed-image
    pipelines:
    - dense_dataset/images/*
    - dense_dataset/transforms.json
    - reconstruction/dense_dataset_manifest.json
    """

    resolved_max_frames = _resolve_dense_dataset_max_frames(frame_manifest, max_frames)
    selected = select_reconstruction_frames(frames, frame_dir, max_frames=resolved_max_frames)
    if not selected:
        raise ValueError("No pose-valid frames available for dense dataset export.")

    dataset_dir = reconstruction_dir / "dense_dataset"
    images_dir = dataset_dir / "images"
    images_dir.mkdir(parents=True, exist_ok=True)

    exported_frames: list[dict] = []
    selected_frame_ids: list[str] = []

    for index, candidate in enumerate(selected):
        frame = candidate.frame
        image_path = candidate.image_path
        if not image_path.exists():
            continue

        destination_name = f"{index:04d}-{image_path.name}"
        destination_path = images_dir / destination_name
        _materialize_asset(image_path, destination_path)

        width, height = _read_image_size(image_path)
        intrinsics = np.array(
            frame.get("intrinsics9") or frame.get("intrinsics_9"),
            dtype=np.float32,
        ).reshape(3, 3, order="F")
        transform = np.array(
            frame.get("camera_transform16") or frame.get("cameraTransform16"),
            dtype=np.float32,
        ).reshape(4, 4, order="F")

        frame_id = str(frame.get("frame_id") or frame.get("id") or destination_name)
        selected_frame_ids.append(frame_id)

        exported_frames.append(
            {
                "file_path": f"images/{destination_name}",
                "frame_id": frame_id,
                "transform_matrix": transform.tolist(),
                "fl_x": float(intrinsics[0, 0]),
                "fl_y": float(intrinsics[1, 1]),
                "cx": float(intrinsics[0, 2]),
                "cy": float(intrinsics[1, 2]),
                "w": int(width),
                "h": int(height),
            }
        )

    if not exported_frames:
        raise ValueError("Dense dataset export produced no frames.")

    transforms_payload = {
        "room_id": room_id,
        "scene_type": "indoor_room",
        "coordinate_source": "arkit_camera_to_world",
        "camera_model": "OPENCV",
        "up_axis": "y",
        "capture_profile": (frame_manifest or {}).get("capture_profile", {}),
        "frames": exported_frames,
    }
    transforms_json_path = dataset_dir / "transforms.json"
    transforms_json_path.write_text(
        json.dumps(transforms_payload, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    transforms_json_path.write_text(
        json.dumps(transforms_payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    manifest_payload = {
        "room_id": room_id,
        "dataset_dir": dataset_dir.name,
        "images_dir": f"{dataset_dir.name}/images",
        "transforms_json": f"{dataset_dir.name}/transforms.json",
        "frame_count": len(exported_frames),
        "frame_budget": resolved_max_frames,
        "selected_frame_ids": selected_frame_ids,
        "capture_profile": (frame_manifest or {}).get("capture_profile", {}),
    }
    manifest_path = reconstruction_dir / "dense_dataset_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest_payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    return DenseDatasetExport(
        dataset_dir=dataset_dir,
        images_dir=images_dir,
        transforms_json_path=transforms_json_path,
        manifest_path=manifest_path,
        selected_frame_ids=selected_frame_ids,
        frame_count=len(exported_frames),
    )


def _resolve_dense_dataset_max_frames(
    frame_manifest: dict | None,
    requested_max_frames: int | None,
) -> int:
    if requested_max_frames is not None:
        return max(1, requested_max_frames)

    env_value = os.getenv("DENSE_DATASET_MAX_FRAMES")
    if env_value:
        return max(1, int(env_value))

    capture_profile = (frame_manifest or {}).get("capture_profile", {})
    intended_use = str(capture_profile.get("intended_use") or "").lower()
    target_overlap = str(capture_profile.get("target_overlap") or "").lower()

    if intended_use == "photoreal_dense_reconstruction":
        base_budget = max(96, MAX_RECONSTRUCTION_FRAMES)
        if target_overlap == "high":
            return max(120, base_budget)
        return base_budget

    return max(72, MAX_RECONSTRUCTION_FRAMES)


def _materialize_asset(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        return
    try:
        destination.symlink_to(source.resolve())
    except OSError:
        destination.write_bytes(source.read_bytes())


def _read_image_size(image_path: Path) -> tuple[int, int]:
    with Image.open(image_path) as image:
        return image.size
