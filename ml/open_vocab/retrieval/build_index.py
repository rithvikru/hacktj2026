from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime

from hacktj2026_ml.paths import ML_ROOT


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create an embedding index build request.")
    parser.add_argument("--manifest", required=True, help="Frame or crop manifest to index.")
    parser.add_argument(
        "--output",
        default="outputs/open_vocab/retrieval-index-request.json",
        help="Output path for the request JSON.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_path = ML_ROOT / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "model_track": "M4",
        "embedding_model": "openclip_vit_l_14",
        "manifest": args.manifest,
        "created_at": datetime.now(UTC).isoformat(),
    }

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(f"Wrote retrieval index request to {output_path}")


if __name__ == "__main__":
    main()
