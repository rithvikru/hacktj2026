from __future__ import annotations

import logging
import math
import os
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)


@dataclass
class DepthResult:
    image_path: str
    depth_map: np.ndarray  # H x W float32, metric depth in meters
    original_size: tuple[int, int]  # (width, height)
    confidence_map: np.ndarray | None = None
    source: str = "arkit"
    frame_id: str | None = None


@dataclass
class ReconstructionFrame:
    frame: dict
    frame_index: int
    image_path: Path
    depth_path: Path | None
    confidence_path: Path | None
    position: np.ndarray
    view_direction: np.ndarray
    valid_depth_coverage: float
    high_confidence_coverage: float
    selection_score: float


MAX_RECONSTRUCTION_FRAMES = int(os.getenv("RECON_MAX_FRAMES", "48"))
MIN_DEPTH_CONFIDENCE = int(os.getenv("RECON_MIN_DEPTH_CONFIDENCE", "1"))
MIN_VALID_DEPTH_COVERAGE = float(os.getenv("RECON_MIN_VALID_DEPTH_COVERAGE", "0.02"))
MIN_DEPTH_METERS = float(os.getenv("RECON_MIN_DEPTH_METERS", "0.1"))
MAX_DEPTH_METERS = float(os.getenv("RECON_MAX_DEPTH_METERS", "8.0"))


_pipe = None


def _load_pipeline():
    global _pipe
    if _pipe is None:
        try:
            import torch
            from transformers import pipeline

            device = "cuda" if torch.cuda.is_available() else "cpu"
            _pipe = pipeline(
                "depth-estimation",
                model="depth-anything/Depth-Anything-V2-Large-hf",
                device=device,
            )
        except ImportError:
            logger.warning(
                "transformers or torch not installed; depth estimation unavailable"
            )
            raise
    return _pipe


def estimate_depth(
    frames: list[dict],
    frame_dir: Path,
    max_frames: int = MAX_RECONSTRUCTION_FRAMES,
) -> list[DepthResult]:
    """Estimate metric depth for reconstruction-selected frames.

    Directly uses uploaded ARKit LiDAR depth whenever it is available.
    Monocular depth is only a fallback for frames without ARKit depth.
    """
    selected_frames = select_reconstruction_frames(
        frames,
        frame_dir,
        max_frames=max_frames,
    )
    if not selected_frames:
        return []

    pipe = None
    results = []
    arkit_count = 0
    monocular_count = 0

    for candidate in selected_frames:
        img_path = candidate.image_path
        if not img_path.exists():
            logger.warning("Image not found, skipping: %s", img_path)
            continue

        with Image.open(img_path) as image:
            original_size = image.size
            if candidate.depth_path and candidate.depth_path.exists():
                results.append(
                    DepthResult(
                        image_path=str(img_path),
                        depth_map=_load_arkit_depth(candidate.depth_path),
                        confidence_map=_load_confidence_map(candidate.confidence_path),
                        original_size=original_size,
                        source="arkit",
                        frame_id=str(
                            candidate.frame.get("frame_id")
                            or candidate.frame.get("id")
                            or ""
                        ),
                    )
                )
                arkit_count += 1
                continue

            if pipe is None:
                pipe = _load_pipeline()

            output = pipe(image.convert("RGB"))
            depth = np.array(output["depth"], dtype=np.float32)
            monocular_count += 1

        results.append(
            DepthResult(
                image_path=str(img_path),
                depth_map=depth,
                original_size=original_size,
                source="monocular",
                frame_id=str(
                    candidate.frame.get("frame_id")
                    or candidate.frame.get("id")
                    or ""
                ),
            )
        )

    logger.info(
        "Selected %d/%d frames for reconstruction (%d direct ARKit depth, %d monocular fallback)",
        len(selected_frames),
        len(frames),
        arkit_count,
        monocular_count,
    )
    return results


def _align_to_arkit_depth(
    predicted_depth: np.ndarray, arkit_depth_path: Path
) -> np.ndarray:
    """Scale predicted depth to match ARKit LiDAR depth (PNG16 in mm)."""
    arkit_img = Image.open(arkit_depth_path)
    arkit_depth = np.array(arkit_img, dtype=np.float32) / 1000.0  # mm to meters

    # Use median ratio for scale alignment (robust to outliers)
    valid = (arkit_depth > 0.1) & (arkit_depth < 10.0)
    if valid.sum() < 100:
        return predicted_depth

    # Resize predicted to match ARKit resolution
    h_ar, w_ar = arkit_depth.shape[:2]
    pred_resized = np.array(
        Image.fromarray(predicted_depth).resize((w_ar, h_ar), Image.BILINEAR)
    )

    ratio = np.median(arkit_depth[valid] / (pred_resized[valid] + 1e-6))
    return predicted_depth * ratio


