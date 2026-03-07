from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime

from hacktj2026_ml.paths import ML_ROOT

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a Grounding DINO job request.")
    parser.add_argument("--prompt", required=True, help="Natural-language prompt to ground.")
    parser.add_argument("--frame", default=None, help="Optional frame path to run against.")
    parser.add_argument(
        "--output",
        default="outputs/open_vocab/grounding-request.json",
        help="Output path for the request JSON.",
    )
    return parser.parse_args()

def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "model_track": "M2",
        "prompt": args.prompt,
        "frame": args.frame,
        "top_k": 20,
        "created_at": datetime.now(UTC).isoformat(),
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(f"Wrote open-vocabulary grounding request to {output_path}")

if __name__ == "__main__":
    main()
