from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime

from hacktj2026_ml.paths import ML_ROOT


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Write a starter evaluation report for M2/M3/M4.")
    parser.add_argument(
        "--output",
        default="outputs/open_vocab/eval/report.json",
        help="Path to the evaluation report JSON.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    report = {
        "model_tracks": ["M2", "M3", "M4"],
        "created_at": datetime.now(UTC).isoformat(),
        "metrics": {
            "recall_at_5": None,
            "mask_iou": None,
            "text_to_region_recall_at_10": None,
            "median_query_latency_seconds": None,
        },
        "acceptance_gate": {
            "recall_at_5": 0.85,
            "mask_iou": 0.75,
            "text_to_region_recall_at_10": 0.90,
            "median_query_latency_seconds": 10.0,
        },
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)

    print(f"Wrote open-vocabulary evaluation scaffold to {output_path}")


if __name__ == "__main__":
    main()
