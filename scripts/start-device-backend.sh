#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ML_DIR="$ROOT_DIR/ml"
PORT="${PORT:-8000}"
SAM2_REPO_DIR="${SAM2_REPO_DIR:-/Users/rithvikr/projects/sam2}"
SAM2_MODEL_DIR="${SAM2_MODEL_DIR:-/Users/rithvikr/models/sam2}"
SAM2_DEFAULT_CONFIG="configs/sam2.1/sam2.1_hiera_s.yaml"
SAM2_DEFAULT_CHECKPOINT="$SAM2_MODEL_DIR/sam2.1_hiera_small.pt"

detect_ip() {
  local iface
  for iface in en0 en1; do
    if ipconfig getifaddr "$iface" >/dev/null 2>&1; then
      ipconfig getifaddr "$iface"
      return 0
    fi
  done
  return 1
}

LAN_IP="$(detect_ip || true)"

echo "Starting ML backend from $ML_DIR"
if [[ -n "${LAN_IP}" ]]; then
  echo "Device URL: http://${LAN_IP}:${PORT}"
else
  echo "Could not auto-detect Wi-Fi LAN IP. Backend will still start on 0.0.0.0:${PORT}."
fi

if [[ -z "${SAM2_CONFIG_PATH:-}" ]]; then
  export SAM2_CONFIG_PATH="$SAM2_DEFAULT_CONFIG"
fi

if [[ -z "${SAM2_CHECKPOINT_PATH:-}" && -f "$SAM2_DEFAULT_CHECKPOINT" ]]; then
  export SAM2_CHECKPOINT_PATH="$SAM2_DEFAULT_CHECKPOINT"
fi

if [[ -n "${SAM2_CONFIG_PATH:-}" && -n "${SAM2_CHECKPOINT_PATH:-}" ]]; then
  echo "SAM2 enabled"
  echo "  config: $SAM2_CONFIG_PATH"
  echo "  checkpoint: $SAM2_CHECKPOINT_PATH"
else
  echo "SAM2 not configured; backend will use bbox-only fallback masks."
fi

cd "$ML_DIR"
exec uv run --group query-serving uvicorn serving.api.app:app --app-dir . --host 0.0.0.0 --port "$PORT"
