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
_embedding_cache: dict[tuple[str, str, tuple[int, int, int, int]], np.ndarray] = {}
_EMBEDDING_CACHE_LIMIT = 20_000

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
    detections: list,
    images: dict[str, np.ndarray],
    cache_namespace: str | None = None,
) -> tuple[object, np.ndarray, list[_DetectionMeta]]:
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

        crop, crop_bounds = _crop_with_context(img, det.bbox_xyxy_norm)
        if crop.size == 0:
            continue

        cache_key = _embedding_cache_key(cache_namespace, det.image_path, crop_bounds)
        cached_embedding = _embedding_cache.get(cache_key)
        if cached_embedding is None:
            pil_crop = Image.fromarray(crop)
            tensor = preprocess(pil_crop).unsqueeze(0).to(device)

            with torch.no_grad():
                feat = model.encode_image(tensor)
                feat = feat / feat.norm(dim=-1, keepdim=True)

            cached_embedding = feat.cpu().numpy().flatten().astype(np.float32)
            _store_embedding(cache_key, cached_embedding)

        embeddings.append(cached_embedding)
        metadata.append(
            _DetectionMeta(
                idx=i, label=det.label, bbox_xyxy_norm=det.bbox_xyxy_norm, image_path=det.image_path
            )
        )

    if not embeddings:
        dim = 768
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

def _crop_with_context(
    image: np.ndarray,
    bbox_xyxy_norm: list[float],
) -> tuple[np.ndarray, tuple[int, int, int, int]]:
    h, w = image.shape[:2]
    x1, y1, x2, y2 = bbox_xyxy_norm

    bw = max(x2 - x1, 1e-6)
    bh = max(y2 - y1, 1e-6)
    area = bw * bh
    pad_scale = 0.35 if area < 0.03 else 0.18

    px1 = max(int((x1 - bw * pad_scale) * w), 0)
    py1 = max(int((y1 - bh * pad_scale) * h), 0)
    px2 = min(int((x2 + bw * pad_scale) * w), w)
    py2 = min(int((y2 + bh * pad_scale) * h), h)

    if px2 <= px1 or py2 <= py1:
        px1 = max(int(x1 * w), 0)
        py1 = max(int(y1 * h), 0)
        px2 = min(int(x2 * w), w)
        py2 = min(int(y2 * h), h)

    return image[py1:py2, px1:px2], (px1, py1, px2, py2)

def _embedding_cache_key(
    namespace: str | None,
    image_path: str,
    crop_bounds: tuple[int, int, int, int],
) -> tuple[str, str, tuple[int, int, int, int]]:
    return (namespace or "", image_path, crop_bounds)

def _store_embedding(
    cache_key: tuple[str, str, tuple[int, int, int, int]],
    embedding: np.ndarray,
) -> None:
    if len(_embedding_cache) >= _EMBEDDING_CACHE_LIMIT:
        _embedding_cache.clear()
    _embedding_cache[cache_key] = embedding
