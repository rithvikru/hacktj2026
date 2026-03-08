# Experimentation Log

This document records the major experiments, fixes, and conclusions reached while turning the repo into a working end-to-end system for:

- iPhone room scan and upload
- natural-language spatial search
- semantic room reconstruction
- dense room twin generation
- H100-backed photoreal reconstruction preparation

This is not a PR changelog. It is a teammate-facing lab notebook.

Last updated: March 8, 2026

## 1. Goal

Build a mobile 3D geolocation app that can:

1. scan a room on iPhone
2. save reusable room state
3. answer natural-language queries about objects in that room
4. render a useful room twin
5. eventually support photoreal dense room reconstruction

## 2. Core Conclusion

The system now has a real end-to-end foundation:

- room scan works
- frame bundles upload
- reconstruction jobs run
- semantic object extraction runs
- the app can talk to a remote backend through a tunnel
- the repo is wired for H100-backed dense training

The biggest remaining gap is not connectivity. It is dense-view quality and final UX polish.

## 3. Major Experiments

### 3.1 Mobile + AR Foundation

What we tried:

- native `ARKit` + `RealityKit` + `RoomPlan`
- world-map save/load
- live AR search overlays
- scan-time capture of RGB, depth, confidence, poses, and intrinsics

What we found:

- RoomPlan is good for room shell and relocalization support
- RoomPlan is not good enough for fine object geometry or photoreal reconstruction
- ARKit/RoomPlan alone will only show coarse white structural proxies during scan

What changed:

- wired real AR session and room scan flows
- added saved `ARWorldMap`
- added frame-bundle generation during scan
- added automatic upload + reconstruction trigger after save

Key files:

- [ScanViewModel.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Scan/ScanViewModel.swift)
- [RoomCaptureViewRepresentable.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Scan/RoomCaptureViewRepresentable.swift)
- [FrameBundleWriter.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Room/FrameBundleWriter.swift)

### 3.2 Frame-Bundle Upload Contract

What we tried:

- app uploads raw scan bundle to backend
- backend ingests manifest plus images/depth/confidence

Problem:

- initial upload/reconstruction contract was broken
- mobile wrote device-local absolute paths
- backend and app disagreed on bundle shape

What changed:

- normalized portable frame-bundle manifests
- fixed multipart upload path
- fixed backend ingestion and persistence

Result:

- real phone scans now upload end to end
- backend receives full room bundle and frame count

Key files:

- [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift)
- [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py)
- [frame_bundle.py](/Users/rithvikr/projects/hacktj2026/ml/serving/storage/frame_bundle.py)

### 3.3 Search Backend Contracts

What we tried:

- planner/query contracts for natural-language search
- open-vocab search route
- room query route
- chat and route-planning endpoints

Problem:

- backend and mobile DTOs diverged
- search payloads and responses were incompatible
- open-vocab fallback could 422 or decode incorrectly

What changed:

- normalized app/backend query contracts
- added explicit planner/query/open-vocab DTOs
- made mobile/backend payloads compatible again

Result:

- app can issue backend query requests without immediate contract failure
- query layer is now structured for planner-driven search

Key files:

- [query_contracts.py](/Users/rithvikr/projects/hacktj2026/ml/src/hacktj2026_ml/query_contracts.py)
- [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py)
- [SearchPlanner.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Query/SearchPlanner.swift)

### 3.4 Open-Vocabulary Search Quality + Runtime

What we tried:

- Grounding DINO for visible query-conditioned detection
- SAM2 for mask refinement
- OpenCLIP rerank/retrieval
- multi-view 3D fusion
- scan-time live-detect route for highlighted small objects

Problems:

- query-time cost exploded with too many prompt aliases, tiles, and frames
- SAM2 was optional and not always configured
- duplicate synonym detections wasted compute

What changed:

- bounded frame count by mode
- bounded tiles and prompt variants
- changed order to `DINO -> CLIP prefilter -> SAM2 on top candidates -> fusion`
- cached CLIP crop embeddings per room
- added explicit SAM2 configuration behavior

Result:

- backend open-vocab path is materially cheaper and more stable
- scan-time detection is backend-powered, but still not yet polished enough to be treated as final UX

Key files:

