# Current System Overview

This is the single best entrypoint for understanding what the project currently does, how the major parts connect, what artifacts are produced, and what is still fallback behavior versus the intended product path.

Use this document first. Then drop into the more specialized specs only when you need detail on one subsystem.

## 1. What The System Is

The project is a mobile-first spatial search system for iPhone with three major capabilities:

1. scan a room and save a reusable room state
2. answer natural-language search questions about objects in that room
3. reconstruct a denser room twin for semantic viewing and future photoreal rendering

The system is split across:

- `mobile/`: the iPhone app
- `ml/`: backend APIs, search, reconstruction, and model pipelines
- `docs/`: specs, research, contracts, and operating docs
- `scripts/`: backend launchers and deployment helpers

## 2. Read This First

If you only read a few files, read these in order:

1. this file: `docs/current-system-overview.md`
2. [TECH-REFERENCE.md](/Users/rithvikr/projects/hacktj2026/docs/TECH-REFERENCE.md)
3. [technical-implementation-spec.md](/Users/rithvikr/projects/hacktj2026/docs/technical-implementation-spec.md)
4. [ai-ml-model-spec.md](/Users/rithvikr/projects/hacktj2026/docs/ai-ml-model-spec.md)
5. [h100-setup.md](/Users/rithvikr/projects/hacktj2026/docs/h100-setup.md)

## 3. High-Level Architecture

The system has three planes.

### 3.1 iPhone Client

Responsibilities:

- RoomPlan room scan
- ARKit world tracking and relocalization
- frame-bundle capture and upload
- live query input
- room viewer modes
- AR overlays and route guidance

Key files:

- [Geolocate3DApp.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/App/Geolocate3DApp.swift)
- [ScanViewModel.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Scan/ScanViewModel.swift)
- [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift)
- [RoomTwinViewModel.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/RoomTwinViewModel.swift)

### 3.2 Backend Compute

Responsibilities:

- API surface
- frame-bundle ingestion
- room reconstruction
- semantic object extraction
- open-vocabulary search
- segmentation and multi-view fusion
- query planning/orchestration
- dense asset export

Key files:

- [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py)
- [reconstruct_room.py](/Users/rithvikr/projects/hacktj2026/ml/serving/workers/reconstruct_room.py)
- [toolkit.py](/Users/rithvikr/projects/hacktj2026/ml/src/hacktj2026_ml/toolkit.py)
- [query_engine.py](/Users/rithvikr/projects/hacktj2026/ml/src/hacktj2026_ml/query_engine.py)

### 3.3 Persistence

Responsibilities:

- app-local SwiftData room state
- backend room metadata in SQLite
- heavy assets on disk

Key files:

- [RoomRecord.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Models/Room/RoomRecord.swift)
- [room_store.py](/Users/rithvikr/projects/hacktj2026/ml/serving/storage/room_store.py)

Runtime output locations:

- `ml/data/room_store.sqlite3`
- `ml/data/rooms/<room_id>/frames/...`
- `ml/data/rooms/<room_id>/reconstruction/...`

## 4. End-To-End Runtime Flow

This is the actual flow the code is built around.

### 4.1 Scan On iPhone

The user opens the scan flow and the app runs:

- RoomPlan for coarse room structure
- ARKit tracking
- frame sampling for RGB, depth, intrinsics, poses, and confidence maps

Important truth:

- RoomPlan is used for room shell and fast structure.
- RoomPlan is not the fine-object reconstruction source of truth.

Relevant files:

- [RoomCaptureViewRepresentable.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Scan/RoomCaptureViewRepresentable.swift)
- [ScanViewModel.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Scan/ScanViewModel.swift)
- [FrameBundleWriter.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Room/FrameBundleWriter.swift)
- [FrameBundleManifest.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Models/Observation/FrameBundleManifest.swift)

### 4.2 Save Room Locally

When the user saves:

- the app writes a room record into SwiftData
- exports the RoomPlan USDZ shell
- archives the `ARWorldMap`
- writes a portable frame-bundle manifest plus assets

