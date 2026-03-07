from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any
from uuid import uuid4

import numpy as np

from hacktj2026_ml.query_contracts import OpenVocabCandidateDTO
from open_vocab.backproject import make_world_transform_16, pixel_to_world


@dataclass(slots=True)
class GroundedObservation:
    detection_idx: int
    image_path: str
    frame_id: str
    label: str
    bbox_xyxy_norm: list[float]
    world_xyz: np.ndarray
    score: float
    stability_score: float
    support_count: int
    mask_ref: str | None
    evidence: list[str]


@dataclass(slots=True)
class FusedCluster:
    observations: list[GroundedObservation]
    center_xyz: np.ndarray
    score: float


def fuse_grounded_detections(
    *,
    detections: list[Any],
    masks_by_detection_idx: dict[int, Any],
    reranked_scores: dict[int, float],
    room: Any,
    images: dict[str, np.ndarray],
    max_candidates: int,
) -> list[OpenVocabCandidateDTO]:
    frame_lookup = _build_frame_lookup(room.frames)
    depth_cache: dict[Path, np.ndarray] = {}
    observations: list[GroundedObservation] = []

    for detection_idx, detection in enumerate(detections):
        frame_meta = _find_frame_meta(frame_lookup, detection.image_path)
        if frame_meta is None:
            continue

        image = images.get(detection.image_path)
        if image is None:
            continue

        mask = masks_by_detection_idx.get(detection_idx)
        grounded = _ground_detection(
            detection_idx=detection_idx,
            detection=detection,
            mask=mask,
            rerank_score=reranked_scores.get(detection_idx),
            frame_meta=frame_meta,
            bundle_dir=room.frame_dir,
            image=image,
            depth_cache=depth_cache,
        )
        if grounded is not None:
            observations.append(grounded)

    if not observations:
        return []

    clusters = cluster_grounded_observations(observations)
    candidates: list[OpenVocabCandidateDTO] = []
    for cluster in clusters[:max_candidates]:
        representative = max(cluster.observations, key=lambda obs: obs.score)
        evidence = sorted({item for obs in cluster.observations for item in obs.evidence})
        evidence.append("multiViewFusion")
        evidence = sorted(set(evidence))
        view_count = len(cluster.observations)
        explanation = (
            f"Fused {view_count} views with mask-aware 3D grounding."
            if view_count > 1
            else "Grounded with mask-aware 3D projection."
        )
        candidates.append(
            OpenVocabCandidateDTO(
                id=str(uuid4()),
                confidence=min(max(cluster.score, 0.0), 1.0),
                bbox_xyxy_norm=representative.bbox_xyxy_norm,
                mask_ref=representative.mask_ref,
                frame_id=representative.frame_id,
                world_transform16=make_world_transform_16(cluster.center_xyz.tolist()),
                evidence=evidence,
                explanation=explanation,
            )
        )

    return candidates


def cluster_grounded_observations(observations: list[GroundedObservation]) -> list[FusedCluster]:
    clusters: list[FusedCluster] = []
    for observation in sorted(observations, key=lambda obs: obs.score, reverse=True):
        matched_cluster = None
        matched_distance = None
        radius = _cluster_radius_for_bbox(observation.bbox_xyxy_norm)

        for cluster in clusters:
            distance = float(np.linalg.norm(observation.world_xyz - cluster.center_xyz))
            cluster_radius = max(
                radius,
                max(_cluster_radius_for_bbox(item.bbox_xyxy_norm) for item in cluster.observations),
            )
            if distance <= cluster_radius and (matched_distance is None or distance < matched_distance):
                matched_cluster = cluster
                matched_distance = distance

        if matched_cluster is None:
            clusters.append(
                FusedCluster(
                    observations=[observation],
                    center_xyz=observation.world_xyz.copy(),
                    score=observation.score,
                )
            )
            continue

        matched_cluster.observations.append(observation)
        matched_cluster.center_xyz = _weighted_center(matched_cluster.observations)
        matched_cluster.score = _cluster_score(matched_cluster.observations)

    clusters.sort(key=lambda cluster: cluster.score, reverse=True)
    return clusters