def select_reconstruction_frames(
    frames: list[dict],
    frame_dir: Path,
    max_frames: int = MAX_RECONSTRUCTION_FRAMES,
) -> list[ReconstructionFrame]:
    """Pick a pose-diverse, depth-backed subset of frames for reconstruction."""
    candidates: list[ReconstructionFrame] = []

    for frame_index, frame in enumerate(frames):
        image_path = _resolve_frame_path(frame, frame_dir, ("image_path", "imagePath", "image", "filename"))
        if image_path is None or not image_path.exists():
            continue

        extrinsics = frame.get("camera_transform16") or frame.get("cameraTransform16")
        intrinsics = frame.get("intrinsics9") or frame.get("intrinsics_9")
        if not isinstance(extrinsics, list) or len(extrinsics) != 16:
            continue
        if not isinstance(intrinsics, list) or len(intrinsics) != 9:
            continue

        transform = np.array(extrinsics, dtype=np.float32).reshape(4, 4, order="F")
        position = transform[:3, 3]
        view_direction = transform[:3, 2]
        view_direction /= np.linalg.norm(view_direction) + 1e-8

        depth_path = _resolve_frame_path(frame, frame_dir, ("depth_path", "depthPath"))
        confidence_path = _resolve_frame_path(
            frame,
            frame_dir,
            ("confidence_map_path", "confidenceMapPath"),
        )
        valid_depth_coverage = 0.0
        high_confidence_coverage = 0.0
        if depth_path and depth_path.exists():
            valid_depth_coverage, high_confidence_coverage = _estimate_depth_coverage(
                depth_path,
                confidence_path,
            )

        selection_score = (
            (2.2 * high_confidence_coverage)
            + (1.4 * valid_depth_coverage)
            + (0.15 if depth_path and depth_path.exists() else 0.0)
        )
        candidates.append(
            ReconstructionFrame(
                frame=frame,
                frame_index=frame_index,
                image_path=image_path,
                depth_path=depth_path if depth_path and depth_path.exists() else None,
                confidence_path=confidence_path if confidence_path and confidence_path.exists() else None,
                position=position,
                view_direction=view_direction,
                valid_depth_coverage=valid_depth_coverage,
                high_confidence_coverage=high_confidence_coverage,
                selection_score=selection_score,
            )
        )

    if not candidates:
        return []

    depth_backed_candidates = [candidate for candidate in candidates if candidate.depth_path]
    if depth_backed_candidates:
        candidates = depth_backed_candidates

    if len(candidates) <= max_frames:
        return sorted(candidates, key=lambda candidate: candidate.frame_index)

    remaining = list(candidates)
    selected = [max(remaining, key=lambda candidate: candidate.selection_score)]
    remaining.remove(selected[0])

    while remaining and len(selected) < max_frames:
        best_index = 0
        best_score = -math.inf
        for index, candidate in enumerate(remaining):
            min_distance = min(
                float(np.linalg.norm(candidate.position - chosen.position))
                for chosen in selected
            )
            min_angle = min(
                _view_angle_degrees(candidate.view_direction, chosen.view_direction)
                for chosen in selected
            )
            diversity_score = (0.65 * min(min_distance, 1.5)) + (0.35 * min(min_angle / 90.0, 1.0))
            redundancy_penalty = 5.0 if min_distance < 0.05 and min_angle < 4.0 else 0.0
            score = candidate.selection_score + diversity_score - redundancy_penalty
            if score > best_score:
                best_score = score
                best_index = index
        selected.append(remaining.pop(best_index))

    return sorted(selected, key=lambda candidate: candidate.frame_index)


def _resolve_frame_path(
    frame: dict,
    frame_dir: Path,
    keys: tuple[str, ...],
) -> Path | None:
    for key in keys:
        reference = frame.get(key)
        if not reference:
            continue
        raw_path = Path(str(reference))
        candidates = []
        if raw_path.is_absolute():
            candidates.append(raw_path)
        else:
            candidates.append(frame_dir / raw_path)
        candidates.append(frame_dir / raw_path.name)
        for candidate in candidates:
            if candidate.exists():
                return candidate
    return None


def _estimate_depth_coverage(
    depth_path: Path,
    confidence_path: Path | None,
) -> tuple[float, float]:
    depth = _load_arkit_depth(depth_path)[::4, ::4]
    valid = (depth > MIN_DEPTH_METERS) & (depth < MAX_DEPTH_METERS)
    if valid.size == 0:
        return 0.0, 0.0

    confidence = _load_confidence_map(confidence_path)
    if confidence is None:
        valid_ratio = float(valid.mean())
        return valid_ratio, valid_ratio

    confidence = confidence[::4, ::4]
    valid_ratio = float((valid & (confidence >= MIN_DEPTH_CONFIDENCE)).mean())
    high_ratio = float((valid & (confidence >= 2)).mean())
    return valid_ratio, high_ratio


def _load_arkit_depth(depth_path: Path) -> np.ndarray:
    return np.array(Image.open(depth_path), dtype=np.float32) / 1000.0


def _load_confidence_map(confidence_path: Path | None) -> np.ndarray | None:
    if confidence_path is None or not confidence_path.exists():
        return None
    return np.array(Image.open(confidence_path), dtype=np.uint8)


def _view_angle_degrees(direction_a: np.ndarray, direction_b: np.ndarray) -> float:
    cosine = float(np.clip(np.dot(direction_a, direction_b), -1.0, 1.0))
    return float(np.degrees(np.arccos(cosine)))
