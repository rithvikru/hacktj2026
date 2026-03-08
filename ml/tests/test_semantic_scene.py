from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

from reconstruction.objects.semantic_scene import (
    build_semantic_scene,
    _infer_support_relation,
    _limit_small_object_payloads,
    _snap_payload_to_support,
)


def test_build_semantic_scene_writes_json_and_low_poly_meshes(
    tmp_path: Path,
    monkeypatch,
):
    frame_dir = tmp_path / "frames"
    images_dir = frame_dir / "images"
    depth_dir = frame_dir / "depth"
    confidence_dir = frame_dir / "confidence"
    images_dir.mkdir(parents=True)
    depth_dir.mkdir()
    confidence_dir.mkdir()

    image = np.full((32, 32, 3), 180, dtype=np.uint8)
    depth = np.full((8, 8), 1200, dtype=np.uint16)
    confidence = np.full((8, 8), 2, dtype=np.uint8)

    frames = []
    for index in range(2):
        image_path = images_dir / f"frame-{index}.jpg"
        depth_path = depth_dir / f"frame-{index}.png"
        confidence_path = confidence_dir / f"frame-{index}.png"
        Image.fromarray(image).save(image_path)
        Image.fromarray(depth).save(depth_path)
        Image.fromarray(confidence).save(confidence_path)
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
                    0.0 + (index * 0.03),
                    0.0,
                    0.0,
                    1.0,
                ],
                "intrinsics9": [32.0, 0.0, 0.0, 0.0, 32.0, 0.0, 16.0, 16.0, 1.0],
            }
        )

    class Detection:
        def __init__(self, image_path: Path):
            self.image_path = str(image_path)
            self.bbox_xyxy_norm = [0.25, 0.25, 0.75, 0.75]
            self.confidence = 0.82
            self.label = "phone"

    class Mask:
        def __init__(self):
            self.mask = np.zeros((32, 32), dtype=bool)
            self.mask[8:24, 8:24] = True

    monkeypatch.setattr(
        "reconstruction.objects.semantic_scene.detect",
        lambda image_paths, *args, **kwargs: [Detection(path) for path in image_paths],
    )
    monkeypatch.setattr(
        "reconstruction.objects.semantic_scene.detect_regions",
        lambda image_path, regions, *args, **kwargs: [Detection(image_path)],
    )
    monkeypatch.setattr(
        "reconstruction.objects.semantic_scene.segment",
        lambda image, boxes: [Mask() for _ in boxes],
    )

    output_dir = tmp_path / "reconstruction"
    result = build_semantic_scene(
        room_id="room-1",
        frame_dir=frame_dir,
        frames=frames,
        output_dir=output_dir,
        label_inventory=["phone"],
    )

    scene = result["scene"]
    assert len(scene["objects"]) == 1
    semantic_json = output_dir / "semantic_scene.json"
    assert semantic_json.exists()

    payload = json.loads(semantic_json.read_text())
    assert payload["objects"][0]["label"] == "phone"
    mesh_url = payload["objects"][0]["mesh_asset_url"]
    mesh_name = mesh_url.rsplit("/", 1)[-1]
    assert (output_dir / mesh_name).exists()
    assert payload["objects"][0]["support_relation"]["type"] == "supported_by_floor"
    assert len(result["observations"]) == 1
    observation = result["observations"][0]
    assert observation["support_relation"]["type"] == "supported_by_floor"
    assert observation["base_anchor_xyz"]
    assert observation["center_xyz"]


def test_snap_payload_to_support_places_small_object_on_surface():
    payload = {
        "label": "bottle",
        "center_xyz": [1.0, 1.0, 2.0],
        "extent_xyz": [0.5, 0.5, 0.5],
        "base_anchor_xyz": [1.0, 0.8, 2.0],
        "support_anchor_xyz": [1.0, 0.8, 2.0],
        "yaw_radians": 0.0,
        "world_transform16": [1.0, 0.0, 0.0, 0.0,
                              0.0, 1.0, 0.0, 0.0,
                              0.0, 0.0, 1.0, 0.0,
                              1.0, 1.0, 2.0, 1.0],
        "footprint_xyz": [],
    }
    support_relation = {
        "type": "supported_by",
        "support_object_id": "table-1",
        "support_label": "table",
        "support_height_y": 0.72,
    }

    _snap_payload_to_support(payload, support_relation)

    assert payload["base_anchor_xyz"][1] == 0.72
    assert payload["support_anchor_xyz"][1] == 0.72
    assert payload["center_xyz"][1] > 0.72
    assert np.allclose(payload["extent_xyz"], [0.14, 0.06, 0.14], atol=1e-6)


def test_infer_support_relation_prefers_nearby_desk_for_small_object():
    payload = {
        "id": "object-1",
        "label": "airpods case",
        "base_anchor_xyz": [1.0, 0.36, -0.25],
    }
    surfaces = [
        {
            "id": "shelf-1",
            "label": "shelf",
            "center_xyz": [0.98, 0.78, -0.27],
            "extent_xyz": [0.38, 0.31, 0.15],
            "footprint_xyz": [],
        },
        {
            "id": "desk-1",
            "label": "desk",
            "center_xyz": [1.09, 0.89, -0.29],
            "extent_xyz": [0.28, 0.21, 0.15],
            "footprint_xyz": [],
        },
    ]

    support_relation = _infer_support_relation(payload, surfaces)

    assert support_relation["type"] == "supported_by"
    assert support_relation["support_object_id"] == "desk-1"
    assert support_relation["support_label"] == "desk"


def test_infer_support_relation_uses_support_hint_to_choose_correct_table():
    payload = {
        "id": "object-1",
        "label": "bottle",
        "base_anchor_xyz": [1.1, 0.75, 0.2],
        "support_hint_label": "desk",
        "support_hint_xyz": [1.2, 0.9, 0.25],
    }
    surfaces = [
        {
            "id": "desk-left",
            "label": "desk",
            "center_xyz": [0.3, 0.8, 0.15],
            "extent_xyz": [0.8, 0.1, 0.6],
            "footprint_xyz": [],
        },
        {
            "id": "desk-right",
            "label": "desk",
            "center_xyz": [1.18, 0.8, 0.24],
            "extent_xyz": [0.8, 0.1, 0.6],
            "footprint_xyz": [],
        },
    ]

    support_relation = _infer_support_relation(payload, surfaces)

    assert support_relation["type"] == "supported_by"
    assert support_relation["support_object_id"] == "desk-right"


def test_limit_small_object_payloads_caps_only_portable_objects():
    payloads = [
        {
            "id": "surface-1",
            "label": "desk",
            "confidence": 0.99,
            "supporting_view_count": 4,
            "mask_supported_views": 2,
        }
    ]
    for index in range(12):
        payloads.append(
            {
                "id": f"small-{index}",
                "label": "bottle",
                "confidence": 0.9 - (index * 0.01),
                "supporting_view_count": 3,
                "mask_supported_views": 1,
            }
        )

    limited = _limit_small_object_payloads(payloads)

    assert sum(1 for item in limited if item["label"] == "desk") == 1
    assert sum(1 for item in limited if item["label"] == "bottle") == 10
