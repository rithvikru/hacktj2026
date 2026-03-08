from __future__ import annotations

import json
import logging
import math
import os
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from uuid import uuid4

import numpy as np
from PIL import Image

from open_vocab.grounding_dino.run_grounding import detect, detect_regions
from open_vocab.sam2.run_segmentation import segment
from reconstruction.da3.run_pipeline import (
    MAX_DEPTH_METERS,
    MIN_DEPTH_METERS,
    MIN_DEPTH_CONFIDENCE,
    ReconstructionFrame,
    select_reconstruction_frames,
)

logger = logging.getLogger(__name__)

SEMANTIC_OBJECT_FRAME_LIMIT = int(os.getenv("SEMANTIC_OBJECT_FRAME_LIMIT", "12"))
SEMANTIC_MAX_DETECTIONS_PER_FRAME = int(os.getenv("SEMANTIC_MAX_DETECTIONS_PER_FRAME", "8"))
SEMANTIC_MAX_POINTS_PER_OBJECT_VIEW = int(os.getenv("SEMANTIC_MAX_POINTS_PER_OBJECT_VIEW", "1400"))
SEMANTIC_CLUSTER_RADIUS_METERS = float(os.getenv("SEMANTIC_CLUSTER_RADIUS_METERS", "0.28"))
SEMANTIC_SMALL_OBJECT_CLUSTER_RADIUS_METERS = float(
    os.getenv("SEMANTIC_SMALL_OBJECT_CLUSTER_RADIUS_METERS", "0.20")
)
SEMANTIC_SMALL_OBJECT_BOX_THRESHOLD = float(
    os.getenv("SEMANTIC_SMALL_OBJECT_BOX_THRESHOLD", "0.10")
)
SEMANTIC_SMALL_OBJECT_TEXT_THRESHOLD = float(
    os.getenv("SEMANTIC_SMALL_OBJECT_TEXT_THRESHOLD", "0.12")
)
SEMANTIC_SURFACE_BOX_THRESHOLD = float(
    os.getenv("SEMANTIC_SURFACE_BOX_THRESHOLD", "0.22")
)
SEMANTIC_SURFACE_TEXT_THRESHOLD = float(
    os.getenv("SEMANTIC_SURFACE_TEXT_THRESHOLD", "0.18")
)
SEMANTIC_REGION_PADDING_X = float(os.getenv("SEMANTIC_REGION_PADDING_X", "0.10"))
SEMANTIC_REGION_PADDING_Y = float(os.getenv("SEMANTIC_REGION_PADDING_Y", "0.14"))
SMALL_OBJECT_MARKER_EXTENT = np.array([0.14, 0.06, 0.14], dtype=np.float32)

SUPPORT_SURFACE_LABELS = {
    "table",
    "desk",
    "counter",
    "shelf",
    "nightstand",
    "dresser",
    "bed",
    "couch",
}

SMALL_OBJECT_LABELS = [
    "laptop",
    "keyboard",
    "mouse",
    "phone",
    "airpods case",
    "wallet",
    "keys",
    "glasses",
    "charger",
    "tv remote",
    "backpack",
    "book",
    "notebook",
    "bottle",
    "can",
    "mug",
    "bowl",
    "plate",
    "shoe",
    "lamp",
    "speaker",
    "monitor",
]

HIGH_PRIORITY_SMALL_OBJECT_LABELS = [
    "laptop",
    "phone",
    "airpods case",
    "wallet",
    "keys",
    "glasses",
    "charger",
    "tv remote",
    "backpack",
    "book",
    "notebook",
    "bottle",
    "can",
    "mug",
]

DEFAULT_SEMANTIC_LABELS = list(SUPPORT_SURFACE_LABELS) + SMALL_OBJECT_LABELS
SURFACE_LABELS = set(SUPPORT_SURFACE_LABELS)

@dataclass(slots=True)
class ObjectView:
    label: str
    score: float
    frame_id: str
    image_path: str
    bbox_xyxy_norm: list[float]
    mask_available: bool
    points_xyz: np.ndarray
    colors_rgb: np.ndarray
    center_xyz: np.ndarray
    support_anchor_xyz: np.ndarray

@dataclass(slots=True)
class ObjectCluster:
    label: str
    views: list[ObjectView] = field(default_factory=list)
    points_xyz: list[np.ndarray] = field(default_factory=list)
    colors_rgb: list[np.ndarray] = field(default_factory=list)

    @property
    def center_xyz(self) -> np.ndarray:
        if not self.points_xyz:
            return np.zeros(3, dtype=np.float32)
        all_points = np.concatenate(self.points_xyz, axis=0)
        return np.median(all_points, axis=0).astype(np.float32)

