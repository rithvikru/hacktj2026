from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import logging

logger = logging.getLogger(__name__)


@dataclass
class Detection:
    image_path: str
    bbox_xyxy_norm: list[float]
    confidence: float
    label: str


_model = None
_processor = None


def _load_model():
    global _model, _processor
    if _model is None:
        import torch
        from transformers import AutoModelForZeroShotObjectDetection, AutoProcessor

        model_id = "IDEA-Research/grounding-dino-tiny"
        _processor = AutoProcessor.from_pretrained(model_id)
        _model = AutoModelForZeroShotObjectDetection.from_pretrained(model_id)
        device = "cuda" if torch.cuda.is_available() else "cpu"
        _model = _model.to(device)
        logger.info("Grounding DINO loaded on %s", device)
    return _model, _processor


def detect(
    image_paths: list[Path],
    text_prompt: str,
    box_threshold: float = 0.25,
    text_threshold: float = 0.25,
    max_prompt_variants: int | None = None,
    max_tiles_per_frame: int | None = None,
) -> list[Detection]:
    from PIL import Image

    model, processor = _load_model()
    device = next(model.parameters()).device
    profile = _prompt_profile(text_prompt)
    detections: list[Detection] = []

    for image_path in image_paths:
        try:
            image = Image.open(image_path).convert("RGB")
        except Exception:
            logger.warning("Failed to open image %s, skipping", image_path)
            continue

        width, height = image.size
        prompt_variants = list(profile["prompt_variants"])
        if max_prompt_variants is not None:
            prompt_variants = prompt_variants[:max_prompt_variants]
        full_threshold = min(box_threshold, profile["full_box_threshold"])
        tile_threshold = min(box_threshold, profile["tile_box_threshold"])

        for prompt_variant in prompt_variants:
            detections.extend(
                _run_detection_pass(
                    image=image,
                    image_path=image_path,
                    prompt_variant=prompt_variant,
                    model=model,
                    processor=processor,
                    device=device,
                    box_threshold=full_threshold,
                    text_threshold=text_threshold,
                )
            )

            if _should_tile(width, height, profile):
                tiles = _iter_tiles(width, height, profile["tile_size"], profile["tile_overlap"])
                if max_tiles_per_frame is not None:
                    tiles = _limit_tiles(tiles, max_tiles_per_frame)
                for tile_bounds in tiles:
                    tile_image = image.crop(tile_bounds)
                    tile_detections = _run_detection_pass(
                        image=tile_image,
                        image_path=image_path,
                        prompt_variant=prompt_variant,
                        model=model,
                        processor=processor,
                        device=device,
                        box_threshold=tile_threshold,
                        text_threshold=text_threshold,
                    )
                    detections.extend(
                        _map_tile_detections_to_full_image(
                            tile_detections,
                            tile_bounds,
                            width,
                            height,
                        )
                    )

    deduped = deduplicate_detections(detections)
    deduped.sort(key=lambda detection: detection.confidence, reverse=True)
    return deduped


def deduplicate_detections(detections: list[Detection], iou_threshold: float = 0.45) -> list[Detection]:
    grouped: dict[str, list[Detection]] = {}
    for detection in detections:
        key = Path(detection.image_path).name
        grouped.setdefault(key, []).append(detection)

    merged: list[Detection] = []
    for group in grouped.values():
        ordered = sorted(group, key=lambda detection: detection.confidence, reverse=True)
        kept: list[Detection] = []
        for candidate in ordered:
            if any(_iou(candidate.bbox_xyxy_norm, existing.bbox_xyxy_norm) >= iou_threshold for existing in kept):
                continue
            kept.append(candidate)
        merged.extend(kept)
    return merged


def _run_detection_pass(
    *,
    image,
    image_path: Path,
    prompt_variant: str,
    model,
    processor,
    device,
    box_threshold: float,
    text_threshold: float,
) -> list[Detection]:
    import torch

    inputs = processor(images=image, text=prompt_variant, return_tensors="pt").to(device)
    with torch.no_grad():
        outputs = model(**inputs)

    results = processor.post_process_grounded_object_detection(
        outputs,
        inputs["input_ids"],
        box_threshold=box_threshold,
        text_threshold=text_threshold,
        target_sizes=[image.size[::-1]],
    )[0]

    width, height = image.size
    detections: list[Detection] = []
    for score, box, label_text in zip(results["scores"], results["boxes"], results["labels"]):
        x1, y1, x2, y2 = box.tolist()
        detections.append(
            Detection(
                image_path=str(image_path),
                bbox_xyxy_norm=[x1 / width, y1 / height, x2 / width, y2 / height],
                confidence=float(score.item()),
                label=str(label_text),
            )
        )
    return detections


def _map_tile_detections_to_full_image(
    detections: list[Detection],
    tile_bounds: tuple[int, int, int, int],
    full_width: int,
    full_height: int,
) -> list[Detection]:
    left, top, right, bottom = tile_bounds
    tile_width = max(right - left, 1)
    tile_height = max(bottom - top, 1)
    mapped: list[Detection] = []

    for detection in detections:
        x1, y1, x2, y2 = detection.bbox_xyxy_norm
        mapped.append(
            Detection(
                image_path=detection.image_path,
                bbox_xyxy_norm=[
                    (left + x1 * tile_width) / full_width,
                    (top + y1 * tile_height) / full_height,
                    (left + x2 * tile_width) / full_width,
                    (top + y2 * tile_height) / full_height,
                ],
                confidence=detection.confidence,
                label=detection.label,
            )
        )
    return mapped


