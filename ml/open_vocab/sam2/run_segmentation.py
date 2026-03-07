from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime

from hacktj2026_ml.paths import ML_ROOT


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a SAM 2 segmentation job request.")
    parser.add_argument("--frame", required=True, help="Frame path to segment.")
    parser.add_argument("--boxes-json", required=True, help="Path to candidate boxes JSON.")
    parser.add_argument(
        "--output",
        default="outputs/open_vocab/segmentation-request.json",
        help="Output path for the request JSON.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "model_track": "M3",
        "frame": args.frame,
        "candidate_boxes": args.boxes_json,
        "created_at": datetime.now(UTC).isoformat(),
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(f"Wrote segmentation request to {output_path}")


if __name__ == "__main__":
    main()
