from __future__ import annotations

import os
from concurrent.futures import ThreadPoolExecutor
import logging
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)
POINTCLOUD_WORKERS = max(1, int(os.getenv("POINTCLOUD_WORKERS", str(min(os.cpu_count() or 1, 16)))))


@dataclass
class PointCloud:
    points: np.ndarray  # N x 3 float32
    colors: np.ndarray  # N x 3 uint8
    normals: np.ndarray | None = None  # N x 3 float32


def generate_pointcloud(
    depth_results: list,  # list of DepthResult
    frame_metadata: list[dict],
    image_dir: Path,
    voxel_size: float = 0.02,  # 2cm voxel grid
    max_depth: float = 8.0,
    min_depth: float = 0.1,
    min_confidence: int = 1,
    max_points_per_frame: int = 12000,
) -> PointCloud:
    """Generate colored point cloud from depth maps + camera poses."""
    all_points = []
    all_colors = []

    metadata_by_id = {
        str(frame_meta.get("frame_id") or frame_meta.get("id")): frame_meta
        for frame_meta in frame_metadata
        if frame_meta.get("frame_id") or frame_meta.get("id")
    }
    metadata_by_name = {
        Path(
            frame_meta.get("image_path")
            or frame_meta.get("imagePath")
            or frame_meta.get("image")
            or frame_meta.get("filename", "")
        ).name: frame_meta
        for frame_meta in frame_metadata
    }

    if POINTCLOUD_WORKERS == 1 or len(depth_results) <= 1:
        projected_chunks = [
            _project_depth_result(
                depth_result=depth_result,
                metadata_by_id=metadata_by_id,
                metadata_by_name=metadata_by_name,
                min_depth=min_depth,
                max_depth=max_depth,
                min_confidence=min_confidence,
                max_points_per_frame=max_points_per_frame,
            )
            for depth_result in depth_results
        ]
    else:
        max_workers = min(POINTCLOUD_WORKERS, len(depth_results))
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            projected_chunks = list(
                executor.map(
                    lambda candidate: _project_depth_result(
                        depth_result=candidate,
                        metadata_by_id=metadata_by_id,
                        metadata_by_name=metadata_by_name,
                        min_depth=min_depth,
                        max_depth=max_depth,
                        min_confidence=min_confidence,
                        max_points_per_frame=max_points_per_frame,
                    ),
                    depth_results,
                )
            )

    for chunk in projected_chunks:
        if chunk is None:
            continue
        points_world, colors_valid = chunk
        all_points.append(points_world)
        all_colors.append(colors_valid)

    if not all_points:
        return PointCloud(
            points=np.zeros((0, 3), dtype=np.float32),
            colors=np.zeros((0, 3), dtype=np.uint8),
        )

    points = np.concatenate(all_points, axis=0)
    colors = np.concatenate(all_colors, axis=0)

    # Voxel grid downsampling
    points, colors = _voxel_downsample(points, colors, voxel_size)

    return PointCloud(
        points=points.astype(np.float32), colors=colors.astype(np.uint8)
    )


def _project_depth_result(
    *,
    depth_result,
    metadata_by_id: dict[str, dict],
    metadata_by_name: dict[str, dict],
    min_depth: float,
    max_depth: float,
    min_confidence: int,
    max_points_per_frame: int,
) -> tuple[np.ndarray, np.ndarray] | None:
    frame_meta = None
    frame_id = getattr(depth_result, "frame_id", None)
    if frame_id:
        frame_meta = metadata_by_id.get(str(frame_id))
    if frame_meta is None:
        frame_meta = metadata_by_name.get(Path(depth_result.image_path).name)
    if frame_meta is None:
        logger.warning("Skipping depth result without matching frame metadata: %s", depth_result.image_path)
        return None

    intrinsics_9 = frame_meta.get("intrinsics9", frame_meta.get("intrinsics_9", []))
    extrinsics_16 = frame_meta.get("cameraTransform16", frame_meta.get("camera_transform16", []))
    if len(intrinsics_9) != 9 or len(extrinsics_16) != 16:
        logger.warning("Skipping frame with invalid intrinsics/extrinsics")
        return None

    K = np.array(intrinsics_9, dtype=np.float32).reshape(3, 3, order="F")
    T = np.array(extrinsics_16, dtype=np.float32).reshape(4, 4, order="F")

    depth = depth_result.depth_map
    h, w = depth.shape

    confidence = getattr(depth_result, "confidence_map", None)
    if confidence is not None and confidence.shape != depth.shape:
        confidence = np.array(
            Image.fromarray(confidence).resize((w, h), Image.NEAREST),
            dtype=np.uint8,
        )

    image = np.array(
        Image.open(depth_result.image_path).convert("RGB").resize((w, h))
    )
    u_coords, v_coords = np.meshgrid(np.arange(w), np.arange(h))

    valid = (depth > min_depth) & (depth < max_depth)
    if confidence is not None:
        valid &= confidence >= min_confidence
    valid_count = int(valid.sum())
    if valid_count == 0:
        return None

    sample_stride = max(1, int(math.sqrt(valid_count / max_points_per_frame)))
    if sample_stride > 1:
        sparse_mask = np.zeros_like(valid, dtype=bool)
        sparse_mask[::sample_stride, ::sample_stride] = True
        valid &= sparse_mask

    u_valid = u_coords[valid].astype(np.float32)
    v_valid = v_coords[valid].astype(np.float32)
    d_valid = depth[valid]
    colors_valid = image[valid]

    rgb_width, rgb_height = depth_result.original_size
    scale_x = w / max(float(rgb_width), 1.0)
    scale_y = h / max(float(rgb_height), 1.0)
    fx = K[0, 0] * scale_x
    fy = K[1, 1] * scale_y
    cx = K[0, 2] * scale_x
    cy = K[1, 2] * scale_y
    x_cam = (u_valid - cx) * d_valid / fx
    y_cam = (v_valid - cy) * d_valid / fy
    z_cam = d_valid

    points_cam = np.stack([x_cam, y_cam, z_cam, np.ones_like(x_cam)], axis=-1)
    points_world = (T @ points_cam.T).T[:, :3]
    return points_world, colors_valid


def _voxel_downsample(
    points: np.ndarray, colors: np.ndarray, voxel_size: float
) -> tuple[np.ndarray, np.ndarray]:
    """Simple voxel grid downsampling."""
    if len(points) == 0:
        return points, colors
    voxel_indices = np.floor(points / voxel_size).astype(np.int64)
    _, unique_idx = np.unique(voxel_indices, axis=0, return_index=True)
    return points[unique_idx], colors[unique_idx]


def save_ply(pointcloud: PointCloud, output_path: Path) -> None:
    """Save point cloud as PLY file."""
    n = len(pointcloud.points)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "wb") as f:
        header = (
            "ply\n"
            "format binary_little_endian 1.0\n"
            f"element vertex {n}\n"
            "property float x\nproperty float y\nproperty float z\n"
            "property uchar red\nproperty uchar green\nproperty uchar blue\n"
            "end_header\n"
        )
        f.write(header.encode("ascii"))

        if n > 0:
            # Write binary data for efficiency
            for i in range(n):
                p = pointcloud.points[i]
                c = pointcloud.colors[i]
                f.write(
                    np.array(p, dtype=np.float32).tobytes()
                    + np.array(c, dtype=np.uint8).tobytes()
                )
