from __future__ import annotations

from typing import Any
from uuid import uuid4

from fastapi import FastAPI
from pydantic import Field

from hacktj2026_ml.query_contracts import (
    APIDTOModel,
    OpenVocabSearchRequest,
    OpenVocabSearchResponseDTO,
    PlannerPlan,
    PlannerRequest,
    QueryRequest,
    QueryResponseDTO,
)
from hacktj2026_ml.query_engine import QueryEngine, build_planner_request
from hacktj2026_ml.toolkit import DefaultQueryToolkit

class RoomCreateRequest(APIDTOModel):
    name: str
    metadata: dict[str, Any] = Field(default_factory=dict)

class RoomCreateResponse(APIDTOModel):
    room_id: str
    name: str
    status: str

class FrameBundleAcceptedResponse(APIDTOModel):
    room_id: str
    bundle_id: str
    status: str
    frame_count: int | None = None
    session_id: str | None = None

class JobAcceptedResponse(APIDTOModel):
    room_id: str
    job_type: str
    status: str
    job_id: str = Field(default_factory=lambda: str(uuid4()))

class SceneGraphNodeDTO(APIDTOModel):
    id: str
    node_type: str
    label: str
    world_transform16: list[float] | None = Field(default=None, min_length=16, max_length=16)
    extent_xyz: list[float] | None = Field(default=None, min_length=3, max_length=3)
    parent_id: str | None = None
    attributes_json: str = "{}"

class SceneGraphEdgeDTO(APIDTOModel):
    id: str
    source_node_id: str
    target_node_id: str
    edge_type: str
    weight: float

class SceneGraphResponseDTO(APIDTOModel):
    room_id: str
    scene_graph_version: int = 0
    nodes: list[SceneGraphNodeDTO] = Field(default_factory=list)
    edges: list[SceneGraphEdgeDTO] = Field(default_factory=list)

class RoomAssetsResponseDTO(APIDTOModel):
    room_id: str
    reconstruction_status: str
    room_usdz_url: str | None = None
    dense_asset_url: str | None = None
    scene_graph_version: int = 0
    frame_bundle_url: str | None = None
    updated_at: str

app = FastAPI(title="hacktj2026-ml", version="0.2.0")
engine = QueryEngine(toolkit=DefaultQueryToolkit())

@app.get("/healthz")
def healthcheck() -> dict[str, str]:
    return {"status": "ok"}

@app.post("/rooms", response_model=RoomCreateResponse)
def create_room(request: RoomCreateRequest) -> RoomCreateResponse:
    return RoomCreateResponse(
        room_id=str(uuid4()),
        name=request.name,
        status="created",
    )

@app.post("/rooms/{room_id}/frame-bundles", response_model=FrameBundleAcceptedResponse)
def upload_frame_bundle(room_id: str) -> FrameBundleAcceptedResponse:
    return FrameBundleAcceptedResponse(
        room_id=room_id,
        bundle_id=str(uuid4()),
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
    return engine.build_plan(request)

@app.post("/rooms/{room_id}/query", response_model=QueryResponseDTO)
def query_room(room_id: str, request: QueryRequest) -> QueryResponseDTO:
    planner_request = build_planner_request(room_id=room_id, request=request)
    return engine.execute_query(planner_request=planner_request, query_request=request)

@app.post("/rooms/{room_id}/open-vocab-search", response_model=OpenVocabSearchResponseDTO)
def open_vocab_search(room_id: str, request: OpenVocabSearchRequest) -> OpenVocabSearchResponseDTO:
    adjusted_request = request.model_copy(update={"room_id": room_id})
    toolkit = engine.toolkit or DefaultQueryToolkit()
    return toolkit.query_open_vocab(adjusted_request)

@app.get("/rooms/{room_id}/scene-graph", response_model=SceneGraphResponseDTO)
def scene_graph(room_id: str) -> SceneGraphResponseDTO:
    return SceneGraphResponseDTO(room_id=room_id)

@app.get("/rooms/{room_id}/hypotheses")
def hypotheses(room_id: str) -> dict[str, Any]:
    return {
        "roomId": room_id,
        "queryLabel": "wallet",
        "resultType": "likelyHidden",
        "modelID": "m7.hidden_ranker",
        "modelVersion": "0.1.0",
        "hypotheses": [],
    }

@app.get("/rooms/{room_id}/assets", response_model=RoomAssetsResponseDTO)
def assets(room_id: str) -> RoomAssetsResponseDTO:
    return RoomAssetsResponseDTO(
        room_id=room_id,
        reconstruction_status="processing",
        room_usdz_url=None,
        dense_asset_url=None,
        scene_graph_version=0,
        frame_bundle_url=None,
        updated_at="2026-03-07T00:00:00Z",
    )