### 4.3 Upload To Backend

The app then:

1. creates or reuses a backend room
2. uploads the frame bundle
3. triggers reconstruction
4. later polls for assets and status

Relevant files:

- [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift)
- [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py)

### 4.4 Backend Reconstruction

The backend reconstruction worker currently runs this order:

1. pose validation
2. ARKit-depth-first depth preparation
3. point-cloud generation
4. semantic object extraction
5. dense training/export path

Relevant files:

- [reconstruct_room.py](/Users/rithvikr/projects/hacktj2026/ml/serving/workers/reconstruct_room.py)
- [run_pipeline.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/da3/run_pipeline.py)
- [generate.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/pointcloud/generate.py)
- [semantic_scene.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/objects/semantic_scene.py)
- [train_splats.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/dense/train_splats.py)

### 4.5 App Viewer Modes

The room viewer has three conceptual modes:

- `Structure`
- `Semantic`
- `Dense`

#### Structure

Shows the RoomPlan shell. This is fast, stable, and coarse.

#### Semantic

Shows semantically meaningful room/object understanding:

- labeled object instances
- support/surface relationships
- low-poly object geometry or tight proxies

This is the most important room twin mode for the actual search product.

#### Dense

Shows the densest available room representation.

Important truth:

- `Dense` is only photoreal if the backend publishes a real dense asset and marks it `densePhotorealReady = true`.
- Otherwise, the app should fall back to a semantic room twin, not a debug point cloud.

Relevant files:

- [RoomTwinView.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/RoomTwinView.swift)
- [RoomTwinViewModel.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/RoomTwinViewModel.swift)
- [SceneViewRepresentable.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/SceneViewRepresentable.swift)

## 5. Search Stack

The current intended search stack is natural-language-first, not fixed-label-first.

### 5.1 Query Planner

The planner layer is supposed to interpret user intent and choose the search path.

Product-level query examples:

- `where is my black wallet`
- `show the charger on the desk`
- `what is likely under the bed`

Related docs:

- [natural-language-search-spec.md](/Users/rithvikr/projects/hacktj2026/docs/natural-language-search-spec.md)

### 5.2 Primary Visible Search Path

The visible search path is:

1. Grounding DINO proposes query-conditioned regions
2. SAM2 refines to masks when enabled
3. OpenCLIP-style retrieval/rerank improves candidate ranking
4. results are projected into 3D and fused across views

Relevant files:

- [run_grounding.py](/Users/rithvikr/projects/hacktj2026/ml/open_vocab/grounding_dino/run_grounding.py)
- [run_segmentation.py](/Users/rithvikr/projects/hacktj2026/ml/open_vocab/sam2/run_segmentation.py)
- [build_index.py](/Users/rithvikr/projects/hacktj2026/ml/open_vocab/retrieval/build_index.py)
- [fusion.py](/Users/rithvikr/projects/hacktj2026/ml/open_vocab/fusion.py)
- [toolkit.py](/Users/rithvikr/projects/hacktj2026/ml/src/hacktj2026_ml/toolkit.py)

### 5.3 Hidden Search Path

If nothing is directly visible, the system can return hypotheses based on:

- room topology
- support surfaces
- containment
- last seen memory
- heuristics or learned ranking

Relevant files:

- [rank.py](/Users/rithvikr/projects/hacktj2026/ml/hidden_inference/rules/rank.py)

## 6. Reconstruction Stack

There are now three different reconstruction layers. They are not interchangeable.

### 6.1 Structure Reconstruction

Source:

- RoomPlan
- ARKit room shell

What it is good for:

- room layout
- walls
- furniture shell
- fast relocalization support

What it is not good for:

- fine object detail
- photoreal appearance
- exact small-item shape

### 6.2 Semantic Reconstruction

Source:

- open-vocab detection
- segmentation
- LiDAR depth projection
- cross-view clustering

Output:

- semantic object scene
- object-centric geometry
- stable 3D transforms
- support anchors and extent estimates

Key output:

