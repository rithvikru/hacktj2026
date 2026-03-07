from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from fastapi import FastAPI
from pydantic import BaseModel, Field

from hacktj2026_ml.contracts import HiddenHypothesisResult
from hacktj2026_ml.query_contracts import (
    FrameSelectionMode,
    HypothesisDTO,
    OpenVocabCandidateDTO,
    OpenVocabSearchRequest,
    OpenVocabSearchResponseDTO,
    PlannerPlan,
    PlannerRelation,
    PlannerRequest,
    QueryRequest,
    QueryResponseDTO,
    SearchResultDTO,
)

class RoomCreateRequest(BaseModel):
    name: str

class FrameBundleRequest(BaseModel):
    bundle_path: str

class FrameBundleAcceptedResponse(BaseModel):
    room_id: str
    bundle_path: str
    status: str
    frame_count: int | None = None
    session_id: str | None = None

class JobAcceptedResponse(BaseModel):
    room_id: str
    job_type: str
    status: str
    job_id: str = Field(default_factory=lambda: str(uuid4()))

app = FastAPI(title="hacktj2026-ml", version="0.1.0")

@app.get("/healthz")
def healthcheck() -> dict[str, str]:
    return {"status": "ok"}

@app.post("/rooms")
def create_room(request: RoomCreateRequest) -> dict[str, str]:
    return {"room_id": str(uuid4()), "name": request.name, "status": "created"}

@app.post("/rooms/{room_id}/frame-bundles", response_model=FrameBundleAcceptedResponse)
def upload_frame_bundle(room_id: str, request: FrameBundleRequest) -> FrameBundleAcceptedResponse:
    return FrameBundleAcceptedResponse(
        room_id=room_id,
        bundle_path=request.bundle_path,
        status="accepted",
    )

@app.post("/rooms/{room_id}/reconstruct", response_model=JobAcceptedResponse)
def reconstruct_room(room_id: str) -> JobAcceptedResponse:
    return JobAcceptedResponse(room_id=room_id, job_type="reconstruct", status="queued")

@app.post("/rooms/{room_id}/index", response_model=JobAcceptedResponse)
def index_room(room_id: str) -> JobAcceptedResponse:
    return JobAcceptedResponse(room_id=room_id, job_type="index", status="queued")

@app.post("/planner/parse", response_model=PlannerPlan)
def parse_query(request: PlannerRequest) -> PlannerPlan:
    return build_planner_plan(
        query_text=request.query_text,
        room_id=request.room_id,
        backend_available=request.backend_available,
    )

@app.post("/rooms/{room_id}/query", response_model=QueryResponseDTO)
def query_room(room_id: str, request: QueryRequest) -> QueryResponseDTO:
    planner_plan = build_planner_plan(
        query_text=request.query_text,
        room_id=room_id,
        backend_available=True,
        frame_selection_mode=request.frame_selection_mode,
    )
    return build_query_response(room_id=room_id, request=request, planner_plan=planner_plan)

@app.post("/rooms/{room_id}/open-vocab-search", response_model=OpenVocabSearchResponseDTO)
def open_vocab_search(room_id: str, request: OpenVocabSearchRequest) -> OpenVocabSearchResponseDTO:
    candidates: list[OpenVocabCandidateDTO] = []
    if request.frame_refs:
        frame_id = request.frame_refs[0]
        candidates.append(
            OpenVocabCandidateDTO(
                id=str(uuid4()),
                confidence=0.58,
                bbox_xyxy_norm=[0.1, 0.1, 0.3, 0.3],
                mask_ref=None,
                frame_id=frame_id,
                world_transform16=None,
                evidence=["backendOpenVocab", "stub"],
                explanation=f"Stub candidate for '{request.target_phrase}' in frame '{frame_id}'.",
            )
        )

    result_type = "detected" if candidates else "not_found"
    return OpenVocabSearchResponseDTO(
        query_text=request.query_text,
        normalized_query=request.normalized_query,
        result_type=result_type,
        model_id="m2.open_vocab.detector",
        model_version="0.1.0",
        candidates=candidates,
    )

@app.get("/rooms/{room_id}/scene-graph")
def scene_graph(room_id: str) -> dict[str, Any]:
    return {"room_id": room_id, "nodes": [], "edges": []}

@app.get("/rooms/{room_id}/hypotheses")
def hypotheses(room_id: str) -> HiddenHypothesisResult:
    return HiddenHypothesisResult(
        result_type="likely_hidden",
        model_id="m7.hidden_ranker",
        model_version="0.1.0",
        query_label="wallet",
        hypotheses=[
            {
                "rank": 1,
                "confidence": 0.66,
                "world_transform16": None,
                "reason_codes": ["near_last_seen", "soft_occluder_present"],
            }
        ],
    )

@app.get("/rooms/{room_id}/assets")
def assets(room_id: str) -> dict[str, Any]:
    return {"room_id": room_id, "assets": []}