def build_semantic_scene(
    *,
    room_id: str,
    frame_dir: Path,
    frames: list[dict[str, Any]],
    output_dir: Path,
    label_inventory: list[str] | None = None,
) -> dict[str, Any]:
    selected_frames = select_reconstruction_frames(
        frames,
        frame_dir,
        max_frames=SEMANTIC_OBJECT_FRAME_LIMIT,
    )
    if not selected_frames:
        return {
            "room_id": room_id,
            "scene_version": 1,
            "generated_at": _now_iso(),
            "objects": [],
        }

    labels = label_inventory or list(DEFAULT_SEMANTIC_LABELS)
    surface_labels = [label for label in labels if label in SURFACE_LABELS]
    small_object_labels = [label for label in labels if label in SMALL_OBJECT_LABELS]

    surface_views = _extract_object_views(
        selected_frames,
        surface_labels,
        box_threshold=SEMANTIC_SURFACE_BOX_THRESHOLD,
        text_threshold=SEMANTIC_SURFACE_TEXT_THRESHOLD,
        max_prompt_variants=2,
        max_tiles_per_frame=2,
    )
    surface_clusters = _cluster_object_views(
        surface_views,
        cluster_radius=SEMANTIC_CLUSTER_RADIUS_METERS,
        min_total_points=220,
        min_confidence=0.24,
        require_surface_support=False,
    )

    region_hints = _build_support_regions(selected_frames, surface_views)
    small_object_views = _extract_object_views(
        selected_frames,
        high_priority_small_labels(small_object_labels),
        box_threshold=SEMANTIC_SMALL_OBJECT_BOX_THRESHOLD,
        text_threshold=SEMANTIC_SMALL_OBJECT_TEXT_THRESHOLD,
        max_prompt_variants=3,
        max_tiles_per_frame=3,
        crop_regions_by_image_path=region_hints,
        per_label_prompts=True,
    )
    small_object_clusters = _cluster_object_views(
        small_object_views,
        cluster_radius=SEMANTIC_SMALL_OBJECT_CLUSTER_RADIUS_METERS,
        min_total_points=12,
        min_confidence=0.12,
        require_surface_support=True,
    )

    reconstruction_dir = output_dir
    reconstruction_dir.mkdir(parents=True, exist_ok=True)

    objects_payload = []
    surface_objects: list[dict[str, Any]] = []
    for cluster in surface_clusters:
        payload = _cluster_to_payload(cluster, room_id=room_id, reconstruction_dir=reconstruction_dir)
        if payload is None:
            continue
        objects_payload.append(payload)
        surface_objects.append(payload)

    for cluster in small_object_clusters:
        payload = _cluster_to_payload(cluster, room_id=room_id, reconstruction_dir=reconstruction_dir)
        if payload is None:
            continue
        objects_payload.append(payload)

    for payload in objects_payload:
        support_relation = _infer_support_relation(payload, surface_objects)
        payload["support_relation"] = support_relation
        _snap_payload_to_support(payload, support_relation)

    objects_payload = _deduplicate_payloads(objects_payload)

    observations = []
    for payload in objects_payload:
        observations.append(
            {
                "id": payload["id"],
                "label": payload["label"],
                "confidence": payload["confidence"],
                "worldTransform16": payload["world_transform16"],
                "world_transform16": payload["world_transform16"],
                "centerXyz": payload["center_xyz"],
                "center_xyz": payload["center_xyz"],
                "extentXyz": payload["extent_xyz"],
                "extent_xyz": payload["extent_xyz"],
                "baseAnchorXyz": payload["base_anchor_xyz"],
                "base_anchor_xyz": payload["base_anchor_xyz"],
                "footprintXyz": payload["footprint_xyz"],
                "footprint_xyz": payload["footprint_xyz"],
                "supportRelation": payload["support_relation"],
                "support_relation": payload["support_relation"],
                "source": "semantic_object_reconstruction",
                "meshAssetURL": payload["mesh_asset_url"],
                "semanticSceneRef": "semantic_scene.json",
            }
        )

    scene = {
        "room_id": room_id,
        "scene_version": 1,
        "generated_at": _now_iso(),
        "labels": labels,
        "objects": objects_payload,
    }
    (reconstruction_dir / "semantic_scene.json").write_text(
        json.dumps(scene, indent=2) + "\n",
        encoding="utf-8",
    )
    return {
        "scene": scene,
        "observations": observations,
    }

def _extract_object_views(
    selected_frames: list[ReconstructionFrame],
    labels: list[str],
    *,
    box_threshold: float = 0.24,
    text_threshold: float = 0.20,
    max_prompt_variants: int = 1,
    max_tiles_per_frame: int = 2,
    crop_regions_by_image_path: dict[str, list[list[float]]] | None = None,
    per_label_prompts: bool = False,
) -> list[ObjectView]:
    if not labels:
        return []

    if crop_regions_by_image_path:
        detections = []
        for frame in selected_frames:
            image_key = str(frame.image_path)
            regions = crop_regions_by_image_path.get(image_key, [])
            if not regions:
                continue
            prompts = labels if per_label_prompts else [" . ".join(labels)]
            for prompt in prompts:
                detections.extend(
                    detect_regions(
                        frame.image_path,
                        regions,
                        prompt,
                        box_threshold=box_threshold,
                        text_threshold=text_threshold,
                        max_prompt_variants=max_prompt_variants,
                    )
                )
    else:
        image_paths = [frame.image_path for frame in selected_frames]
        prompts = labels if per_label_prompts else [" . ".join(labels)]
        detections = []
        for prompt in prompts:
            detections.extend(
                detect(
                    image_paths,
                    prompt,
                    box_threshold=box_threshold,
                    text_threshold=text_threshold,
                    max_prompt_variants=max_prompt_variants,
                    max_tiles_per_frame=max_tiles_per_frame,
                )
            )
    if not detections:
        return []

    frame_lookup = {str(frame.image_path): frame for frame in selected_frames}
    image_cache: dict[str, np.ndarray] = {}
    grouped: dict[str, list[Any]] = {}
    for detection in detections:
        if detection.image_path not in frame_lookup:
            continue
        grouped.setdefault(detection.image_path, []).append(detection)

    views: list[ObjectView] = []
    for image_path, image_detections in grouped.items():
        image_detections = sorted(image_detections, key=lambda item: item.confidence, reverse=True)[
            :SEMANTIC_MAX_DETECTIONS_PER_FRAME
        ]
        image = image_cache.setdefault(image_path, np.array(Image.open(image_path).convert("RGB")))
        try:
            masks = segment(image, [item.bbox_xyxy_norm for item in image_detections])
        except Exception as exc:
            logger.warning("Semantic object mask refinement failed for %s: %s", image_path, exc)
            masks = []

        candidate_frame = frame_lookup[image_path]
        for index, detection in enumerate(image_detections):
            canonical_label = _canonicalize_label(str(detection.label), labels)
            if canonical_label is None:
                continue
            mask = masks[index] if index < len(masks) else None
            view = _project_object_view(
                frame=candidate_frame,
                detection=detection,
                canonical_label=canonical_label,
                image=image,
                mask=mask,
            )
            if view is not None:
                views.append(view)

    return views

