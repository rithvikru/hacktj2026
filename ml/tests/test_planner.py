from hacktj2026_ml.planner import build_planner_plan
from hacktj2026_ml.query_contracts import (
    LocalCapabilities,
    PlannerRequest,
    RoomMetadataSummary,
    SceneGraphSummary,
    SignalCapabilities,
)


def make_request(query_text: str, **overrides) -> PlannerRequest:
    payload = {
        "query_text": query_text,
        "room_id": "room-1",
        "session_mode": "live",
        "backend_available": True,
        "signal_capabilities": SignalCapabilities(),
        "local_capabilities": LocalCapabilities(
            local_accelerator_available=True,
            supported_labels=["wallet", "tv remote"],
        ),
        "scene_graph_summary": SceneGraphSummary(),
        "room_metadata_summary": RoomMetadataSummary(),
    }
    payload.update(overrides)
    return PlannerRequest(**payload)


def test_planner_preserves_attributes_and_relations():
    plan = build_planner_plan(make_request("Where is my black wallet near the bed?"))

    assert plan.intent == "findObject"
    assert plan.target_phrase == "black wallet"
    assert plan.canonical_query_label == "black wallet"
    assert plan.attributes == ["black"]
    assert [(relation.relation, relation.reference) for relation in plan.relations] == [("near", "bed")]
    assert plan.search_class == "planner_led_open_vocab_visible_search"
    assert plan.executor_order == [
        "backend_open_vocab",
        "local_observation",
        "scene_graph",
        "hidden_inference",
    ]


def test_planner_detects_target_ambiguity():
    plan = build_planner_plan(make_request("where is my charger"))

    assert plan.intent == "findObject"
    assert plan.canonical_query_label == "charger"
    assert len(plan.ambiguities) == 1
    ambiguity = plan.ambiguities[0]
    assert ambiguity.ambiguity_type == "target"
    assert "phone charger" in ambiguity.candidates


def test_planner_uses_room_context_to_canonicalize_remote():
    plan = build_planner_plan(
        make_request(
            "find the remote",
            room_metadata_summary=RoomMetadataSummary(
                prominent_furniture=["TV", "couch"],
                sections=["living room"],
            ),
        )
    )

    assert plan.canonical_query_label == "tv remote"


def test_planner_switches_to_hidden_likelihood_for_likely_queries():
    plan = build_planner_plan(make_request("where are the likely places I left my keys"))

    assert plan.intent == "findLikelyObjectLocation"
    assert plan.search_class == "hidden_object_likelihood_inference"
    assert plan.should_compute_hidden_fallback is True


def test_planner_signal_priority_requires_capability():
    plan = build_planner_plan(
        make_request(
            "find my tagged wallet",
            signal_capabilities=SignalCapabilities(tag_support_available=True),
        )
    )

    assert plan.search_class == "signal_based_localization"
    assert plan.executor_order[0] == "signal"
