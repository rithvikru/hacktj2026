from __future__ import annotations

from dataclasses import dataclass
import base64
import json
import logging
import os
from pathlib import Path
import re
from typing import Any

logger = logging.getLogger(__name__)

GEMINI_API_URL_TEMPLATE = (
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
)
DEFAULT_GEMINI_MODEL_ID = os.getenv("GEMINI_MODEL_ID", "gemini-3-flash-preview")
DEFAULT_MAX_DETECTIONS_PER_IMAGE = max(
    1, int(os.getenv("GEMINI_MAX_DETECTIONS_PER_IMAGE", "16"))
)

@dataclass
class GeminiDetection:
    image_path: str
    bbox_xyxy_norm: list[float]
    confidence: float
    label: str

def detect(
    image_paths: list[Path],
    text_prompt: str,
    box_threshold: float = 0.0,
    text_threshold: float = 0.0,
    max_prompt_variants: int | None = None,
    max_tiles_per_frame: int | None = None,
) -> list[GeminiDetection]:
    del box_threshold, text_threshold, max_prompt_variants, max_tiles_per_frame
    detections: list[GeminiDetection] = []
    for image_path in image_paths:
        detections.extend(_detect_single_image(image_path=image_path, text_prompt=text_prompt))
    return detections

def detect_regions(
    image_path: Path,
    regions_xyxy_norm: list[list[float]],
    text_prompt: str,
    box_threshold: float = 0.0,
    text_threshold: float = 0.0,
    max_prompt_variants: int | None = None,
) -> list[GeminiDetection]:
    del box_threshold, text_threshold, max_prompt_variants
    from PIL import Image

    try:
        image = Image.open(image_path).convert("RGB")
    except Exception:
        logger.warning("Failed to open image %s, skipping Gemini region detection", image_path)
        return []

    width, height = image.size
    detections: list[GeminiDetection] = []
    for region in regions_xyxy_norm:
        crop_bounds = _normalized_region_bounds(region, width, height)
        if crop_bounds is None:
            continue
        crop = image.crop(crop_bounds)
        region_detections = _detect_image_object(
            image_bytes=_image_to_jpeg_bytes(crop),
            image_path=str(image_path),
            text_prompt=text_prompt,
        )
        detections.extend(
            _map_crop_detections_to_full_image(
                region_detections,
                crop_bounds,
                width,
                height,
            )
        )
    return deduplicate_detections(detections)

def deduplicate_detections(
    detections: list[GeminiDetection],
    iou_threshold: float = 0.45,
) -> list[GeminiDetection]:
    grouped: dict[str, list[GeminiDetection]] = {}
    for detection in detections:
        grouped.setdefault(Path(detection.image_path).name, []).append(detection)

    merged: list[GeminiDetection] = []
    for group in grouped.values():
        ordered = sorted(group, key=lambda detection: detection.confidence, reverse=True)
        kept: list[GeminiDetection] = []
        for candidate in ordered:
            if any(_iou(candidate.bbox_xyxy_norm, existing.bbox_xyxy_norm) >= iou_threshold for existing in kept):
                continue
            kept.append(candidate)
        merged.extend(kept)
    return merged

def _detect_single_image(image_path: Path, text_prompt: str) -> list[GeminiDetection]:
    try:
        image_bytes = image_path.read_bytes()
    except Exception:
        logger.warning("Failed to read image %s for Gemini detection", image_path)
        return []
    return _detect_image_object(image_bytes=image_bytes, image_path=str(image_path), text_prompt=text_prompt)

