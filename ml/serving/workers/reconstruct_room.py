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
    """Full reconstruction pipeline: validate -> depth -> pointcloud -> semantic -> dense."""
    import asyncio

    output_dir = Path("data/rooms") / room_id / "reconstruction"
    output_dir.mkdir(parents=True, exist_ok=True)

    room_store.update(room_id, reconstruction_status="processing")

    try:
        # Run CPU/GPU-heavy work in a thread to avoid blocking the event loop
        result = await asyncio.to_thread(
            _run_pipeline, room_id, frame_dir, frames, output_dir
        )
        observations = result.pop("observations", [])
        scene_graph = result.pop("scene_graph", None)
        room_store.update(
            room_id,
            reconstruction_status="complete",
            reconstruction_assets=result,
            observations=observations,
            scene_graph=scene_graph,
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
    from serving.storage.frame_bundle import load_manifest

    manifest_path = frame_dir / "manifest.json"
    frame_manifest = load_manifest(manifest_path) if manifest_path.exists() else {}

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

    depth_results = estimate_depth(frames, frame_dir)
    if not depth_results:
        raise ValueError("No reconstructable frames found in frame bundle")

    arkit_results = sum(1 for result in depth_results if result.source == "arkit")
    logger.info(
        "Depth estimation complete: %d results (%d direct ARKit depth, %d monocular fallback)",
        len(depth_results),
        arkit_results,
        len(depth_results) - arkit_results,
    )

    # 3. Point cloud generation
    from reconstruction.pointcloud.generate import generate_pointcloud, save_ply

    pc = generate_pointcloud(depth_results, frames, frame_dir)
    ply_path = output_dir / "pointcloud.ply"
    save_ply(pc, ply_path)
    logger.info("Point cloud saved: %d points", len(pc.points))

    # 4. Semantic object sidecar
    from reconstruction.objects.semantic_scene import build_semantic_scene
    from serving.scene_graph.builder import build_scene_graph

    semantic_result = build_semantic_scene(
        room_id=room_id,
        frame_dir=frame_dir,
        frames=frames,
        output_dir=output_dir,
    )

    # 5. Dense training / export
    from reconstruction.dense.train_splats import train_dense_scene

    assets = {"pointCloudURL": f"/rooms/{room_id}/assets/pointcloud.ply"}
    try:
        dense_result = train_dense_scene(
            room_id=room_id,
            frame_dir=frame_dir,
            frames=frames,
            pointcloud_path=ply_path,
            reconstruction_dir=output_dir,
            frame_manifest=frame_manifest,
        )
    except Exception:
        logger.exception(
            "Gaussian export failed for room %s; returning point cloud preview only",
            room_id,
        )
        dense_result = None

    if dense_result and dense_result.asset_path and dense_result.asset_path.exists():
        assets["denseAssetURL"] = f"/rooms/{room_id}/assets/{dense_result.asset_path.name}"
        assets["splatURL"] = assets["denseAssetURL"]
        assets["denseAssetKind"] = dense_result.asset_kind
        assets["denseRenderer"] = dense_result.renderer
        assets["densePhotorealReady"] = dense_result.photoreal_ready
        assets["denseTrainingBackend"] = dense_result.training_backend
        assets["denseDatasetManifestURL"] = f"/rooms/{room_id}/assets/{dense_result.dataset_manifest_path.name}"
        assets["denseTransformsURL"] = f"/rooms/{room_id}/assets/{dense_result.transforms_json_path.name}"
        assets["denseDiagnosticsURL"] = f"/rooms/{room_id}/assets/{dense_result.diagnostics_path.name}"
    semantic_scene_path = output_dir / "semantic_scene.json"
    observations = list(semantic_result["observations"])
    scene_graph = None
    if semantic_scene_path.exists():
        assets["semanticSceneURL"] = f"/rooms/{room_id}/assets/{semantic_scene_path.name}"
        assets["semanticObjectCount"] = len(semantic_result["scene"]["objects"])
    room = type(
        "SceneGraphRoom",
        (),
        {
            "room_id": room_id,
            "name": room_id,
            "observations": observations,
            "frames": frames,
        },
    )()
    scene_graph = build_scene_graph(room)

    return {
        **assets,
        "observations": observations,
        "scene_graph": scene_graph,
    }
