from __future__ import annotations

import json
import logging
import os
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from reconstruction.dense.posed_dataset import DenseDatasetExport, export_dense_dataset
from reconstruction.gaussian.export_scene import train_gaussians

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class DenseTrainingArtifacts:
    asset_path: Path | None
    asset_kind: str
    renderer: str
    photoreal_ready: bool
    training_backend: str
    dataset_manifest_path: Path
    transforms_json_path: Path
    diagnostics_path: Path


def train_dense_scene(
    room_id: str,
    frame_dir: Path,
    frames: list[dict],
    pointcloud_path: Path,
    reconstruction_dir: Path,
    frame_manifest: dict | None = None,
) -> DenseTrainingArtifacts:
    dataset_export = export_dense_dataset(
        room_id=room_id,
        frame_dir=frame_dir,
        frames=frames,
        reconstruction_dir=reconstruction_dir,
        frame_manifest=frame_manifest,
    )

    diagnostics: dict[str, object] = {
        "room_id": room_id,
        "frame_count": dataset_export.frame_count,
        "dataset_manifest_path": str(dataset_export.manifest_path),
        "transforms_json_path": str(dataset_export.transforms_json_path),
        "training_backend": "fallback_pointcloud",
        "photoreal_ready": False,
        "asset_kind": "pointcloud_fallback",
    }

    asset_path: Path | None = None
    training_backend = "fallback_pointcloud"
    photoreal_ready = False
    asset_kind = "pointcloud_fallback"
    renderer = "pointcloud"
    started_at = time.perf_counter()

    external_command = os.getenv("HACKTJ2026_DENSE_TRAIN_COMMAND")
    if external_command:
        diagnostics["external_command"] = external_command
        try:
            external_started_at = time.perf_counter()
            asset_path = _run_external_dense_training(
                command_template=external_command,
                dataset_export=dataset_export,
                pointcloud_path=pointcloud_path,
                reconstruction_dir=reconstruction_dir,
            )
            diagnostics["external_duration_seconds"] = round(
                time.perf_counter() - external_started_at,
                3,
            )
            if asset_path is not None:
                training_backend = "external_command"
                photoreal_ready = asset_path.suffix.lower() in {".splat", ".ksplat", ".ply"}
                asset_kind = "gaussian_splat" if photoreal_ready else "pointcloud_fallback"
                renderer = "gaussian_splats_web" if photoreal_ready else "pointcloud"
        except Exception as exc:
            logger.warning("External dense training failed: %s", exc)
            diagnostics["external_error"] = str(exc)

    if asset_path is None:
        asset_path = train_gaussians(pointcloud_path, frame_dir, frames, reconstruction_dir)
        if asset_path is not None:
            suffix = asset_path.suffix.lower()
            photoreal_ready = suffix in {".splat", ".ksplat"} and asset_path.name != "scene.splat"
            asset_kind = "gaussian_splat" if photoreal_ready else "pointcloud_fallback"
            renderer = "gaussian_splats_web" if suffix in {".splat", ".ksplat", ".ply"} else "pointcloud"
            training_backend = "gaussian_export"

    diagnostics.update(
        {
            "training_backend": training_backend,
            "photoreal_ready": photoreal_ready,
            "asset_kind": asset_kind,
            "renderer": renderer,
            "asset_path": str(asset_path) if asset_path else None,
            "total_duration_seconds": round(time.perf_counter() - started_at, 3),
        }
    )

    diagnostics_path = reconstruction_dir / "dense_training_diagnostics.json"
    diagnostics_path.write_text(
        json.dumps(diagnostics, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    return DenseTrainingArtifacts(
        asset_path=asset_path,
        asset_kind=asset_kind,
        renderer=renderer,
        photoreal_ready=photoreal_ready,
        training_backend=training_backend,
        dataset_manifest_path=dataset_export.manifest_path,
        transforms_json_path=dataset_export.transforms_json_path,
        diagnostics_path=diagnostics_path,
    )


def _run_external_dense_training(
    command_template: str,
    dataset_export: DenseDatasetExport,
    pointcloud_path: Path,
    reconstruction_dir: Path,
) -> Path | None:
    dataset_dir = dataset_export.dataset_dir.resolve()
    images_dir = dataset_export.images_dir.resolve()
    transforms_json_path = dataset_export.transforms_json_path.resolve()
    pointcloud_path = pointcloud_path.resolve()
    reconstruction_dir = reconstruction_dir.resolve()

    command = command_template.format(
        dataset_dir=str(dataset_dir),
        image_dir=str(images_dir),
        transforms_json=str(transforms_json_path),
        pointcloud_path=str(pointcloud_path),
        output_dir=str(reconstruction_dir),
    )
    result = subprocess.run(
        command,
        cwd=reconstruction_dir,
        shell=True,
        check=False,
        capture_output=True,
        text=True,
        timeout=int(os.getenv("HACKTJ2026_DENSE_TRAIN_TIMEOUT_SECONDS", "3600")),
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "dense trainer failed")

    for candidate in _find_dense_assets(reconstruction_dir):
        return _materialize_reconstruction_asset(candidate, reconstruction_dir)
    return None


def _find_dense_assets(reconstruction_dir: Path) -> list[Path]:
    candidates = []
    for pattern in ("*.ksplat", "*.splat", "*.ply"):
        candidates.extend(reconstruction_dir.rglob(pattern))
    excluded_names = {"pointcloud.ply", "gaussians.ply"}
    return [
        candidate
        for candidate in sorted(candidates)
        if candidate.name not in excluded_names and candidate.is_file()
    ]


def _materialize_reconstruction_asset(asset_path: Path, reconstruction_dir: Path) -> Path:
    if asset_path.parent == reconstruction_dir:
        return asset_path

    target = reconstruction_dir / asset_path.name
    if target.exists():
        return target

    try:
        target.symlink_to(asset_path.resolve())
    except OSError:
        target.write_bytes(asset_path.read_bytes())
    return target