def robust_depth_from_bbox(depth_map_m: np.ndarray, bbox_xyxy_norm: list[float]) -> tuple[float | None, tuple[float, float]]:
    x1, y1, x2, y2 = bbox_xyxy_norm
    samples = [
        ((x1 + x2) * 0.5, (y1 + y2) * 0.5),
        (x1 + (x2 - x1) * 0.35, y1 + (y2 - y1) * 0.35),
        (x1 + (x2 - x1) * 0.65, y1 + (y2 - y1) * 0.35),
        (x1 + (x2 - x1) * 0.35, y1 + (y2 - y1) * 0.65),
        (x1 + (x2 - x1) * 0.65, y1 + (y2 - y1) * 0.65),
    ]
    values = [
        depth_value_at_uv_norm(depth_map_m, u_norm, v_norm)
        for u_norm, v_norm in samples
    ]
    valid = [value for value in values if value is not None and value > 0]
    if not valid:
        return None, samples[0]
    return float(np.quantile(np.asarray(valid, dtype=np.float32), 0.35)), samples[0]


def robust_depth_from_mask(depth_map_m: np.ndarray, mask: np.ndarray) -> tuple[float | None, tuple[float, float], int]:
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None, (0.5, 0.5), 0

    if len(xs) > 512:
        step = max(1, len(xs) // 512)
        xs = xs[::step]
        ys = ys[::step]

    mask_h, mask_w = mask.shape[:2]
    depth_h, depth_w = depth_map_m.shape[:2]
    depth_xs = np.clip((xs.astype(np.float32) / max(mask_w, 1) * depth_w).astype(int), 0, depth_w - 1)
    depth_ys = np.clip((ys.astype(np.float32) / max(mask_h, 1) * depth_h).astype(int), 0, depth_h - 1)
    values = depth_map_m[depth_ys, depth_xs]
    valid = values[values > 0]
    if valid.size == 0:
        centroid = ((float(xs.mean()) + 0.5) / mask_w, (float(ys.mean()) + 0.5) / mask_h)
        return None, centroid, int(len(xs))

    centroid = ((float(xs.mean()) + 0.5) / mask_w, (float(ys.mean()) + 0.5) / mask_h)
    return float(np.quantile(valid, 0.30)), centroid, int(valid.size)


def depth_value_at_uv_norm(depth_map_m: np.ndarray, u_norm: float, v_norm: float) -> float | None:
    height, width = depth_map_m.shape[:2]
    x = min(max(int(u_norm * width), 0), width - 1)
    y = min(max(int(v_norm * height), 0), height - 1)
    value = float(depth_map_m[y, x])
    return value if value > 0 else None


def _ground_detection(
    *,
    detection_idx: int,
    detection: Any,
    mask: Any,
    rerank_score: float | None,
    frame_meta: dict[str, Any],
    bundle_dir: Path,
    image: np.ndarray,
    depth_cache: dict[Path, np.ndarray],
) -> GroundedObservation | None:
    intrinsics = frame_meta.get("intrinsics9") or frame_meta.get("intrinsics_9") or frame_meta.get("intrinsics")
    extrinsics = (
        frame_meta.get("camera_transform16")
        or frame_meta.get("cameraTransform16")
        or frame_meta.get("cameraPoseTransform")
        or frame_meta.get("extrinsics")
    )
    if not intrinsics or not extrinsics:
        return None

    depth_scalar = frame_meta.get("estimatedDepth") or frame_meta.get("depth")
    depth_map_m = _load_depth_map(bundle_dir, frame_meta, depth_cache)
    support_count = 1
    uv_norm = (
        (detection.bbox_xyxy_norm[0] + detection.bbox_xyxy_norm[2]) * 0.5,
        (detection.bbox_xyxy_norm[1] + detection.bbox_xyxy_norm[3]) * 0.5,
    )

    if depth_map_m is not None:
        if mask is not None and getattr(mask, "mask", None) is not None:
            depth_m, uv_norm, support_count = robust_depth_from_mask(depth_map_m, mask.mask)
        else:
            depth_m, uv_norm = robust_depth_from_bbox(depth_map_m, detection.bbox_xyxy_norm)
            support_count = 5
    else:
        depth_m = float(depth_scalar) if depth_scalar not in (None, "", 0) else None

    if depth_m in (None, "", 0):
        return None

    image_h, image_w = image.shape[:2]
    u = uv_norm[0] * image_w
    v = uv_norm[1] * image_h
    world_xyz = np.asarray(pixel_to_world(u, v, float(depth_m), intrinsics, extrinsics), dtype=np.float32)

    stability_score = float(getattr(mask, "stability_score", 0.5) or 0.5)
    blended_score = max(float(detection.confidence), float(rerank_score or 0.0))
    blended_score *= 0.7 + 0.3 * min(max(stability_score, 0.0), 1.0)
    blended_score *= 0.8 + 0.2 * min(support_count / 32.0, 1.0)

    evidence = ["backendOpenVocab", "groundingDINO"]
    mask_ref = None
    if mask is not None:
        evidence.append("sam2")
        mask_ref = f"sam2:{Path(detection.image_path).name}:{detection_idx}"
    if rerank_score is not None:
        evidence.append("clipReranked")

    return GroundedObservation(
        detection_idx=detection_idx,
        image_path=detection.image_path,
        frame_id=_frame_id(frame_meta, detection.image_path),
        label=detection.label,
        bbox_xyxy_norm=detection.bbox_xyxy_norm,
        world_xyz=world_xyz,
        score=min(max(blended_score, 0.0), 1.0),
        stability_score=stability_score,
        support_count=support_count,
        mask_ref=mask_ref,
        evidence=evidence,
    )


def _build_frame_lookup(frames: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    lookup: dict[str, dict[str, Any]] = {}
    for frame in frames:
        for key in ("image_path", "imagePath", "filename", "image"):
            reference = frame.get(key)
            if not reference:
                continue
            path = Path(str(reference))
            lookup[str(path).replace("\\", "/")] = frame
            lookup[path.name] = frame
    return lookup


def _find_frame_meta(frame_lookup: dict[str, dict[str, Any]], image_path: str) -> dict[str, Any] | None:
    path = Path(image_path)
    return frame_lookup.get(str(path).replace("\\", "/")) or frame_lookup.get(path.name)


def _load_depth_map(
    bundle_dir: Path,
    frame_meta: dict[str, Any],
    depth_cache: dict[Path, np.ndarray],
) -> np.ndarray | None:
    try:
        from PIL import Image
    except ImportError:
        return None

    depth_reference = frame_meta.get("depth_path") or frame_meta.get("depthPath")
    if not depth_reference:
        return None

    depth_path = _resolve_bundle_file(bundle_dir, depth_reference)
    if not depth_path.exists():
        return None
    if depth_path in depth_cache:
        return depth_cache[depth_path]

    depth_arr = np.asarray(Image.open(depth_path), dtype=np.float32)
    if depth_arr.ndim > 2:
        depth_arr = depth_arr[..., 0]
    if depth_path.suffix.lower() == ".png":
        depth_arr = depth_arr / 1000.0
    depth_cache[depth_path] = depth_arr
    return depth_arr


def _resolve_bundle_file(bundle_dir: Path, reference: str) -> Path:
    candidate = Path(reference)
    if candidate.is_absolute():
        return candidate
    direct = bundle_dir / candidate
    if direct.exists():
        return direct
    named = bundle_dir / candidate.name
    if named.exists():
        return named
    return direct


def _frame_id(frame_meta: dict[str, Any], image_path: str) -> str:
    return str(frame_meta.get("frame_id") or frame_meta.get("id") or Path(image_path).name)


def _cluster_radius_for_bbox(bbox_xyxy_norm: list[float]) -> float:
    area = max((bbox_xyxy_norm[2] - bbox_xyxy_norm[0]) * (bbox_xyxy_norm[3] - bbox_xyxy_norm[1]), 0.0)
    if area < 0.01:
        return 0.12
    if area < 0.04:
        return 0.18
    return 0.28


def _weighted_center(observations: list[GroundedObservation]) -> np.ndarray:
    weights = np.asarray([max(obs.score, 1e-3) for obs in observations], dtype=np.float32)
    points = np.stack([obs.world_xyz for obs in observations], axis=0)
    return np.average(points, axis=0, weights=weights)


def _cluster_score(observations: list[GroundedObservation]) -> float:
    scores = np.asarray([obs.score for obs in observations], dtype=np.float32)
    mean_score = float(scores.mean()) if len(scores) else 0.0
    view_bonus = min(0.15, 0.03 * max(len(observations) - 1, 0))
    return min(mean_score + view_bonus, 1.0)
