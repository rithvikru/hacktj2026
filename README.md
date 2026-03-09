# Geolocate3D

3D spatial intelligence app for iPhone 15 Pro Max. Scan a room with LiDAR or smart glasses, then find any object with natural language — "where are my keys?"

## How it works

1. **Scan** — LiDAR room capture or Ray-Ban Meta glasses stream builds a 3D model of your space
2. **Understand** — On-device object detection + open-vocab grounding labels everything in the scene
3. **Search** — Ask in plain English; the app highlights the object in AR with a navigation path

## Project structure

```
mobile/          iOS app (Swift, SwiftUI + ARKit + RoomPlan)
ml/              ML workspace (PyTorch, CoreML export, serving)
scripts/         Backend launchers and H100 bootstrap
src/             Shared utilities
```

### Mobile (`mobile/`)

SwiftPM package built with [xtool](https://github.com/nicklama/xtool). Targets iPhone 15 Pro Max (iOS 17+).

Key modules:
- `App/` — Entry point, navigation, coordinators
- `Features/` — Scan, AR search, room viewer, outdoor capture, wearables
- `Services/` — Backend client, location, thermal monitoring
- `DesignSystem/` — Colors, typography, reusable components
- `Models/` — Room, observation, and scan data types

### ML (`ml/`)

Python workspace managed with `uv`. See `ml/README.md` for setup and entrypoints.

- `closed_set/` — On-device detector (training, eval, CoreML export)
- `open_vocab/` — GroundingDINO + SAM2 for open-vocabulary search
- `reconstruction/` — Dense 3D reconstruction pipeline
- `hidden_inference/` — Candidate ranking for "where did I leave X?"
- `serving/` — FastAPI backend with query and chat endpoints

## Quick start

### iOS app

```bash
cd mobile
xtool build          # cross-compile from Linux
xtool install        # deploy to connected iPhone via USB
```

### ML backend

```bash
cd ml
uv sync --group dev --group query-serving
uv run uvicorn serving.api.app:app --app-dir . --reload
```

### Device backend (local Mac)

```bash
./scripts/start-device-backend.sh
```

### H100 backend (remote GPU)

```bash
./scripts/bootstrap-h100.sh
./scripts/start-h100-backend.sh
```

## SAM2 (optional)

The backend auto-enables SAM2 mask refinement if `SAM2_CONFIG_PATH` and `SAM2_CHECKPOINT_PATH` are set. Without them it falls back to bounding-box-only masks.

## Wearables

Ray-Ban Meta smart glasses integration is on `main`. Outdoor capture uses `WearablesBridge` + GPS for location-stamped frame streaming.

## Team

Built at HackTJ 2026.
