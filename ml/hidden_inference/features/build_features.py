from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime

from hacktj2026_ml.paths import ML_ROOT

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

def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "model_track": "M7",
        "query_label": args.query_label,
        "room_graph": args.room_graph,
        "feature_set": [
            "distance_from_last_seen",
            "support_surface_prior",
            "container_prior",
            "soft_occluder_presence",
            "hard_occluder_presence",
            "room_section_prior",
            "temporal_decay",
        ],
        "created_at": datetime.now(UTC).isoformat(),
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(f"Wrote hidden-inference feature scaffold to {output_path}")

if __name__ == "__main__":
    main()
