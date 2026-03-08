from __future__ import annotations

import asyncio
import json
import logging
import os
import tempfile
import zipfile
from pathlib import Path
from typing import Any
from uuid import uuid4

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from pydantic import Field
from starlette.datastructures import UploadFile as StarletteUploadFile

from hacktj2026_ml.chat_contracts import ChatRequestDTO, ChatResponseDTO
from hacktj2026_ml.chat_service import ChatService
from hacktj2026_ml.query_contracts import (
    APIDTOModel,
    OpenVocabSearchRequest,
    OpenVocabSearchResponseDTO,
    PlannerPlan,
    PlannerRequest,
    QueryRequest,
)
from hacktj2026_ml.query_engine import (
    QueryEngine,
    build_open_vocab_request,
    build_planner_request,
)
from hacktj2026_ml.route_planner import plan_route
from hacktj2026_ml.toolkit import DefaultQueryToolkit
from serving.scene_graph.builder import build_scene_graph
from serving.storage.frame_bundle import (
    extract_frame_records,
    load_manifest,
    normalize_frame_bundle_manifest,
    write_manifest,
)
from serving.storage.room_store import RoomStore
from serving.workers.reconstruction_queue import (
    enqueue_reconstruction,
    shutdown_reconstruction_queue,
)

logger = logging.getLogger(__name__)
MAX_MULTIPART_FILES = int(os.getenv("HACKTJ2026_MAX_MULTIPART_FILES", "5000"))
MAX_MULTIPART_FIELDS = int(os.getenv("HACKTJ2026_MAX_MULTIPART_FIELDS", "64"))
SCAN_LIVE_DEFAULT_LABELS = [
    "phone",
    "airpods case",
    "wallet",
    "keys",
    "glasses",
    "charger",
    "tv remote",
    "spoon",
    "bottle",
    "can",
]

# --- Request / Response models ---


class RoomCreateRequest(APIDTOModel):
    room_id: str | None = None
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
    dense_asset_kind: str | None = None
    dense_renderer: str | None = None
    dense_photoreal_ready: bool = False
    dense_training_backend: str | None = None
    dense_dataset_manifest_url: str | None = None
    dense_transforms_url: str | None = None
    dense_diagnostics_url: str | None = None
    scene_graph_version: int = 0
    frame_bundle_url: str | None = None
    updated_at: str


class SemanticSceneResponseDTO(APIDTOModel):
    room_id: str
    scene_version: int = 0
    generated_at: str | None = None
    labels: list[str] = Field(default_factory=list)
    objects: list[dict[str, Any]] = Field(default_factory=list)


class RouteRequestDTO(APIDTOModel):
    start_world_transform16: list[float] = Field(min_length=16, max_length=16)
    target_world_transform16: list[float] | None = Field(default=None, min_length=16, max_length=16)
    target_label: str | None = None
    grid_resolution_m: float = 0.20
    obstacle_inflation_radius_m: float = 0.25


class RouteWaypointDTO(APIDTOModel):
    x: float
    y: float
    z: float
    world_transform16: list[float] = Field(min_length=16, max_length=16)


class RouteResponseDTO(APIDTOModel):
    reachable: bool
    reason: str
    target_label: str | None = None
    snapped_goal_world_transform16: list[float] | None = Field(default=None, min_length=16, max_length=16)
    waypoints: list[RouteWaypointDTO] = Field(default_factory=list)


class LiveScanDetectionDTO(APIDTOModel):
    id: str
    label: str
    confidence: float = Field(ge=0.0, le=1.0)
    bbox_xyxy_norm: list[float] = Field(min_length=4, max_length=4)
    mask_available: bool = False


class LiveScanDetectResponseDTO(APIDTOModel):
    labels: list[str] = Field(default_factory=list)
    detections: list[LiveScanDetectionDTO] = Field(default_factory=list)


# --- App setup ---

app = FastAPI(title="hacktj2026-ml", version="0.2.0")
engine = QueryEngine(toolkit=DefaultQueryToolkit())
chat_service = ChatService(query_engine=engine)


@app.on_event("shutdown")
def shutdown_workers() -> None:
    shutdown_reconstruction_queue()


# --- Endpoints ---


@app.get("/healthz")
def healthcheck() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/scan/live-detect", response_model=LiveScanDetectResponseDTO)
async def live_detect_scan(
    file: UploadFile = File(...),
    labels: str | None = Form(default=None),
    max_candidates: int = Form(default=6, alias="maxCandidates"),
) -> LiveScanDetectResponseDTO:
    label_list = _parse_live_detect_labels(labels)
    if not label_list:
        label_list = list(SCAN_LIVE_DEFAULT_LABELS)
    max_candidates = max(1, min(max_candidates, 12))

    suffix = Path(file.filename or "scan.jpg").suffix or ".jpg"
    temp_image = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    try:
        temp_image.write(await file.read())
        temp_image.close()
        return await asyncio.to_thread(
            _run_live_detect_scan,
            Path(temp_image.name),
            label_list,
            max_candidates,
        )
    finally:
        Path(temp_image.name).unlink(missing_ok=True)


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
    room_id = request.room_id or str(uuid4())
    existing = store.get(room_id)
    room = store.create(room_id, request.name)
    status = "existing" if existing is not None else "created"
    return {"roomID": room.room_id, "name": room.name, "status": status}


