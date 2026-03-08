from __future__ import annotations

import math
import os
from pathlib import Path

import numpy as np

from reconstruction.pointcloud.generate import PointCloud

FAST_PREVIEW_VOXEL_SIZE = float(os.getenv("FAST_PREVIEW_VOXEL_SIZE", "0.10"))
FAST_PREVIEW_MAX_VOXELS = max(1, int(os.getenv("FAST_PREVIEW_MAX_VOXELS", "12000")))

def export_low_poly_preview_mesh(
    pointcloud: PointCloud,
    output_dir: Path,
    voxel_size: float = FAST_PREVIEW_VOXEL_SIZE,
    max_voxels: int = FAST_PREVIEW_MAX_VOXELS,
) -> Path | None:
    if len(pointcloud.points) == 0:
        return None

    voxel_indices = np.floor(pointcloud.points / voxel_size).astype(np.int32)
    unique_voxels = np.unique(voxel_indices, axis=0)
    if len(unique_voxels) == 0:
        return None

    if len(unique_voxels) > max_voxels:
        stride = max(1, math.ceil(len(unique_voxels) / max_voxels))
        unique_voxels = unique_voxels[::stride]

    occupied = {tuple(int(component) for component in voxel) for voxel in unique_voxels}
    if not occupied:
        return None

    mesh_path = output_dir / "fast_preview.obj"
    output_dir.mkdir(parents=True, exist_ok=True)

    directions = [
        ((1, 0, 0), ((1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1))),
        ((-1, 0, 0), ((0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0))),
        ((0, 1, 0), ((0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0))),
        ((0, -1, 0), ((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1))),
        ((0, 0, 1), ((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1))),
        ((0, 0, -1), ((0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0))),
    ]

    lines = [
        "# hacktj2026 fast low-poly room preview",
        "o fast_preview_room",
    ]
    vertex_index = 1

    for voxel in sorted(occupied):
        base = np.array(voxel, dtype=np.float32) * voxel_size
        for direction, corners in directions:
            neighbor = (
                voxel[0] + direction[0],
                voxel[1] + direction[1],
                voxel[2] + direction[2],
            )
            if neighbor in occupied:
                continue

            face_indices: list[int] = []
            for corner in corners:
                vertex = base + (np.array(corner, dtype=np.float32) * voxel_size)
                lines.append(f"v {vertex[0]:.5f} {vertex[1]:.5f} {vertex[2]:.5f}")
                face_indices.append(vertex_index)
                vertex_index += 1
            lines.append("f " + " ".join(str(index) for index in face_indices))

    mesh_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return mesh_path
