from __future__ import annotations

import logging
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
    image_paths: list[Path],
    arkit_depth_dir: Path | None = None,
) -> list[DepthResult]:
    """Estimate metric depth for each image.

    Uses ARKit LiDAR depth for scale alignment if available.
    """
    pipe = _load_pipeline()
    results = []

    for img_path in image_paths:
        if not img_path.exists():
            logger.warning("Image not found, skipping: %s", img_path)
            continue

        image = Image.open(img_path).convert("RGB")
        output = pipe(image)
        depth = np.array(output["depth"], dtype=np.float32)

        # If ARKit depth is available, use it for metric scale alignment
        if arkit_depth_dir:
            arkit_depth_path = arkit_depth_dir / f"{img_path.stem}_depth.png"
            if arkit_depth_path.exists():
                depth = _align_to_arkit_depth(depth, arkit_depth_path)

        results.append(
            DepthResult(
                image_path=str(img_path),
                depth_map=depth,
                original_size=image.size,
            )
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
