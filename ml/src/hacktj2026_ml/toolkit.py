from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Protocol
from uuid import uuid4

from hacktj2026_ml.query_contracts import (
    HypothesisDTO,
    ObservationSummary,
    OpenVocabCandidateDTO,
    OpenVocabSearchRequest,
    OpenVocabSearchResponseDTO,
    PlannerPlan,
    PlannerRequest,
    SearchResultDTO,
)

logger = logging.getLogger(__name__)

INTERACTIVE_OPEN_VOCAB_FRAME_LIMIT = 4
HYBRID_OPEN_VOCAB_FRAME_LIMIT = 12
QUALITY_OPEN_VOCAB_FRAME_LIMIT = 24
OPEN_VOCAB_CLIP_PREFILTER_MULTIPLIER = 3


class QueryToolkit(Protocol):
    def query_signal(self, request: PlannerRequest, plan: PlannerPlan) -> list[SearchResultDTO]: ...

    def query_local_observations(self, request: PlannerRequest, plan: PlannerPlan) -> list[SearchResultDTO]: ...

    def query_open_vocab(self, request: OpenVocabSearchRequest) -> OpenVocabSearchResponseDTO: ...

    def query_scene_graph(self, request: PlannerRequest, plan: PlannerPlan) -> list[SearchResultDTO]: ...

    def query_hidden_hypotheses(self, request: PlannerRequest, plan: PlannerPlan) -> list[HypothesisDTO]: ...


@dataclass(slots=True)
class DefaultQueryToolkit:
    """Spec-aligned default toolkit using only currently available room summaries."""

    def query_signal(self, request: PlannerRequest, plan: PlannerPlan) -> list[SearchResultDTO]:
        return []

    def query_local_observations(self, request: PlannerRequest, plan: PlannerPlan) -> list[SearchResultDTO]:
        matches = [
            summary
            for summary in request.recent_observations_summary
            if observation_matches(plan.canonical_query_label, summary)
        ]
        return [observation_to_result(summary) for summary in sorted(matches, key=sort_observation, reverse=True)]

    def query_open_vocab(self, request: OpenVocabSearchRequest) -> OpenVocabSearchResponseDTO:
        candidates = _run_open_vocab_pipeline(request)
        return OpenVocabSearchResponseDTO(
            query_text=request.query_text,
            normalized_query=request.normalized_query,
            result_type="detected" if candidates else "not_found",
            model_id="m2.open_vocab.grounding_dino+sam2+clip+fusion",
            model_version="0.4.0",
            candidates=candidates,
        )

    def query_scene_graph(self, request: PlannerRequest, plan: PlannerPlan) -> list[SearchResultDTO]:
        if not plan.relations:
            return []

        references = {relation.reference.lower() for relation in plan.relations}
        salient_nodes = {node.lower() for node in request.scene_graph_summary.salient_nodes}
        prominent_furniture = {item.lower() for item in request.room_metadata_summary.prominent_furniture}
        if not (references & (salient_nodes | prominent_furniture)):
            return []

        return [
            SearchResultDTO(
                id=str(uuid4()),
                label=plan.canonical_query_label,
                result_type="last_seen",
                confidence=0.41,
                world_transform16=None,
                bbox_xyxy_norm=None,
                frame_id=None,
                mask_ref=None,
                model_id="scene_graph.relation_lookup",
                model_version="0.1.0",
                evidence=["sceneGraph", "relationConstraint"],
                explanation=f"Room structure contains relation context for '{plan.target_phrase}'.",
                timestamp=now_iso(),
            )
        ]

    def query_hidden_hypotheses(self, request: PlannerRequest, plan: PlannerPlan) -> list[HypothesisDTO]:
        # Try real hidden inference pipeline with scene graph data
        try:
            from hidden_inference.rules.rank import rank_for_query
            from serving.storage.room_store import RoomStore

            store = RoomStore()
            room = store.get(request.room_id)
            if room and room.scene_graph:
                result = rank_for_query(
                    room.scene_graph, room.observations, plan.canonical_query_label
                )
                return [
                    HypothesisDTO(
                        id=str(uuid4()),
                        query_label=plan.canonical_query_label,
                        hypothesis_type="inferred",
                        rank=h.rank,
                        confidence=h.confidence,
                        world_transform16=h.world_transform16,
                        region_id=None,
                        support_object_id=None,
                        occluder_object_id=None,
                        reason_codes=h.reason_codes,
                        explanation=f"Hidden inference rank #{h.rank} for '{plan.canonical_query_label}'.",
                        generated_at=now_iso(),
                    )
                    for h in result.hypotheses
                ]
        except Exception:
            logger.debug("Hidden inference pipeline unavailable, falling back to stub", exc_info=True)

        # Fallback: observation-based stub
        matching_observation = next(
            (
                observation
                for observation in request.recent_observations_summary
                if observation_matches(plan.canonical_query_label, observation)
            ),
            None,
        )
        if matching_observation is None:
            return []

        reason_codes = ["near_last_seen"]
        if plan.relations:
            reason_codes.append("relation_constrained")

        return [
            HypothesisDTO(
                id=str(uuid4()),
                query_label=plan.canonical_query_label,
                hypothesis_type="inferred",
                rank=1,
                confidence=max(min(matching_observation.confidence * 0.75, 0.79), 0.25),
                world_transform16=matching_observation.world_transform16,
                region_id=None,
                support_object_id=None,
                occluder_object_id=None,
                reason_codes=reason_codes,
                explanation=(
                    f"Likely near the last remembered '{matching_observation.label}' observation."
                ),
                generated_at=now_iso(),
            )
        ]