@app.post("/rooms/{room_id}/frame-bundles", response_model=FrameBundleAcceptedResponse)
async def upload_frame_bundle(
    room_id: str,
    request: Request,
) -> FrameBundleAcceptedResponse:
    store = RoomStore()
    room = store.get(room_id)
    if not room:
        raise HTTPException(404, "Room not found")

    data_dir = Path("data/rooms") / room_id / "frames"
    data_dir.mkdir(parents=True, exist_ok=True)

    try:
        form = await request.form(
            max_files=MAX_MULTIPART_FILES,
            max_fields=MAX_MULTIPART_FIELDS,
        )
    except Exception as exc:
        message = str(exc)
        if "Too many files" in message:
            raise HTTPException(
                400,
                f"Too many files in frame bundle upload. Maximum number of files is {MAX_MULTIPART_FILES}.",
            ) from exc
        raise

    file = form.get("file")
    manifest = form.get("manifest")
    images = [value for value in form.getlist("images") if isinstance(value, StarletteUploadFile)]
    depth_files = [
        value for value in form.getlist("depth_files") if isinstance(value, StarletteUploadFile)
    ]
    confidence_files = [
        value for value in form.getlist("confidence_files") if isinstance(value, StarletteUploadFile)
    ]

    if isinstance(manifest, StarletteUploadFile):
        await _save_upload(manifest, data_dir / "manifest.json")
        for upload in images:
            await _save_upload(upload, data_dir / "images" / Path(upload.filename or "image.bin").name)
        for upload in depth_files:
            await _save_upload(upload, data_dir / "depth" / Path(upload.filename or "depth.bin").name)
        for upload in confidence_files:
            await _save_upload(
                upload,
                data_dir / "confidence" / Path(upload.filename or "confidence.bin").name,
            )
    elif isinstance(file, StarletteUploadFile):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=Path(file.filename or "bundle.zip").suffix or ".zip")
        content = await file.read()
        tmp.write(content)
        tmp.close()
        try:
            with zipfile.ZipFile(tmp.name, "r") as zf:
                _safe_extract_zip(zf, data_dir)
        except zipfile.BadZipFile as exc:
            raise HTTPException(400, "Frame bundle must be uploaded as multipart files or a ZIP archive.") from exc
        finally:
            Path(tmp.name).unlink(missing_ok=True)
    else:
        raise HTTPException(400, "No frame bundle payload provided.")

    manifest_path = data_dir / "manifest.json"
    frames: list[dict[str, Any]] = []
    session_id: str | None = None
    if manifest_path.exists():
        manifest_payload = normalize_frame_bundle_manifest(load_manifest(manifest_path), data_dir)
        write_manifest(manifest_path, manifest_payload)
        frames = extract_frame_records(manifest_payload)
        session_id = manifest_payload.get("session_id")

    room.frame_dir = data_dir
    room.frames = frames
    room.observations = _extract_observations(frames)
    room.scene_graph = build_scene_graph(room)
    store.update(
        room_id,
        frame_dir=data_dir,
        frames=frames,
        observations=room.observations,
        scene_graph=room.scene_graph,
    )

    return FrameBundleAcceptedResponse(
        room_id=room_id,
        bundle_id=str(uuid4()),
        status="accepted",
        frame_count=len(frames),
        session_id=session_id,
    )


