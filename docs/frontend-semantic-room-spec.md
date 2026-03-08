# Frontend Semantic Room Spec

## Purpose

The backend now produces three different room representations:

1. `RoomPlan` scaffold
2. dense room asset (`scene.splat` or point cloud fallback)
3. semantic object scene (`semantic_scene.json` + per-object `.obj` meshes)

The frontend must stop treating the room twin as a generic debug viewer and instead present a layered semantic experience:

- immediate structure
- persistent semantic objects
- optional dense realism
- clear search and selection states

This document is the source of truth for frontend changes required to make that experience visually pleasing and intuitive.

## Product Behavior

### Default room twin behavior

When a saved room opens:

1. load the RoomPlan scaffold immediately
2. load semantic object scene as soon as available
3. render semantic objects as the primary layer
4. keep scaffold visible only as a low-contrast architectural ghost
5. dense layer remains optional and off by default

The default room twin should feel like:

- architectural shell
- semantic objects placed in context
- clean labels and selection affordances

It should not feel like:

- a raw point-cloud debugger
- a pile of white RoomPlan boxes
- a stack of unrelated toggles

## New Backend Contracts To Use

### Reconstruction assets

`GET /rooms/{room_id}/assets`

Use:

- `status`
- `pointCloudURL`
- `splatURL`
- `semanticSceneURL`
- `semanticObjectCount`

### Semantic object scene

`GET /rooms/{room_id}/semantic-objects`

Each object record contains:

- `id`
- `label`
- `confidence`
- `world_transform16`
- `center_xyz`
- `extent_xyz`
- `base_anchor_xyz`
- `support_anchor_xyz`
- `support_normal_xyz`
- `principal_axis_xyz`
- `yaw_radians`
- `footprint_xyz`
- `mesh_kind`
- `mesh_asset_url`
- `point_count`
- `supporting_view_count`
- `mask_supported_views`
- `bbox_fallback_views`
- `support_relation`

These fields are the canonical frontend source for semantic placement.

## Frontend Data Model Changes

### Add new DTOs in the backend client layer

File to update:

- [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift)

Required DTOs:

- `SemanticSceneResponse`
- `SemanticSceneObject`
- `SupportRelationDTO`

Required client methods:

- `fetchSemanticScene(roomID:)`
- `downloadSemanticObjectMesh(from:suggestedFileName:into:)`

### Add local room twin state

File to update:

- [RoomTwinViewModel.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/RoomTwinViewModel.swift)

Add:

- `semanticScene: SemanticSceneResponse?`
- `semanticObjects: [SemanticSceneObject]`
- `semanticMeshLocalURLs: [String: URL]`
- `selectedSemanticObjectID: String?`
- `showSemanticObjects: Bool`
- `showDensePoints: Bool`
- `showArchitectureShell: Bool`
- `viewerMode: ViewerMode`

`ViewerMode` values:

- `semantic`
- `dense`
- `architecture`

Default:

- `viewerMode = .semantic`

## Viewer Rendering Rules

### Layer priority

Highest priority:

1. selected semantic object
2. semantic object meshes
3. scaffold shell
4. dense layer
5. heatmap/hypothesis layer

### What should be visible by default

Default on:

- semantic objects
- soft architecture shell

Default off:

- dense points
- heatmap
- raw observation pins

### Scaffold rendering

File to update:

- [SceneViewRepresentable.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/SceneViewRepresentable.swift)

Required behavior:

- if semantic objects are loaded, the scaffold must become a low-emphasis shell
- reduce material opacity significantly
- use neutral warm-gray / desaturated cyan, not bright white
- do not show RoomPlan object boxes as the dominant visual layer

### Semantic object rendering

Add a new SceneKit group:

- `semanticObjectGroup`

For each semantic object:

1. download or load cached `.obj`
2. place it using `world_transform16`
3. tint by semantic category or confidence
4. give it subtle physically readable shading
5. add selection outline / glow on tap

If mesh asset is missing:

- render a fallback oriented box using:
  - `extent_xyz`
  - `world_transform16`

### Dense rendering

Dense mode should mean:

- if `.splat` exists, render splat sample cloud
- if only `.ply` exists, render point cloud fallback

But dense mode should never fully replace semantic objects.

Rule:

- in `dense` mode, keep semantic objects visible at reduced opacity unless the user explicitly hides them

## Room Twin UX Changes

### Replace current toggle bar with mode-first controls

File to update:

- [LayerToggleBar.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/LayerToggleBar.swift)

Current problem:

- the user is asked to reason about scaffold / objects / heatmap / dense all at once

Required replacement:

Primary segmented control:

- `Semantic`
- `Dense`
- `Structure`

Secondary chips:

- `Show Labels`
- `Show Search Hits`
- `Show Hypotheses`

### Status copy

File to update:

- [RoomTwinView.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/RoomTwinView.swift)

Replace generic reconstruction text with user-facing states:

- `Preparing room geometry`
- `Building semantic objects`
- `Dense room preview ready`
- `Semantic room preview ready`

If semantic objects exist but dense does not:

- do not present this as failure
- semantic scene is already a successful state

## Selection And Search Integration

### Search result behavior

Files to update:

- [RoomTwinView.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/RoomTwinView.swift)
- [LiveSearchView.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Search/LiveSearchView.swift)
- [QueryConsoleView.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Query/QueryConsoleView.swift)

Required behavior:

- selecting a search result should focus the room twin camera on the nearest semantic object
- selected object should pulse / outline
- a bottom info card should show:
  - label
  - confidence
  - support relation
  - anchor description like `on desk`, `on floor`, `on shelf`

### Semantic object tap behavior

Tap on object mesh:

- select object
- show compact card
- allow:
  - `Locate in AR`
  - `Show related search evidence`
  - `Open object detail`

## Visual Design Rules

### Color system

Use:

- architecture shell: low-contrast neutral
- semantic objects: category-tinted but restrained
- selected object: bright cyan or amber edge glow
- hypotheses: amber/red translucent volumes
- dense points: low-alpha realism layer, never primary chrome

### Motion

Use motion only for:

- mode transitions
- object selection highlight
- loading in semantic objects progressively

Do not animate the whole scene gratuitously.

### Labeling

Do not pin labels for every object at once.

Rules:

- only show labels for selected object
- show nearby labels on demand
- hide low-confidence semantic objects unless user enables `show all`

## Frontend File-Level Work Breakdown

### Required now

- [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift)
  - add semantic scene DTOs and fetch/download methods
- [RoomTwinViewModel.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/RoomTwinViewModel.swift)
  - fetch semantic scene
  - cache mesh assets
  - expose semantic viewer state
- [SceneViewRepresentable.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/SceneViewRepresentable.swift)
  - render semantic mesh group
  - render fallback oriented boxes
  - reduce scaffold dominance
  - keep dense layer secondary
- [RoomTwinView.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/RoomTwinView.swift)
  - switch to mode-first controls
  - add semantic status states
  - add selection card
- [LayerToggleBar.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/LayerToggleBar.swift)
  - replace raw toggle strip with mode selector
- [AnnotationPin.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Viewer/AnnotationPin.swift)
  - restrict to selected/nearby semantic objects only

### Required next

- [QueryConsoleView.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Query/QueryConsoleView.swift)
  - deep-link query result into selected semantic object
- [LiveSearchView.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Search/LiveSearchView.swift)
  - hand off selected AR result into semantic room twin view

## Acceptance Criteria

Frontend work is complete when:

1. opening a room shows semantic objects as the primary visual layer
2. white RoomPlan boxes are no longer the dominant default visual
3. dense mode is optional and visually secondary
4. tapping a semantic object shows a clean info card
5. search results highlight and focus the correct semantic object
6. room twin can load `semantic_scene.json` and render `.obj` object meshes without user confusion
7. if dense assets are still processing, the user still sees a good semantic room twin
