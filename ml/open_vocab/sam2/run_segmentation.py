from __future__ import annotations

import logging
import os
from dataclasses import dataclass

import numpy as np

logger = logging.getLogger(__name__)


@dataclass
class Mask:
    bbox_xyxy_norm: list[float]
    mask: np.ndarray | None  # H x W binary mask, None if SAM2 unavailable
    area: int
    stability_score: float


_predictor = None
_sam2_available: bool | None = None


def _load_predictor():
    global _predictor, _sam2_available
    if _sam2_available is not None:
        return _predictor

    try:
        sam2_config = _normalized_sam2_config(os.getenv("SAM2_CONFIG_PATH"))
        sam2_checkpoint = os.getenv("SAM2_CHECKPOINT_PATH")
        if not sam2_config or not sam2_checkpoint:
            logger.info(
                "SAM 2 not configured; set SAM2_CONFIG_PATH and SAM2_CHECKPOINT_PATH to enable mask refinement"
            )
            _predictor = None
            _sam2_available = False
            return _predictor

        import torch
        from sam2.build_sam import build_sam2
        from sam2.sam2_image_predictor import SAM2ImagePredictor

        device = "cuda" if torch.cuda.is_available() else "cpu"
        sam2_model = build_sam2(sam2_config, sam2_checkpoint, device=device)
        _predictor = SAM2ImagePredictor(sam2_model)
        _sam2_available = True
        logger.info("SAM 2 loaded on %s", device)
    except Exception as exc:
        logger.warning("SAM 2 not available, falling back to bbox-only masks: %s", exc)
        _predictor = None
        _sam2_available = False

    return _predictor


def _normalized_sam2_config(config_value: str | None) -> str | None:
    if not config_value:
        return None
    marker = "configs/"
    normalized = config_value.replace("\\", "/")
    if marker in normalized:
        return normalized[normalized.index(marker):]
    return config_value


def segment(image: np.ndarray, bboxes_xyxy_norm: list[list[float]]) -> list[Mask]:
    """Refine bounding boxes into masks. Falls back to bbox-only if SAM2 unavailable."""
    if not bboxes_xyxy_norm:
        return []

    h, w = image.shape[:2]
    predictor = _load_predictor()

    if predictor is None or not _sam2_available:
        # Fallback: return bbox-only masks
        masks = []
        for bbox in bboxes_xyxy_norm:
            x1, y1, x2, y2 = bbox
            area = int((x2 - x1) * w * (y2 - y1) * h)
            masks.append(
                Mask(bbox_xyxy_norm=bbox, mask=None, area=max(area, 1), stability_score=0.5)
            )
        return masks

    import torch

    predictor.set_image(image)

    # Convert normalized bboxes to pixel coordinates
    boxes_pixel = []
    for bbox in bboxes_xyxy_norm:
        x1, y1, x2, y2 = bbox
        boxes_pixel.append([x1 * w, y1 * h, x2 * w, y2 * h])

    input_boxes = torch.tensor(boxes_pixel, device=predictor.device)
    masks_out, scores, _ = predictor.predict(
        box=input_boxes,
        multimask_output=False,
    )

    results = []
    for i, bbox in enumerate(bboxes_xyxy_norm):
        mask_arr = masks_out[i, 0].cpu().numpy().astype(bool) if masks_out.ndim == 4 else masks_out[i].cpu().numpy().astype(bool)
        area = int(mask_arr.sum())
        stability = scores[i].item() if scores.ndim == 1 else scores[i, 0].item()
        results.append(
            Mask(bbox_xyxy_norm=bbox, mask=mask_arr, area=max(area, 1), stability_score=stability)
        )

    return results
