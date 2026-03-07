from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime

from hacktj2026_ml.planner import build_planner_plan
from hacktj2026_ml.query_contracts import (
    OpenVocabSearchRequest,
    PlannerPlan,
    PlannerRequest,
    QueryRequest,
    QueryResponseDTO,
    ResultType,
    SearchResultDTO,
)
from hacktj2026_ml.toolkit import DefaultQueryToolkit, QueryToolkit

_RESULT_PRIORITY: dict[ResultType, int] = {
    "detected": 0,
    "signal_estimated": 1,
    "last_seen": 2,
    "likely_hidden": 3,
    "not_found": 4,
}


@dataclass(slots=True)
class QueryEngine:
    toolkit: QueryToolkit | None = None

    def build_plan(self, request: PlannerRequest) -> PlannerPlan:
        return build_planner_plan(request)

    def execute_query(self, planner_request: PlannerRequest, query_request: QueryRequest) -> QueryResponseDTO:
        toolkit = self.toolkit or DefaultQueryToolkit()
        planner_plan = self.build_plan(planner_request)

        results: list[SearchResultDTO] = []
        hypotheses = []

        for executor in planner_plan.executor_order:
            if executor == "signal":
                results.extend(toolkit.query_signal(planner_request, planner_plan))
            elif executor == "backend_open_vocab":
                open_vocab_request = build_open_vocab_request(
                    room_id=planner_request.room_id,
                    plan=planner_plan,
                    query_request=query_request,
                )
                open_vocab_response = toolkit.query_open_vocab(open_vocab_request)
                results.extend(open_vocab_candidates_to_results(open_vocab_response, planner_plan))
            elif executor == "local_observation":
                results.extend(toolkit.query_local_observations(planner_request, planner_plan))
            elif executor == "scene_graph":
                results.extend(toolkit.query_scene_graph(planner_request, planner_plan))
            elif executor == "hidden_inference" and planner_plan.should_compute_hidden_fallback:
                hypotheses.extend(toolkit.query_hidden_hypotheses(planner_request, planner_plan))

        primary_result, result_type = aggregate_primary_result(results, hypotheses)
        explanation = build_response_explanation(primary_result, hypotheses, result_type, planner_plan)

        sorted_results = sorted(
            deduplicate_results(results),
            key=lambda result: (_RESULT_PRIORITY[result.result_type], -result.confidence, result.label),
        )
        return QueryResponseDTO(
            query_id=planner_plan.query_id,
            query_text=query_request.query_text,
            query_label=planner_plan.canonical_query_label,
            result_type=result_type,
            primary_result=primary_result,
            results=sorted_results,
            hypotheses=hypotheses,
            explanation=explanation,
            generated_at=now_iso(),
            planner_plan=planner_plan,
        )


def build_planner_request(room_id: str, request: QueryRequest) -> PlannerRequest:
    return PlannerRequest(
        query_text=request.query_text,
        room_id=room_id,
        session_mode=request.session_mode,
        backend_available=True,
        signal_capabilities=request.signal_capabilities,
        local_capabilities=request.local_capabilities,
        recent_observations_summary=request.recent_observations_summary,
        scene_graph_summary=request.scene_graph_summary,
        room_metadata_summary=request.room_metadata_summary,
        voice_transcript_confidence=request.voice_transcript_confidence,
        prior_query_history=request.prior_query_history,
        object_prototype_catalog=request.object_prototype_catalog,
        user_aliases=request.user_aliases,
        recent_hidden_hypotheses=request.recent_hidden_hypotheses,
    )


def build_open_vocab_request(
    room_id: str,
    plan: PlannerPlan,
    query_request: QueryRequest,
) -> OpenVocabSearchRequest:
    return OpenVocabSearchRequest(
        query_text=plan.query_text,
        normalized_query=plan.normalized_query,
        target_phrase=plan.target_phrase,
        attributes=plan.attributes,
        relations=plan.relations,
        room_id=room_id,
        frame_selection_mode=query_request.frame_selection_mode,
        frame_refs=query_request.frame_refs,
    )


def open_vocab_candidates_to_results(
    response,
    planner_plan: PlannerPlan,
) -> list[SearchResultDTO]:
    results: list[SearchResultDTO] = []
    for candidate in response.candidates:
        results.append(
            SearchResultDTO(
                id=candidate.id,
                label=planner_plan.canonical_query_label,
                result_type="detected",
                confidence=candidate.confidence,
                world_transform16=candidate.world_transform16,
                bbox_xyxy_norm=candidate.bbox_xyxy_norm,
                frame_id=candidate.frame_id,
                mask_ref=candidate.mask_ref,
                model_id=response.model_id,
                model_version=response.model_version,
                evidence=candidate.evidence,
                explanation=candidate.explanation,
                timestamp=now_iso(),
            )
        )
    return results


def aggregate_primary_result(results, hypotheses):
    if results:
        sorted_results = sorted(
            results,
            key=lambda result: (_RESULT_PRIORITY[result.result_type], -result.confidence),
        )
        return sorted_results[0], sorted_results[0].result_type

    if hypotheses:
        return None, "likely_hidden"

    return None, "not_found"


def build_response_explanation(
    primary_result: SearchResultDTO | None,
    hypotheses,
    result_type: ResultType,
    planner_plan: PlannerPlan,
) -> str:
    if primary_result is not None:
        return primary_result.explanation
    if hypotheses:
        top = hypotheses[0]
        return (
            f"No direct match was confirmed for '{planner_plan.canonical_query_label}'. "
            f"Returning likely-hidden hypotheses. Top reason codes: {', '.join(top.reason_codes)}."
        )
    if planner_plan.ambiguities:
        return (
            f"No reliable evidence was found for '{planner_plan.canonical_query_label}'. "
            "The query remains ambiguous, so alternatives were preserved in the plan."
        )
    return f"No matching evidence was found for '{planner_plan.canonical_query_label}'."


def deduplicate_results(results: list[SearchResultDTO]) -> list[SearchResultDTO]:
    deduped: dict[tuple[object, ...], SearchResultDTO] = {}
    for result in results:
        bbox_key = tuple(round(value, 4) for value in result.bbox_xyxy_norm or [])
        world_key = tuple(round(value, 4) for value in result.world_transform16 or [])
        key = (
            result.label,
            result.result_type,
            result.frame_id,
            bbox_key,
            world_key,
            result.mask_ref or result.id,
        )
        current = deduped.get(key)
        if current is None or result.confidence > current.confidence:
            deduped[key] = result
    return list(deduped.values())


def now_iso() -> str:
    return datetime.now(UTC).isoformat()
