from pathlib import Path

import numpy as np

from reconstruction.fast_preview.export_mesh import export_low_poly_preview_mesh
from reconstruction.pointcloud.generate import PointCloud


def test_export_low_poly_preview_mesh_writes_obj(tmp_path: Path):
    pointcloud = PointCloud(
        points=np.array(
            [
                [0.00, 0.00, 0.00],
                [0.04, 0.02, 0.01],
                [0.15, 0.00, 0.00],
            ],
            dtype=np.float32,
        ),
        colors=np.array(
            [
                [255, 255, 255],
                [240, 240, 240],
                [200, 200, 200],
            ],
            dtype=np.uint8,
        ),
    )

    mesh_path = export_low_poly_preview_mesh(
        pointcloud,
        tmp_path,
        voxel_size=0.10,
        max_voxels=16,
    )

    assert mesh_path is not None
    assert mesh_path.exists()

    contents = mesh_path.read_text(encoding="utf-8")
    assert contents.startswith("# hacktj2026 fast low-poly room preview")
    assert "\nv " in contents
    assert "\nf " in contents
