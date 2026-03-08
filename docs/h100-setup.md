# H100 Setup

This is the exact path to get the backend running on a new H100 box with the photoreal dense-training hook enabled.

## Assumptions

- OS: Ubuntu 22.04 or newer
- NVIDIA driver and CUDA runtime are already installed and visible to `nvidia-smi`
- You want the backend reachable by your iPhone over LAN

## 1. Clone the repo

```bash
git clone git@github.com:rithvikru/hacktj2026.git
cd hacktj2026
git checkout ml
```

If you do not have SSH configured:

```bash
git clone https://github.com/rithvikru/hacktj2026.git
cd hacktj2026
git checkout ml
```

## 2. Bootstrap the H100 stack

This installs:

- the main ML/backend venv in `ml/.venv`
- CUDA PyTorch wheels
- a dedicated Nerfstudio/gsplat venv in `.venvs/nerfstudio`

Run:

```bash
./scripts/bootstrap-h100.sh
```

Optional overrides:

```bash
PYTHON_VERSION=3.12 \
TORCH_VERSION=2.6.0 \
TORCHVISION_VERSION=0.21.0 \
TORCHAUDIO_VERSION=2.6.0 \
TORCH_INDEX_URL=https://download.pytorch.org/whl/cu124 \
./scripts/bootstrap-h100.sh
```

## 3. Verify the stack

```bash
./scripts/verify-h100-stack.sh
```

You want to see:

- `cuda_available True`
- your `H100` device name
- `nerfstudio_ok True`
- `gsplat_ok True`

## 4. Start the backend

```bash
./scripts/start-h100-backend.sh
```

The launcher prints the LAN URL and wires the backend to use Nerfstudio `splatfacto` through:

- `HACKTJ2026_DENSE_TRAIN_COMMAND`

The dense trainer hook receives:

- `{dataset_dir}`
- `{image_dir}`
- `{transforms_json}`
- `{pointcloud_path}`
- `{output_dir}`

If you need to override the training command, export your own `HACKTJ2026_DENSE_TRAIN_COMMAND` before starting.

## 5. Test the backend

On the H100 box:

```bash
curl http://127.0.0.1:8000/healthz
```

From another device on the same LAN:

```bash
curl http://YOUR_H100_IP:8000/healthz
```

You want:

```json
{"status":"ok"}
```

## 6. Point the iPhone app at the H100 backend

In the app:

1. Open `Settings`
2. Set backend URL to `http://YOUR_H100_IP:8000`
3. Tap `Test Connection`

## 7. What happens after a scan

When you save a new room:

1. the app uploads the frame bundle
2. the backend reconstructs the room shell and semantic objects
3. the dense dataset is exported to `reconstruction/dense_dataset`
4. the external Nerfstudio trainer runs
5. the backend publishes:
   - `denseAssetURL`
   - `denseAssetKind`
   - `denseRenderer`
   - `densePhotorealReady`

## 8. Tuning knobs

Useful environment variables:

```bash
export PORT=8000
export HACKTJ2026_DENSE_TRAIN_TIMEOUT_SECONDS=7200
export NERFSTUDIO_TRAIN_STEPS=30000
export NERFSTUDIO_MODEL_VARIANT=splatfacto-big
export NERFSTUDIO_VENV="$PWD/.venvs/nerfstudio"
```

## 9. What this gives you

- fast backend search and semantic reconstruction
- a real GPU-backed dense training path
- photoreal-ready dense asset publishing when the trainer succeeds

## 10. What this does not magically solve

- the phone still needs a proper splat-capable viewer path
- capture quality still matters
- large rooms with weak overlap can still train poorly