- `semantic_scene.json`
- `semantic-object-*.obj`

This is the most product-relevant layer for search, explanation, and object-level overlays.

### 6.3 Dense Reconstruction

Source:

- posed dense dataset exported from scans
- point cloud initialization
- external dense trainer hook

Important truth:

- without a real external dense trainer, this path is fallback-quality
- with a real H100-backed trainer, this becomes the photoreal path

Key files:

- [posed_dataset.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/dense/posed_dataset.py)
- [train_splats.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/dense/train_splats.py)
- [run-nerfstudio-splatfacto.sh](/Users/rithvikr/projects/hacktj2026/scripts/run-nerfstudio-splatfacto.sh)

## 7. What “Photoreal Dense” Actually Means In This Repo

Photoreal dense is now a separate, explicit backend path.

The backend exports:

- `denseAssetURL`
- `denseAssetKind`
- `denseRenderer`
- `densePhotorealReady`
- `denseTrainingBackend`
- `denseDatasetManifestURL`
- `denseTransformsURL`
- `denseDiagnosticsURL`

If `densePhotorealReady` is `true`, the backend is claiming that the room has a real splat-capable dense asset ready for the app to render.

If `densePhotorealReady` is `false`, the room does not yet have a true photoreal dense twin and the UI should not pretend otherwise.

This distinction is non-negotiable.

## 8. H100 Path

The H100 is intended to power the real dense training path.

The H100 flow is:

1. bootstrap the CUDA/PyTorch env
2. bootstrap the Nerfstudio/gsplat env
3. start backend with external dense training enabled
4. upload scans from phone
5. backend exports a posed dense dataset and launches the external trainer
6. backend publishes a real dense asset when training succeeds

Docs and scripts:

- [h100-setup.md](/Users/rithvikr/projects/hacktj2026/docs/h100-setup.md)
- [bootstrap-h100.sh](/Users/rithvikr/projects/hacktj2026/scripts/bootstrap-h100.sh)
- [verify-h100-stack.sh](/Users/rithvikr/projects/hacktj2026/scripts/verify-h100-stack.sh)
- [start-h100-backend.sh](/Users/rithvikr/projects/hacktj2026/scripts/start-h100-backend.sh)
- [run-nerfstudio-splatfacto.sh](/Users/rithvikr/projects/hacktj2026/scripts/run-nerfstudio-splatfacto.sh)

## 9. API Surface

Major backend endpoints:

- `GET /healthz`
- `GET /rooms`
- `POST /rooms`
- `POST /rooms/{room_id}/frame-bundles`
- `POST /rooms/{room_id}/reconstruct`
- `GET /rooms/{room_id}/assets`
- `GET /rooms/{room_id}/scene-graph`
- `GET /rooms/{room_id}/semantic-objects`
- `POST /rooms/{room_id}/query`
- `POST /rooms/{room_id}/open-vocab-search`
- `POST /planner/parse`
- `POST /rooms/{room_id}/chat`
- `POST /rooms/{room_id}/route`
- `POST /scan/live-detect`

Primary backend entrypoint:

- [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py)

## 10. Room Asset Layout On Disk

For a room `ROOM_ID`, expect:

### Frame bundle

- `ml/data/rooms/ROOM_ID/frames/manifest.json`
- `ml/data/rooms/ROOM_ID/frames/images/...`
- `ml/data/rooms/ROOM_ID/frames/depth/...`
- `ml/data/rooms/ROOM_ID/frames/confidence/...`

### Reconstruction outputs

- `ml/data/rooms/ROOM_ID/reconstruction/pointcloud.ply`
- `ml/data/rooms/ROOM_ID/reconstruction/semantic_scene.json`
- `ml/data/rooms/ROOM_ID/reconstruction/semantic-object-*.obj`
- `ml/data/rooms/ROOM_ID/reconstruction/dense_dataset/...`
- `ml/data/rooms/ROOM_ID/reconstruction/dense_dataset_manifest.json`
- `ml/data/rooms/ROOM_ID/reconstruction/dense_training_diagnostics.json`
- dense asset output such as `.splat`, `.ksplat`, or trainer-exported `.ply`

