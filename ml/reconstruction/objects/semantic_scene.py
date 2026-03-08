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

from open_vocab.grounding_dino.run_grounding import detect
from open_vocab.sam2.run_segmentation import segment
from reconstruction.da3.run_pipeline import (
    MAX_DEPTH_METERS,
    MIN_DEPTH_METERS,
    MIN_DEPTH_CONFIDENCE,
    ReconstructionFrame,
    select_reconstruction_frames,
)

logger = logging.getLogger(__name__)

SEMANTIC_OBJECT_FRAME_LIMIT = int(os.getenv("SEMANTIC_OBJECT_FRAME_LIMIT", "8"))
SEMANTIC_MAX_DETECTIONS_PER_FRAME = int(os.getenv("SEMANTIC_MAX_DETECTIONS_PER_FRAME", "8"))
SEMANTIC_MAX_POINTS_PER_OBJECT_VIEW = int(os.getenv("SEMANTIC_MAX_POINTS_PER_OBJECT_VIEW", "1400"))
SEMANTIC_CLUSTER_RADIUS_METERS = float(os.getenv("SEMANTIC_CLUSTER_RADIUS_METERS", "0.28"))

DEFAULT_SEMANTIC_LABELS = [
    "table",
    "desk",
    "counter",
    "shelf",
    "nightstand",
    "dresser",
    "chair",
    "couch",
    "bed",
    "monitor",
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
]

SURFACE_LABELS = {"table", "desk", "counter", "shelf", "nightstand", "dresser", "chair", "couch", "bed"}


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
    views = _extract_object_views(selected_frames, labels)
    clusters = _cluster_object_views(views)

    reconstruction_dir = output_dir
    reconstruction_dir.mkdir(parents=True, exist_ok=True)

    objects_payload = []
    observations = []
    surface_objects: list[dict[str, Any]] = []
    for cluster in clusters:
        payload = _cluster_to_payload(cluster, room_id=room_id, reconstruction_dir=reconstruction_dir)
        if payload is None:
            continue
        objects_payload.append(payload)
        observations.append(
            {
                "id": payload["id"],
                "label": payload["label"],
                "confidence": payload["confidence"],
                "worldTransform16": payload["world_transform16"],
                "world_transform16": payload["world_transform16"],
                "extentXyz": payload["extent_xyz"],
                "extent_xyz": payload["extent_xyz"],
                "source": "semantic_object_reconstruction",
                "meshAssetURL": payload["mesh_asset_url"],
                "semanticSceneRef": "semantic_scene.json",
            }
        )
        if payload["label"] in SURFACE_LABELS:
            surface_objects.append(payload)

    for payload in objects_payload:
        support_relation = _infer_support_relation(payload, surface_objects)
        payload["support_relation"] = support_relation
        payload["base_anchor_xyz"] = payload["support_anchor_xyz"]

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
) -> list[ObjectView]:
    prompt = " . ".join(labels)
    image_paths = [frame.image_path for frame in selected_frames]
    detections = detect(
        image_paths,
        prompt,
        box_threshold=0.24,
        text_threshold=0.20,
        max_prompt_variants=1,
        max_tiles_per_frame=2,
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


def _cluster_object_views(views: list[ObjectView]) -> list[ObjectCluster]:
    clusters: list[ObjectCluster] = []
    for view in sorted(views, key=lambda item: item.score, reverse=True):
        matched = None
        best_distance = None
        for cluster in clusters:
            if cluster.label != view.label:
                continue
            distance = float(np.linalg.norm(view.center_xyz - cluster.center_xyz))
            if distance <= SEMANTIC_CLUSTER_RADIUS_METERS and (
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
        if total_points < 120:
            continue
        if _cluster_confidence(cluster) < 0.32:
            continue
        if cluster.label in SURFACE_LABELS:
            filtered_clusters.append(cluster)
            continue
        supporting_views = len(cluster.views)
        mask_views = sum(1 for view in cluster.views if view.mask_available)
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
    support_anchor = np.array([center[0], np.min(points[:, 1]), center[2]], dtype=np.float32)
    footprint = _footprint_from_obb(center, extent, yaw, support_anchor[1])
    mesh_id = str(uuid4())
    mesh_filename = f"semantic-object-{mesh_id}.obj"
    _write_box_obj(reconstruction_dir / mesh_filename, center, extent, yaw)

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
        "mesh_kind": "low_poly_obb",
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
        horizontal_distance = float(np.linalg.norm(anchor[[0, 2]] - surface_center[[0, 2]]))
        radius = float(max(surface_extent[0], surface_extent[2]) * 0.65)
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