def build_planner_plan(
    query_text: str,
    room_id: str,
    backend_available: bool,
    frame_selection_mode: FrameSelectionMode = "live_priority",
) -> PlannerPlan:
    normalized_query = normalize_query(query_text)
    attributes = extract_attributes(normalized_query)
    relations = extract_relations(normalized_query)
    target_phrase = extract_target_phrase(normalized_query)
    query_id = str(uuid4())
    search_class = (
        "planner_led_open_vocab_visible_search"
        if backend_available
        else "last_seen_retrieval"
    )
    executor_order = (
        ["signal", "backend_open_vocab", "local_observation", "scene_graph", "hidden_inference"]
        if backend_available
        else ["signal", "local_observation", "scene_graph", "hidden_inference"]
    )
    notes = [f"Frame selection mode: {frame_selection_mode}."]
    if attributes:
        notes.append("Preserve extracted attributes during grounding and retrieval.")
    if relations:
        notes.append("Use extracted relations during scene-graph filtering and re-ranking.")

    return PlannerPlan(
        query_id=query_id,
        query_text=query_text,
        normalized_query=normalized_query,
        intent="findObject",
        target_phrase=target_phrase,
        canonical_query_label=target_phrase,
        attributes=attributes,
        relations=relations,
        search_class=search_class,
        executor_order=executor_order,
        requires_backend=backend_available,
        can_use_local_accelerator=False,
        should_compute_hidden_fallback=True,
        ambiguities=[],
        notes=notes,
    )

def build_query_response(
    room_id: str,
    request: QueryRequest,
    planner_plan: PlannerPlan,
) -> QueryResponseDTO:
    timestamp = now_iso()
    query_text_lower = request.query_text.lower()

    if "wallet" in query_text_lower:
        primary_result = SearchResultDTO(
            id=str(uuid4()),
            label="wallet",
            result_type="last_seen",
            confidence=0.74,
            world_transform16=None,
            bbox_xyxy_norm=None,
            frame_id=None,
            mask_ref=None,
            model_id="memory.last_seen",
            model_version="1.0.0",
            evidence=["lastSeenMemory", "stub"],
            explanation="Stub result: wallet was last observed in this room.",
            timestamp=timestamp,
        )
        return QueryResponseDTO(
            query_id=planner_plan.query_id,
            query_text=request.query_text,
            query_label=planner_plan.canonical_query_label,
            result_type="last_seen",
            primary_result=primary_result,
            results=[primary_result],
            hypotheses=[],
            explanation="Stub planner response using last-seen memory.",
            generated_at=timestamp,
            planner_plan=planner_plan,
        )

    if "airpods" in query_text_lower or "headphones" in query_text_lower:
        hypothesis = HypothesisDTO(
            id=str(uuid4()),
            query_label=planner_plan.canonical_query_label,
            hypothesis_type="inferred",
            rank=1,
            confidence=0.61,
            world_transform16=None,
            region_id=None,
            support_object_id=None,
            occluder_object_id=None,
            reason_codes=["near_last_seen", "soft_occluder_present"],
            explanation="Stub hypothesis: likely near the most recent soft-occluded region.",
            generated_at=timestamp,
        )
        return QueryResponseDTO(
            query_id=planner_plan.query_id,
            query_text=request.query_text,
            query_label=planner_plan.canonical_query_label,
            result_type="likely_hidden",
            primary_result=None,
            results=[],
            hypotheses=[hypothesis],
            explanation="Stub planner response using hidden-location fallback.",
            generated_at=timestamp,
            planner_plan=planner_plan,
        )

    return QueryResponseDTO(
        query_id=planner_plan.query_id,
        query_text=request.query_text,
        query_label=planner_plan.canonical_query_label,
        result_type="not_found",
        primary_result=None,
        results=[],
        hypotheses=[],
        explanation=f"No stubbed result is available for room '{room_id}'.",
        generated_at=timestamp,
        planner_plan=planner_plan,
    )

def normalize_query(query_text: str) -> str:
    cleaned = " ".join(query_text.strip().lower().replace("?", "").split())
    filler_prefixes = ("where is ", "where are ", "show me ", "find ", "locate ")
    for prefix in filler_prefixes:
        if cleaned.startswith(prefix):
            cleaned = cleaned.removeprefix(prefix).strip()
            break
    return strip_leading_noise(cleaned)

def extract_attributes(normalized_query: str) -> list[str]:
    known_attributes = {"black", "blue", "white", "red", "small", "large", "left", "right"}
    return [token for token in normalized_query.split() if token in known_attributes]

def extract_relations(normalized_query: str) -> list[PlannerRelation]:
    relation_markers = {
        "near": "near",
        "next to": "near",
        "under": "under",
        "inside": "inside",
        "behind": "behind",
        "in front of": "in_front_of",
        "on": "on",
    }
    relations: list[PlannerRelation] = []
    for marker, normalized_relation in relation_markers.items():
        if marker not in normalized_query:
            continue
        reference = strip_leading_noise(normalized_query.split(marker, maxsplit=1)[1].strip())
        if reference:
            relations.append(PlannerRelation(relation=normalized_relation, reference=reference))
            break
    return relations

def build_target_phrase(normalized_query: str, relations: list[PlannerRelation]) -> str:
    if not relations:
        return strip_leading_noise(normalized_query)
    relation = relations[0]
    suffix = f"{relation.relation.replace('_', ' ')} {relation.reference}"
    if normalized_query.endswith(suffix):
        return strip_leading_noise(normalized_query[: -len(suffix)].strip())
    return strip_leading_noise(normalized_query)

def extract_target_phrase(normalized_query: str) -> str:
    relation_markers = (" next to ", " in front of ", " near ", " under ", " inside ", " behind ", " on ")
    for marker in relation_markers:
        if marker in normalized_query:
            return strip_leading_noise(normalized_query.split(marker, maxsplit=1)[0].strip())
    return strip_leading_noise(normalized_query)

def strip_leading_noise(text: str) -> str:
    noise_words = {"my", "the", "a", "an", "please"}
    tokens = text.split()
    while tokens and tokens[0] in noise_words:
        tokens.pop(0)
    return " ".join(tokens)

def now_iso() -> str:
    return datetime.now(UTC).isoformat()