## 11. Current Model Stack

The current intended model stack is:

- planner: GPT-class model
- visible grounding: Grounding DINO
- segmentation: SAM2
- retrieval/rerank: OpenCLIP
- delayed dense geometry support: DA3 fallback path plus ARKit-depth-first reconstruction
- dense photoreal training: external dense trainer hook
- hidden ranking: rule-based first, learned later

Important truth:

- not every stage requires training from scratch
- many stages start from pretrained models
- the dense room twin quality depends heavily on the external trainer path, not just the repo’s internal Python code

## 12. What Is Real Today Vs What Is Still Transitional

### Real Today

- iPhone scan and save flow
- frame-bundle upload
- backend room creation and persistence
- room reconstruction worker
- semantic object extraction and semantic JSON/mesh export
- live detect endpoint
- natural-language/backend query surface
- H100 bootstrap/start scripts

### Transitional / Fallback

- dense photoreal rendering on the phone depends on the real dense asset being produced
- any view that shows raw point clouds is debugging or fallback behavior, not product UX
- RoomPlan object display remains coarse and should never be treated as final semantic object quality
- not all small objects will reconstruct as detailed meshes; many are still low-poly proxies or extent-based geometry

## 13. Why The System May Look Different From The Product Pitch

The product pitch is:

- photoreal room twin
- semantic object understanding
- natural-language spatial search

The actual code reality is:

- RoomPlan gives the room shell
- semantic reconstruction gives object-level scene understanding
- dense reconstruction becomes photoreal only if the external dense trainer succeeds

That distinction matters because otherwise the UI lies to the user.

## 14. Common Failure Modes

### Dense Looks Like Random Dots

Cause:

- a fallback point-cloud path is being shown instead of a real photoreal dense asset

Fix direction:

- ensure the backend produces a real dense asset
- ensure the app only uses dense mode when `densePhotorealReady = true`

### Room Looks Like White Boxes

Cause:

- the user is seeing RoomPlan structure, not semantic or dense content

Fix direction:

- switch to semantic mode
- improve semantic rendering layer

### Reconstruction Feels Slow

Cause:

- dense training is GPU-heavy
- large frame bundles increase cost

Fix direction:

- use pose-diverse frame selection
- run the H100 path
- separate semantic readiness from photoreal readiness in the UI

## 15. Recommended Mental Model

Think of the project as four layers stacked together:

1. `Structure`
   - RoomPlan shell and AR scaffolding
2. `Semantics`
   - labeled object instances and support relationships
3. `Search`
   - natural-language query and object localization
4. `Dense Photoreal`
   - optional but important room twin quality layer powered by the H100 path

If you conflate those four layers, the app becomes confusing and the reconstruction expectations become wrong.

## 16. Related Docs

- [technical-implementation-spec.md](/Users/rithvikr/projects/hacktj2026/docs/technical-implementation-spec.md)
- [ai-ml-model-spec.md](/Users/rithvikr/projects/hacktj2026/docs/ai-ml-model-spec.md)
- [natural-language-search-spec.md](/Users/rithvikr/projects/hacktj2026/docs/natural-language-search-spec.md)
- [execution-checklist.md](/Users/rithvikr/projects/hacktj2026/docs/execution-checklist.md)
- [frontend-semantic-room-spec.md](/Users/rithvikr/projects/hacktj2026/docs/frontend-semantic-room-spec.md)
- [frontend-photoreal-dense-spec.md](/Users/rithvikr/projects/hacktj2026/docs/frontend-photoreal-dense-spec.md)
- [reconstruction-research-and-fixes.md](/Users/rithvikr/projects/hacktj2026/docs/reconstruction-research-and-fixes.md)
- [semantic-object-reconstruction.md](/Users/rithvikr/projects/hacktj2026/docs/semantic-object-reconstruction.md)
- [h100-setup.md](/Users/rithvikr/projects/hacktj2026/docs/h100-setup.md)
