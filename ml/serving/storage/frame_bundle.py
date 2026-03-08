from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_IMAGE_KEYS = ("image_path", "imagePath", "image", "filename")
_DEPTH_KEYS = ("depth_path", "depthPath")
_CONFIDENCE_KEYS = ("confidence_map_path", "confidenceMapPath")
_TRANSFORM_KEYS = ("camera_transform16", "cameraTransform16", "cameraPoseTransform", "extrinsics")
_INTRINSICS_KEYS = ("intrinsics9", "intrinsics_9")

def load_manifest(manifest_path: Path) -> dict[str, Any]:
    with manifest_path.open("r", encoding="utf-8") as handle:
        return json.load(handle)

def write_manifest(manifest_path: Path, manifest: dict[str, Any]) -> None:
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with manifest_path.open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")

def normalize_frame_bundle_manifest(manifest: dict[str, Any], bundle_dir: Path) -> dict[str, Any]:
    normalized = dict(manifest)
    frames = [normalize_frame_record(frame, bundle_dir) for frame in manifest.get("frames", [])]
    normalized["frames"] = frames
    normalized.setdefault("frame_count", len(frames))
    return normalized

def normalize_frame_record(frame: dict[str, Any], bundle_dir: Path) -> dict[str, Any]:
    normalized = dict(frame)

    image_path = _normalize_asset_reference(normalized, bundle_dir, _IMAGE_KEYS, "images")
    if image_path:
        normalized["image_path"] = image_path
        normalized["imagePath"] = image_path
        normalized["image"] = image_path
        normalized["filename"] = image_path

    depth_path = _normalize_asset_reference(normalized, bundle_dir, _DEPTH_KEYS, "depth")
    if depth_path:
        normalized["depth_path"] = depth_path
        normalized["depthPath"] = depth_path

    confidence_path = _normalize_asset_reference(normalized, bundle_dir, _CONFIDENCE_KEYS, "confidence")
    if confidence_path:
        normalized["confidence_map_path"] = confidence_path
        normalized["confidenceMapPath"] = confidence_path

    transform = _first_present(normalized, _TRANSFORM_KEYS)
    if transform is not None:
        normalized["camera_transform16"] = transform
        normalized["cameraTransform16"] = transform
        normalized.setdefault("extrinsics", transform)

    intrinsics = _first_present(normalized, _INTRINSICS_KEYS)
    if intrinsics is not None:
        normalized["intrinsics9"] = intrinsics
        normalized["intrinsics_9"] = intrinsics

    frame_id = normalized.get("frame_id") or normalized.get("id")
    if frame_id is not None:
        normalized["frame_id"] = frame_id
        normalized["id"] = frame_id

    return normalized

def extract_frame_records(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    return [dict(frame) for frame in manifest.get("frames", [])]

def _normalize_asset_reference(
    frame: dict[str, Any],
    bundle_dir: Path,
    keys: tuple[str, ...],
    folder_name: str,
) -> str | None:
    reference = _first_present(frame, keys)
    if reference is None:
        return None

    raw_path = Path(str(reference))
    candidates = []

    if not raw_path.is_absolute():
        candidates.append(bundle_dir / raw_path)
    candidates.append(bundle_dir / folder_name / raw_path.name)
    candidates.append(bundle_dir / raw_path.name)

    for candidate in candidates:
        if candidate.exists():
            return candidate.relative_to(bundle_dir).as_posix()

    if raw_path.name:
        return f"{folder_name}/{raw_path.name}"
    return None

def _first_present(payload: dict[str, Any], keys: tuple[str, ...]) -> Any:
    for key in keys:
        if key in payload and payload[key] not in (None, ""):
            return payload[key]
    return None