def observation_matches(query_label: str, observation: ObservationSummary) -> bool:
    query_tokens = set(query_label.lower().split())
    label_tokens = set(observation.label.lower().split())
    return bool(query_tokens <= label_tokens or label_tokens <= query_tokens or query_tokens & label_tokens)


def observation_to_result(observation: ObservationSummary) -> SearchResultDTO:
    result_type = observation.evidence_class or "last_seen"
    explanation = (
        f"Matched local room memory for '{observation.label}'."
        if result_type == "last_seen"
        else f"Matched recent visible observation for '{observation.label}'."
    )
    return SearchResultDTO(
        id=str(uuid4()),
        label=observation.label,
        result_type=result_type,
        confidence=observation.confidence,
        world_transform16=observation.world_transform16,
        bbox_xyxy_norm=None,
        frame_id=None,
        mask_ref=None,
        model_id=observation.source or "memory.local_observation",
        model_version="1.0.0",
        evidence=["localObservation", observation.source or "memory"],
        explanation=explanation,
        timestamp=observation.observed_at or now_iso(),
    )


def sort_observation(observation: ObservationSummary) -> tuple[float, str]:
    return (observation.confidence, observation.observed_at or "")


def now_iso() -> str:
    return datetime.now(UTC).isoformat()


def _run_open_vocab_pipeline(request: OpenVocabSearchRequest) -> list[OpenVocabCandidateDTO]:
    """Run the full open-vocab pipeline: Grounding DINO -> SAM2 -> CLIP rerank -> fused 3D grounding.

    Falls back to dummy results if ML dependencies are not installed.
    """
    try:
        from serving.storage.room_store import RoomStore
    except ImportError as exc:
        logger.warning("ML pipeline imports unavailable, returning empty results: %s", exc)
        return []

    store = RoomStore()
    room = store.get(request.room_id)
    if not room or not room.frame_dir:
        logger.info("No frames available for room %s", request.room_id)
        return []

    candidates = _run_open_vocab_pipeline_once(request, room)
    if not _should_escalate_open_vocab_search(
        request=request,
        room=room,
        candidates=candidates,
    ):
        return candidates

    escalated_mode = _next_open_vocab_mode(request.frame_selection_mode)
    if escalated_mode is None:
        return candidates

    logger.info(
        "Escalating open-vocab search for room %s from %s to %s",
        request.room_id,
        request.frame_selection_mode,
        escalated_mode,
    )
    escalated_request = request.model_copy(update={"frame_selection_mode": escalated_mode})
    escalated_candidates = _run_open_vocab_pipeline_once(escalated_request, room)
    if _prefer_escalated_candidates(escalated_candidates, candidates):
        return escalated_candidates
    return candidates


