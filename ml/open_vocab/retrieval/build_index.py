from __future__ import annotations

import logging
from dataclasses import dataclass

import numpy as np

logger = logging.getLogger(__name__)


@dataclass
class RetrievalResult:
    detection_idx: int
    similarity: float
    label: str
    bbox_xyxy_norm: list[float]
    image_path: str


_clip_model = None
_clip_preprocess = None
_clip_tokenizer = None


def _load_clip():
    global _clip_model, _clip_preprocess, _clip_tokenizer
    if _clip_model is None:
        import open_clip
        import torch

        device = "cuda" if torch.cuda.is_available() else "cpu"
        _clip_model, _, _clip_preprocess = open_clip.create_model_and_transforms(
            "ViT-L-14", pretrained="openai", device=device
        )
        _clip_tokenizer = open_clip.get_tokenizer("ViT-L-14")
        _clip_model.eval()
        logger.info("OpenCLIP ViT-L-14 loaded on %s", device)
    return _clip_model, _clip_preprocess, _clip_tokenizer


@dataclass
class _DetectionMeta:
    idx: int
    label: str
    bbox_xyxy_norm: list[float]
    image_path: str


def build_index(
    detections: list, images: dict[str, np.ndarray]
) -> tuple[object, np.ndarray, list[_DetectionMeta]]:
    """Build FAISS index from detection crops using OpenCLIP.

    Args:
        detections: list of Detection objects (from run_grounding)
        images: dict mapping image_path -> HxWxC numpy array (RGB)

    Returns:
        (faiss_index, embeddings_array, metadata_list)
    """
    import faiss
    import torch
    from PIL import Image

    model, preprocess, _ = _load_clip()
    device = next(model.parameters()).device

    embeddings = []
    metadata = []

    for i, det in enumerate(detections):
        img = images.get(det.image_path)
        if img is None:
            continue

        h, w = img.shape[:2]
        x1, y1, x2, y2 = det.bbox_xyxy_norm
        crop = img[int(y1 * h) : int(y2 * h), int(x1 * w) : int(x2 * w)]
        if crop.size == 0:
            continue

        pil_crop = Image.fromarray(crop)
        tensor = preprocess(pil_crop).unsqueeze(0).to(device)

        with torch.no_grad():
            feat = model.encode_image(tensor)
            feat = feat / feat.norm(dim=-1, keepdim=True)

        embeddings.append(feat.cpu().numpy().flatten())
        metadata.append(
            _DetectionMeta(
                idx=i, label=det.label, bbox_xyxy_norm=det.bbox_xyxy_norm, image_path=det.image_path
            )
        )

    if not embeddings:
        dim = 768  # ViT-L-14
        index = faiss.IndexFlatIP(dim)
        return index, np.empty((0, dim), dtype=np.float32), []

    emb_array = np.stack(embeddings).astype(np.float32)
    faiss.normalize_L2(emb_array)

    index = faiss.IndexFlatIP(emb_array.shape[1])
    index.add(emb_array)

    return index, emb_array, metadata


def query_index(
    index,
    embeddings: np.ndarray,
    metadata: list[_DetectionMeta],
    text_query: str,
    top_k: int = 5,
) -> list[RetrievalResult]:
    """Query the FAISS index with a text prompt. Returns top-k results by similarity."""
    import faiss
    import torch

    if index.ntotal == 0:
        return []

    model, _, tokenizer = _load_clip()
    device = next(model.parameters()).device

    tokens = tokenizer([text_query]).to(device)
    with torch.no_grad():
        text_feat = model.encode_text(tokens)
        text_feat = text_feat / text_feat.norm(dim=-1, keepdim=True)

    query_vec = text_feat.cpu().numpy().astype(np.float32)
    faiss.normalize_L2(query_vec)

    k = min(top_k, index.ntotal)
    scores, indices = index.search(query_vec, k)

    results = []
    for score, idx in zip(scores[0], indices[0]):
        if idx < 0:
            continue
        meta = metadata[idx]
        results.append(
            RetrievalResult(
                detection_idx=meta.idx,
                similarity=float(score),
                label=meta.label,
                bbox_xyxy_norm=meta.bbox_xyxy_norm,
                image_path=meta.image_path,
            )
        )

    return results
