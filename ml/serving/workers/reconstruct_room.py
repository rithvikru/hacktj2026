from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime

from hacktj2026_ml.paths import ML_ROOT

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a reconstruction worker job file.")
    parser.add_argument("--room-id", required=True, help="Logical room identifier.")
    parser.add_argument("--frame-bundle", required=True, help="Path to the uploaded frame bundle.")
    parser.add_argument(
        "--output",
        default="outputs/serving/reconstruct-worker-job.json",
        help="Output path for the worker job JSON.",
    )
    return parser.parse_args()

def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "job_type": "reconstruct_room",
        "room_id": args.room_id,
        "frame_bundle": args.frame_bundle,
        "created_at": datetime.now(UTC).isoformat(),
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(f"Wrote reconstruction worker job to {output_path}")

if __name__ == "__main__":
    main()
