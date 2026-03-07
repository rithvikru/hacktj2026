from __future__ import annotations

import logging
from pathlib import Path

logger = logging.getLogger(__name__)


async def reconstruct_room(
    room_id: str,
    frame_dir: Path,
    frames: list[dict],
    room_store,
) -> None:
    """Full reconstruction pipeline: validate -> depth -> pointcloud -> 3DGS."""
    import asyncio

    output_dir = Path("data/rooms") / room_id / "reconstruction"
    output_dir.mkdir(parents=True, exist_ok=True)

    room_store.update(room_id, reconstruction_status="processing")

    try:
        # Run CPU/GPU-heavy work in a thread to avoid blocking the event loop
        assets = await asyncio.to_thread(
            _run_pipeline, room_id, frame_dir, frames, output_dir
        )
        room_store.update(
            room_id,
            reconstruction_status="complete",
            reconstruction_assets=assets,
        )
    except Exception as e:
        logger.exception("Reconstruction failed for room %s", room_id)
        room_store.update(
            room_id,
            reconstruction_status="failed",
            reconstruction_assets={"error": str(e)},
        )


def _run_pipeline(
    room_id: str,
    frame_dir: Path,
    frames: list[dict],
    output_dir: Path,
) -> dict:
    """Synchronous pipeline steps."""
    # 1. Validate poses
    from reconstruction.pose_validation.validate_poses import validate_poses

    report = validate_poses(frames)
    logger.info(
        "Pose validation: %d/%d valid, %d jumps, %d warnings",
        report.valid_frames,
        report.total_frames,
        report.pose_jump_count,
        len(report.warnings),
    )

    # 2. Depth estimation
    from reconstruction.da3.run_pipeline import estimate_depth

    image_paths = []
    for f in frames:
        img_name = f.get("imagePath", f.get("image_path", ""))
        if img_name:
            p = frame_dir / img_name
            if p.exists():
                image_paths.append(p)

    if not image_paths:
        raise ValueError("No valid images found in frame bundle")

    arkit_depth_dir = frame_dir / "depth"
    depth_results = estimate_depth(
        image_paths,
        arkit_depth_dir=arkit_depth_dir if arkit_depth_dir.is_dir() else None,
    )
    logger.info("Depth estimation complete: %d results", len(depth_results))

    # 3. Point cloud generation
    from reconstruction.pointcloud.generate import generate_pointcloud, save_ply

    pc = generate_pointcloud(depth_results, frames, frame_dir)
    ply_path = output_dir / "pointcloud.ply"
    save_ply(pc, ply_path)
    logger.info("Point cloud saved: %d points", len(pc.points))

    # 4. 3DGS training
    from reconstruction.gaussian.export_scene import train_gaussians

    splat_path = train_gaussians(ply_path, frame_dir, frames, output_dir)

    assets = {"pointCloudURL": f"/rooms/{room_id}/assets/pointcloud.ply"}
    if splat_path and splat_path.exists():
        assets["splatURL"] = f"/rooms/{room_id}/assets/{splat_path.name}"

    return assets
