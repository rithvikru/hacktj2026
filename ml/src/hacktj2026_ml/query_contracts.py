from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


def _to_camel(field_name: str) -> str:
    parts = field_name.split("_")
    return parts[0] + "".join(part.capitalize() for part in parts[1:])


class APIDTOModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=_to_camel,
        populate_by_name=True,
        extra="forbid",
    )


PlannerIntent = Literal[
    "findObject",
    "findLikelyObjectLocation",
    "countObjects",
    "listObjectsInSection",
    "showNearest",
    "showSupportingSurface",
    "showContainedItems",
    "explainWhy",
]
SearchClass = Literal[
    "planner_led_open_vocab_visible_search",
    "local_accelerated_visible_search",
    "last_seen_retrieval",
    "signal_based_localization",
    "hidden_object_likelihood_inference",
]
ExecutorName = Literal[
    "signal",
    "backend_open_vocab",
    "local_observation",
    "scene_graph",
    "hidden_inference",
]
SessionMode = Literal["live", "saved"]
FrameSelectionMode = Literal["live_priority", "saved_priority", "hybrid", "explicit_frame_refs"]
ResultType = Literal["detected", "last_seen", "signal_estimated", "likely_hidden", "not_found"]
HypothesisType = Literal["cooperative", "tagged", "inferred"]
AmbiguityType = Literal["target", "attribute", "relation", "reference"]


class SignalCapabilities(APIDTOModel):
    cooperative_available: bool = False
    tag_support_available: bool = False


class LocalCapabilities(APIDTOModel):
    local_accelerator_available: bool = False
    supported_labels: list[str] = Field(default_factory=list)


class ObservationSummary(APIDTOModel):
    label: str
    confidence: float = Field(ge=0.0, le=1.0)
    observed_at: str | None = None
    evidence_class: ResultType | None = None
    source: str | None = None
    world_transform16: list[float] | None = Field(default=None, min_length=16, max_length=16)


class SceneGraphSummary(APIDTOModel):
    salient_nodes: list[str] = Field(default_factory=list)
    relation_facts: list[str] = Field(default_factory=list)


class RoomMetadataSummary(APIDTOModel):
    room_name: str | None = None
    sections: list[str] = Field(default_factory=list)
    prominent_surfaces: list[str] = Field(default_factory=list)
    prominent_furniture: list[str] = Field(default_factory=list)


class PlannerRelation(APIDTOModel):
    relation: str
    reference: str


class PlannerAmbiguity(APIDTOModel):
    ambiguity_type: AmbiguityType
    candidates: list[str] = Field(min_length=2)
    explanation: str | None = None


class PlannerRequest(APIDTOModel):
    query_text: str
    room_id: str
    session_mode: SessionMode
    backend_available: bool
    signal_capabilities: SignalCapabilities
    local_capabilities: LocalCapabilities
    recent_observations_summary: list[ObservationSummary] = Field(default_factory=list)
    scene_graph_summary: SceneGraphSummary = Field(default_factory=SceneGraphSummary)
    room_metadata_summary: RoomMetadataSummary = Field(default_factory=RoomMetadataSummary)
    voice_transcript_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    prior_query_history: list[str] = Field(default_factory=list)
    object_prototype_catalog: list[str] = Field(default_factory=list)
    user_aliases: dict[str, list[str]] = Field(default_factory=dict)
    recent_hidden_hypotheses: list[str] = Field(default_factory=list)


class PlannerPlan(APIDTOModel):
    query_id: str
    query_text: str
    normalized_query: str
    intent: PlannerIntent
    target_phrase: str
    canonical_query_label: str
    attributes: list[str] = Field(default_factory=list)
    relations: list[PlannerRelation] = Field(default_factory=list)
    search_class: SearchClass
    executor_order: list[ExecutorName] = Field(min_length=1)
    requires_backend: bool
    can_use_local_accelerator: bool
    should_compute_hidden_fallback: bool
    ambiguities: list[PlannerAmbiguity] = Field(default_factory=list)
    notes: list[str] = Field(default_factory=list)


class OpenVocabSearchRequest(APIDTOModel):
    query_text: str
    normalized_query: str
    target_phrase: str
    attributes: list[str] = Field(default_factory=list)
    relations: list[PlannerRelation] = Field(default_factory=list)
    room_id: str
    frame_selection_mode: FrameSelectionMode = "live_priority"
    frame_refs: list[str] = Field(default_factory=list)
    max_candidates: int = Field(default=20, ge=1, le=100)


class OpenVocabCandidateDTO(APIDTOModel):
    id: str
    confidence: float = Field(ge=0.0, le=1.0)
    bbox_xyxy_norm: list[float] = Field(min_length=4, max_length=4)
    mask_ref: str | None = None
    frame_id: str
    world_transform16: list[float] | None = Field(default=None, min_length=16, max_length=16)
    evidence: list[str] = Field(default_factory=list)
    explanation: str


class OpenVocabSearchResponseDTO(APIDTOModel):
    query_text: str
    normalized_query: str
    result_type: Literal["detected", "not_found"]
    model_id: str
    model_version: str
    candidates: list[OpenVocabCandidateDTO] = Field(default_factory=list)


class SearchResultDTO(APIDTOModel):
    id: str
    label: str
    result_type: ResultType
    confidence: float = Field(ge=0.0, le=1.0)
    world_transform16: list[float] | None = Field(default=None, min_length=16, max_length=16)
    bbox_xyxy_norm: list[float] | None = Field(default=None, min_length=4, max_length=4)
    frame_id: str | None = None
    mask_ref: str | None = None
    model_id: str
    model_version: str
    evidence: list[str] = Field(default_factory=list)
    explanation: str
    timestamp: str


class HypothesisDTO(APIDTOModel):
    id: str
    query_label: str
    hypothesis_type: HypothesisType
    rank: int = Field(ge=1)
    confidence: float = Field(ge=0.0, le=1.0)
    world_transform16: list[float] | None = Field(default=None, min_length=16, max_length=16)
    region_id: str | None = None
    support_object_id: str | None = None
    occluder_object_id: str | None = None
    reason_codes: list[str] = Field(default_factory=list)
    explanation: str
    generated_at: str


class QueryRequest(APIDTOModel):
    query_text: str
    session_mode: SessionMode = "live"
    frame_selection_mode: FrameSelectionMode = "live_priority"
    frame_refs: list[str] = Field(default_factory=list)
    voice_transcript_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    signal_capabilities: SignalCapabilities = Field(default_factory=SignalCapabilities)
    local_capabilities: LocalCapabilities = Field(default_factory=LocalCapabilities)
    recent_observations_summary: list[ObservationSummary] = Field(default_factory=list)
    scene_graph_summary: SceneGraphSummary = Field(default_factory=SceneGraphSummary)
    room_metadata_summary: RoomMetadataSummary = Field(default_factory=RoomMetadataSummary)
    prior_query_history: list[str] = Field(default_factory=list)
    object_prototype_catalog: list[str] = Field(default_factory=list)
    user_aliases: dict[str, list[str]] = Field(default_factory=dict)
    recent_hidden_hypotheses: list[str] = Field(default_factory=list)


class QueryResponseDTO(APIDTOModel):
    query_id: str
    query_text: str
    query_label: str
    result_type: ResultType
    primary_result: SearchResultDTO | None = None
    results: list[SearchResultDTO] = Field(default_factory=list)
    hypotheses: list[HypothesisDTO] = Field(default_factory=list)
    explanation: str
    generated_at: str
    planner_plan: PlannerPlan
