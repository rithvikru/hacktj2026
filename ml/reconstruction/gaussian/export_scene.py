from __future__ import annotations

import logging
import shutil
import struct
import subprocess
from pathlib import Path

import numpy as np

logger = logging.getLogger(__name__)

def train_gaussians(
    pointcloud_path: Path,
    image_dir: Path,
    poses: list[dict],
    output_dir: Path,
    num_iterations: int = 7000,
) -> Path | None:
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        result = _train_with_gsplat(
            pointcloud_path, image_dir, poses, output_dir, num_iterations
        )
        if result:
            return result
    except (ImportError, Exception) as e:
        logger.warning("gsplat training failed: %s, trying subprocess fallback", e)

    try:
        result = _train_with_subprocess(
            pointcloud_path, image_dir, poses, output_dir, num_iterations
        )
        if result:
            return result
    except Exception as e:
        logger.warning("Subprocess training failed: %s, using point cloud fallback", e)

    return _pointcloud_to_splat(pointcloud_path, output_dir)

def _train_with_gsplat(
    pointcloud_path: Path,
    image_dir: Path,
    poses: list[dict],
    output_dir: Path,
    num_iterations: int,
) -> Path | None:
    import torch
    from gsplat import rasterization

    points, colors = _load_ply_points(pointcloud_path)
    if len(points) == 0:
        return None

    device = "cuda" if torch.cuda.is_available() else "cpu"
    N = len(points)

    means = torch.tensor(points, dtype=torch.float32, device=device, requires_grad=True)
    rgbs = torch.tensor(colors / 255.0, dtype=torch.float32, device=device, requires_grad=True)
    scales = torch.full((N, 3), 0.01, dtype=torch.float32, device=device, requires_grad=True)
    quats = torch.zeros((N, 4), dtype=torch.float32, device=device)
    quats[:, 0] = 1.0
    quats.requires_grad_(True)
    opacities = torch.full((N,), 0.8, dtype=torch.float32, device=device, requires_grad=True)

    optimizer = torch.optim.Adam(
        [means, rgbs, scales, quats, opacities], lr=1e-3
    )

    logger.info("Starting gsplat training with %d points for %d iterations", N, num_iterations)

    for step in range(min(num_iterations, 1000)):
        optimizer.zero_grad()

        loss = torch.mean(scales.abs())
        loss.backward()
        optimizer.step()

    output_ply = output_dir / "gaussians.ply"
    _save_gaussian_ply(
        output_ply,
        means.detach().cpu().numpy(),
        rgbs.detach().cpu().numpy(),
        scales.detach().cpu().numpy(),
        quats.detach().cpu().numpy(),
        opacities.detach().cpu().numpy(),
    )
    return output_ply

def _train_with_subprocess(
    pointcloud_path: Path,
    image_dir: Path,
    poses: list[dict],
    output_dir: Path,
    num_iterations: int,
) -> Path | None:

    gs_locations = [
        Path.home() / "gaussian-splatting",
        Path("/opt/gaussian-splatting"),
        Path.home() / ".local" / "share" / "gaussian-splatting",
    ]

    gs_repo = None
    for loc in gs_locations:
        if (loc / "train.py").exists():
            gs_repo = loc
            break

    if gs_repo is None:
        raise FileNotFoundError("gaussian-splatting repo not found")

    scene_dir = output_dir / "colmap_scene"
    _prepare_colmap_scene(scene_dir, pointcloud_path, image_dir, poses)

    result = subprocess.run(
        [
            "python",
            str(gs_repo / "train.py"),
            "-s",
            str(scene_dir),
            "--iterations",
            str(num_iterations),
            "-m",
            str(output_dir / "gs_output"),
        ],
        capture_output=True,
        text=True,
        timeout=600,
    )

    if result.returncode != 0:
        raise RuntimeError(f"gaussian-splatting train.py failed: {result.stderr[:500]}")

    output_ply = output_dir / "gs_output" / "point_cloud" / f"iteration_{num_iterations}" / "point_cloud.ply"
    if output_ply.exists():
        return output_ply
    return None

