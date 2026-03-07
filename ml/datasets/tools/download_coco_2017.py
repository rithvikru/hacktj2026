from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from download_utils import (
    download_file,
    ensure_directory,
    extract_zip,
    probe_url,
    relative_to,
    write_json,
)
from hacktj2026_ml.paths import ML_ROOT


COCO_FILES = {
    "train2017": {
        "url": "https://images.cocodataset.org/zips/train2017.zip",
        "archive_relpath": Path("raw/train2017.zip"),
        "extract_dir": Path("raw"),
    },
    "val2017": {
        "url": "https://images.cocodataset.org/zips/val2017.zip",
        "archive_relpath": Path("raw/val2017.zip"),
        "extract_dir": Path("raw"),
    },
    "annotations_trainval2017": {
        "url": "https://images.cocodataset.org/annotations/annotations_trainval2017.zip",
        "archive_relpath": Path("annotations/annotations_trainval2017.zip"),
        "extract_dir": Path("annotations"),
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download official COCO 2017 archives.")
    parser.add_argument(
        "--output-root",
        default="datasets/external/public/coco",
        help="Directory under ml/ where COCO files should be stored.",
    )
    parser.add_argument(
        "--file",
        action="append",
        choices=tuple(COCO_FILES.keys()),
        default=None,
        help="COCO archive to acquire. Repeat to request multiple. Defaults to all required files.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing archives and extracted files.",
    )
    parser.add_argument(
        "--skip-extract",
        action="store_true",
        help="Download archives without extracting them.",
    )
    parser.add_argument(
        "--allow-http-fallback",
        action="store_true",
        help="Fall back to the official COCO HTTP host if the HTTPS certificate is invalid.",
    )
    parser.add_argument(
        "--verify-urls",
        action="store_true",
        help="Probe the selected URLs before downloading.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the planned files and exit.",
    )
    return parser.parse_args()


def resolve_path(raw_path: str) -> Path:
    candidate = Path(raw_path)
    if candidate.is_absolute():
        return candidate
    return (ML_ROOT / candidate).resolve()


def main() -> None:
    args = parse_args()
    output_root = resolve_path(args.output_root)
    manifests_dir = output_root / "manifests"
    requested_files = args.file or list(COCO_FILES.keys())

    plan = {
        "dataset": "coco_2017",
        "output_root": relative_to(ML_ROOT, output_root),
        "requested_files": requested_files,
        "skip_extract": args.skip_extract,
        "allow_http_fallback": args.allow_http_fallback,
    }

    if args.verify_urls:
        probes: dict[str, Any] = {}
        for file_id in requested_files:
            file_spec = COCO_FILES[file_id]
            resolved_url, status, used_http_fallback = probe_url(
                file_spec["url"],
                allow_http_fallback=args.allow_http_fallback,
            )
            probes[file_id] = {
                "source_url": file_spec["url"],
                "resolved_url": resolved_url,
                "status": status,
                "used_http_fallback": used_http_fallback,
            }
        plan["probes"] = probes

    if args.dry_run:
        print(json.dumps(plan, indent=2))
        return

    ensure_directory(output_root)
    run_manifest: dict[str, Any] = {
        **plan,
        "created_at": datetime.now(UTC).isoformat(),
        "downloads": {},
    }

    for file_id in requested_files:
        file_spec = COCO_FILES[file_id]
        archive_path = output_root / file_spec["archive_relpath"]
        result = download_file(
            file_spec["url"],
            archive_path,
            overwrite=args.overwrite,
            allow_http_fallback=args.allow_http_fallback,
        )
        extracted_to = None
        if not args.skip_extract:
            extract_dir = output_root / file_spec["extract_dir"]
            extract_zip(archive_path, extract_dir, overwrite=args.overwrite)
            extracted_to = relative_to(ML_ROOT, extract_dir)

        run_manifest["downloads"][file_id] = {
            "source_url": result.source_url,
            "resolved_url": result.resolved_url,
            "archive_path": relative_to(ML_ROOT, archive_path),
            "bytes_written": result.bytes_written,
            "used_http_fallback": result.used_http_fallback,
            "extracted_to": extracted_to,
        }

    manifest_path = manifests_dir / "download-manifest.json"
    write_json(manifest_path, run_manifest)
    print(f"Wrote COCO files under {relative_to(ML_ROOT, output_root)}")
    print(f"Wrote download manifest to {relative_to(ML_ROOT, manifest_path)}")


if __name__ == "__main__":
    main()
