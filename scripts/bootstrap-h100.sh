#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ML_DIR="$ROOT_DIR/ml"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu124}"
TORCH_VERSION="${TORCH_VERSION:-2.6.0}"
TORCHVISION_VERSION="${TORCHVISION_VERSION:-0.21.0}"
TORCHAUDIO_VERSION="${TORCHAUDIO_VERSION:-2.6.0}"
NERFSTUDIO_VENV="${NERFSTUDIO_VENV:-$ROOT_DIR/.venvs/nerfstudio}"

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    return 0
  fi

  echo "uv not found; installing via Astral installer"
  curl -LsSf https://astral.sh/uv/install.sh | sh

  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  if ! command -v uv >/dev/null 2>&1; then
    echo "uv installation succeeded but uv is still not on PATH." >&2
    echo "Add \$HOME/.local/bin or \$HOME/.cargo/bin to PATH and rerun." >&2
    exit 1
  fi
}

install_main_backend_env() {
  echo "==> Setting up main ML/backend environment"
  cd "$ML_DIR"
  uv venv .venv --python "$PYTHON_VERSION"

  (
    source .venv/bin/activate
    uv sync --group dev --group query-serving --group reconstruction
    uv pip install --upgrade \
      "torch==${TORCH_VERSION}" \
      "torchvision==${TORCHVISION_VERSION}" \
      "torchaudio==${TORCHAUDIO_VERSION}" \
      --index-url "$TORCH_INDEX_URL"
    uv pip install --upgrade ninja
  )
}

install_nerfstudio_env() {
  echo "==> Setting up Nerfstudio/gsplat environment"
  mkdir -p "$(dirname "$NERFSTUDIO_VENV")"
  uv venv "$NERFSTUDIO_VENV" --python "$PYTHON_VERSION"
  (
    source "$NERFSTUDIO_VENV/bin/activate"
    uv pip install --upgrade pip setuptools wheel
    uv pip install --upgrade \
      "torch==${TORCH_VERSION}" \
      "torchvision==${TORCHVISION_VERSION}" \
      "torchaudio==${TORCHAUDIO_VERSION}" \
      --index-url "$TORCH_INDEX_URL"
    uv pip install --upgrade nerfstudio gsplat ninja
  )
}

verify_stack() {
  echo "==> Verifying CUDA/PyTorch/Nerfstudio stack"
  (
    source "$ML_DIR/.venv/bin/activate"
    python - <<'PY'
import torch
print("torch", torch.__version__)
print("cuda_available", torch.cuda.is_available())
print("device_count", torch.cuda.device_count())
if torch.cuda.is_available():
    print("device_name", torch.cuda.get_device_name(0))
    print("capability", torch.cuda.get_device_capability(0))
PY
  )

  (
    source "$NERFSTUDIO_VENV/bin/activate"
    python - <<'PY'
import importlib
for mod in ("nerfstudio", "gsplat"):
    importlib.import_module(mod)
print("nerfstudio_ok", True)
print("gsplat_ok", True)
PY
  )
}

main() {
  echo "Bootstrapping H100 stack from $ROOT_DIR"
  ensure_uv
  install_main_backend_env
  install_nerfstudio_env
  verify_stack

  cat <<EOF

Bootstrap complete.

Next:
  1. source $ML_DIR/.venv/bin/activate
  2. ./scripts/start-h100-backend.sh

Nerfstudio venv:
  $NERFSTUDIO_VENV
EOF
}

main "$@"