def _iter_tiles(width: int, height: int, tile_size: int, overlap: float) -> list[tuple[int, int, int, int]]:
    step = max(int(tile_size * (1.0 - overlap)), tile_size // 3, 1)
    xs = _tile_starts(width, tile_size, step)
    ys = _tile_starts(height, tile_size, step)
    return [
        (x, y, min(x + tile_size, width), min(y + tile_size, height))
        for y in ys
        for x in xs
    ]


def _limit_tiles(
    tiles: list[tuple[int, int, int, int]],
    max_tiles_per_frame: int,
) -> list[tuple[int, int, int, int]]:
    if max_tiles_per_frame <= 0 or len(tiles) <= max_tiles_per_frame:
        return tiles
    if max_tiles_per_frame == 1:
        return [tiles[0]]

    stride = max((len(tiles) - 1) / max(max_tiles_per_frame - 1, 1), 1.0)
    selected_indices = []
    for index in range(max_tiles_per_frame):
        candidate = round(index * stride)
        candidate = min(candidate, len(tiles) - 1)
        if not selected_indices or candidate != selected_indices[-1]:
            selected_indices.append(candidate)
    if selected_indices[-1] != len(tiles) - 1:
        selected_indices[-1] = len(tiles) - 1
    return [tiles[index] for index in selected_indices]


def _tile_starts(length: int, tile_size: int, step: int) -> list[int]:
    if length <= tile_size:
        return [0]
    starts = list(range(0, max(length - tile_size, 0) + 1, step))
    final_start = max(length - tile_size, 0)
    if starts[-1] != final_start:
        starts.append(final_start)
    return starts


def _should_tile(width: int, height: int, profile: dict[str, object]) -> bool:
    if profile["force_tiles"]:
        return True
    longest_side = max(width, height)
    tile_size = int(profile["tile_size"])
    return longest_side > tile_size


def _prompt_profile(text_prompt: str) -> dict[str, object]:
    prompt = text_prompt.strip().lower()
    prompt_variants: list[str] = []
    seen_variants: set[str] = set()
    _append_prompt_variant(prompt_variants, seen_variants, prompt)
    force_tiles = False
    full_box_threshold = 0.25
    tile_box_threshold = 0.18
    tile_size = 960
    tile_overlap = 0.25

    alias_map = {
        "phone": {"phone", "mobile phone", "smartphone", "iphone"},
        "iphone": {"iphone", "phone", "smartphone", "mobile phone"},
        "smartphone": {"smartphone", "phone", "mobile phone", "iphone"},
        "airpods": {"airpods case", "earbuds case", "charging case", "small earbuds case"},
        "airpods case": {"airpods case", "earbuds case", "charging case", "small earbuds case"},
        "earbuds": {"earbuds case", "airpods case", "charging case"},
        "water bottle": {"water bottle", "plastic bottle", "bottle"},
        "bottle": {"bottle", "water bottle", "plastic bottle"},
        "coke can": {"coke can", "coca cola can", "soda can", "drink can", "aluminum can"},
        "soda can": {"soda can", "drink can", "aluminum can", "coke can"},
        "drink can": {"drink can", "soda can", "aluminum can", "coke can"},
        "can": {"can", "drink can", "soda can", "aluminum can"},
        "pringles": {"pringles can", "chips can", "snack can", "cylindrical can"},
        "pringles can": {"pringles can", "chips can", "snack can", "cylindrical can"},
        "wallet": {"wallet", "billfold", "small wallet"},
        "glasses": {"glasses", "eyeglasses", "spectacles"},
        "keys": {"keys", "keychain", "car keys"},
        "charger": {"charger", "charging cable", "power adapter"},
    }

    for token, variants in alias_map.items():
        if token in prompt:
            for variant in variants:
                _append_prompt_variant(prompt_variants, seen_variants, variant)

    small_object_tokens = {
        "phone",
        "iphone",
        "smartphone",
        "airpods",
        "airpods case",
        "earbuds",
        "charger",
        "keys",
        "wallet",
        "glasses",
        "bottle",
        "water bottle",
        "can",
        "coke can",
        "soda can",
        "drink can",
        "pringles",
        "pringles can",
    }
    if any(token in prompt for token in small_object_tokens):
        force_tiles = True
        full_box_threshold = 0.22
        tile_box_threshold = 0.12
        tile_size = 768
        tile_overlap = 0.35

    return {
        "prompt_variants": prompt_variants,
        "force_tiles": force_tiles,
        "full_box_threshold": full_box_threshold,
        "tile_box_threshold": tile_box_threshold,
        "tile_size": tile_size,
        "tile_overlap": tile_overlap,
    }


def _append_prompt_variant(prompt_variants: list[str], seen_variants: set[str], variant: str) -> None:
    normalized = variant.strip().lower()
    if not normalized or normalized in seen_variants:
        return
    prompt_variants.append(normalized)
    seen_variants.add(normalized)


def _iou(box_a: list[float], box_b: list[float]) -> float:
    ax1, ay1, ax2, ay2 = box_a
    bx1, by1, bx2, by2 = box_b
    ix1 = max(ax1, bx1)
    iy1 = max(ay1, by1)
    ix2 = min(ax2, bx2)
    iy2 = min(ay2, by2)
    inter_w = max(ix2 - ix1, 0.0)
    inter_h = max(iy2 - iy1, 0.0)
    intersection = inter_w * inter_h
    if intersection <= 0:
        return 0.0
    area_a = max(ax2 - ax1, 0.0) * max(ay2 - ay1, 0.0)
    area_b = max(bx2 - bx1, 0.0) * max(by2 - by1, 0.0)
    union = max(area_a + area_b - intersection, 1e-8)
    return intersection / union