def _run_open_vocab_pipeline_once(
    request: OpenVocabSearchRequest,
    room,
) -> list[OpenVocabCandidateDTO]:
    import numpy as np
    from PIL import Image

    from open_vocab.fusion import fuse_grounded_detections
    from open_vocab.grounding_dino.run_grounding import detect
    from open_vocab.retrieval.build_index import build_index, query_index
    from open_vocab.sam2.run_segmentation import segment

    runtime = _open_vocab_runtime_settings(request)

    image_paths = _select_room_image_paths(
        room_frame_dir=room.frame_dir,
        frames=room.frames,
        frame_selection_mode=request.frame_selection_mode,
        frame_refs=request.frame_refs,
        frame_limit=runtime["frame_limit"],
    )

    if not image_paths:
        # Try to find any images in the frame directory
        for ext in ("*.jpg", "*.jpeg", "*.png"):
            image_paths.extend(room.frame_dir.glob(ext))

    if not image_paths:
        logger.info("No image files found for room %s", request.room_id)
        return []

    # 1. Grounding DINO detection
    detections = detect(
        image_paths,
        request.target_phrase,
        max_prompt_variants=runtime["max_prompt_variants"],
        max_tiles_per_frame=runtime["max_tiles_per_frame"],
    )
    if not detections:
        return []
    detections = detections[: runtime["detection_limit"]]

    # 2. Load images as numpy arrays for downstream steps
    images: dict[str, np.ndarray] = {}
    for det in detections:
        if det.image_path not in images:
            try:
                images[det.image_path] = np.array(Image.open(det.image_path).convert("RGB"))
            except Exception:
                pass

    # 3. CLIP reranking via cached crop embeddings.
    reranked_scores: dict[int, float] = {}
    try:
        index, embeddings, metadata = build_index(
            detections,
            images,
            cache_namespace=request.room_id,
        )
        reranked = query_index(
            index,
            embeddings,
            metadata,
            request.target_phrase,
            top_k=min(
                len(detections),
                max(request.max_candidates * OPEN_VOCAB_CLIP_PREFILTER_MULTIPLIER, runtime["sam2_top_k"]),
            ),
        )
        for item in reranked:
            reranked_scores[item.detection_idx] = item.similarity
    except Exception as exc:
        logger.warning("CLIP reranking failed, using raw detections: %s", exc)
        reranked = None

    selected_detections = _select_open_vocab_candidates(
        detections=detections,
        reranked=reranked,
        sam2_top_k=runtime["sam2_top_k"],
        fallback_top_k=runtime["fallback_top_k"],
    )
    if not selected_detections:
        return []

    remapped_scores = {
        idx: reranked_scores.get(original_idx)
        for idx, original_idx in enumerate(selected_detections.original_indices)
        if original_idx in reranked_scores
    }

    # 4. SAM 2 mask refinement only for the top candidates.
    masks_by_detection_idx: dict[int, object] = {}
    for img_path, img_arr in images.items():
        dets_for_img = [
            (idx, det)
            for idx, det in enumerate(selected_detections.detections)
            if det.image_path == img_path
        ]
        if not dets_for_img:
            continue
        bboxes = [det.bbox_xyxy_norm for _, det in dets_for_img]
        try:
            masks = segment(img_arr, bboxes)
            for (idx, _), mask in zip(dets_for_img, masks):
                masks_by_detection_idx[idx] = mask
        except Exception:
            pass  # non-critical

    # 5. Fuse detections into stable 3D candidates, inspired by Open3DIS-style multi-view lifting.
    fused_candidates = fuse_grounded_detections(
        detections=selected_detections.detections,
        masks_by_detection_idx=masks_by_detection_idx,
        reranked_scores=remapped_scores,
        room=room,
        images=images,
        max_candidates=request.max_candidates,
    )
    if fused_candidates:
        return fused_candidates

    # 6. Fallback to per-frame raw candidates if fused grounding cannot be built.
    candidates: list[OpenVocabCandidateDTO] = []
    if reranked:
        for rr in reranked[: request.max_candidates]:
            if rr.detection_idx >= len(detections):
                continue
            det = detections[rr.detection_idx]
            world_t16 = _try_backproject(det, room, images)
            candidates.append(
                OpenVocabCandidateDTO(
                    id=str(uuid4()),
                    confidence=min(max(rr.similarity, 0.0), 1.0),
                    bbox_xyxy_norm=rr.bbox_xyxy_norm,
                    mask_ref=None,
                    frame_id=Path(rr.image_path).name,
                    world_transform16=world_t16,
                    evidence=["backendOpenVocab", "groundingDINO", "clipReranked", "singleViewFallback"],
                    explanation=f"Detected '{rr.label}' with CLIP similarity {rr.similarity:.2f}.",
                )
            )
    else:
        for det in detections[: min(request.max_candidates, runtime["fallback_top_k"])]:
            world_t16 = _try_backproject(det, room, images)
            candidates.append(
                OpenVocabCandidateDTO(
                    id=str(uuid4()),
                    confidence=min(max(det.confidence, 0.0), 1.0),
                    bbox_xyxy_norm=det.bbox_xyxy_norm,
                    mask_ref=None,
                    frame_id=Path(det.image_path).name,
                    world_transform16=world_t16,
                    evidence=["backendOpenVocab", "groundingDINO", "singleViewFallback"],
                    explanation=f"Detected '{det.label}' with confidence {det.confidence:.2f}.",
                )
            )

    return candidates


