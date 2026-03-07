from __future__ import annotations

import numpy as np


def pixel_to_world(
    u: float,
    v: float,
    depth: float,
    intrinsics_9: list[float],
    extrinsics_16: list[float],
) -> list[float]:
    """Convert 2D pixel + depth to 3D world coordinates.

    intrinsics_9: 3x3 camera intrinsics in column-major order (9 floats)
    extrinsics_16: 4x4 camera-to-world transform in column-major order (16 floats)
    Returns: [x, y, z] world coordinates
    """
    K = np.array(intrinsics_9).reshape(3, 3, order="F")
    T = np.array(extrinsics_16).reshape(4, 4, order="F")

    fx, fy = K[0, 0], K[1, 1]
    cx, cy = K[0, 2], K[1, 2]
    x_cam = (u - cx) * depth / fx
    y_cam = (v - cy) * depth / fy
    z_cam = depth

    point_cam = np.array([x_cam, y_cam, z_cam, 1.0])
    point_world = T @ point_cam

    return point_world[:3].tolist()


def bbox_center_to_world(
    bbox_xyxy_norm: list[float],
    image_w: int,
    image_h: int,
    depth: float,
    intrinsics_9: list[float],
    extrinsics_16: list[float],
) -> list[float]:
    """Convert bbox center to world coordinates."""
    u = (bbox_xyxy_norm[0] + bbox_xyxy_norm[2]) / 2 * image_w
    v = (bbox_xyxy_norm[1] + bbox_xyxy_norm[3]) / 2 * image_h
    return pixel_to_world(u, v, depth, intrinsics_9, extrinsics_16)


def make_world_transform_16(position: list[float]) -> list[float]:
    """Create a 4x4 identity transform with given translation, as 16 column-major floats."""
    T = np.eye(4)
    T[0, 3] = position[0]
    T[1, 3] = position[1]
    T[2, 3] = position[2]
    return T.flatten(order="F").tolist()
