from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

from reconstruction.dense.posed_dataset import export_dense_dataset


def test_export_dense_dataset_writes_transforms_and_manifest(tmp_path: Path):
    frame_dir = tmp_path / "frames"
    images_dir = frame_dir / "images"
    depth_dir = frame_dir / "depth"
    confidence_dir = frame_dir / "confidence"
    images_dir.mkdir(parents=True)
    depth_dir.mkdir()
    confidence_dir.mkdir()

    frames = []
    for index in range(3):
        image_path = images_dir / f"frame-{index}.jpg"
        depth_path = depth_dir / f"frame-{index}.png"
        confidence_path = confidence_dir / f"frame-{index}.png"
        Image.fromarray(np.full((24, 32, 3), 120 + index, dtype=np.uint8)).save(image_path)
        Image.fromarray(np.full((8, 8), 1600, dtype=np.uint16)).save(depth_path)
        Image.fromarray(np.full((8, 8), 2, dtype=np.uint8)).save(confidence_path)
        frames.append(
            {
                "frame_id": f"frame-{index}",
                "image_path": f"images/frame-{index}.jpg",
                "depth_path": f"depth/frame-{index}.png",
                "confidence_map_path": f"confidence/frame-{index}.png",
                "camera_transform16": [
                    1.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    1.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    1.0,
                    0.0,
                    float(index) * 0.15,
                    0.0,
                    0.0,
                    1.0,
                ],
                "intrinsics9": [120.0, 0.0, 0.0, 0.0, 120.0, 0.0, 16.0, 12.0, 1.0],
            }
        )

    reconstruction_dir = tmp_path / "reconstruction"
    export = export_dense_dataset(
        room_id="room-1",
        frame_dir=frame_dir,
        frames=frames,
        reconstruction_dir=reconstruction_dir,
        frame_manifest={
            "capture_profile": {
                "profile_id": "dense_room_twin_v1",
                "intended_use": "photoreal_dense_reconstruction",
            }
        },
        max_frames=2,
    )

    assert export.frame_count == 2
    assert export.transforms_json_path.exists()
    assert export.manifest_path.exists()

    transforms_payload = json.loads(export.transforms_json_path.read_text())
    assert transforms_payload["capture_profile"]["profile_id"] == "dense_room_twin_v1"
    assert len(transforms_payload["frames"]) == 2

    manifest_payload = json.loads(export.manifest_path.read_text())
    assert manifest_payload["frame_count"] == 2
    assert manifest_payload["capture_profile"]["intended_use"] == "photoreal_dense_reconstruction"