@dataclass(slots=True)
class FrameCandidate:
    path: Path
    order_index: int
    timestamp: str
    has_grounding: bool
    has_depth: bool


def _frame_candidates(
    room_frame_dir: Path,
    frames: list[dict],
) -> list[FrameCandidate]:
    candidates: list[FrameCandidate] = []
    for index, frame in enumerate(frames):
        reference = (
            frame.get("image_path")
            or frame.get("imagePath")
            or frame.get("filename")
            or frame.get("image")
        )
        if not reference:
            continue
        path = _resolve_room_file(room_frame_dir, reference)
        if not path.exists():
            continue
        candidates.append(
            FrameCandidate(
                path=path,
                order_index=index,
                timestamp=str(frame.get("timestamp") or frame.get("observedAt") or ""),
                has_grounding=_frame_has_grounding_metadata(frame),
                has_depth=_frame_has_depth(frame),
            )
        )

    candidates.sort(key=lambda candidate: (candidate.timestamp or "", candidate.order_index))
    return candidates


def _frame_has_grounding_metadata(frame: dict) -> bool:
    intrinsics = frame.get("intrinsics9") or frame.get("intrinsics_9") or frame.get("intrinsics")
    extrinsics = (
        frame.get("camera_transform16")
        or frame.get("cameraTransform16")
        or frame.get("cameraPoseTransform")
        or frame.get("extrinsics")
    )
    return isinstance(intrinsics, list) and len(intrinsics) == 9 and isinstance(extrinsics, list) and len(extrinsics) == 16


def _frame_has_depth(frame: dict) -> bool:
    return bool(
        frame.get("depth_path")
        or frame.get("depthPath")
        or frame.get("estimatedDepth")
        or frame.get("depth")
    )


def _preferred_frame_pool(candidates: list[FrameCandidate]) -> list[FrameCandidate]:
    depth_ready = [candidate for candidate in candidates if candidate.has_grounding and candidate.has_depth]
    if depth_ready:
        return depth_ready
    grounding_ready = [candidate for candidate in candidates if candidate.has_grounding]
    if grounding_ready:
        return grounding_ready
    return candidates


