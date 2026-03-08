from __future__ import annotations

from pathlib import Path

from serving.storage.frame_bundle import normalize_frame_bundle_manifest

def test_normalize_frame_bundle_manifest_rewrites_asset_paths(tmp_path: Path):
    images_dir = tmp_path / "images"
    depth_dir = tmp_path / "depth"
    confidence_dir = tmp_path / "confidence"
    images_dir.mkdir()
    depth_dir.mkdir()
    confidence_dir.mkdir()

    (images_dir / "frame-1.jpg").write_bytes(b"jpg")
    (depth_dir / "frame-1.png").write_bytes(b"png")
    (confidence_dir / "frame-1.png").write_bytes(b"conf")

    manifest = {
        "session_id": "session-1",
        "frames": [
            {
                "frame_id": "frame-1",
                "image_path": "/private/var/mobile/Containers/Data/Application/demo/images/frame-1.jpg",
                "depth_path": "/private/var/mobile/Containers/Data/Application/demo/depth/frame-1.png",
                "confidence_map_path": "/private/var/mobile/Containers/Data/Application/demo/confidence/frame-1.png",
                "cameraTransform16": [0.0] * 15 + [1.0],
                "intrinsics9": [1.0] * 9,
            }
        ],
    }

    normalized = normalize_frame_bundle_manifest(manifest, tmp_path)
    frame = normalized["frames"][0]

    assert frame["image_path"] == "images/frame-1.jpg"
    assert frame["depth_path"] == "depth/frame-1.png"
    assert frame["confidence_map_path"] == "confidence/frame-1.png"
    assert frame["filename"] == "images/frame-1.jpg"
