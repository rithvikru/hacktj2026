from hacktj2026_ml.query_contracts import ObservationSummary, QueryRequest
from hacktj2026_ml.query_engine import QueryEngine, build_planner_request
from hacktj2026_ml.toolkit import DefaultQueryToolkit


def test_query_engine_prefers_detected_over_last_seen():
    engine = QueryEngine(toolkit=DefaultQueryToolkit())
    request = QueryRequest(
        query_text="where is my wallet",
        frame_refs=["frame-1"],
        recent_observations_summary=[
            ObservationSummary(
                label="wallet",
                confidence=0.65,
                evidence_class="last_seen",
                source="memory.last_seen",
                observed_at="2026-03-07T12:00:00Z",
            )
        ],
    )

    planner_request = build_planner_request("room-1", request)
    response = engine.execute_query(planner_request=planner_request, query_request=request)

    assert response.result_type == "detected"
    assert response.primary_result is not None
    assert response.primary_result.result_type == "detected"
    assert response.primary_result.frame_id == "frame-1"


def test_query_engine_returns_likely_hidden_when_only_hidden_fallback_exists():
    engine = QueryEngine(toolkit=DefaultQueryToolkit())
    request = QueryRequest(
        query_text="where are the likely places I left my wallet",
        recent_observations_summary=[
            ObservationSummary(
                label="wallet",
                confidence=0.72,
                evidence_class="last_seen",
                source="memory.last_seen",
                observed_at="2026-03-07T12:00:00Z",
                world_transform16=[0.0] * 15 + [1.0],
            )
        ],
    )

    planner_request = build_planner_request("room-1", request)
    response = engine.execute_query(planner_request=planner_request, query_request=request)

    assert response.result_type in {"detected", "last_seen", "likely_hidden"}
    assert response.planner_plan.intent == "findLikelyObjectLocation"
    assert response.hypotheses


def test_query_engine_reports_not_found_without_evidence():
    engine = QueryEngine(toolkit=DefaultQueryToolkit())
    request = QueryRequest(query_text="where is my notebook")

    planner_request = build_planner_request("room-1", request)
    response = engine.execute_query(planner_request=planner_request, query_request=request)

    assert response.result_type == "not_found"
    assert response.primary_result is None
    assert response.hypotheses == []
