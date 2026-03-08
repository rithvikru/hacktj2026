from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import json
import logging
import time
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

    await asyncio.to_thread(
        _execute_reconstruction,
        room_id,
        frame_dir,
        frames,
        room_store,
    )


def run_reconstruction_job(room_id: str) -> None:
    from serving.storage.room_store import RoomStore

    room_store = RoomStore()
    room = room_store.get(room_id)
    if room is None:
        raise ValueError(f"Room {room_id} not found")
    if room.frame_dir is None:
        raise ValueError(f"Room {room_id} has no uploaded frame bundle")

    _execute_reconstruction(
        room_id=room_id,
        frame_dir=room.frame_dir,
        frames=room.frames,
        room_store=room_store,
    )


def _execute_reconstruction(
    room_id: str,
    frame_dir: Path,
    frames: list[dict],
    room_store,
) -> None:
    output_dir = Path("data/rooms") / room_id / "reconstruction"
    output_dir.mkdir(parents=True, exist_ok=True)

    room_store.update(room_id, reconstruction_status="processing")

    try:
        def _preview_callback(preview_payload: dict) -> None:
            room_store.update(
                room_id,
                reconstruction_status="processing",
                reconstruction_assets=preview_payload["assets"],
                observations=preview_payload["observations"],
                scene_graph=preview_payload["scene_graph"],
            )

        result = _run_pipeline(
            room_id,
            frame_dir,
            frames,
            output_dir,
            preview_callback=_preview_callback,
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
    except Exception as exc:
        logger.exception("Reconstruction failed for room %s", room_id)
        room_store.update(
            room_id,
            reconstruction_status="failed",
            reconstruction_assets={"error": str(exc)},
        )


def _run_pipeline(
    room_id: str,
    frame_dir: Path,
    frames: list[dict],
    output_dir: Path,
    preview_callback=None,
) -> dict:
    """Synchronous pipeline steps."""
    from serving.storage.frame_bundle import load_manifest

    manifest_path = frame_dir / "manifest.json"
    frame_manifest = load_manifest(manifest_path) if manifest_path.exists() else {}
    stage_durations: dict[str, float] = {}
    pipeline_started_at = time.perf_counter()

    # 1. Validate poses
    from reconstruction.pose_validation.validate_poses import validate_poses

    stage_started_at = time.perf_counter()
    report = validate_poses(frames)
    stage_durations["pose_validation_seconds"] = round(
        time.perf_counter() - stage_started_at,
        3,
    )
    logger.info(
        "Pose validation: %d/%d valid, %d jumps, %d warnings",
        report.valid_frames,
        report.total_frames,
        report.pose_jump_count,
        len(report.warnings),
    )

    # 2. Depth estimation
    from reconstruction.da3.run_pipeline import estimate_depth

    stage_started_at = time.perf_counter()
    depth_results = estimate_depth(frames, frame_dir)
    stage_durations["depth_estimation_seconds"] = round(
        time.perf_counter() - stage_started_at,
        3,
    )
    if not depth_results:
        raise ValueError("No reconstructable frames found in frame bundle")

    arkit_results = sum(1 for result in depth_results if result.source == "arkit")
    logger.info(
        "Depth estimation complete: %d results (%d direct ARKit depth, %d monocular fallback)",
        len(depth_results),
        arkit_results,
        len(depth_results) - arkit_results,
    )

    # 3-4. Point cloud and semantic extraction can overlap.
    from serving.scene_graph.builder import build_scene_graph

    with ThreadPoolExecutor(max_workers=2) as executor:
        pointcloud_future = executor.submit(
            _generate_pointcloud_artifacts,
            depth_results,
            frames,
            frame_dir,
            output_dir,
        )
        semantic_future = executor.submit(
            _build_semantic_artifacts,
            room_id,
            frame_dir,
            frames,
            output_dir,
        )
        pc, ply_path, preview_mesh_path, pointcloud_duration = pointcloud_future.result()

        if preview_callback is not None:
            preview_assets = {
                "pointCloudURL": f"/rooms/{room_id}/assets/pointcloud.ply",
            }
            if preview_mesh_path and preview_mesh_path.exists():
                preview_assets["denseAssetURL"] = f"/rooms/{room_id}/assets/{preview_mesh_path.name}"
                preview_assets["denseAssetKind"] = "low_poly_mesh"
                preview_assets["denseRenderer"] = "scenekit_mesh"
                preview_assets["densePhotorealReady"] = False
                preview_assets["denseTrainingBackend"] = "fast_preview_mesh"

            preview_callback(
                {
                    "assets": preview_assets,
                    "observations": [],
                    "scene_graph": None,
                }
            )

        semantic_result, semantic_duration = semantic_future.result()

    stage_durations["pointcloud_seconds"] = pointcloud_duration
    stage_durations["semantic_scene_seconds"] = semantic_duration
    logger.info("Point cloud saved: %d points", len(pc.points))

    assets = {"pointCloudURL": f"/rooms/{room_id}/assets/pointcloud.ply"}
    if preview_mesh_path and preview_mesh_path.exists():
        assets["denseAssetURL"] = f"/rooms/{room_id}/assets/{preview_mesh_path.name}"
        assets["denseAssetKind"] = "low_poly_mesh"
        assets["denseRenderer"] = "scenekit_mesh"
        assets["densePhotorealReady"] = False
        assets["denseTrainingBackend"] = "fast_preview_mesh"
    semantic_scene_path = output_dir / "semantic_scene.json"
    observations = list(semantic_result["observations"])
    scene_graph = None
    if semantic_scene_path.exists():
        assets["semanticSceneURL"] = f"/rooms/{room_id}/assets/{semantic_scene_path.name}"
        assets["semanticObjectCount"] = len(semantic_result["scene"]["objects"])
    diagnostics = {
        "room_id": room_id,
        "input_frame_count": len(frames),
        "reconstruction_frame_count": len(depth_results),
        "arkit_depth_frame_count": arkit_results,
        "monocular_depth_frame_count": len(depth_results) - arkit_results,
        "point_count": len(pc.points),
        "semantic_object_count": len(semantic_result["scene"]["objects"]),
        "stage_durations": stage_durations,
        "total_duration_seconds": round(time.perf_counter() - pipeline_started_at, 3),
    }
    diagnostics_path = output_dir / "reconstruction_diagnostics.json"
    diagnostics_path.write_text(
        json.dumps(diagnostics, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    assets["reconstructionDiagnosticsURL"] = f"/rooms/{room_id}/assets/{diagnostics_path.name}"
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

    if preview_callback is not None:
        preview_callback(
            {
                "assets": dict(assets),
                "observations": observations,
                "scene_graph": scene_graph,
            }
        )

    # 5. Dense training / export
    from reconstruction.dense.train_splats import train_dense_scene

    try:
        stage_started_at = time.perf_counter()
        dense_result = train_dense_scene(
            room_id=room_id,
            frame_dir=frame_dir,
            frames=frames,
            pointcloud_path=ply_path,
            reconstruction_dir=output_dir,
            frame_manifest=frame_manifest,
        )
        stage_durations["dense_training_seconds"] = round(
            time.perf_counter() - stage_started_at,
            3,
        )
    except Exception:
        logger.exception(
            "Gaussian export failed for room %s; returning point cloud preview only",
            room_id,
        )
        stage_durations["dense_training_seconds"] = round(
            time.perf_counter() - stage_started_at,
            3,
        )
        dense_result = None

    if dense_result:
        assets["denseDatasetManifestURL"] = f"/rooms/{room_id}/assets/{dense_result.dataset_manifest_path.name}"
        assets["denseTransformsURL"] = f"/rooms/{room_id}/assets/{dense_result.transforms_json_path.name}"
        assets["denseDiagnosticsURL"] = f"/rooms/{room_id}/assets/{dense_result.diagnostics_path.name}"

    if (
        dense_result
        and dense_result.asset_path
        and dense_result.asset_path.exists()
        and (dense_result.photoreal_ready or preview_mesh_path is None)
    ):
        assets["denseAssetURL"] = f"/rooms/{room_id}/assets/{dense_result.asset_path.name}"
        assets["splatURL"] = assets["denseAssetURL"]
        assets["denseAssetKind"] = dense_result.asset_kind
        assets["denseRenderer"] = dense_result.renderer
        assets["densePhotorealReady"] = dense_result.photoreal_ready
        assets["denseTrainingBackend"] = dense_result.training_backend

    return {
        **assets,
        "observations": observations,
        "scene_graph": scene_graph,
    }


def _generate_pointcloud_artifacts(
    depth_results: list,
    frames: list[dict],
    frame_dir: Path,
    output_dir: Path,
) -> tuple[object, Path, Path | None, float]:
    from reconstruction.pointcloud.generate import generate_pointcloud, save_ply
    from reconstruction.fast_preview.export_mesh import export_low_poly_preview_mesh

    started_at = time.perf_counter()
    pointcloud = generate_pointcloud(depth_results, frames, frame_dir)
    ply_path = output_dir / "pointcloud.ply"
    save_ply(pointcloud, ply_path)
    preview_mesh_path = export_low_poly_preview_mesh(pointcloud, output_dir)
    duration = round(time.perf_counter() - started_at, 3)
    return pointcloud, ply_path, preview_mesh_path, duration


def _build_semantic_artifacts(
    room_id: str,
    frame_dir: Path,
    frames: list[dict],
    output_dir: Path,
) -> tuple[dict, float]:
    from reconstruction.objects.semantic_scene import build_semantic_scene

    started_at = time.perf_counter()
    semantic_result = build_semantic_scene(
        room_id=room_id,
        frame_dir=frame_dir,
        frames=frames,
        output_dir=output_dir,
    )
    duration = round(time.perf_counter() - started_at, 3)
    return semantic_result, duration
