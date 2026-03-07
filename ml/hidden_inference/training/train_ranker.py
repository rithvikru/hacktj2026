from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime

from hacktj2026_ml.paths import ML_ROOT

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a hidden-ranker training request.")
    parser.add_argument("--dataset", required=True, help="Hidden-target training dataset manifest.")
    parser.add_argument(
        "--output",
        default="outputs/hidden_inference/train-ranker.json",
        help="Output path for the training request JSON.",
    )
    return parser.parse_args()

def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "model_track": "M7",
        "dataset": args.dataset,
        "learning_objective": "rank_top_k_hidden_regions",
        "created_at": datetime.now(UTC).isoformat(),
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(f"Wrote hidden-ranker training scaffold to {output_path}")

if __name__ == "__main__":
    main()
