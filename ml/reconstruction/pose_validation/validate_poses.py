from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime

from hacktj2026_ml.paths import ML_ROOT

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a pose-validation job request.")
    parser.add_argument("--frame-bundle", required=True, help="Path to the room frame bundle.")
    parser.add_argument(
        "--output",
        default="outputs/reconstruction/pose-validation.json",
        help="Output path for the validation request JSON.",
    )
    return parser.parse_args()

def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "frame_bundle": args.frame_bundle,
        "checks": [
            "missing_pose_fraction",
            "pose_jump_outliers",
            "intrinsics_consistency",
            "roomplan_alignment_error",
        ],
        "created_at": datetime.now(UTC).isoformat(),
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(f"Wrote pose-validation scaffold to {output_path}")

if __name__ == "__main__":
    main()