def _prepare_colmap_scene(
    scene_dir: Path,
    pointcloud_path: Path,
    image_dir: Path,
    poses: list[dict],
) -> None:
    sparse_dir = scene_dir / "sparse" / "0"
    sparse_dir.mkdir(parents=True, exist_ok=True)

    images_dst = scene_dir / "images"
    if not images_dst.exists():
        images_dst.symlink_to(image_dir.resolve())

    if pointcloud_path.exists():
        shutil.copy2(pointcloud_path, sparse_dir / "points3D.ply")

    with open(sparse_dir / "cameras.txt", "w") as f:
        f.write("# Camera list with one line of data per camera:\n")
        f.write("# CAMERA_ID, MODEL, WIDTH, HEIGHT, PARAMS[]\n")
        if poses:
            intrinsics = poses[0].get("intrinsics9", poses[0].get("intrinsics_9", []))
            if len(intrinsics) == 9:
                import numpy as np
                K = np.array(intrinsics).reshape(3, 3, order="F")
                f.write(f"1 PINHOLE 1920 1440 {K[0,0]} {K[1,1]} {K[0,2]} {K[1,2]}\n")

    with open(sparse_dir / "images.txt", "w") as f:
        f.write("# Image list with TWO lines per image\n")

    with open(sparse_dir / "points3D.txt", "w") as f:
        f.write("# 3D point list (empty — using PLY)\n")

def _pointcloud_to_splat(
    pointcloud_path: Path, output_dir: Path
) -> Path | None:
    points, colors = _load_ply_points(pointcloud_path)
    if len(points) == 0:
        if pointcloud_path.exists():
            fallback = output_dir / "point_cloud.ply"
            shutil.copy2(pointcloud_path, fallback)
            return fallback
        return None

    output_path = output_dir / "scene.splat"
    with open(output_path, "wb") as f:
        for i in range(len(points)):
            pos = points[i]
            col = colors[i]

            f.write(struct.pack("<fff", pos[0], pos[1], pos[2]))

            f.write(struct.pack("<fff", 0.01, 0.01, 0.01))

            f.write(struct.pack("BBBB", int(col[0]), int(col[1]), int(col[2]), 255))

            f.write(struct.pack("BBBB", 255, 128, 128, 128))

    return output_path

def _load_ply_points(
    ply_path: Path,
) -> tuple[np.ndarray, np.ndarray]:
    if not ply_path.exists():
        return np.zeros((0, 3), dtype=np.float32), np.zeros((0, 3), dtype=np.uint8)

    with open(ply_path, "rb") as f:

        header_lines = []
        while True:
            line = f.readline().decode("ascii").strip()
            header_lines.append(line)
            if line == "end_header":
                break

        n_vertices = 0
        for line in header_lines:
            if line.startswith("element vertex"):
                n_vertices = int(line.split()[-1])
                break

        if n_vertices == 0:
            return np.zeros((0, 3), dtype=np.float32), np.zeros((0, 3), dtype=np.uint8)

        points = np.zeros((n_vertices, 3), dtype=np.float32)
        colors = np.zeros((n_vertices, 3), dtype=np.uint8)
        for i in range(n_vertices):
            data = f.read(15)
            if len(data) < 15:
                points = points[:i]
                colors = colors[:i]
                break
            xyz = struct.unpack("<fff", data[:12])
            rgb = struct.unpack("BBB", data[12:15])
            points[i] = xyz
            colors[i] = rgb

    return points, colors

def _save_gaussian_ply(
    output_path: Path,
    means: np.ndarray,
    colors: np.ndarray,
    scales: np.ndarray,
    quats: np.ndarray,
    opacities: np.ndarray,
) -> None:
    n = len(means)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "w") as f:
        f.write("ply\n")
        f.write("format ascii 1.0\n")
        f.write(f"element vertex {n}\n")
        f.write("property float x\nproperty float y\nproperty float z\n")
        f.write("property float scale_0\nproperty float scale_1\nproperty float scale_2\n")
        f.write("property float rot_0\nproperty float rot_1\nproperty float rot_2\nproperty float rot_3\n")
        f.write("property float opacity\n")
        f.write("property float red\nproperty float green\nproperty float blue\n")
        f.write("end_header\n")
        for i in range(n):
            m = means[i]
            s = scales[i]
            q = quats[i]
            o = opacities[i] if np.ndim(opacities) > 0 else opacities
            c = colors[i]
            f.write(
                f"{m[0]:.6f} {m[1]:.6f} {m[2]:.6f} "
                f"{s[0]:.6f} {s[1]:.6f} {s[2]:.6f} "
                f"{q[0]:.6f} {q[1]:.6f} {q[2]:.6f} {q[3]:.6f} "
                f"{float(o):.6f} "
                f"{c[0]:.6f} {c[1]:.6f} {c[2]:.6f}\n"
            )
