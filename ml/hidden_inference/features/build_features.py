from __future__ import annotations

import argparse
import json
import math
from datetime import UTC, datetime
from pathlib import Path

import yaml

from hacktj2026_ml.paths import ML_ROOT
from hidden_inference.rules.rank import Candidate

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a feature-build job for M7.")
    parser.add_argument("--query-label", required=True, help="Target object label.")
    parser.add_argument("--room-graph", required=True, help="Path to the room graph JSON.")
    parser.add_argument(
        "--output",
        default="outputs/hidden_inference/features.json",
        help="Output path for the feature build JSON.",
    )
    return parser.parse_args()

def load_label_priors() -> dict:
    yaml_path = Path(__file__).parent.parent.parent / "datasets" / "manifests" / "closed-set-labels.yaml"
    if not yaml_path.exists():
        return {}
    with open(yaml_path) as f:
        data = yaml.safe_load(f)
    return {label["canonical_label"]: label for label in data.get("labels", [])}

def build_candidates(
    scene_graph: dict, observations: list[dict], query_label: str
) -> list[Candidate]:
    last_seen = _find_last_seen(observations, query_label)
    last_seen_pos = _extract_position_from_obs(last_seen) if last_seen else None

    candidate_nodes = [
        n
        for n in scene_graph.get("nodes", [])
        if n.get("nodeType") in ("surface", "container", "furniture")
    ]

    priors = load_label_priors()
    query_priors = priors.get(query_label, {})
    support_priors = {p.lower() for p in query_priors.get("support_priors", [])}
    container_priors = {p.lower() for p in query_priors.get("container_priors", [])}

    soft_occluder_words = {"blanket", "cushion", "pillow", "clothing", "towel", "cloth"}
    hard_occluder_words = {"drawer", "cabinet", "closet", "box", "bag"}

    candidates: list[Candidate] = []
    for node in candidate_nodes:
        node_label = node.get("label", "").lower()
        node_pos = _extract_position_from_node(node)

        if last_seen_pos and node_pos:
            dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(last_seen_pos, node_pos)))
        else:
            dist = 5.0
        distance_score = max(0.0, 1.0 - dist / 5.0)

        support_score = 0.7 if any(p in node_label for p in support_priors) else 0.1
        container_score = 0.7 if any(p in node_label for p in container_priors) else 0.1
        soft_occluder = 0.6 if any(w in node_label for w in soft_occluder_words) else 0.0
        hard_occluder = 0.5 if any(w in node_label for w in hard_occluder_words) else 0.0
        temporal_decay = _compute_temporal_decay(last_seen) if last_seen else 0.5

        candidates.append(
            Candidate(
                region_id=node.get("id", "unknown"),
                distance_from_last_seen=distance_score,
                support_surface_prior=support_score,
                container_prior=container_score,
                soft_occluder_presence=soft_occluder,
                hard_occluder_presence=hard_occluder,
                room_section_prior=0.3,
                temporal_decay=temporal_decay,
            )
        )

    if not candidates:
        candidates = _default_candidates()

    return candidates

def _find_last_seen(observations: list[dict], query_label: str) -> dict | None:
    query_lower = query_label.lower()
    matches = [o for o in observations if query_lower in o.get("label", "").lower()]
    if not matches:
        return None
    return max(matches, key=lambda o: o.get("observedAt", o.get("observed_at", "")))

def _extract_position_from_node(node: dict) -> tuple[float, float, float] | None:
    transform = node.get("worldTransform16")
    if not transform or len(transform) < 16:
        return None
    return (transform[12], transform[13], transform[14])

def _extract_position_from_obs(obs: dict) -> tuple[float, float, float] | None:
    transform = obs.get("worldTransform16") or obs.get("world_transform16")
    if not transform or len(transform) < 16:
        return None
    return (transform[12], transform[13], transform[14])

def _compute_temporal_decay(last_seen: dict) -> float:
    observed_at = last_seen.get("observedAt", last_seen.get("observed_at", ""))
    if not observed_at:
        return 0.5
    try:
        dt = datetime.fromisoformat(observed_at.replace("Z", "+00:00"))
        age_hours = (datetime.now(UTC) - dt).total_seconds() / 3600
        return max(0.1, 1.0 - age_hours / 24.0)
    except (ValueError, TypeError):
        return 0.5

def _default_candidates() -> list[Candidate]:
    return [
        Candidate("fallback_table", 0.3, 0.5, 0.1, 0.0, 0.0, 0.3, 0.5),
        Candidate("fallback_desk", 0.2, 0.4, 0.1, 0.0, 0.0, 0.3, 0.5),
        Candidate("fallback_room_center", 0.1, 0.2, 0.1, 0.0, 0.0, 0.3, 0.5),
    ]

def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    room_graph_path = ML_ROOT / args.room_graph
    with room_graph_path.open("r", encoding="utf-8") as f:
        room_data = json.load(f)

    scene_graph = room_data.get("scene_graph", room_data)
    observations = room_data.get("observations", [])

    candidates = build_candidates(scene_graph, observations, args.query_label)

    payload = {
        "model_track": "M7",
        "query_label": args.query_label,
        "room_graph": args.room_graph,
        "candidates": [
            {
                "region_id": c.region_id,
                "distance_from_last_seen": c.distance_from_last_seen,
                "support_surface_prior": c.support_surface_prior,
                "container_prior": c.container_prior,
                "soft_occluder_presence": c.soft_occluder_presence,
                "hard_occluder_presence": c.hard_occluder_presence,
                "room_section_prior": c.room_section_prior,
                "temporal_decay": c.temporal_decay,
            }
            for c in candidates
        ],
        "created_at": datetime.now(UTC).isoformat(),
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(f"Wrote hidden-inference features to {output_path}")

if __name__ == "__main__":
    main()
