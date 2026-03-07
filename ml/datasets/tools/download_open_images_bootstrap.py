from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

from download_utils import (
    copy_file,
    download_file,
    ensure_directory,
    relative_to,
    write_json,
)
from hacktj2026_ml.paths import ML_ROOT


DEFAULT_CLASS_NAMES = [
    "Remote control",
    "Mobile phone",
    "Glasses",
    "Backpack",
    "Drawer",
    "Bed",
    "Couch",
    "Headphones",
]

CLASS_DESCRIPTIONS_URL = "https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions-boxable.csv"
IMAGE_INFO_URLS = {
    "train": "https://storage.googleapis.com/openimages/2018_04/train/train-images-boxable-with-rotation.csv",
    "validation": "https://storage.googleapis.com/openimages/2018_04/validation/validation-images-with-rotation.csv",
    "test": "https://storage.googleapis.com/openimages/2018_04/test/test-images-with-rotation.csv",
}
BBOX_URLS = {
    # The official Open Images V7 page still points bbox train annotations at this V6 file.
    "train": "https://storage.googleapis.com/openimages/v6/oidv6-train-annotations-bbox.csv",
    "validation": "https://storage.googleapis.com/openimages/v5/validation-annotations-bbox.csv",
    "test": "https://storage.googleapis.com/openimages/v5/test-annotations-bbox.csv",
}
SEGMENTATION_URLS = {
    "train": "https://storage.googleapis.com/openimages/v5/train-annotations-object-segmentation.csv",
    "validation": "https://storage.googleapis.com/openimages/v5/validation-annotations-object-segmentation.csv",
    "test": "https://storage.googleapis.com/openimages/v5/test-annotations-object-segmentation.csv",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download an Open Images bootstrap subset.")
    parser.add_argument(
        "--output-root",
        default="datasets/external/public/open-images-v7",
        help="Directory under ml/ where Open Images files should be stored.",
    )
    parser.add_argument(
        "--subset",
        action="append",
        choices=("train", "validation", "test"),
        default=None,
        help="Subset to acquire. Repeat to request multiple subsets. Defaults to validation.",
    )
    parser.add_argument(
        "--class-name",
        action="append",
        default=None,
        help="Display-name class to include. Repeat to add more classes.",
    )
    parser.add_argument(
        "--max-images-per-class",
        type=int,
        default=250,
        help="Maximum unique images per requested class and subset.",
    )
    parser.add_argument(
        "--image-source",
        choices=("thumbnail", "original"),
        default="thumbnail",
        help="Which official image URL field to download.",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=8,
        help="Concurrent image download workers.",
    )
    parser.add_argument(
        "--metadata-only",
        action="store_true",
        help="Download metadata and filtered manifests without downloading image files.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing downloaded files and generated subsets.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the planned work without downloading files.",
    )
    return parser.parse_args()


def resolve_path(raw_path: str) -> Path:
    candidate = Path(raw_path)
    if candidate.is_absolute():
        return candidate
    return (ML_ROOT / candidate).resolve()


def read_class_map(path: Path) -> dict[str, str]:
    class_map: dict[str, str] = {}
    with path.open("r", encoding="utf-8", newline="") as handle:
        for label_id, display_name in csv.reader(handle):
            class_map[display_name] = label_id
    return class_map


def select_target_rows(
    bbox_path: Path,
    *,
    label_id_to_name: dict[str, str],
    max_images_per_class: int,
) -> tuple[list[dict[str, str]], set[str], dict[str, int]]:
    selected_rows: list[dict[str, str]] = []
    selected_image_ids: set[str] = set()
    per_class_image_ids: dict[str, set[str]] = defaultdict(set)

    with bbox_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            label_name = label_id_to_name.get(row["LabelName"])
            if label_name is None:
                continue

            image_id = row["ImageID"]
            should_select = image_id in selected_image_ids
            if not should_select and len(per_class_image_ids[label_name]) < max_images_per_class:
                per_class_image_ids[label_name].add(image_id)
                selected_image_ids.add(image_id)
                should_select = True

            if should_select:
                selected_rows.append(row)

    counts = {label_name: len(image_ids) for label_name, image_ids in per_class_image_ids.items()}
    return selected_rows, selected_image_ids, counts


def write_filtered_csv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    ensure_directory(path.parent)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def filter_image_info_rows(
    image_info_path: Path,
    *,
    selected_image_ids: set[str],
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with image_info_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if row["ImageID"] in selected_image_ids:
                rows.append(row)
    return rows


def download_subset_images(
    image_rows: list[dict[str, str]],
    *,
    subset: str,
    image_source: str,
    image_dir: Path,
    workers: int,
    overwrite: bool,
) -> list[dict[str, Any]]:
    ensure_directory(image_dir)
    url_key = "Thumbnail300KURL" if image_source == "thumbnail" else "OriginalURL"
    results: list[dict[str, Any]] = []

    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {}
        for row in image_rows:
            image_url = row.get(url_key) or row.get("OriginalURL")
            if not image_url:
                continue
            suffix = Path(image_url.split("?", 1)[0]).suffix or ".jpg"
            destination = image_dir / f"{row['ImageID']}{suffix}"
            future = executor.submit(
                download_file,
                image_url,
                destination,
                overwrite=overwrite,
            )
            futures[future] = (row["ImageID"], image_url, destination)

        for future in as_completed(futures):
            image_id, image_url, destination = futures[future]
            result = future.result()
            results.append(
                {
                    "image_id": image_id,
                    "source_url": image_url,
                    "resolved_url": result.resolved_url,
                    "destination": destination.as_posix(),
                    "bytes_written": result.bytes_written,
                }
            )

    results.sort(key=lambda item: item["image_id"])
    return results


def main() -> None:
    args = parse_args()
    output_root = resolve_path(args.output_root)
    subsets = args.subset or ["validation"]
    class_names = args.class_name or DEFAULT_CLASS_NAMES

    annotations_dir = output_root / "annotations"
    metadata_dir = annotations_dir / "metadata"
    bbox_dir = annotations_dir / "bbox"
    segmentation_dir = annotations_dir / "segmentation"
    image_info_dir = annotations_dir / "image_info"
    subsets_dir = output_root / "subsets"
    raw_images_dir = output_root / "raw" / "images"
    manifests_dir = output_root / "manifests"

    if args.dry_run:
        plan = {
            "output_root": relative_to(ML_ROOT, output_root),
            "subsets": subsets,
            "class_names": class_names,
            "max_images_per_class": args.max_images_per_class,
            "image_source": args.image_source,
            "metadata_only": args.metadata_only,
        }
        print(json.dumps(plan, indent=2))
        return

    class_descriptions_path = metadata_dir / "oidv7-class-descriptions-boxable.csv"
    download_file(CLASS_DESCRIPTIONS_URL, class_descriptions_path, overwrite=args.overwrite)
    class_map = read_class_map(class_descriptions_path)

    missing_classes = [class_name for class_name in class_names if class_name not in class_map]
    if missing_classes:
        raise ValueError(f"Open Images class names not found: {missing_classes}")

    label_id_to_name = {class_map[class_name]: class_name for class_name in class_names}
    run_manifest: dict[str, Any] = {
        "dataset": "open_images_v7_bootstrap",
        "class_names": class_names,
        "label_ids": label_id_to_name,
        "subsets": {},
    }

    for subset in subsets:
        image_info_path = image_info_dir / f"{subset}-images-with-rotation.csv"
        bbox_path = bbox_dir / f"{subset}-annotations-bbox.csv"
        segmentation_path = segmentation_dir / f"{subset}-annotations-object-segmentation.csv"

        download_file(IMAGE_INFO_URLS[subset], image_info_path, overwrite=args.overwrite)
        download_file(BBOX_URLS[subset], bbox_path, overwrite=args.overwrite)
        download_file(SEGMENTATION_URLS[subset], segmentation_path, overwrite=args.overwrite)

        selected_rows, selected_image_ids, per_class_counts = select_target_rows(
            bbox_path,
            label_id_to_name=label_id_to_name,
            max_images_per_class=args.max_images_per_class,
        )
        filtered_bbox_path = subsets_dir / subset / f"{subset}-target-bbox.csv"
        write_filtered_csv(
            filtered_bbox_path,
            [
                "ImageID",
                "Source",
                "LabelName",
                "Confidence",
                "XMin",
                "XMax",
                "YMin",
                "YMax",
                "IsOccluded",
                "IsTruncated",
                "IsGroupOf",
                "IsDepiction",
                "IsInside",
            ],
            selected_rows,
        )

        image_rows = filter_image_info_rows(image_info_path, selected_image_ids=selected_image_ids)
        filtered_image_info_path = subsets_dir / subset / f"{subset}-images.csv"
        if image_rows:
            write_filtered_csv(filtered_image_info_path, list(image_rows[0].keys()), image_rows)
        else:
            write_filtered_csv(
                filtered_image_info_path,
                [
                    "ImageID",
                    "Subset",
                    "OriginalURL",
                    "OriginalLandingURL",
                    "License",
                    "AuthorProfileURL",
                    "Author",
                    "Title",
                    "OriginalSize",
                    "OriginalMD5",
                    "Thumbnail300KURL",
                    "Rotation",
                ],
                [],
            )

        downloads = []
        if not args.metadata_only and image_rows:
            downloads = download_subset_images(
                image_rows,
                subset=subset,
                image_source=args.image_source,
                image_dir=raw_images_dir / subset,
                workers=args.workers,
                overwrite=args.overwrite,
            )

        copy_file(filtered_bbox_path, manifests_dir / f"{subset}-target-bbox.csv", overwrite=args.overwrite)
        copy_file(filtered_image_info_path, manifests_dir / f"{subset}-images.csv", overwrite=args.overwrite)

        run_manifest["subsets"][subset] = {
            "image_info_source": relative_to(ML_ROOT, image_info_path),
            "bbox_source": relative_to(ML_ROOT, bbox_path),
            "segmentation_source": relative_to(ML_ROOT, segmentation_path),
            "filtered_bbox": relative_to(ML_ROOT, filtered_bbox_path),
            "filtered_images": relative_to(ML_ROOT, filtered_image_info_path),
            "selected_image_count": len(selected_image_ids),
            "selected_bbox_count": len(selected_rows),
            "per_class_counts": per_class_counts,
            "downloaded_image_count": len(downloads),
        }

    manifest_path = manifests_dir / "bootstrap-selection-manifest.json"
    write_json(manifest_path, run_manifest)
    print(f"Wrote Open Images bootstrap files under {relative_to(ML_ROOT, output_root)}")
    print(f"Wrote selection manifest to {relative_to(ML_ROOT, manifest_path)}")


if __name__ == "__main__":
    main()