def _try_backproject(det, room, images: dict) -> list[float] | None:
    """Try to back-project a detection to world coordinates using frame metadata."""
    try:
        from open_vocab.backproject import bbox_center_to_world, make_world_transform_16

        # Find frame metadata for this detection
        frame_name = Path(det.image_path).name
        frame_meta = None
        for f in room.frames:
            references = [
                f.get("image_path"),
                f.get("imagePath"),
                f.get("filename"),
                f.get("image"),
            ]
            if any(Path(str(reference)).name == frame_name for reference in references if reference):
                frame_meta = f
                break

        if frame_meta is None:
            return None

        intrinsics = frame_meta.get("intrinsics9") or frame_meta.get("intrinsics_9") or frame_meta.get("intrinsics")
        extrinsics = (
            frame_meta.get("camera_transform16")
            or frame_meta.get("cameraTransform16")
            or frame_meta.get("extrinsics")
            or frame_meta.get("cameraPoseTransform")
        )
        depth = frame_meta.get("estimatedDepth") or frame_meta.get("depth")

        if not intrinsics or not extrinsics:
            return None

        img = images.get(det.image_path)
        if img is None:
            return None

        if depth in (None, "", 0):
            depth_path = frame_meta.get("depth_path") or frame_meta.get("depthPath")
            if depth_path:
                depth = _sample_depth_at_bbox_center(
                    bundle_dir=room.frame_dir,
                    depth_reference=depth_path,
                    bbox_xyxy_norm=det.bbox_xyxy_norm,
                )

        if depth in (None, "", 0):
            return None

        h, w = img.shape[:2]
        pos = bbox_center_to_world(det.bbox_xyxy_norm, w, h, float(depth), intrinsics, extrinsics)
        return make_world_transform_16(pos)
    except Exception:
        return None


def _resolve_room_file(bundle_dir: Path, reference: str) -> Path:
    candidate = Path(reference)
    if candidate.is_absolute():
        return candidate
    if (bundle_dir / candidate).exists():
        return bundle_dir / candidate
    return bundle_dir / candidate.name