@app.post("/rooms/{room_id}/reconstruct", response_model=JobAcceptedResponse)
async def reconstruct_room_endpoint(room_id: str) -> JobAcceptedResponse:
    store = RoomStore()
    room = store.get(room_id)
    if not room:
        raise HTTPException(404, "Room not found")
    if not room.frame_dir:
        raise HTTPException(400, "No frames uploaded")

    store.update(room_id, reconstruction_status="queued", reconstruction_assets={})
    enqueue_reconstruction(room_id)
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
    # iOS expects: {"resultType": str, "results": [...], "explanation": str}
    serialized = response.model_dump(by_alias=True)
    return {
        "resultType": serialized.get("resultType", "not_found"),
        "results": [
            {
                "id": r.get("id", ""),
                "label": r.get("label", ""),
                "confidence": r.get("confidence", 0.0),
                "worldTransform": r.get("worldTransform16"),
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


@app.post("/rooms/{room_id}/route", response_model=RouteResponseDTO)
def route_room(room_id: str, request: RouteRequestDTO) -> RouteResponseDTO:
    store = RoomStore()
    room = store.get(room_id)
    if not room:
        raise HTTPException(404, "Room not found")

    route = plan_route(
        room=room,
        start_world_transform16=request.start_world_transform16,
        target_world_transform16=request.target_world_transform16,
        target_label=request.target_label,
        grid_resolution_m=request.grid_resolution_m,
        obstacle_inflation_radius_m=request.obstacle_inflation_radius_m,
    )
    return RouteResponseDTO(**route)


@app.post("/rooms/{room_id}/open-vocab-search", response_model=OpenVocabSearchResponseDTO)
def open_vocab_search(room_id: str, request: dict[str, Any]) -> OpenVocabSearchResponseDTO:
    adjusted_request = _build_open_vocab_request_from_payload(room_id=room_id, payload=request)
    toolkit = engine.toolkit or DefaultQueryToolkit()
    return toolkit.query_open_vocab(adjusted_request)


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
    # Prevent path traversal
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


@app.get("/rooms/{room_id}/semantic-objects", response_model=SemanticSceneResponseDTO)
def semantic_objects(room_id: str) -> SemanticSceneResponseDTO:
    scene_path = Path("data/rooms") / room_id / "reconstruction" / "semantic_scene.json"
    if not scene_path.exists():
        return SemanticSceneResponseDTO(room_id=room_id, scene_version=0, generated_at=None, objects=[])
    payload = json.loads(scene_path.read_text(encoding="utf-8"))
    payload.setdefault("room_id", room_id)
    payload.setdefault("scene_version", 1)
    payload.setdefault("objects", [])
    return SemanticSceneResponseDTO.model_validate(payload)


async def _save_upload(upload: UploadFile, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(await upload.read())


def _build_open_vocab_request_from_payload(room_id: str, payload: dict[str, Any]) -> OpenVocabSearchRequest:
    try:
        return OpenVocabSearchRequest.model_validate({**payload, "room_id": room_id})
    except Exception:
        query_text = (
            payload.get("query")
            or payload.get("queryText")
            or payload.get("query_text")
            or ""
        ).strip()
        if not query_text:
            raise HTTPException(422, "Open-vocab search requires query text.")

        frame_refs = payload.get("frameRefs") or payload.get("frame_refs") or []
        query_request = QueryRequest(query_text=query_text, frame_refs=frame_refs)
        planner_request = build_planner_request(room_id=room_id, request=query_request)
        planner_plan = engine.build_plan(planner_request)
        return build_open_vocab_request(room_id=room_id, plan=planner_plan, query_request=query_request)


def _extract_observations(frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    observations: list[dict[str, Any]] = []
    for frame in frames:
        frame_observations = frame.get("observations", [])
        if isinstance(frame_observations, list):
            observations.extend(item for item in frame_observations if isinstance(item, dict))
    return observations


def _parse_live_detect_labels(raw_labels: str | None) -> list[str]:
    if raw_labels is None:
        return []
    labels = [label.strip() for label in raw_labels.split(",")]
    return [label for label in labels if label]


def _run_live_detect_scan(
    image_path: Path,
    label_list: list[str],
    max_candidates: int,
) -> LiveScanDetectResponseDTO:
    try:
        import numpy as np
        from PIL import Image

        from open_vocab.grounding_dino.run_grounding import detect
        from open_vocab.sam2.run_segmentation import segment
    except ImportError as exc:
        logger.warning("Live scan detection dependencies unavailable: %s", exc)
        return LiveScanDetectResponseDTO(labels=label_list, detections=[])

    try:
        prompt = " . ".join(label_list)
        detections = detect(
            [image_path],
            prompt,
            box_threshold=0.18,
            text_threshold=0.18,
            max_prompt_variants=1,
            max_tiles_per_frame=4,
        )[:max_candidates]

        if not detections:
            return LiveScanDetectResponseDTO(labels=label_list, detections=[])

        try:
            image = np.array(Image.open(image_path).convert("RGB"))
            masks = segment(image, [detection.bbox_xyxy_norm for detection in detections])
        except Exception as exc:
            logger.warning("Live scan mask refinement failed; continuing with boxes only: %s", exc)
            masks = []

        response_detections = [
            LiveScanDetectionDTO(
                id=str(uuid4()),
                label=detection.label,
                confidence=min(max(float(detection.confidence), 0.0), 1.0),
                bbox_xyxy_norm=[float(value) for value in detection.bbox_xyxy_norm],
                mask_available=index < len(masks) and getattr(masks[index], "mask", None) is not None,
            )
            for index, detection in enumerate(detections)
        ]
        return LiveScanDetectResponseDTO(labels=label_list, detections=response_detections)
    except Exception as exc:
        logger.warning("Live scan detection failed; returning no detections: %s", exc)
        return LiveScanDetectResponseDTO(labels=label_list, detections=[])


def _safe_extract_zip(archive: zipfile.ZipFile, destination: Path) -> None:
    destination = destination.resolve()
    for member in archive.infolist():
        member_path = (destination / member.filename).resolve()
        if destination not in member_path.parents and member_path != destination:
            raise HTTPException(400, "Frame bundle archive contains an invalid path.")
    archive.extractall(destination)
