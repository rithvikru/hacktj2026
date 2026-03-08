# Frontend Photoreal Dense Spec

## Purpose

Dense mode must stop behaving like a debug visualization.

For this app, `Dense` means:

- render a real splat/twin when the backend has produced one
- otherwise fall back to the semantic room twin
- never show a raw point-cloud star field as the primary user experience

This document is the source of truth for frontend changes around the photoreal dense path.

## User-Facing Rules

### 1. Dense mode is gated by asset quality

The frontend must not assume that any `denseAssetURL` is photoreal.

Use the backend asset flags:

- `denseAssetURL`
- `denseAssetKind`
- `denseRenderer`
- `densePhotorealReady`
- `denseDatasetManifestURL`
- `denseTransformsURL`
- `denseDiagnosticsURL`

Interpretation:

- `densePhotorealReady = true`
  - show the dedicated splat viewer
- `densePhotorealReady = false`
  - keep the user in the semantic room twin
  - show a status line explaining that a real splat is still unavailable

### 2. Dense mode must not show raw point dots

The old SceneKit point-cloud renderer is debug-only.

It must not be the default visual for end users.

If the backend only has:

- `pointcloud.ply`
- fallback `scene.splat`

then dense mode should present:

- semantic objects
- architectural shell
- copy indicating that the photoreal room twin is still processing or unavailable

### 3. Semantic mode remains the default

When opening a room:

1. show `Semantic`
2. load semantic objects first
3. load photoreal dense asset opportunistically
4. let the user enter `Dense` only after the asset is real

## Backend Contract

### Assets endpoint

`GET /rooms/{room_id}/assets`

Required fields now:

- `status`
- `pointCloudURL`
- `denseAssetURL`
- `denseAssetKind`
- `denseRenderer`
- `densePhotorealReady`
- `denseTrainingBackend`
- `denseDatasetManifestURL`
- `denseTransformsURL`
- `denseDiagnosticsURL`
- `semanticSceneURL`
- `semanticObjectCount`

### Expected asset kinds

- `gaussian_splat`
- `pointcloud_fallback`

### Expected renderer values

- `gaussian_splats_web`
- `pointcloud`

## Frontend Behavior

### Room twin mode logic

File:

- [RoomTwinViewModel.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/RoomTwinViewModel.swift)

Rules:

- `viewerMode = .semantic` by default
- `viewerMode = .dense` is allowed even if photoreal is unavailable
- but in that case the UI must stay on the semantic twin and show an explanatory status line

State required:

- `denseAssetRemoteURL`
- `denseAssetKind`
- `denseRenderer`
- `densePhotorealReady`
- `shouldUsePhotorealDenseViewer`

### Dense renderer choice

File:

- [RoomTwinView.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/RoomTwinView.swift)

Rules:

- if `viewerMode == .dense` and `densePhotorealReady == true`
  - render `SplatWebViewRepresentable`
- else
  - render the semantic SceneKit twin

### Splat viewer requirements

Current implementation:

- `WKWebView`
- `@mkkellogg/gaussian-splats-3d` loaded via module import

Source for minimal viewer pattern:

- https://github.com/mkkellogg/GaussianSplats3D

Future preferred implementation:

- native Metal splat renderer

The current web viewer is acceptable as the first real splat-capable frontend path.

## Visual Design Rules

### Semantic mode

- primary mode
- readable object meshes
- ghosted architecture shell
- labels and search focus

### Dense mode when photoreal is ready

- full-screen splat viewer
- black or near-black background
- loading state centered
- failures shown as a bottom card, not a blank screen
- keep navigation/actions identical to semantic mode

### Dense mode when photoreal is not ready

- no point cloud
- no star field
- no raw debug nodes
- same semantic twin as fallback
- status text:
  - `Dense mode needs a real splat asset; showing semantic room twin`

## Capture Profile Expectations

Dense capture is now a first-class profile.

Files:

- [FrameBundleManifest.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Models/Observation/FrameBundleManifest.swift)
- [ScanViewModel.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Scan/ScanViewModel.swift)
- [FrameBundleWriter.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Room/FrameBundleWriter.swift)

Current profile:

- `profile_id = dense_room_twin_v1`
- intended use: `photoreal_dense_reconstruction`
- higher overlap
- faster keyframe sampling
- higher JPEG quality

Frontend implication:

- scan completion UI should call out that the room was captured for dense reconstruction
- the room card should be able to show `Dense capture recorded`

## Remaining Frontend Tasks

1. Add a dedicated room-twin header badge for:
   - `Photoreal Ready`
   - `Training Dense Twin`
   - `Semantic Only`

2. Add a dense-mode onboarding tooltip:
   - explain that photoreal requires the backend splat asset

3. Add a debug sheet behind a long press or hidden dev menu:
   - `denseDatasetManifestURL`
   - `denseTransformsURL`
   - `denseDiagnosticsURL`

4. Add a future native Metal renderer swap point:
   - keep `SplatWebViewRepresentable` behind a protocol or wrapper so it can be replaced later

## Non-Goals

- Do not expose raw point clouds as the main dense experience
- Do not let `Dense` silently downgrade into random dots
- Do not use RoomPlan scaffold alone as proof of dense reconstruction quality
