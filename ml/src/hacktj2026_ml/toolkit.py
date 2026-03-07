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
            model_id="m2.open_vocab.grounding_dino+clip",
            model_version="0.2.0",
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
    """Run the full open-vocab pipeline: Grounding DINO -> SAM2 -> CLIP rerank -> backproject.

    Falls back to dummy results if ML dependencies are not installed.
    """
    try:
        import numpy as np
        from PIL import Image

        from open_vocab.backproject import bbox_center_to_world, make_world_transform_16
        from open_vocab.grounding_dino.run_grounding import detect
        from open_vocab.retrieval.build_index import build_index, query_index
        from open_vocab.sam2.run_segmentation import segment
        from serving.storage.room_store import RoomStore
    except ImportError as exc:
        logger.warning("ML pipeline imports unavailable, returning empty results: %s", exc)
        return []

    store = RoomStore()
    room = store.get(request.room_id)
    if not room or not room.frame_dir:
        logger.info("No frames available for room %s", request.room_id)
        return []

    # Collect image paths from frame_refs or all frames in the room
    image_paths: list[Path] = []
    if request.frame_refs:
        for ref in request.frame_refs:
            p = room.frame_dir / ref
            if p.exists():
                image_paths.append(p)
    else:
        for frame in room.frames:
            filename = frame.get("filename") or frame.get("image")
            if filename:
                p = room.frame_dir / filename
                if p.exists():
                    image_paths.append(p)

    if not image_paths:
        # Try to find any images in the frame directory
        for ext in ("*.jpg", "*.jpeg", "*.png"):
            image_paths.extend(room.frame_dir.glob(ext))

    if not image_paths:
        logger.info("No image files found for room %s", request.room_id)
        return []

    # 1. Grounding DINO detection
    detections = detect(image_paths, request.target_phrase)
    if not detections:
        return []

    # 2. Load images as numpy arrays for downstream steps
    images: dict[str, np.ndarray] = {}
    for det in detections:
        if det.image_path not in images:
            try:
                images[det.image_path] = np.array(Image.open(det.image_path).convert("RGB"))
            except Exception:
                pass

    # 3. Optional SAM 2 mask refinement (per image)
    # We run segment for logging/metrics but use detections for the final result
    for img_path, img_arr in images.items():
        dets_for_img = [d for d in detections if d.image_path == img_path]
        bboxes = [d.bbox_xyxy_norm for d in dets_for_img]
        try:
            segment(img_arr, bboxes)
        except Exception:
            pass  # non-critical

    # 4. CLIP reranking via FAISS
    try:
        index, embeddings, metadata = build_index(detections, images)
        reranked = query_index(index, embeddings, metadata, request.target_phrase, top_k=request.max_candidates)
    except Exception as exc:
        logger.warning("CLIP reranking failed, using raw detections: %s", exc)
        reranked = None

    # 5. Build candidates with optional back-projection
    candidates: list[OpenVocabCandidateDTO] = []

    if reranked:
        for rr in reranked:
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
                    evidence=["backendOpenVocab", "groundingDINO", "clipReranked"],
                    explanation=f"Detected '{rr.label}' with CLIP similarity {rr.similarity:.2f}.",
                )
            )
    else:
        for det in detections[: request.max_candidates]:
            world_t16 = _try_backproject(det, room, images)
            candidates.append(
                OpenVocabCandidateDTO(
                    id=str(uuid4()),
                    confidence=min(max(det.confidence, 0.0), 1.0),
                    bbox_xyxy_norm=det.bbox_xyxy_norm,
                    mask_ref=None,
                    frame_id=Path(det.image_path).name,
                    world_transform16=world_t16,
                    evidence=["backendOpenVocab", "groundingDINO"],
                    explanation=f"Detected '{det.label}' with confidence {det.confidence:.2f}.",
                )
            )

    return candidates


def _try_backproject(det, room, images: dict) -> list[float] | None:
    """Try to back-project a detection to world coordinates using frame metadata."""
    try:
        from open_vocab.backproject import bbox_center_to_world, make_world_transform_16

        # Find frame metadata for this detection
        frame_name = Path(det.image_path).name
        frame_meta = None
        for f in room.frames:
            fname = f.get("filename") or f.get("image", "")
            if fname == frame_name:
                frame_meta = f
                break

        if frame_meta is None:
            return None

        intrinsics = frame_meta.get("intrinsics")
        extrinsics = frame_meta.get("extrinsics") or frame_meta.get("cameraPoseTransform")
        depth = frame_meta.get("estimatedDepth") or frame_meta.get("depth")

        if not intrinsics or not extrinsics or not depth:
            return None

        img = images.get(det.image_path)
        if img is None:
            return None

        h, w = img.shape[:2]
        pos = bbox_center_to_world(det.bbox_xyxy_norm, w, h, float(depth), intrinsics, extrinsics)
        return make_world_transform_16(pos)
    except Exception:
        return None