- [toolkit.py](/Users/rithvikr/projects/hacktj2026/ml/src/hacktj2026_ml/toolkit.py)
- [run_grounding.py](/Users/rithvikr/projects/hacktj2026/ml/open_vocab/grounding_dino/run_grounding.py)
- [run_segmentation.py](/Users/rithvikr/projects/hacktj2026/ml/open_vocab/sam2/run_segmentation.py)
- [fusion.py](/Users/rithvikr/projects/hacktj2026/ml/open_vocab/fusion.py)

### 3.5 Dense Reconstruction Pipeline

What we tried first:

- backend point-cloud generation
- fallback gaussian export
- SceneKit dense viewer on phone

Observed problem:

- dense view looked like random dots
- viewer lagged
- output was not photoreal or end-user-meaningful

Root cause:

- the app was effectively rendering sampled point clouds, not true splats
- the backend dense path was not yet a real H100-trained photoreal pipeline

What changed:

- fixed reconstruction to be ARKit-depth-first instead of over-relying on monocular depth
- fixed intrinsics scaling for depth unprojection
- added pose-diverse frame selection
- split dense asset metadata into real-vs-fallback semantics
- changed app dense mode to avoid raw point-cloud UX as the default

Result:

- reconstruction became much faster and more geometrically coherent
- dense path is now explicitly marked as photoreal-ready only when a real dense asset exists
- the repo is prepared for external H100 training instead of pretending fallback points are a final product

Key files:

- [run_pipeline.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/da3/run_pipeline.py)
- [generate.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/pointcloud/generate.py)
- [train_splats.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/dense/train_splats.py)
- [RoomTwinViewModel.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/RoomTwinViewModel.swift)

### 3.6 Semantic Object Reconstruction

What we tried:

- object-centric semantic reconstruction as a sidecar to room reconstruction
- project detection/mask pixels into 3D using LiDAR depth
- cluster observations across views
- export low-poly object meshes and semantic JSON

Why:

- RoomPlan is too coarse for object semantics
- search wants stable 3D object instances, not just room shell

What changed:

- built semantic scene extraction pipeline
- exported `semantic_scene.json`
- exported per-object mesh files
- added backend endpoint to retrieve semantic objects

Result:

- latest successful rooms produce semantic object instances
- room reconstruction is now useful semantically even when dense photoreal output is still in progress or unavailable

Key files:

- [semantic_scene.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/objects/semantic_scene.py)
- [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py)
- [semantic-object-reconstruction.md](/Users/rithvikr/projects/hacktj2026/docs/semantic-object-reconstruction.md)

### 3.7 Backend Persistence

What we tried:

- initially used in-memory backend room state

Problem:

- backend restarts lost room metadata/status

What changed:

- moved backend room state to SQLite-backed store

Result:

- room metadata survives restart
- backend state is usable across repeated demo iterations

Key files:

- [room_store.py](/Users/rithvikr/projects/hacktj2026/ml/serving/storage/room_store.py)

### 3.8 Device Connectivity

What we tried:

- local Mac backend over LAN
- remote cluster backend over public IP
- remote cluster backend over Cloudflare tunnel

Problems:

- local Mac backend worked only when phone and Mac could reach each other
- remote cluster public port `8000` was blocked by upstream network rules
- the first Cloudflare attempt was hijacked by an existing `/etc/cloudflared/config.yml` on the box

What changed:

- confirmed the backend was healthy locally on the cluster
- confirmed public `:8000` ingress was blocked
- used `cloudflared --config /dev/null tunnel --url http://127.0.0.1:8000`

Result:

- remote backend is now reachable on phone through a working `trycloudflare.com` URL

Important note:

- quick tunnels are for development only
- the exact `trycloudflare.com` URL is ephemeral and will change when the tunnel restarts

### 3.9 H100 Deployment Path

What we tried:

- convert the dense path from local fallback behavior into a proper H100-targeted backend setup

What changed:

- added H100 bootstrap script
- added backend launcher for H100 box
- added Nerfstudio/gsplat training wrapper
- added verification script
- added H100 runbook

Result:

- there is now a reproducible path from `git clone` to live H100 backend
- the backend can invoke an external dense trainer using exported posed room datasets

Key files:

