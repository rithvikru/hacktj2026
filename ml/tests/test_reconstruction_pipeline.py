from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

from reconstruction.da3.run_pipeline import estimate_depth, select_reconstruction_frames
from reconstruction.pointcloud.generate import generate_pointcloud


def test_estimate_depth_prefers_arkit_depth_without_loading_model(
    tmp_path: Path,
    monkeypatch,
):
    images_dir = tmp_path / "images"
    depth_dir = tmp_path / "depth"
    confidence_dir = tmp_path / "confidence"
    images_dir.mkdir()
    depth_dir.mkdir()
    confidence_dir.mkdir()

    image_path = images_dir / "frame-1.jpg"
    Image.fromarray(np.full((12, 12, 3), 127, dtype=np.uint8)).save(image_path)

    depth_path = depth_dir / "frame-1.png"
    Image.fromarray(np.full((12, 12), 1500, dtype=np.uint16)).save(depth_path)

    confidence_path = confidence_dir / "frame-1.png"
    Image.fromarray(np.full((12, 12), 2, dtype=np.uint8)).save(confidence_path)

    frame = {
        "frame_id": "frame-1",
        "image_path": "images/frame-1.jpg",
        "depth_path": "depth/frame-1.png",
        "confidence_map_path": "confidence/frame-1.png",
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
            0.0,
            0.0,
            0.0,
            1.0,
        ],
        "intrinsics9": [100.0, 0.0, 0.0, 0.0, 100.0, 0.0, 6.0, 6.0, 1.0],
    }

    def _unexpected_pipeline_load():
        raise AssertionError("Monocular depth pipeline should not load when ARKit depth exists")

    monkeypatch.setattr(
        "reconstruction.da3.run_pipeline._load_pipeline",
        _unexpected_pipeline_load,
    )

    results = estimate_depth([frame], tmp_path, max_frames=8)

    assert len(results) == 1
    assert results[0].source == "arkit"
    assert results[0].frame_id == "frame-1"
    assert results[0].confidence_map is not None
    assert np.isclose(results[0].depth_map.mean(), 1.5)


def test_select_reconstruction_frames_limits_to_pose_diverse_subset(tmp_path: Path):
    images_dir = tmp_path / "images"
    depth_dir = tmp_path / "depth"
    confidence_dir = tmp_path / "confidence"
    images_dir.mkdir()
    depth_dir.mkdir()
    confidence_dir.mkdir()

    frames = []
    for index in range(6):
        image_path = images_dir / f"frame-{index}.jpg"
        Image.fromarray(np.full((12, 12, 3), 50 + index, dtype=np.uint8)).save(image_path)
        depth_path = depth_dir / f"frame-{index}.png"
        Image.fromarray(np.full((12, 12), 1200 + (index * 10), dtype=np.uint16)).save(depth_path)
        confidence_path = confidence_dir / f"frame-{index}.png"
        Image.fromarray(np.full((12, 12), 2, dtype=np.uint8)).save(confidence_path)
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
                    float(index) * 0.2,
                    0.0,
                    0.0,
                    1.0,
                ],
                "intrinsics9": [100.0, 0.0, 0.0, 0.0, 100.0, 0.0, 6.0, 6.0, 1.0],
            }
        )

    selected = select_reconstruction_frames(frames, tmp_path, max_frames=3)

    assert len(selected) == 3
    assert [candidate.frame_index for candidate in selected] == sorted(
        candidate.frame_index for candidate in selected
    )
    assert all(candidate.depth_path is not None for candidate in selected)


def test_generate_pointcloud_scales_intrinsics_to_depth_resolution_and_filters_confidence():
    depth_result = type(
        "DepthResultStub",
        (),
        {
            "image_path": "ignored.jpg",
            "depth_map": np.array([[1.0, 1.0], [1.0, 1.0]], dtype=np.float32),
            "confidence_map": np.array([[0, 0], [0, 2]], dtype=np.uint8),
            "original_size": (6, 4),
            "frame_id": "frame-1",
        },
    )()

    frame_metadata = [
        {
            "frame_id": "frame-1",
            "image_path": "ignored.jpg",
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
                0.0,
                0.0,
                0.0,
                1.0,
            ],
            "intrinsics9": [6.0, 0.0, 0.0, 0.0, 4.0, 0.0, 3.0, 2.0, 1.0],
        }
    ]

    original_open = Image.open

    def _fake_open(path):
        if str(path) == "ignored.jpg":
            return Image.fromarray(np.full((4, 6, 3), 200, dtype=np.uint8))
        return original_open(path)

    pointcloud = None
    try:
        Image.open = _fake_open
        pointcloud = generate_pointcloud(
            [depth_result],
            frame_metadata,
            Path("."),
            max_points_per_frame=100,
        )
    finally:
        Image.open = original_open

    assert pointcloud is not None
    assert pointcloud.points.shape == (1, 3)
    np.testing.assert_allclose(pointcloud.points[0], np.array([0.0, 0.0, 1.0]), atol=1e-5)