def _detect_image_object(image_bytes: bytes, image_path: str, text_prompt: str) -> list[GeminiDetection]:
    import httpx

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not set")

    model_id = os.getenv("GEMINI_MODEL_ID", DEFAULT_GEMINI_MODEL_ID)
    prompt = _build_detection_prompt(text_prompt)
    payload = {
        "contents": [
            {
                "parts": [
                    {"text": prompt},
                    {
                        "inline_data": {
                            "mime_type": "image/jpeg",
                            "data": base64.b64encode(image_bytes).decode("ascii"),
                        }
                    },
                ]
            }
        ],
        "generationConfig": {
            "responseMimeType": "application/json",
            "temperature": 0.0,
            "topP": 0.1,
            "topK": 1,
        },
    }

    url = f"{GEMINI_API_URL_TEMPLATE.format(model=model_id)}?key={api_key}"
    with httpx.Client(timeout=_gemini_http_timeout()) as client:
        response = client.post(url, json=payload)
        response.raise_for_status()

    detections_json = _extract_json_payload(response.json())
    parsed = _parse_detection_payload(detections_json)
    detections: list[GeminiDetection] = []
    for item in parsed[:DEFAULT_MAX_DETECTIONS_PER_IMAGE]:
        label = str(item.get("label", "")).strip()
        box = _normalize_box(item.get("box_2d") or item.get("box2d") or item.get("bbox"))
        if not label or box is None:
            continue
        detections.append(
            GeminiDetection(
                image_path=image_path,
                bbox_xyxy_norm=box,
                confidence=float(item.get("confidence") or 0.72),
                label=label,
            )
        )
    detections.sort(key=lambda detection: detection.confidence, reverse=True)
    return deduplicate_detections(detections)

def _gemini_http_timeout():
    import httpx

    timeout_seconds = os.getenv("GEMINI_TIMEOUT_SECONDS")
    if timeout_seconds is None or timeout_seconds.strip() == "":

        return httpx.Timeout(connect=20.0, read=None, write=None, pool=None)
    try:
        seconds = float(timeout_seconds)
    except ValueError:
        logger.warning("Invalid GEMINI_TIMEOUT_SECONDS=%r; using no read timeout", timeout_seconds)
        return httpx.Timeout(connect=20.0, read=None, write=None, pool=None)
    if seconds <= 0:
        return httpx.Timeout(connect=20.0, read=None, write=None, pool=None)
    return httpx.Timeout(connect=20.0, read=seconds, write=seconds, pool=seconds)

def _build_detection_prompt(text_prompt: str) -> str:
    return (
        "You are an object detector for an AR room-mapping app.\n"
        f"Find visible objects relevant to this request: {text_prompt!r}.\n"
        "Return ONLY JSON.\n"
        "Return a JSON array of detections. Each detection must be an object with:\n"
        '- "label": short object label\n'
        '- "box_2d": [ymin, xmin, ymax, xmax] normalized to 0..1000\n'
        '- optional "confidence": number from 0..1\n'
        "Rules:\n"
        "- Only include objects clearly visible in the image.\n"
        "- Use one tight box per object instance.\n"
        "- If nothing relevant is visible, return [].\n"
    )

def _extract_json_payload(response_json: dict[str, Any]) -> Any:
    candidates = response_json.get("candidates") or []
    if not candidates:
        return []
    parts = candidates[0].get("content", {}).get("parts", [])
    text = "".join(part.get("text", "") for part in parts if isinstance(part, dict))
    return _parse_json_text(text)

def _parse_json_text(text: str) -> Any:
    stripped = text.strip()
    if not stripped:
        return []
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        pass

    fenced = re.search(r"```(?:json)?\s*(.*?)```", stripped, re.DOTALL | re.IGNORECASE)
    if fenced:
        try:
            return json.loads(fenced.group(1).strip())
        except json.JSONDecodeError:
            pass

    start = stripped.find("[")
    end = stripped.rfind("]")
    if start != -1 and end != -1 and end > start:
        try:
            return json.loads(stripped[start : end + 1])
        except json.JSONDecodeError:
            pass

    start = stripped.find("{")
    end = stripped.rfind("}")
    if start != -1 and end != -1 and end > start:
        try:
            return json.loads(stripped[start : end + 1])
        except json.JSONDecodeError:
            pass

    logger.warning("Gemini returned unparseable detection payload: %s", stripped[:300])
    return []

