#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ML_DIR="$ROOT_DIR/ml"
NERFSTUDIO_VENV="${NERFSTUDIO_VENV:-$ROOT_DIR/.venvs/nerfstudio}"

if [[ ! -x "$ML_DIR/.venv/bin/python" ]]; then
  echo "Main ML venv not found." >&2
  exit 1
fi

source "$ML_DIR/.venv/bin/activate"
python - <<'PY'
import torch
print("torch", torch.__version__)
print("cuda_available", torch.cuda.is_available())
print("device_count", torch.cuda.device_count())
if torch.cuda.is_available():
    print("device_name", torch.cuda.get_device_name(0))
    print("device_capability", torch.cuda.get_device_capability(0))
PY

if [[ -x "$NERFSTUDIO_VENV/bin/python" ]]; then
  source "$NERFSTUDIO_VENV/bin/activate"
  python - <<'PY'
import nerfstudio, gsplat
print("nerfstudio_ok", True)
print("gsplat_ok", True)
PY
fi