def _project_object_view(
    *,
    frame: ReconstructionFrame,
    detection: Any,
    canonical_label: str,
    image: np.ndarray,
    mask: Any,
) -> ObjectView | None:
    if frame.depth_path is None or not frame.depth_path.exists():
        return None

    depth_map_m = np.array(Image.open(frame.depth_path), dtype=np.float32) / 1000.0
    confidence_map = None
    if frame.confidence_path and frame.confidence_path.exists():
        confidence_map = np.array(Image.open(frame.confidence_path), dtype=np.uint8)

    image_h, image_w = image.shape[:2]
    depth_h, depth_w = depth_map_m.shape[:2]
    intrinsics = frame.frame.get("intrinsics9") or frame.frame.get("intrinsics_9")
    extrinsics = frame.frame.get("camera_transform16") or frame.frame.get("cameraTransform16")
    if not intrinsics or not extrinsics:
        return None

    points_uv = _mask_pixels(mask, detection.bbox_xyxy_norm, image_w, image_h)
    if points_uv.size == 0:
        return None

    if len(points_uv) > SEMANTIC_MAX_POINTS_PER_OBJECT_VIEW:
        stride = max(1, len(points_uv) // SEMANTIC_MAX_POINTS_PER_OBJECT_VIEW)
        points_uv = points_uv[::stride]

    depth_x = np.clip((points_uv[:, 0] / max(image_w, 1) * depth_w).astype(int), 0, depth_w - 1)
    depth_y = np.clip((points_uv[:, 1] / max(image_h, 1) * depth_h).astype(int), 0, depth_h - 1)
    depths = depth_map_m[depth_y, depth_x]
    valid = (depths > MIN_DEPTH_METERS) & (depths < MAX_DEPTH_METERS)
    if confidence_map is not None:
        valid &= confidence_map[depth_y, depth_x] >= MIN_DEPTH_CONFIDENCE
    if not np.any(valid):
        return None

    points_uv = points_uv[valid]
    depth_x = depth_x[valid]
    depth_y = depth_y[valid]
    depths = depths[valid]

    colors = image[
        np.clip(points_uv[:, 1].astype(int), 0, image_h - 1),
        np.clip(points_uv[:, 0].astype(int), 0, image_w - 1),
    ]
    world_points = _pixels_to_world(
        pixels_uv=points_uv,
        depths_m=depths,
        image_size=(image_w, image_h),
        depth_size=(depth_w, depth_h),
        intrinsics_9=intrinsics,
        extrinsics_16=extrinsics,
    )
    if world_points.size == 0:
        return None

    center = np.median(world_points, axis=0).astype(np.float32)
    support_anchor = np.array(
        [center[0], np.min(world_points[:, 1]), center[2]],
        dtype=np.float32,
    )
    frame_id = str(frame.frame.get("frame_id") or frame.frame.get("id") or image_path_stem(frame.image_path))
    return ObjectView(
        label=canonical_label,
        score=float(detection.confidence),
        frame_id=frame_id,
        image_path=str(frame.image_path),
        bbox_xyxy_norm=[float(value) for value in detection.bbox_xyxy_norm],
        mask_available=mask is not None and getattr(mask, "mask", None) is not None,
        points_xyz=world_points.astype(np.float32),
        colors_rgb=colors.astype(np.uint8),
        center_xyz=center,
        support_anchor_xyz=support_anchor,
    )

def _mask_pixels(mask: Any, bbox_xyxy_norm: list[float], image_w: int, image_h: int) -> np.ndarray:
    real_mask = None if mask is None else getattr(mask, "mask", None)
    if real_mask is not None:
        ys, xs = np.nonzero(real_mask)
        if len(xs) == 0:
            return np.zeros((0, 2), dtype=np.float32)
        return np.stack([xs.astype(np.float32), ys.astype(np.float32)], axis=1)

    x1, y1, x2, y2 = bbox_xyxy_norm
    px1 = max(int(x1 * image_w), 0)
    py1 = max(int(y1 * image_h), 0)
    px2 = min(int(x2 * image_w), image_w)
    py2 = min(int(y2 * image_h), image_h)
    if px2 <= px1 or py2 <= py1:
        return np.zeros((0, 2), dtype=np.float32)
    xs, ys = np.meshgrid(np.arange(px1, px2), np.arange(py1, py2))
    return np.stack([xs.reshape(-1).astype(np.float32), ys.reshape(-1).astype(np.float32)], axis=1)

def _pixels_to_world(
    *,
    pixels_uv: np.ndarray,
    depths_m: np.ndarray,
    image_size: tuple[int, int],
    depth_size: tuple[int, int],
    intrinsics_9: list[float],
    extrinsics_16: list[float],
) -> np.ndarray:
    image_w, image_h = image_size
    depth_w, depth_h = depth_size
    K = np.array(intrinsics_9, dtype=np.float32).reshape(3, 3, order="F")
    T = np.array(extrinsics_16, dtype=np.float32).reshape(4, 4, order="F")

    scale_x = depth_w / max(float(image_w), 1.0)
    scale_y = depth_h / max(float(image_h), 1.0)
    fx = K[0, 0] * scale_x
    fy = K[1, 1] * scale_y
    cx = K[0, 2] * scale_x
    cy = K[1, 2] * scale_y

    u_depth = pixels_uv[:, 0] * scale_x
    v_depth = pixels_uv[:, 1] * scale_y
    x_cam = (u_depth - cx) * depths_m / fx
    y_cam = (v_depth - cy) * depths_m / fy
    points_cam = np.stack([x_cam, y_cam, depths_m, np.ones_like(depths_m)], axis=1)
    return (T @ points_cam.T).T[:, :3]

def _cluster_object_views(
    views: list[ObjectView],
    *,
    cluster_radius: float,
    min_total_points: int,
    min_confidence: float,
    require_surface_support: bool,
) -> list[ObjectCluster]:
    clusters: list[ObjectCluster] = []
    for view in sorted(views, key=lambda item: item.score, reverse=True):
        matched = None
        best_distance = None
        for cluster in clusters:
            if cluster.label != view.label:
                continue
            distance = float(np.linalg.norm(view.center_xyz - cluster.center_xyz))
            if distance <= cluster_radius and (
                best_distance is None or distance < best_distance
            ):
                matched = cluster
                best_distance = distance

        if matched is None:
            cluster = ObjectCluster(label=view.label)
            cluster.views.append(view)
            cluster.points_xyz.append(view.points_xyz)
            cluster.colors_rgb.append(view.colors_rgb)
            clusters.append(cluster)
        else:
            matched.views.append(view)
            matched.points_xyz.append(view.points_xyz)
            matched.colors_rgb.append(view.colors_rgb)

    filtered_clusters = []
    for cluster in clusters:
        total_points = sum(len(points) for points in cluster.points_xyz)
        if total_points < min_total_points:
            continue
        if _cluster_confidence(cluster) < min_confidence:
            continue
        if cluster.label in SURFACE_LABELS:
            filtered_clusters.append(cluster)
            continue
        supporting_views = len(cluster.views)
        mask_views = sum(1 for view in cluster.views if view.mask_available)
        if not require_surface_support:
            filtered_clusters.append(cluster)
            continue
        if supporting_views >= 2 or mask_views >= 1:
            filtered_clusters.append(cluster)
    clusters = filtered_clusters
    clusters.sort(key=lambda cluster: (_cluster_confidence(cluster), len(cluster.views)), reverse=True)
    return clusters

def _canonicalize_label(raw_label: str, inventory: list[str]) -> str | None:
    raw_tokens = set(raw_label.strip().lower().replace(".", " ").split())
    if not raw_tokens:
        return None

    best_label = None
    best_score = 0.0
    best_token_count = 0
    for candidate in inventory:
        candidate_tokens = set(candidate.split())
        overlap = len(raw_tokens & candidate_tokens)
        if overlap == 0:
            continue
        score = overlap / max(len(candidate_tokens), 1)
        token_count = len(candidate_tokens)
        if (
            score > best_score
            or (math.isclose(score, best_score) and token_count > best_token_count)
        ):
            best_label = candidate
            best_score = score
            best_token_count = token_count

    if best_label is None or best_score < 0.5:
        return None
    return best_label

def high_priority_small_labels(labels: list[str]) -> list[str]:
    priority = [label for label in HIGH_PRIORITY_SMALL_OBJECT_LABELS if label in labels]
    remainder = [label for label in labels if label not in priority]
    return priority + remainder

def _build_support_regions(
    selected_frames: list[ReconstructionFrame],
    surface_views: list[ObjectView],
) -> dict[str, list[list[float]]]:
    regions_by_image_path: dict[str, list[list[float]]] = {}
    if not surface_views:
        for frame in selected_frames:
            regions_by_image_path[str(frame.image_path)] = [[0.0, 0.0, 1.0, 1.0]]
        return regions_by_image_path

    for frame in selected_frames:
        image_key = str(frame.image_path)
        regions: list[list[float]] = []
        for view in surface_views:
            if view.image_path != image_key or view.label not in SUPPORT_SURFACE_LABELS:
                continue
            regions.append(
                _expanded_bbox(
                    view.bbox_xyxy_norm,
                    pad_x=SEMANTIC_REGION_PADDING_X,
                    pad_y=SEMANTIC_REGION_PADDING_Y,
                )
            )
        if not regions:
            regions = [[0.0, 0.0, 1.0, 1.0]]
        regions_by_image_path[image_key] = _deduplicate_regions(regions)
    return regions_by_image_path

def _expanded_bbox(
    bbox_xyxy_norm: list[float],
    *,
    pad_x: float,
    pad_y: float,
) -> list[float]:
    x1, y1, x2, y2 = bbox_xyxy_norm
    return [
        max(0.0, x1 - pad_x),
        max(0.0, y1 - pad_y),
        min(1.0, x2 + pad_x),
        min(1.0, y2 + pad_y),
    ]

def _deduplicate_regions(regions: list[list[float]]) -> list[list[float]]:
    deduped: list[list[float]] = []
    for region in sorted(regions, key=_bbox_area, reverse=True):
        if any(_bbox_iou(region, existing) >= 0.65 for existing in deduped):
            continue
        deduped.append(region)
    return deduped[:4]

def _deduplicate_payloads(objects_payload: list[dict[str, Any]]) -> list[dict[str, Any]]:
    deduped: list[dict[str, Any]] = []
    for payload in sorted(objects_payload, key=lambda item: item.get("confidence", 0.0), reverse=True):
        label = payload.get("label")
        center = np.array(payload.get("center_xyz", [0.0, 0.0, 0.0]), dtype=np.float32)
        duplicate = False
        for existing in deduped:
            if existing.get("label") != label:
                continue
            existing_center = np.array(existing.get("center_xyz", [0.0, 0.0, 0.0]), dtype=np.float32)
            if float(np.linalg.norm(center - existing_center)) <= 0.45:
                duplicate = True
                break
        if not duplicate:
            deduped.append(payload)
    return deduped

def _bbox_area(bbox_xyxy_norm: list[float]) -> float:
    x1, y1, x2, y2 = bbox_xyxy_norm
    return max(x2 - x1, 0.0) * max(y2 - y1, 0.0)

def _bbox_iou(box_a: list[float], box_b: list[float]) -> float:
    ax1, ay1, ax2, ay2 = box_a
    bx1, by1, bx2, by2 = box_b
    ix1 = max(ax1, bx1)
    iy1 = max(ay1, by1)
    ix2 = min(ax2, bx2)
    iy2 = min(ay2, by2)
    inter_w = max(ix2 - ix1, 0.0)
    inter_h = max(iy2 - iy1, 0.0)
    inter = inter_w * inter_h
    if inter <= 0.0:
        return 0.0
    union = _bbox_area(box_a) + _bbox_area(box_b) - inter
    return inter / max(union, 1e-8)

def _cluster_to_payload(
    cluster: ObjectCluster,
    *,
    room_id: str,
    reconstruction_dir: Path,
) -> dict[str, Any] | None:
    points = np.concatenate(cluster.points_xyz, axis=0)
    if len(points) < 32:
        return None

    center, extent, yaw = _fit_upright_obb(points)
    if cluster.label not in SURFACE_LABELS:
        extent = SMALL_OBJECT_MARKER_EXTENT.copy()
    support_anchor = np.array([center[0], np.min(points[:, 1]), center[2]], dtype=np.float32)
    footprint = _footprint_from_obb(center, extent, yaw, support_anchor[1])
    mesh_id = str(uuid4())
    mesh_filename = f"semantic-object-{mesh_id}.obj"
    mesh_kind = _write_proxy_obj(reconstruction_dir / mesh_filename, cluster.label, extent)

    object_id = str(uuid4())
    confidence = _cluster_confidence(cluster)
    world_transform16 = _transform_from_center_yaw(center, yaw)
    bbox_min = points.min(axis=0)
    bbox_max = points.max(axis=0)

    return {
        "id": object_id,
        "label": cluster.label,
        "confidence": confidence,
        "world_transform16": world_transform16,
        "center_xyz": center.astype(float).tolist(),
        "extent_xyz": extent.astype(float).tolist(),
        "axis_aligned_min_xyz": bbox_min.astype(float).tolist(),
        "axis_aligned_max_xyz": bbox_max.astype(float).tolist(),
        "base_anchor_xyz": support_anchor.astype(float).tolist(),
        "support_anchor_xyz": support_anchor.astype(float).tolist(),
        "support_normal_xyz": [0.0, 1.0, 0.0],
        "principal_axis_xyz": [float(math.cos(yaw)), 0.0, float(math.sin(yaw))],
        "yaw_radians": float(yaw),
        "footprint_xyz": [corner.astype(float).tolist() for corner in footprint],
        "mesh_kind": mesh_kind,
        "mesh_asset_url": f"/rooms/{room_id}/assets/{mesh_filename}",
        "point_count": int(len(points)),
        "supporting_view_count": len(cluster.views),
        "observed_frame_ids": sorted({view.frame_id for view in cluster.views}),
        "mask_supported_views": sum(1 for view in cluster.views if view.mask_available),
        "bbox_fallback_views": sum(1 for view in cluster.views if not view.mask_available),
    }

def _fit_upright_obb(points: np.ndarray) -> tuple[np.ndarray, np.ndarray, float]:
    center = np.median(points, axis=0).astype(np.float32)
    centered_xz = points[:, [0, 2]] - center[[0, 2]]
    if len(points) >= 3 and np.any(np.std(centered_xz, axis=0) > 1e-4):
        covariance = np.cov(centered_xz.T)
        eigenvalues, eigenvectors = np.linalg.eigh(covariance)
        principal = eigenvectors[:, int(np.argmax(eigenvalues))]
        yaw = float(math.atan2(principal[1], principal[0]))
    else:
        yaw = 0.0

    cos_yaw = math.cos(-yaw)
    sin_yaw = math.sin(-yaw)
    rotation = np.array([[cos_yaw, -sin_yaw], [sin_yaw, cos_yaw]], dtype=np.float32)
    rotated_xz = centered_xz @ rotation.T
    min_xz = np.min(rotated_xz, axis=0)
    max_xz = np.max(rotated_xz, axis=0)
    min_y = float(np.min(points[:, 1]))
    max_y = float(np.max(points[:, 1]))

    extent = np.array(
        [
            max(float(max_xz[0] - min_xz[0]), 0.02),
            max(max_y - min_y, 0.02),
            max(float(max_xz[1] - min_xz[1]), 0.02),
        ],
        dtype=np.float32,
    )
    center = np.array([center[0], (min_y + max_y) * 0.5, center[2]], dtype=np.float32)
    return center, extent, yaw

def _footprint_from_obb(center: np.ndarray, extent: np.ndarray, yaw: float, y_value: float) -> list[np.ndarray]:
    half_x = extent[0] * 0.5
    half_z = extent[2] * 0.5
    corners_local = np.array(
        [
            [-half_x, 0.0, -half_z],
            [half_x, 0.0, -half_z],
            [half_x, 0.0, half_z],
            [-half_x, 0.0, half_z],
        ],
        dtype=np.float32,
    )
    rotation = _rotation_y(yaw)[:3, :3]
    corners = []
    for corner in corners_local:
        world = (rotation @ corner.reshape(3, 1)).reshape(3)
        corners.append(np.array([center[0] + world[0], y_value, center[2] + world[2]], dtype=np.float32))
    return corners

def _write_box_obj(output_path: Path, center: np.ndarray, extent: np.ndarray, yaw: float) -> None:
    half_x, half_y, half_z = extent[0] * 0.5, extent[1] * 0.5, extent[2] * 0.5
    vertices = np.array(
        [
            [-half_x, -half_y, -half_z],
            [half_x, -half_y, -half_z],
            [half_x, half_y, -half_z],
            [-half_x, half_y, -half_z],
            [-half_x, -half_y, half_z],
            [half_x, -half_y, half_z],
            [half_x, half_y, half_z],
            [-half_x, half_y, half_z],
        ],
        dtype=np.float32,
    )
    rotation = _rotation_y(yaw)[:3, :3]
    transformed = (rotation @ vertices.T).T + center
    faces = [
        (1, 2, 3),
        (1, 3, 4),
        (5, 6, 7),
        (5, 7, 8),
        (1, 5, 8),
        (1, 8, 4),
        (2, 6, 7),
        (2, 7, 3),
        (4, 3, 7),
        (4, 7, 8),
        (1, 2, 6),
        (1, 6, 5),
    ]
    with output_path.open("w", encoding="utf-8") as handle:
        handle.write("# semantic low-poly object box\n")
        for vertex in transformed:
            handle.write(f"v {vertex[0]:.6f} {vertex[1]:.6f} {vertex[2]:.6f}\n")
        for face in faces:
            handle.write(f"f {face[0]} {face[1]} {face[2]}\n")

def _write_proxy_obj(output_path: Path, label: str, extent: np.ndarray) -> str:
    label_key = label.lower()
    if any(token in label_key for token in ("bottle", "can", "mug")):
        vertices, faces = _make_cylinder_proxy(extent, segments=14)
        mesh_kind = "semantic_proxy_cylinder"
    elif any(token in label_key for token in ("laptop",)):
        vertices, faces = _make_laptop_proxy(extent)
        mesh_kind = "semantic_proxy_laptop"
    elif any(token in label_key for token in ("phone", "wallet", "airpods", "remote", "keyboard", "mouse", "book", "notebook")):
        vertices, faces = _make_slab_proxy(extent)
        mesh_kind = "semantic_proxy_slab"
    elif any(token in label_key for token in ("backpack", "bag")):
        vertices, faces = _make_backpack_proxy(extent)
        mesh_kind = "semantic_proxy_backpack"
    elif any(token in label_key for token in ("lamp",)):
        vertices, faces = _make_lamp_proxy(extent)
        mesh_kind = "semantic_proxy_lamp"
    elif any(token in label_key for token in ("charger", "speaker", "monitor")):
        vertices, faces = _make_box_proxy(extent)
        mesh_kind = "semantic_proxy_box"
    else:
        vertices, faces = _make_box_proxy(extent)
        mesh_kind = "low_poly_obb"

    _write_mesh_obj(output_path, vertices, faces)
    return mesh_kind

def _write_mesh_obj(output_path: Path, vertices: np.ndarray, faces: list[tuple[int, int, int]]) -> None:
    with output_path.open("w", encoding="utf-8") as handle:
        handle.write("# semantic proxy object mesh\n")
        for vertex in vertices:
            handle.write(f"v {vertex[0]:.6f} {vertex[1]:.6f} {vertex[2]:.6f}\n")
        for face in faces:
            handle.write(f"f {face[0]} {face[1]} {face[2]}\n")

def _make_box_proxy(extent: np.ndarray, *, center: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> tuple[np.ndarray, list[tuple[int, int, int]]]:
    cx, cy, cz = center
    half_x, half_y, half_z = extent[0] * 0.5, extent[1] * 0.5, extent[2] * 0.5
    vertices = np.array(
        [
            [cx - half_x, cy - half_y, cz - half_z],
            [cx + half_x, cy - half_y, cz - half_z],
            [cx + half_x, cy + half_y, cz - half_z],
            [cx - half_x, cy + half_y, cz - half_z],
            [cx - half_x, cy - half_y, cz + half_z],
            [cx + half_x, cy - half_y, cz + half_z],
            [cx + half_x, cy + half_y, cz + half_z],
            [cx - half_x, cy + half_y, cz + half_z],
        ],
        dtype=np.float32,
    )
    faces = [
        (1, 2, 3), (1, 3, 4),
        (5, 6, 7), (5, 7, 8),
        (1, 5, 8), (1, 8, 4),
        (2, 6, 7), (2, 7, 3),
        (4, 3, 7), (4, 7, 8),
        (1, 2, 6), (1, 6, 5),
    ]
    return vertices, faces

def _make_slab_proxy(extent: np.ndarray) -> tuple[np.ndarray, list[tuple[int, int, int]]]:
    slab_extent = np.array(
        [
            max(float(extent[0]), 0.06),
            max(min(float(extent[1]), 0.04), 0.012),
            max(float(extent[2]), 0.04),
        ],
        dtype=np.float32,
    )
    return _make_box_proxy(slab_extent)

def _make_cylinder_proxy(extent: np.ndarray, *, segments: int = 12) -> tuple[np.ndarray, list[tuple[int, int, int]]]:
    radius_x = max(float(extent[0]) * 0.45, 0.025)
    radius_z = max(float(extent[2]) * 0.45, 0.025)
    height = max(float(extent[1]), 0.06)
    half_y = height * 0.5

    vertices: list[list[float]] = [
        [0.0, -half_y, 0.0],
        [0.0, half_y, 0.0],
    ]
    for level_y in (-half_y, half_y):
        for index in range(segments):
            angle = (2.0 * math.pi * index) / segments
            vertices.append([
                math.cos(angle) * radius_x,
                level_y,
                math.sin(angle) * radius_z,
            ])

    faces: list[tuple[int, int, int]] = []
    top_center = 2
    bottom_center = 1
    bottom_ring_start = 3
    top_ring_start = 3 + segments

    for index in range(segments):
        next_index = (index + 1) % segments
        b0 = bottom_ring_start + index
        b1 = bottom_ring_start + next_index
        t0 = top_ring_start + index
        t1 = top_ring_start + next_index
        faces.append((bottom_center, b1, b0))
        faces.append((top_center, t0, t1))
        faces.append((b0, b1, t1))
        faces.append((b0, t1, t0))

    return np.array(vertices, dtype=np.float32), faces

def _make_laptop_proxy(extent: np.ndarray) -> tuple[np.ndarray, list[tuple[int, int, int]]]:
    width = max(float(extent[0]), 0.16)
    depth = max(float(extent[2]), 0.11)
    height = max(float(extent[1]), 0.025)
    base_thickness = max(min(height * 0.35, 0.018), 0.010)
    screen_thickness = max(base_thickness * 0.6, 0.006)
    screen_height = max(height * 1.6, 0.12)

    base_vertices, base_faces = _make_box_proxy(
        np.array([width, base_thickness, depth], dtype=np.float32),
        center=(0.0, -screen_height * 0.1, 0.0),
    )

    screen_center_z = -depth * 0.35
    screen_center_y = screen_height * 0.35
    screen_vertices, screen_faces = _make_box_proxy(
        np.array([width, screen_height, screen_thickness], dtype=np.float32),
        center=(0.0, screen_center_y, screen_center_z),
    )
    screen_vertices = _rotate_vertices_x(screen_vertices, math.radians(-18.0), pivot=np.array([0.0, 0.0, -depth * 0.5], dtype=np.float32))

    return _combine_meshes([(base_vertices, base_faces), (screen_vertices, screen_faces)])

def _make_backpack_proxy(extent: np.ndarray) -> tuple[np.ndarray, list[tuple[int, int, int]]]:
    width = max(float(extent[0]), 0.18)
    height = max(float(extent[1]), 0.26)
    depth = max(float(extent[2]), 0.10)
    half_w = width * 0.5
    half_h = height * 0.5
    half_d = depth * 0.5
    taper = width * 0.14

    vertices = np.array(
        [
            [-half_w, -half_h, -half_d],
            [half_w, -half_h, -half_d],
            [half_w, half_h * 0.7, -half_d],
            [-half_w, half_h * 0.7, -half_d],
            [-(half_w - taper), half_h, half_d],
            [(half_w - taper), half_h, half_d],
            [half_w, -half_h, half_d],
            [-half_w, -half_h, half_d],
        ],
        dtype=np.float32,
    )
    faces = [
        (1, 2, 3), (1, 3, 4),
        (8, 7, 6), (8, 6, 5),
        (1, 8, 5), (1, 5, 4),
        (2, 7, 6), (2, 6, 3),
        (4, 3, 6), (4, 6, 5),
        (1, 2, 7), (1, 7, 8),
    ]
    return vertices, faces

def _make_lamp_proxy(extent: np.ndarray) -> tuple[np.ndarray, list[tuple[int, int, int]]]:
    width = max(float(extent[0]), 0.12)
    height = max(float(extent[1]), 0.24)
    depth = max(float(extent[2]), 0.12)
    base_vertices, base_faces = _make_cylinder_proxy(np.array([width * 0.8, height * 0.12, depth * 0.8], dtype=np.float32), segments=12)
    stem_vertices, stem_faces = _make_cylinder_proxy(np.array([width * 0.16, height * 0.55, depth * 0.16], dtype=np.float32), segments=10)
    stem_vertices[:, 1] += height * 0.15
    shade_vertices, shade_faces = _make_cylinder_proxy(np.array([width, height * 0.35, depth], dtype=np.float32), segments=14)
    shade_vertices[:, 1] += height * 0.34
    return _combine_meshes([(base_vertices, base_faces), (stem_vertices, stem_faces), (shade_vertices, shade_faces)])

def _rotate_vertices_x(vertices: np.ndarray, angle: float, *, pivot: np.ndarray) -> np.ndarray:
    rotation = np.array(
        [
            [1.0, 0.0, 0.0],
            [0.0, math.cos(angle), -math.sin(angle)],
            [0.0, math.sin(angle), math.cos(angle)],
        ],
        dtype=np.float32,
    )
    shifted = vertices - pivot
    return (shifted @ rotation.T) + pivot

def _combine_meshes(meshes: list[tuple[np.ndarray, list[tuple[int, int, int]]]]) -> tuple[np.ndarray, list[tuple[int, int, int]]]:
    all_vertices: list[np.ndarray] = []
    all_faces: list[tuple[int, int, int]] = []
    vertex_offset = 0
    for vertices, faces in meshes:
        all_vertices.append(vertices)
        all_faces.extend(
            (a + vertex_offset, b + vertex_offset, c + vertex_offset)
            for a, b, c in faces
        )
        vertex_offset += len(vertices)
    return np.concatenate(all_vertices, axis=0).astype(np.float32), all_faces

def _cluster_confidence(cluster: ObjectCluster) -> float:
    view_scores = np.array([view.score for view in cluster.views], dtype=np.float32)
    if view_scores.size == 0:
        return 0.0
    base = float(np.clip(np.mean(view_scores), 0.0, 1.0))
    support_bonus = min(len(cluster.views) / 6.0, 1.0) * 0.15
    return float(min(base + support_bonus, 0.98))

def _infer_support_relation(
    payload: dict[str, Any],
    surface_objects: list[dict[str, Any]],
) -> dict[str, Any]:
    if payload["label"] in SURFACE_LABELS:
        return {
            "type": "self_surface",
            "support_object_id": None,
            "support_label": payload["label"],
            "support_height_y": payload["base_anchor_xyz"][1],
        }

    anchor = np.array(payload["base_anchor_xyz"], dtype=np.float32)
    best_surface = None
    best_score = None
    for surface in surface_objects:
        if surface["id"] == payload["id"]:
            continue
        surface_center = np.array(surface["center_xyz"], dtype=np.float32)
        surface_extent = np.array(surface["extent_xyz"], dtype=np.float32)
        top_y = surface_center[1] + (surface_extent[1] * 0.5)
        vertical_gap = float(anchor[1] - top_y)
        if vertical_gap < -0.08 or vertical_gap > 0.35:
            continue
        horizontal_distance = _horizontal_distance_to_surface(anchor[[0, 2]], surface)
        radius = float(max(surface_extent[0], surface_extent[2]) * 0.75)
        if horizontal_distance > radius:
            continue
        score = horizontal_distance + abs(vertical_gap) * 0.5
        if best_score is None or score < best_score:
            best_score = score
            best_surface = surface

    if best_surface is not None:
        return {
            "type": "supported_by",
            "support_object_id": best_surface["id"],
            "support_label": best_surface["label"],
            "support_height_y": best_surface["center_xyz"][1] + (best_surface["extent_xyz"][1] * 0.5),
        }

    return {
        "type": "supported_by_floor",
        "support_object_id": None,
        "support_label": "floor",
        "support_height_y": payload["base_anchor_xyz"][1],
    }

def _horizontal_distance_to_surface(anchor_xz: np.ndarray, surface: dict[str, Any]) -> float:
    footprint = surface.get("footprint_xyz") or []
    if len(footprint) >= 3:
        polygon = np.array([[point[0], point[2]] for point in footprint], dtype=np.float32)
        if _point_in_polygon(anchor_xz, polygon):
            return 0.0
        return min(
            _distance_point_to_segment(anchor_xz, polygon[index], polygon[(index + 1) % len(polygon)])
            for index in range(len(polygon))
        )
    surface_center = np.array(surface["center_xyz"], dtype=np.float32)
    return float(np.linalg.norm(anchor_xz - surface_center[[0, 2]]))

def _point_in_polygon(point: np.ndarray, polygon: np.ndarray) -> bool:
    x, y = float(point[0]), float(point[1])
    inside = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        xi, yi = float(polygon[i][0]), float(polygon[i][1])
        xj, yj = float(polygon[j][0]), float(polygon[j][1])
        intersects = ((yi > y) != (yj > y)) and (
            x < (xj - xi) * (y - yi) / max(yj - yi, 1e-8) + xi
        )
        if intersects:
            inside = not inside
        j = i
    return inside

def _distance_point_to_segment(point: np.ndarray, start: np.ndarray, end: np.ndarray) -> float:
    segment = end - start
    segment_length_sq = float(np.dot(segment, segment))
    if segment_length_sq <= 1e-8:
        return float(np.linalg.norm(point - start))
    t = float(np.dot(point - start, segment) / segment_length_sq)
    t = max(0.0, min(1.0, t))
    projection = start + (segment * t)
    return float(np.linalg.norm(point - projection))

def _snap_payload_to_support(payload: dict[str, Any], support_relation: dict[str, Any]) -> None:
    if payload["label"] in SURFACE_LABELS:
        return

    support_y = float(support_relation["support_height_y"])
    extent = SMALL_OBJECT_MARKER_EXTENT.copy()
    center = np.array(payload["center_xyz"], dtype=np.float32)
    center[1] = support_y + (extent[1] * 0.5)
    payload["extent_xyz"] = extent.astype(float).tolist()
    payload["center_xyz"] = center.astype(float).tolist()
    payload["base_anchor_xyz"] = [float(center[0]), support_y, float(center[2])]
    payload["support_anchor_xyz"] = [float(center[0]), support_y, float(center[2])]
    payload["world_transform16"] = _transform_from_center_yaw(center, float(payload["yaw_radians"]))
    payload["footprint_xyz"] = [
        corner.astype(float).tolist()
        for corner in _footprint_from_obb(center, extent, float(payload["yaw_radians"]), support_y)
    ]

def _transform_from_center_yaw(center: np.ndarray, yaw: float) -> list[float]:
    transform = _rotation_y(yaw)
    transform[0, 3] = center[0]
    transform[1, 3] = center[1]
    transform[2, 3] = center[2]
    return transform.flatten(order="F").tolist()

def _rotation_y(yaw: float) -> np.ndarray:
    cos_yaw = math.cos(yaw)
    sin_yaw = math.sin(yaw)
    transform = np.eye(4, dtype=np.float32)
    transform[0, 0] = cos_yaw
    transform[0, 2] = sin_yaw
    transform[2, 0] = -sin_yaw
    transform[2, 2] = cos_yaw
    return transform

def _now_iso() -> str:
    return datetime.now(UTC).isoformat()

def image_path_stem(image_path: Path) -> str:
    return image_path.stem
