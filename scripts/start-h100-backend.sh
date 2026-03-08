#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ML_DIR="$ROOT_DIR/ml"
PORT="${PORT:-8000}"
NERFSTUDIO_VENV="${NERFSTUDIO_VENV:-$ROOT_DIR/.venvs/nerfstudio}"

detect_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

LAN_IP="$(detect_ip || true)"

if [[ ! -x "$ML_DIR/.venv/bin/python" ]]; then
  echo "Main ML venv not found. Run ./scripts/bootstrap-h100.sh first." >&2
  exit 1
fi

if [[ -z "${HACKTJ2026_DENSE_TRAIN_COMMAND:-}" ]]; then
  export HACKTJ2026_DENSE_TRAIN_COMMAND="$ROOT_DIR/scripts/run-nerfstudio-splatfacto.sh --dataset-dir {dataset_dir} --image-dir {image_dir} --transforms-json {transforms_json} --pointcloud-path {pointcloud_path} --output-dir {output_dir}"
fi

export HACKTJ2026_DENSE_TRAIN_TIMEOUT_SECONDS="${HACKTJ2026_DENSE_TRAIN_TIMEOUT_SECONDS:-7200}"

echo "Starting H100 backend from $ML_DIR"
if [[ -n "${LAN_IP}" ]]; then
  echo "Device URL: http://${LAN_IP}:${PORT}"
fi
echo "Dense trainer command:"
echo "  $HACKTJ2026_DENSE_TRAIN_COMMAND"
echo "Nerfstudio venv:"
echo "  $NERFSTUDIO_VENV"

cd "$ML_DIR"
source .venv/bin/activate
exec uvicorn serving.api.app:app --app-dir . --host 0.0.0.0 --port "$PORT"