def _select_room_image_paths(
    *,
    room_frame_dir: Path,
    frames: list[dict],
    frame_selection_mode: str = "saved_priority",
    frame_refs: list[str],
    frame_limit: int,
) -> list[Path]:
    if frame_refs:
        return _dedupe_existing_paths(
            _resolve_room_file(room_frame_dir, ref)
            for ref in frame_refs
        )

    candidates = _frame_candidates(room_frame_dir, frames)
    preferred = _preferred_frame_pool(candidates)
    resolved = [candidate.path for candidate in preferred]
    if len(resolved) <= frame_limit:
        return resolved

    if frame_selection_mode == "live_priority":
        recent = resolved[-frame_limit:]
        logger.info(
            "Using %d most recent geometry-ready room frames for live open-vocab search",
            len(recent),
        )
        return recent

    if frame_selection_mode == "hybrid":
        recent_budget = max(frame_limit // 2, 1)
        recent = resolved[-recent_budget:]
        earlier = resolved[:-recent_budget]
        sampled_earlier = _evenly_sample_paths(earlier, frame_limit - len(recent))
        hybrid = _dedupe_existing_paths([*sampled_earlier, *recent])
        logger.info(
            "Using %d hybrid geometry-ready room frames (%d sampled + %d recent) for open-vocab search",
            len(hybrid),
            len(sampled_earlier),
            len(recent),
        )
        return hybrid[:frame_limit]

    sampled = _evenly_sample_paths(resolved, frame_limit)
    logger.info(
        "Sampling %d/%d room frames for open-vocab search",
        len(sampled),
        len(resolved),
    )
    return sampled


def _should_escalate_open_vocab_search(
    *,
    request: OpenVocabSearchRequest,
    room,
    candidates: list[OpenVocabCandidateDTO],
) -> bool:
    if request.frame_refs:
        return False
    if room.reconstruction_status != "complete":
        return False
    if request.frame_selection_mode not in {"live_priority", "hybrid"}:
        return False
    if not room.frames or len(room.frames) < 12:
        return False
    if not candidates:
        return True
    return not any(candidate.world_transform16 for candidate in candidates)


def _next_open_vocab_mode(frame_selection_mode: str) -> str | None:
    if frame_selection_mode == "live_priority":
        return "saved_priority"
    if frame_selection_mode == "hybrid":
        return "saved_priority"
    return None


def _prefer_escalated_candidates(
    escalated: list[OpenVocabCandidateDTO],
    baseline: list[OpenVocabCandidateDTO],
) -> bool:
    if not escalated:
        return False
    if not baseline:
        return True

    escalated_grounded = sum(1 for candidate in escalated if candidate.world_transform16)
    baseline_grounded = sum(1 for candidate in baseline if candidate.world_transform16)
    if escalated_grounded != baseline_grounded:
        return escalated_grounded > baseline_grounded

    escalated_score = max(candidate.confidence for candidate in escalated)
    baseline_score = max(candidate.confidence for candidate in baseline)
    return escalated_score >= baseline_score


def _dedupe_existing_paths(paths) -> list[Path]:
    deduped: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        if not path.exists() or path in seen:
            continue
        deduped.append(path)
        seen.add(path)
    return deduped


def _evenly_sample_paths(paths: list[Path], limit: int) -> list[Path]:
    if limit <= 0 or not paths:
        return []
    if len(paths) <= limit:
        return list(paths)

    stride = max(len(paths) // limit, 1)
    sampled = list(paths[::stride])
    if len(sampled) > limit:
        sampled = sampled[:limit]
    if sampled and sampled[-1] != paths[-1] and len(sampled) < limit:
        sampled.append(paths[-1])
    elif sampled and sampled[-1] != paths[-1]:
        sampled[-1] = paths[-1]
    return sampled


@dataclass(slots=True)
class SelectedDetections:
    detections: list
    original_indices: list[int]


def _select_open_vocab_candidates(
    *,
    detections: list,
    reranked,
    sam2_top_k: int,
    fallback_top_k: int,
) -> SelectedDetections:
    if reranked:
        ranked_indices: list[int] = []
        for item in reranked:
            if item.detection_idx >= len(detections) or item.detection_idx in ranked_indices:
                continue
            ranked_indices.append(item.detection_idx)
            if len(ranked_indices) >= sam2_top_k:
                break
        if ranked_indices:
            return SelectedDetections(
                detections=[detections[idx] for idx in ranked_indices],
                original_indices=ranked_indices,
            )

    fallback_indices = list(range(min(len(detections), fallback_top_k)))
    return SelectedDetections(
        detections=[detections[idx] for idx in fallback_indices],
        original_indices=fallback_indices,
    )


def _open_vocab_runtime_settings(request: OpenVocabSearchRequest) -> dict[str, int]:
    if request.frame_selection_mode == "live_priority":
        return {
            "frame_limit": INTERACTIVE_OPEN_VOCAB_FRAME_LIMIT,
            "max_prompt_variants": 2,
            "max_tiles_per_frame": 3,
            "detection_limit": 32,
            "sam2_top_k": 4,
            "fallback_top_k": 8,
        }
    if request.frame_selection_mode == "hybrid":
        return {
            "frame_limit": HYBRID_OPEN_VOCAB_FRAME_LIMIT,
            "max_prompt_variants": 3,
            "max_tiles_per_frame": 6,
            "detection_limit": 72,
            "sam2_top_k": 8,
            "fallback_top_k": 12,
        }
    if request.frame_selection_mode == "saved_priority":
        return {
            "frame_limit": QUALITY_OPEN_VOCAB_FRAME_LIMIT,
            "max_prompt_variants": 4,
            "max_tiles_per_frame": 8,
            "detection_limit": 96,
            "sam2_top_k": 12,
            "fallback_top_k": 16,
        }
    return {
        "frame_limit": min(QUALITY_OPEN_VOCAB_FRAME_LIMIT, max(len(request.frame_refs), 1)),
        "max_prompt_variants": 3,
        "max_tiles_per_frame": 6,
        "detection_limit": 72,
        "sam2_top_k": 8,
        "fallback_top_k": 12,
    }


def _sample_depth_at_bbox_center(
    bundle_dir: Path,
    depth_reference: str,
    bbox_xyxy_norm: list[float],
) -> float | None:
    try:
        from PIL import Image
        import numpy as np
    except ImportError:
        return None

    depth_path = _resolve_room_file(bundle_dir, depth_reference)
    if not depth_path.exists():
        return None

    depth_image = np.array(Image.open(depth_path), dtype=np.float32)
    if depth_image.ndim > 2:
        depth_image = depth_image[..., 0]

    height, width = depth_image.shape[:2]
    center_x = min(max(int(((bbox_xyxy_norm[0] + bbox_xyxy_norm[2]) * 0.5) * width), 0), width - 1)
    center_y = min(max(int(((bbox_xyxy_norm[1] + bbox_xyxy_norm[3]) * 0.5) * height), 0), height - 1)
    value = float(depth_image[center_y, center_x])
    if value <= 0:
        return None
    if depth_path.suffix.lower() == ".png":
        return value / 1000.0
    return value
