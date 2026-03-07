from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
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
        candidates: list[OpenVocabCandidateDTO] = []
        for frame_id in request.frame_refs[: request.max_candidates]:
            candidates.append(
                OpenVocabCandidateDTO(
                    id=str(uuid4()),
                    confidence=0.52,
                    bbox_xyxy_norm=[0.12, 0.16, 0.34, 0.48],
                    mask_ref=None,
                    frame_id=frame_id,
                    world_transform16=None,
                    evidence=["backendOpenVocab", "frameRef"],
                    explanation=f"Candidate for '{request.target_phrase}' in preselected frame '{frame_id}'.",
                )
            )

        return OpenVocabSearchResponseDTO(
            query_text=request.query_text,
            normalized_query=request.normalized_query,
            result_type="detected" if candidates else "not_found",
            model_id="m2.open_vocab.detector",
            model_version="0.1.0",
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
