from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from typing import Iterable

from hacktj2026_ml.contracts import HiddenHypothesisResult
from hacktj2026_ml.paths import ML_ROOT

@dataclass
class Candidate:
    region_id: str
    distance_from_last_seen: float
    support_surface_prior: float
    container_prior: float
    soft_occluder_presence: float
    hard_occluder_presence: float
    room_section_prior: float
    temporal_decay: float

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the starter rule-based hidden ranker.")
    parser.add_argument("--query-label", required=True, help="Target object label.")
    parser.add_argument(
        "--input-json",
        default=None,
        help="Optional JSON file containing candidate feature records.",
    )
    parser.add_argument(
        "--output",
        default="outputs/hidden_inference/ranked-hypotheses.json",
        help="Output path for the ranked hypotheses JSON.",
    )
    return parser.parse_args()

def default_candidates() -> list[Candidate]:
    return [
        Candidate("region_under_blanket", 0.15, 0.70, 0.10, 1.00, 0.00, 0.60, 0.90),
        Candidate("region_nightstand_drawer", 0.40, 0.35, 0.85, 0.00, 1.00, 0.70, 0.75),
        Candidate("region_floor_beside_bed", 0.25, 0.60, 0.00, 0.20, 0.00, 0.55, 0.80),
    ]

def load_candidates(input_json: str | None) -> list[Candidate]:
    if input_json is None:
        return default_candidates()

    with (ML_ROOT / input_json).open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    return [Candidate(**item) for item in payload["candidates"]]

def score(candidate: Candidate) -> float:
    value = 0.0
    value += max(0.0, 1.0 - candidate.distance_from_last_seen) * 0.30
    value += candidate.support_surface_prior * 0.20
    value += candidate.container_prior * 0.15
    value += candidate.soft_occluder_presence * 0.15
    value += candidate.hard_occluder_presence * 0.10
    value += candidate.room_section_prior * 0.05
    value += candidate.temporal_decay * 0.05
    return round(min(value, 1.0), 4)

def reason_codes(candidate: Candidate) -> list[str]:
    reasons: list[str] = []
    if candidate.distance_from_last_seen <= 0.25:
        reasons.append("near_last_seen")
    if candidate.soft_occluder_presence >= 0.75:
        reasons.append("soft_occluder_present")
    if candidate.hard_occluder_presence >= 0.75:
        reasons.append("hard_occluder_present")
    if candidate.container_prior >= 0.70:
        reasons.append("high_container_prior")
    if candidate.support_surface_prior >= 0.60:
        reasons.append("size_compatible_surface")
    if not reasons:
        reasons.append("fallback_prior_match")
    return reasons

def build_result(query_label: str, candidates: Iterable[Candidate]) -> HiddenHypothesisResult:
    ranked = sorted(
        (
            {
                "rank": 0,
                "confidence": score(candidate),
                "world_transform16": None,
                "reason_codes": reason_codes(candidate),
                "region_id": candidate.region_id,
            }
            for candidate in candidates
        ),
        key=lambda item: item["confidence"],
        reverse=True,
    )

    hypotheses = []
    for index, item in enumerate(ranked, start=1):
        item["rank"] = index
        item.pop("region_id", None)
        hypotheses.append(item)

    return HiddenHypothesisResult(
        result_type="likely_hidden",
        model_id="m7.hidden_ranker",
        model_version="0.1.0",
        query_label=query_label,
        hypotheses=hypotheses,
    )

def rank_for_query(
    scene_graph: dict, observations: list[dict], query_label: str
) -> HiddenHypothesisResult:
    from hidden_inference.features.build_features import build_candidates

    candidates = build_candidates(scene_graph, observations, query_label)
    return build_result(query_label, candidates)

def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    result = build_result(args.query_label, load_candidates(args.input_json))
    with output_path.open("w", encoding="utf-8") as handle:
        handle.write(result.model_dump_json(indent=2))

    print(f"Wrote ranked hypotheses to {output_path}")

if __name__ == "__main__":
    main()
