#!/usr/bin/env bash

set -euo pipefail

DATASET_DIR=""
IMAGE_DIR=""
TRANSFORMS_JSON=""
POINTCLOUD_PATH=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dataset-dir)
      DATASET_DIR="$2"
      shift 2
      ;;
    --image-dir)
      IMAGE_DIR="$2"
      shift 2
      ;;
    --transforms-json)
      TRANSFORMS_JSON="$2"
      shift 2
      ;;
    --pointcloud-path)
      POINTCLOUD_PATH="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$DATASET_DIR" || -z "$TRANSFORMS_JSON" || -z "$POINTCLOUD_PATH" || -z "$OUTPUT_DIR" ]]; then
  echo "Usage: $0 --dataset-dir <dir> --image-dir <dir> --transforms-json <json> --pointcloud-path <ply> --output-dir <dir>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NERFSTUDIO_VENV="${NERFSTUDIO_VENV:-$ROOT_DIR/.venvs/nerfstudio}"
TRAIN_STEPS="${NERFSTUDIO_TRAIN_STEPS:-30000}"
MODEL_VARIANT="${NERFSTUDIO_MODEL_VARIANT:-splatfacto-big}"
EXPORT_DIR="$OUTPUT_DIR/nerfstudio_export"
TRAIN_DIR="$OUTPUT_DIR/nerfstudio_runs"

if [[ ! -x "$NERFSTUDIO_VENV/bin/ns-train" ]]; then
  echo "Nerfstudio CLI not found in $NERFSTUDIO_VENV. Run ./scripts/bootstrap-h100.sh first." >&2
  exit 1
fi

mkdir -p "$EXPORT_DIR" "$TRAIN_DIR"

# Seed the dataset with the point cloud so splatfacto can initialize from geometry.
cp -f "$POINTCLOUD_PATH" "$DATASET_DIR/sparse_pc.ply"
"$NERFSTUDIO_VENV/bin/python" - "$TRANSFORMS_JSON" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["ply_file_path"] = "sparse_pc.ply"
payload.setdefault("camera_model", "OPENCV")
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

source "$NERFSTUDIO_VENV/bin/activate"

ns-train "$MODEL_VARIANT" \
  --vis tensorboard \
  --max-num-iterations "$TRAIN_STEPS" \
  --output-dir "$TRAIN_DIR" \
  --pipeline.model.cull_alpha_thresh=0.005 \
  --data "$DATASET_DIR"

LATEST_CONFIG="$(find "$TRAIN_DIR" -name config.yml | sort | tail -n 1)"
if [[ -z "$LATEST_CONFIG" ]]; then
  echo "Could not find Nerfstudio config.yml after training." >&2
  exit 1
fi

ns-export gaussian-splat \
  --load-config "$LATEST_CONFIG" \
  --output-dir "$EXPORT_DIR"

EXPORTED_ASSET="$(find "$EXPORT_DIR" -type f \( -name '*.ply' -o -name '*.splat' -o -name '*.ksplat' \) | sort | tail -n 1)"
if [[ -z "$EXPORTED_ASSET" ]]; then
  echo "Nerfstudio export finished but no splat asset was found." >&2
  exit 1
fi

FINAL_ASSET="$OUTPUT_DIR/$(basename "$EXPORTED_ASSET")"
cp -f "$EXPORTED_ASSET" "$FINAL_ASSET"
echo "$FINAL_ASSET"
