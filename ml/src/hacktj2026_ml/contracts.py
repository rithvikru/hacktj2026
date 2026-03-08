from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

ResultType = Literal["detected", "last_seen", "signal_estimated", "likely_hidden"]

class DetectionCandidate(BaseModel):
    score: float = Field(ge=0.0, le=1.0)
    bbox_xyxy_norm: list[float] = Field(min_length=4, max_length=4)
    mask_ref: str | None = None
    frame_id: str

class DetectionResult(BaseModel):
    result_type: Literal["detected", "last_seen", "signal_estimated"]
    model_id: str
    model_version: str
    label: str
    score: float = Field(ge=0.0, le=1.0)
    bbox_xyxy_norm: list[float] = Field(min_length=4, max_length=4)
    mask_ref: str | None = None
    frame_id: str
    timestamp: str

class OpenVocabResult(BaseModel):
    result_type: Literal["detected"]
    model_id: str
    model_version: str
    query_text: str
    candidates: list[DetectionCandidate]

class HiddenHypothesis(BaseModel):
    rank: int = Field(ge=1)
    confidence: float = Field(ge=0.0, le=1.0)
    world_transform16: list[float] | None = Field(default=None, min_length=16, max_length=16)
    reason_codes: list[str]

class HiddenHypothesisResult(BaseModel):
    result_type: Literal["likely_hidden"]
    model_id: str
    model_version: str
    query_label: str
    hypotheses: list[HiddenHypothesis]

class ModelManifest(BaseModel):
    model_id: str
    model_family: str
    version: str
    training_data_manifest: str
    eval_report_path: str
    input_contract: dict
    output_contract: dict
    thresholds: dict
    owner: str
    created_at: str