- [bootstrap-h100.sh](/Users/rithvikr/projects/hacktj2026/scripts/bootstrap-h100.sh)
- [start-h100-backend.sh](/Users/rithvikr/projects/hacktj2026/scripts/start-h100-backend.sh)
- [run-nerfstudio-splatfacto.sh](/Users/rithvikr/projects/hacktj2026/scripts/run-nerfstudio-splatfacto.sh)
- [verify-h100-stack.sh](/Users/rithvikr/projects/hacktj2026/scripts/verify-h100-stack.sh)
- [h100-setup.md](/Users/rithvikr/projects/hacktj2026/docs/h100-setup.md)

## 4. Real Device Observations

### Observed On Phone

- RoomPlan scan shows coarse white structural proxies, not fine objects
- upload flow now reaches backend
- stale reconstruction-state UI was previously misleading and was fixed
- dense view looked like dots when fallback point-cloud rendering was shown
- semantic reconstruction is a better representation of object-level understanding than old dense fallback view

### Observed On Backend

- room creation works
- frame-bundle upload works
- reconstruction jobs start and complete
- semantic object extraction produces object instances and mesh artifacts
- dense path now distinguishes fallback from photoreal-ready assets

## 5. What Worked

- iPhone scan and save
- frame-bundle capture
- backend ingestion
- reconstruction worker
- semantic scene generation
- remote H100 backend startup
- remote backend access through tunnel
- H100 dense-training hook wiring

## 6. What Did Not Work Well

- raw point-cloud dense view as an end-user experience
- relying on RoomPlan alone for object fidelity
- assuming public cluster port `8000` would be reachable
- treating fallback dense output as equivalent to photoreal output
- scan-time small-object overlays as a polished feature yet

## 7. Current State

The current system should be understood as four layers:

1. `Structure`
   - RoomPlan shell and AR scaffolding
2. `Semantics`
   - object instances and support relationships
3. `Search`
   - natural-language plus open-vocab localization
4. `Dense Photoreal`
   - H100-backed path, still dependent on successful external dense training and a good viewer path

The product should lean primarily on:

- semantic room understanding
- natural-language search
- photoreal dense twin as a quality layer

It should not rely on:

- RoomPlan alone for objects
- raw point clouds as user-facing dense mode

## 8. Current Biggest Blockers

### 8.1 Dense Viewer Quality

Need:

- reliable splat-capable mobile rendering
- dense asset loading that feels intentional and visually useful

### 8.2 Final Photoreal Pipeline Validation

Need:

- actual H100 training runs on uploaded room datasets
- validation of final dense artifact quality and latency

### 8.3 UI/UX

Need:

- more intuitive room mode switching
- better distinction between `Structure`, `Semantic`, and true `Dense`
- better progress and state messaging

### 8.4 Search Experience Polish

Need:

- better scan-time object surfacing
- clearer search result presentation
- smoother route/overlay behavior

## 9. Recommended Next Steps

1. Run real H100 dense training on multiple saved rooms and inspect resulting dense assets.
2. Validate the final dense viewer path on iPhone with those assets.
3. Make semantic mode the default meaningful room twin.
4. Improve dense-mode UX only when a real photoreal asset is present.
5. Continue polishing live search and scan-time overlays after dense path quality is proven.

## 10. Related Docs

- [current-system-overview.md](/Users/rithvikr/projects/hacktj2026/docs/current-system-overview.md)
- [TECH-REFERENCE.md](/Users/rithvikr/projects/hacktj2026/docs/TECH-REFERENCE.md)
- [technical-implementation-spec.md](/Users/rithvikr/projects/hacktj2026/docs/technical-implementation-spec.md)
- [ai-ml-model-spec.md](/Users/rithvikr/projects/hacktj2026/docs/ai-ml-model-spec.md)
- [reconstruction-research-and-fixes.md](/Users/rithvikr/projects/hacktj2026/docs/reconstruction-research-and-fixes.md)
- [semantic-object-reconstruction.md](/Users/rithvikr/projects/hacktj2026/docs/semantic-object-reconstruction.md)
- [frontend-semantic-room-spec.md](/Users/rithvikr/projects/hacktj2026/docs/frontend-semantic-room-spec.md)
- [frontend-photoreal-dense-spec.md](/Users/rithvikr/projects/hacktj2026/docs/frontend-photoreal-dense-spec.md)
- [h100-setup.md](/Users/rithvikr/projects/hacktj2026/docs/h100-setup.md)