def _parse_detection_payload(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        for key in ("detections", "objects", "items", "results"):
            value = payload.get(key)
            if isinstance(value, list):
                return [item for item in value if isinstance(item, dict)]
    return []

def _normalize_box(raw_box: Any) -> list[float] | None:
    if not isinstance(raw_box, list) or len(raw_box) != 4:
        return None
    try:
        ymin, xmin, ymax, xmax = [float(value) for value in raw_box]
    except Exception:
        return None
    if max(abs(ymin), abs(xmin), abs(ymax), abs(xmax)) > 1.5:
        ymin /= 1000.0
        xmin /= 1000.0
        ymax /= 1000.0
        xmax /= 1000.0
    ymin = min(max(ymin, 0.0), 1.0)
    xmin = min(max(xmin, 0.0), 1.0)
    ymax = min(max(ymax, 0.0), 1.0)
    xmax = min(max(xmax, 0.0), 1.0)
    if xmax <= xmin or ymax <= ymin:
        return None
    return [xmin, ymin, xmax, ymax]

def _image_to_jpeg_bytes(image) -> bytes:
    from io import BytesIO

    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=95)
    return buffer.getvalue()

def _normalized_region_bounds(
    region_xyxy_norm: list[float],
    image_width: int,
    image_height: int,
) -> tuple[int, int, int, int] | None:
    if len(region_xyxy_norm) != 4:
        return None
    x1 = max(0, min(image_width - 1, int(region_xyxy_norm[0] * image_width)))
    y1 = max(0, min(image_height - 1, int(region_xyxy_norm[1] * image_height)))
    x2 = max(x1 + 1, min(image_width, int(region_xyxy_norm[2] * image_width)))
    y2 = max(y1 + 1, min(image_height, int(region_xyxy_norm[3] * image_height)))
    if x2 <= x1 or y2 <= y1:
        return None
    return (x1, y1, x2, y2)

def _map_crop_detections_to_full_image(
    detections: list[GeminiDetection],
    crop_bounds: tuple[int, int, int, int],
    full_width: int,
    full_height: int,
) -> list[GeminiDetection]:
    left, top, right, bottom = crop_bounds
    crop_width = max(right - left, 1)
    crop_height = max(bottom - top, 1)
    mapped: list[GeminiDetection] = []
    for detection in detections:
        x1, y1, x2, y2 = detection.bbox_xyxy_norm
        mapped.append(
            GeminiDetection(
                image_path=detection.image_path,
                bbox_xyxy_norm=[
                    ((x1 * crop_width) + left) / full_width,
                    ((y1 * crop_height) + top) / full_height,
                    ((x2 * crop_width) + left) / full_width,
                    ((y2 * crop_height) + top) / full_height,
                ],
                confidence=detection.confidence,
                label=detection.label,
            )
        )
    return mapped

def _iou(box_a: list[float], box_b: list[float]) -> float:
    xa1, ya1, xa2, ya2 = box_a
    xb1, yb1, xb2, yb2 = box_b
    inter_x1 = max(xa1, xb1)
    inter_y1 = max(ya1, yb1)
    inter_x2 = min(xa2, xb2)
    inter_y2 = min(ya2, yb2)
    inter_w = max(0.0, inter_x2 - inter_x1)
    inter_h = max(0.0, inter_y2 - inter_y1)
    inter_area = inter_w * inter_h
    if inter_area <= 0:
        return 0.0
    area_a = max(0.0, xa2 - xa1) * max(0.0, ya2 - ya1)
    area_b = max(0.0, xb2 - xb1) * max(0.0, yb2 - yb1)
    union = area_a + area_b - inter_area
    if union <= 0:
        return 0.0
    return inter_area / union
