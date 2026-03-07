from __future__ import annotations

import asyncio
import json
import tempfile
import zipfile
from pathlib import Path
from typing import Any
from uuid import uuid4

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from hacktj2026_ml.chat_contracts import ChatRequestDTO, ChatResponseDTO
from hacktj2026_ml.chat_service import ChatService
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
from serving.scene_graph.builder import build_scene_graph
from serving.storage.home_store import HomeStore
from serving.storage.room_store import RoomStore

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

class HomeCreateRequest(APIDTOModel):
    name: str
    metadata: dict[str, Any] = Field(default_factory=dict)

class HomeAttachRoomRequest(APIDTOModel):
    room_id: str

class HomeSearchRequest(APIDTOModel):
    query_text: str
    current_room_id: str | None = None

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

class SimpleQueryBody(BaseModel):
    query: str | None = None
    query_text: str | None = None

    @property
    def resolved_query(self) -> str:
        return self.query or self.query_text or ""

app = FastAPI(title="hacktj2026-ml", version="0.2.0")
engine = QueryEngine(toolkit=DefaultQueryToolkit())
chat_service = ChatService(query_engine=engine)

@app.get("/healthz")
def healthcheck() -> dict[str, str]:
    return {"status": "ok"}

@app.get("/rooms")
def list_rooms():
    store = RoomStore()
    return [
        {"roomID": r.room_id, "name": r.name, "status": r.reconstruction_status}
        for r in store.list_all()
    ]

@app.post("/rooms")
def create_room(request: RoomCreateRequest):
    store = RoomStore()
    room_id = str(uuid4())
    store.create(room_id, request.name)
    return {"roomID": room_id, "name": request.name, "status": "created"}

@app.get("/homes")
def list_homes():
    store = HomeStore()
    return [
        {"homeID": h.home_id, "name": h.name, "roomCount": len(h.room_ids), "updatedAt": h.updated_at}
        for h in store.list_all()
    ]

@app.post("/homes")
def create_home(request: HomeCreateRequest):
    store = HomeStore()
    home = store.create(request.name, metadata=request.metadata)
    return {"homeID": home.home_id, "name": home.name, "status": "created"}

@app.post("/homes/{home_id}/rooms")
def attach_room_to_home(home_id: str, request: HomeAttachRoomRequest):
    homes = HomeStore()
    rooms = RoomStore()
    if not rooms.get(request.room_id):
        raise HTTPException(404, "Room not found")
    home = homes.attach_room(home_id, request.room_id)
    if not home:
        raise HTTPException(404, "Home not found")
    return {"homeID": home.home_id, "roomIDs": home.room_ids, "status": "updated"}

@app.post("/homes/{home_id}/map/rebuild")
def rebuild_home_map(home_id: str):
    store = HomeStore()
    try:
        return store.rebuild_map(home_id)
    except KeyError:
        raise HTTPException(404, "Home not found") from None

@app.post("/homes/{home_id}/search")
def search_home(home_id: str, request: HomeSearchRequest):
    store = HomeStore()
    try:
        return store.search(home_id, request.query_text, current_room_id=request.current_room_id)
    except KeyError:
        raise HTTPException(404, "Home not found") from None

@app.get("/homes/{home_id}/route")
def route_home(home_id: str, target_room_id: str, current_room_id: str | None = None):
    store = HomeStore()
    try:
        return store.route(home_id, target_room_id=target_room_id, current_room_id=current_room_id)
    except KeyError:
        raise HTTPException(404, "Home not found") from None

@app.get("/homes/{home_id}/memories")
def list_home_memories(home_id: str):
    store = HomeStore()
    try:
        return {
            "homeID": home_id,
            "memories": [
                {
                    "id": memory.id,
                    "label": memory.label,
                    "roomId": memory.room_id,
                    "roomName": memory.room_name,
                    "confidence": memory.confidence,
                    "confidenceState": memory.confidence_state,
                    "recencySeconds": memory.recency_seconds,
                    "memoryFreshness": memory.memory_freshness,
                }
                for memory in store.list_memories(home_id)
            ],
        }
    except KeyError:
        raise HTTPException(404, "Home not found") from None

@app.get("/homes/{home_id}/change-events")
def list_home_change_events(home_id: str):
    store = HomeStore()
    try:
        return {"homeID": home_id, "events": store.change_events(home_id)}
    except KeyError:
        raise HTTPException(404, "Home not found") from None

@app.post("/rooms/{room_id}/frame-bundles")
async def upload_frame_bundle(room_id: str, file: UploadFile = File(...)):
    store = RoomStore()
    room = store.get(room_id)
    if not room:
        raise HTTPException(404, "Room not found")

    data_dir = Path("data/rooms") / room_id / "frames"
    data_dir.mkdir(parents=True, exist_ok=True)

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".zip")
    content = await file.read()
    tmp.write(content)
    tmp.close()

    with zipfile.ZipFile(tmp.name, "r") as zf:
        zf.extractall(data_dir)
    Path(tmp.name).unlink()

    manifest_path = data_dir / "manifest.json"
    frames: list[dict] = []
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        frames = manifest.get("frames", [])

    room.frame_dir = data_dir
    room.frames = frames

    room.scene_graph = build_scene_graph(room)

    return {
        "roomID": room_id,
        "bundleID": str(uuid4()),
        "status": "accepted",
        "frameCount": len(frames),
    }

