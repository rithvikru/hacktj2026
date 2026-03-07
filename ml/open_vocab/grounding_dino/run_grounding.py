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
) -> list[Detection]:
    import torch
    from PIL import Image

    model, processor = _load_model()
    device = next(model.parameters()).device
    detections: list[Detection] = []

    for img_path in image_paths:
        try:
            image = Image.open(img_path).convert("RGB")
        except Exception:
            logger.warning("Failed to open image %s, skipping", img_path)
            continue

        inputs = processor(images=image, text=text_prompt, return_tensors="pt").to(device)

        with torch.no_grad():
            outputs = model(**inputs)

        results = processor.post_process_grounded_object_detection(
            outputs,
            inputs["input_ids"],
            box_threshold=box_threshold,
            text_threshold=text_threshold,
            target_sizes=[image.size[::-1]],
        )[0]

        w, h = image.size
        for score, box, label_text in zip(results["scores"], results["boxes"], results["labels"]):
            x1, y1, x2, y2 = box.tolist()
            detections.append(
                Detection(
                    image_path=str(img_path),
                    bbox_xyxy_norm=[x1 / w, y1 / h, x2 / w, y2 / h],
                    confidence=score.item(),
                    label=label_text,
                )
            )

    detections.sort(key=lambda d: d.confidence, reverse=True)
    return detections
