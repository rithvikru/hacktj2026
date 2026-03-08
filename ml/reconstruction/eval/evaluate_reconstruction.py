from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime

from hacktj2026_ml.paths import ML_ROOT

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Write a starter evaluation report for M5/M6.")
    parser.add_argument(
        "--output",
        default="outputs/reconstruction/eval/report.json",
        help="Path to the evaluation report JSON.",
    )
    return parser.parse_args()

def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    report = {
        "model_tracks": ["M5", "M6"],
        "created_at": datetime.now(UTC).isoformat(),
        "metrics": {
            "median_alignment_error_m": None,
            "job_runtime_seconds": None,
            "viewer_alignment_verified": None,
        },
        "acceptance_gate": {
            "median_alignment_error_m": 0.25,
            "job_runtime_seconds": 300,
            "viewer_alignment_verified": True,
        },
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)

    print(f"Wrote reconstruction evaluation scaffold to {output_path}")

if __name__ == "__main__":
    main()
