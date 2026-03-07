from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime

from hacktj2026_ml.paths import ML_ROOT


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create an open-vocabulary worker job file.")
    parser.add_argument("--room-id", required=True, help="Logical room identifier.")
    parser.add_argument("--query-text", required=True, help="Natural-language search query.")
    parser.add_argument(
        "--output",
        default="outputs/serving/open-vocab-worker-job.json",
        help="Output path for the worker job JSON.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "job_type": "open_vocab_search",
        "room_id": args.room_id,
        "query_text": args.query_text,
        "created_at": datetime.now(UTC).isoformat(),
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(f"Wrote open-vocab worker job to {output_path}")


if __name__ == "__main__":
    main()
