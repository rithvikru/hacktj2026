from __future__ import annotations

from typing import Any
from uuid import uuid4

from fastapi import FastAPI
from pydantic import BaseModel

from hacktj2026_ml.contracts import HiddenHypothesisResult, OpenVocabResult


class RoomCreateRequest(BaseModel):
    name: str


class FrameBundleRequest(BaseModel):
    bundle_path: str


class QueryRequest(BaseModel):
    query_text: str


class OpenVocabSearchRequest(BaseModel):
    query_text: str
    frame_refs: list[str] = []


app = FastAPI(title="hacktj2026-ml", version="0.1.0")


@app.get("/healthz")
def healthcheck() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/rooms")
def create_room(request: RoomCreateRequest) -> dict[str, str]:
    return {"room_id": str(uuid4()), "name": request.name, "status": "created"}


@app.post("/rooms/{room_id}/frame-bundles")
def upload_frame_bundle(room_id: str, request: FrameBundleRequest) -> dict[str, str]:
    return {"room_id": room_id, "bundle_path": request.bundle_path, "status": "accepted"}


@app.post("/rooms/{room_id}/reconstruct")
def reconstruct_room(room_id: str) -> dict[str, str]:
    return {"room_id": room_id, "job_type": "reconstruct", "status": "queued"}


@app.post("/rooms/{room_id}/index")
def index_room(room_id: str) -> dict[str, str]:
    return {"room_id": room_id, "job_type": "index", "status": "queued"}


@app.post("/rooms/{room_id}/query")
def query_room(room_id: str, request: QueryRequest) -> dict[str, Any]:
    return {
        "room_id": room_id,
        "query_text": request.query_text,
        "status": "accepted",
        "result_type": "pending",
    }


@app.post("/rooms/{room_id}/open-vocab-search")
def open_vocab_search(room_id: str, request: OpenVocabSearchRequest) -> OpenVocabResult:
    candidates = []
    if request.frame_refs:
        candidates.append(
            {
                "score": 0.5,
                "bbox_xyxy_norm": [0.1, 0.1, 0.3, 0.3],
                "mask_ref": None,
                "frame_id": request.frame_refs[0],
            }
        )
    return OpenVocabResult(
        result_type="detected",
        model_id="m2.open_vocab.detector",
        model_version="0.1.0",
        query_text=request.query_text,
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