@app.post("/rooms/{room_id}/reconstruct", response_model=JobAcceptedResponse)
async def reconstruct_room_endpoint(room_id: str) -> JobAcceptedResponse:
    store = RoomStore()
    room = store.get(room_id)
    if not room:
        raise HTTPException(404, "Room not found")
    if not room.frame_dir:
        raise HTTPException(400, "No frames uploaded")

    from serving.workers.reconstruct_room import reconstruct_room

    asyncio.create_task(
        reconstruct_room(room_id, room.frame_dir, room.frames, store)
    )
    return JobAcceptedResponse(room_id=room_id, job_type="reconstruct", status="queued")

@app.post("/rooms/{room_id}/index", response_model=JobAcceptedResponse)
def index_room(room_id: str) -> JobAcceptedResponse:
    return JobAcceptedResponse(room_id=room_id, job_type="index", status="queued")

@app.post("/planner/parse", response_model=PlannerPlan)
def parse_query(request: PlannerRequest) -> PlannerPlan:
    return engine.build_plan(request)

@app.post("/rooms/{room_id}/query")
def query_room(room_id: str, request: QueryRequest) -> dict:
    planner_request = build_planner_request(room_id=room_id, request=request)
    response = engine.execute_query(planner_request=planner_request, query_request=request)

    serialized = response.model_dump(by_alias=True)
    return {
        "resultType": serialized.get("resultType", "not_found"),
        "results": [
            {
                "id": r.get("id", ""),
                "label": r.get("label", ""),
                "resultType": r.get("resultType", "not_found"),
                "confidence": r.get("confidence", 0.0),
                "confidenceState": r.get("confidenceState"),
                "worldTransform": r.get("worldTransform16"),
                "roomId": r.get("roomId"),
                "roomName": r.get("roomName"),
                "recencySeconds": r.get("recencySeconds"),
                "memoryFreshness": r.get("memoryFreshness"),
                "routeHint": r.get("routeHint"),
                "evidence": r.get("evidence", []),
                "explanation": r.get("explanation", ""),
            }
            for r in serialized.get("results", [])
        ],
        "explanation": serialized.get("explanation", ""),
    }

@app.post("/rooms/{room_id}/chat", response_model=ChatResponseDTO)
def chat_room(room_id: str, request: ChatRequestDTO) -> ChatResponseDTO:
    adjusted_request = request.model_copy(update={"room_id": room_id})
    return chat_service.chat(adjusted_request)

@app.post("/rooms/{room_id}/open-vocab-search")
def open_vocab_search(room_id: str, request: OpenVocabSearchRequest) -> list[dict]:
    adjusted_request = request.model_copy(update={"room_id": room_id})
    toolkit = engine.toolkit or DefaultQueryToolkit()
    response = toolkit.query_open_vocab(adjusted_request)

    return [
        {
            "id": c.id,
            "label": request.target_phrase,
            "resultType": "detected",
            "confidence": c.confidence,
            "confidenceState": "live_seen",
            "worldTransform": c.world_transform16,
            "evidence": c.evidence,
            "explanation": c.explanation,
        }
        for c in response.candidates
    ]

@app.get("/rooms/{room_id}/scene-graph")
def scene_graph(room_id: str):
    store = RoomStore()
    room = store.get(room_id)
    if not room or not room.scene_graph:
        return {"roomId": room_id, "sceneGraphVersion": 0, "nodes": [], "edges": []}
    return room.scene_graph

@app.get("/rooms/{room_id}/hypotheses")
def hypotheses(room_id: str, queryLabel: str | None = None):
    store = RoomStore()
    room = store.get(room_id)
    if not room:
        return {"roomId": room_id, "hypotheses": []}

    if queryLabel and room.scene_graph:
        try:
            from hidden_inference.rules.rank import rank_for_query

            result = rank_for_query(room.scene_graph, room.observations, queryLabel)
            return {
                "roomId": room_id,
                "queryLabel": queryLabel,
                "resultType": result.result_type,
                "modelId": result.model_id,
                "hypotheses": [h.model_dump(by_alias=True) for h in result.hypotheses],
            }
        except Exception:
            pass

    return {"roomId": room_id, "hypotheses": room.observations}

@app.get("/rooms/{room_id}/assets/{filename}")
async def get_asset_file(room_id: str, filename: str):

    if ".." in filename or "/" in filename:
        raise HTTPException(400, "Invalid filename")
    file_path = Path("data/rooms") / room_id / "reconstruction" / filename
    if not file_path.exists():
        raise HTTPException(404, "Asset not found")
    return FileResponse(file_path)

@app.get("/rooms/{room_id}/assets")
def assets(room_id: str):
    store = RoomStore()
    room = store.get(room_id)
    if not room:
        return {"status": "pending"}
    return {"status": room.reconstruction_status, **room.reconstruction_assets}
