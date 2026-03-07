#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ML_DIR="$ROOT_DIR/ml"
PORT="${PORT:-8000}"

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

cd "$ML_DIR"
exec uv run uvicorn serving.api.app:app --app-dir . --host 0.0.0.0 --port "$PORT" --reload
