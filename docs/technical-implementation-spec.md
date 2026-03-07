# Mobile 3D Geolocation App Technical Implementation Spec

Status: source of truth for full-system implementation  
Version: `v2.0`  
Last updated: `2026-03-07`

Related implementation specs:

- `docs/ai-ml-model-spec.md`

## 1. Objective

Build a native iPhone-centered spatial intelligence system that lets a user:

1. Scan a room once or rescan at any time.
2. Create a persistent 3D digital twin of the room.
3. Ask natural queries such as:
   - `Where are my AirPods?`
   - `Show me the wallet near the bed`
   - `What is under the chair?`
   - `How many chairs are in this room?`
   - `Where are the likely places I left my keys?`
4. Search in real time while moving the phone around the room.
5. Search later from a saved room model using delayed processing.
6. Visualize likely and confirmed object locations inside a live AR camera view and inside a saved 3D room view.
7. Support both:
   - `confirmed location` results
   - `probabilistic hidden-location` results

This document assumes aggressive implementation capacity. It does not constrain features for hackathon time. It does constrain the system to current hardware, physics, and public APIs.

## 2. Capability Statement

The system will be built as a hybrid of:

1. `on-device spatial capture and AR guidance`
2. `persistent room memory`
3. `server-side reconstruction and semantic indexing`
4. `multi-stage object search`
5. `probabilistic hidden-object inference`
6. `optional cooperative and tagged-object sensing`

The system must support four result types:

1. `Visible Confirmed`
   - object is currently visible and detected
2. `Previously Confirmed`
   - object was previously observed and anchored in the room
3. `Signal Confirmed`
   - object or companion device is actively localized through UWB/BLE/custom accessory sensing
4. `Likely Hidden`
   - object is not directly sensed, but the system infers likely locations from spatial memory, priors, and occlusion reasoning

## 3. Non-Negotiable Constraints

These are hard constraints and remain in force even in the full-system version:

1. The iPhone 15 Pro Max does not provide a public thermal camera feed.
2. Public Apple APIs do not provide a general-purpose third-party path to read AirPods location or Precision Finding from a custom app.
3. LiDAR and RGB capture on iPhone can reconstruct visible geometry and appearance, not directly see through opaque occluders.
4. Therefore:
   - `thermal overlay` must be treated as a visualization effect, not a thermal measurement
   - `hidden object` without cooperative sensing or custom instrumentation must be treated as probabilistic inference, not direct detection
5. The system must distinguish in UI and in code between:
   - `detected`
   - `last seen`
   - `signal-derived`
   - `estimated likely location`

## 4. Product Definition

The product is not a single AR view. It is a spatial operating layer with five product tracks.

### 4.1 Track A: Live Spatial Search

Use the live camera plus AR tracking to detect, localize, and guide users to objects during a current session.

### 4.2 Track B: Persistent Room Twin

Save a room as a persistent digital twin that can be reopened, inspected, queried, and relocalized later.

### 4.3 Track C: Semantic Room Intelligence

Build a structured room graph that understands surfaces, furniture, containment, proximity, and user objects.

### 4.4 Track D: Hidden Object Engine

Provide best-effort hidden-object support across three modes:

1. `cooperative`
2. `instrumented`
3. `probabilistic non-cooperative`

### 4.5 Track E: Delayed Reconstruction and Indexing

Run heavier 3D reconstruction and open-vocabulary reasoning off-device using exported frames, poses, and semantics.

## 5. Target Hardware and Runtime

Primary client:

1. `iPhone 15 Pro Max`
2. `iOS 17+`
3. physical device only

Optional secondary hardware:

1. second iPhone for companion hidden-target mode
2. custom UWB/BLE accessory tag for tagged-object mode
3. Mac or GPU backend for delayed reconstruction

## 6. System Architecture

Use a three-plane architecture:

```text
iPhone Client
  -> live capture, AR, local detection, relocalization, UI, local cache

Backend Compute Plane
  -> reconstruction, open-vocabulary detection, segmentation, scene graph indexing, query planning

Persistence Plane
  -> room assets, frame bundles, embeddings, scene graph, object memory, search history
```

### 6.1 Client Responsibilities

The iPhone client is responsible for:

1. AR session management
2. RoomPlan scanning
3. local room relocalization
4. low-latency visible-object search
5. AR guidance overlays
6. local object memory
7. typed and spoken query input
8. optional peer discovery and Nearby Interaction

### 6.2 Backend Responsibilities

The backend is responsible for:

1. delayed reconstruction
2. frame selection and indexing
3. open-vocabulary object search
4. segmentation refinement
5. semantic scene graph construction
6. hidden-object likelihood inference
7. embedding-based retrieval
8. heavy analytics over saved rooms

### 6.3 Persistence Responsibilities

Persist these data classes:

1. room metadata
2. AR world maps
3. RoomPlan exports
4. frame bundles
5. camera poses and intrinsics
6. dense reconstruction assets
7. scene graph
8. object observations
9. object hypotheses
10. query results

## 7. Technology Stack

Use this stack unless a future revision changes it:

| Layer | Choice |
| --- | --- |
| Mobile app | `Swift`, `SwiftUI`, `RealityKit`, `ARKit`, `RoomPlan` |
| Local persistence | `SwiftData` + asset files |
| Voice | `Speech` |
| Query normalization | `NaturalLanguage` + structured parser |
| Local detection | `Vision` + `Core ML` |
| Local rendering | `RealityKit` + optional custom `Metal` materials |
| Peer discovery | `MultipeerConnectivity` |
| UWB | `Nearby Interaction` |
| Backend API | `Python`, `FastAPI` or `gRPC` |
| Backend ML | `PyTorch` |
| Reconstruction | `DA3`, `COLMAP`-class SfM where needed, `3D Gaussian Splatting` |
| Open-vocabulary search | `Grounding DINO` + segmentation model such as `SAM 2` |
| Semantic embeddings | CLIP-like image-text embeddings or equivalent multimodal encoder |
| Storage | object storage + relational metadata DB + vector index |
| Analytics jobs | batch workers and GPU workers |

## 8. System Modes

The app must expose these modes explicitly.

### 8.1 Live Scan

Purpose:

1. scan visible room geometry
2. capture room structure
3. capture keyframes
4. create or update room memory

### 8.2 Live Search

Purpose:

1. relocalize into room
2. search visible targets in real time
3. guide user to current or prior target position

### 8.3 Saved Twin Viewer

Purpose:

1. view saved room model
2. inspect surfaces, objects, and hypotheses
3. navigate and zoom the room

### 8.4 Semantic Query

Purpose:

1. answer spatial questions from saved scene state
2. return objects, counts, sections, surfaces, and hypotheses

### 8.5 Hidden Search

Purpose:

1. locate cooperative targets
2. locate tagged targets
3. estimate non-cooperative hidden targets

## 9. Search Taxonomy

All searches must be classified before execution.

### 9.1 Search Classes

1. `closed-set visible search`
2. `open-vocabulary visible search`
3. `last-seen retrieval`
4. `signal-based localization`
5. `hidden-object likelihood inference`

### 9.2 Result Confidence Classes

1. `confirmed-high`
2. `confirmed-medium`
3. `last-seen`
4. `signal-estimated`
5. `likelihood-ranked`
6. `no-result`

## 10. Implementation Tracks

Build the system as five parallel workstreams.

### 10.1 Workstream 1: Spatial Foundation

Deliver:

1. room scanning
2. room persistence
3. relocalization
4. room viewer
5. room graph

### 10.2 Workstream 2: Real-Time Search

Deliver:

1. on-device closed-set detection
2. 3D localization
3. observation tracking
4. AR overlay guidance

### 10.3 Workstream 3: Delayed Intelligence

Deliver:

1. backend frame ingestion
2. delayed reconstruction
3. semantic indexing
4. open-vocabulary search

### 10.4 Workstream 4: Hidden Object Engine

Deliver:

1. cooperative UWB path
2. tagged-object path
3. probabilistic hidden inference path

### 10.5 Workstream 5: Query and Planning

Deliver:

1. typed and voice input
2. query parser
3. search planner
4. explanation and evidence layer

## 11. Mobile App Project Structure

Use this project layout:

```text
App/
  Geolocate3DApp.swift
  AppCoordinator.swift

Features/
  Home/
  Scan/
  Search/
  Viewer/
  Query/
  HiddenSearch/
  Settings/

Services/
  AR/
  Room/
  Detection/
  Memory/
  Query/
  Nearby/
  Persistence/
  Speech/
  Backend/

Models/
  Room/
  Geometry/
  SceneGraph/
  Observation/
  Query/
  HiddenSearch/

Resources/
  ML/
  Schemas/
  Prompts/
```

## 12. Mobile Feature Modules

Create these top-level features:

1. `HomeView`
2. `ScanRoomView`
3. `SearchView`
4. `RoomTwinView`
5. `QueryConsoleView`
6. `HiddenSearchView`
7. `CompanionTargetView`

## 13. Data Model

Use local metadata models plus backend-normalized schemas.

### 13.1 `RoomRecord`

Fields:

1. `id: UUID`
2. `name: String`
3. `createdAt: Date`
4. `updatedAt: Date`
5. `previewImagePath: String`
6. `capturedRoomJSONPath: String`
7. `roomUSDZPath: String`
8. `worldMapPath: String`
9. `frameBundlePath: String?`
10. `denseAssetPath: String?`
11. `sceneGraphVersion: Int`
12. `reconstructionStatus: ReconstructionStatus`

### 13.2 `ObjectPrototype`

Fields:

1. `id: UUID`
2. `canonicalName: String`
3. `displayName: String`
4. `synonyms: [String]`
5. `searchModes: [SearchMode]`
6. `closedSetEnabled: Bool`
7. `openVocabularyEnabled: Bool`
8. `signalCapable: Bool`
9. `supportSurfaces: [String]`
10. `occlusionPriors: [String]`

### 13.3 `ObjectObservation`

Fields:

1. `id: UUID`
2. `roomID: UUID`
3. `prototypeID: UUID?`
4. `label: String`
5. `source: ObservationSource`
6. `confidence: Double`
7. `worldTransform16: [Float]`
8. `observedAt: Date`
9. `boundingBox: NormalizedRect?`
10. `maskPath: String?`
11. `snapshotPath: String?`
12. `embeddingID: UUID?`
13. `visibilityState: VisibilityState`
14. `evidence: [ObservationEvidence]`

### 13.4 `ObjectHypothesis`

Fields:

1. `id: UUID`
2. `roomID: UUID`
3. `queryLabel: String`
4. `hypothesisType: HypothesisType`
5. `rank: Int`
6. `confidence: Double`
7. `worldTransform16: [Float]?`
8. `supportObjectID: UUID?`
9. `occluderObjectID: UUID?`
10. `reasonCodes: [String]`
11. `generatedAt: Date`

### 13.5 `SceneNode`

Fields:

1. `id: UUID`
2. `roomID: UUID`
3. `nodeType: SceneNodeType`
4. `label: String`
5. `worldTransform16: [Float]`
6. `extentXYZ: [Float]`
7. `parentID: UUID?`
8. `attributesJSON: String`

### 13.6 `FrameRecord`

Fields:

1. `id: UUID`
2. `roomID: UUID`
3. `timestamp: Date`
4. `imagePath: String`
5. `depthPath: String?`
6. `confidenceMapPath: String?`
7. `cameraTransform16: [Float]`
8. `intrinsics9: [Float]`
9. `trackingState: String`
10. `selectedForUpload: Bool`

## 14. Persistence Rules

Apply these rules exactly:

1. Store heavy assets in files or object storage, not directly in SwiftData.
2. Archive `ARWorldMap` with `NSKeyedArchiver`.
3. Persist transforms as `16` column-major floats.
4. Every room save must include:
   - RoomPlan export
   - preview image
   - saved world map if available
5. Every delayed reconstruction upload must include:
   - RGB keyframes
   - timestamps
   - camera poses
   - camera intrinsics
   - device metadata

## 15. Capture Pipeline

Implement the primary scan pipeline as follows:

1. create dedicated `ARSession`
2. configure `ARWorldTrackingConfiguration`
3. enable when supported:
   - `planeDetection = [.horizontal, .vertical]`
   - `sceneReconstruction = .meshWithClassification`
   - supported scene depth semantics
4. launch `RoomCaptureView`
5. use the RoomPlan path that supports a custom `ARSession`
6. during capture:
   - collect RoomPlan structural output
   - collect periodic RGB keyframes
   - collect camera transforms and intrinsics
   - collect optional scene depth snapshots
   - collect local object observations
7. on scan completion:
   - export `CapturedRoom`
   - export `USDZ`
   - request current world map
   - persist everything locally
   - queue backend upload if delayed processing is enabled

## 16. Relocalization Pipeline

Implement relocalization as follows:

1. load saved `ARWorldMap`
2. initialize new `ARWorldTrackingConfiguration`
3. set `initialWorldMap`
4. start AR session
5. keep UI in `Relocalizing` until tracking is stable
6. only restore persistent overlays after stable relocalization
7. if relocalization fails:
   - offer live-only mode
   - keep room viewer and backend query features available

## 17. Real-Time Detection Stack

Use a two-tier detection stack.

### 17.1 Tier 1: On-Device Closed-Set Detector

Purpose:

1. low-latency search for known personal objects
2. resilient demo and daily-use path

Implementation:

1. train closed-set object detector with `Create ML` or custom Core ML conversion
2. run on downscaled frames
3. process at `2-10 fps` depending on thermal budget
4. maintain tracks between detector passes
5. localize detections into 3D using depth and raycast fusion

### 17.2 Tier 2: Backend Open-Vocabulary Detector

Purpose:

1. search by arbitrary label or phrase
2. support queries like `show me the blue notebook`

Implementation:

1. select keyframes from the current live session or saved room
2. send them to backend
3. run text-conditioned detection with `Grounding DINO`
4. refine masks with `SAM 2` or equivalent
5. project detections back into 3D room coordinates using saved poses and depth
6. return ranked object candidates to client

## 18. 3D Localization and Tracking

For every detection:

1. derive image-space box or mask
2. estimate depth using:
   - scene depth if present
   - raycast against AR mesh if depth is absent
3. compute 3D point in camera coordinates
4. transform into world coordinates
5. fuse repeated detections into an observation track
6. save only stable tracks

Observation fusion rules:

1. merge same-label observations within `0.4m` and `2s`
2. smooth active display transform
3. preserve highest-confidence evidence
4. label newest stable confirmed observation as `last seen`

## 19. Delayed Reconstruction Pipeline

This pipeline is a first-class subsystem, not a stretch goal.

### 19.1 Input Bundle

Every backend reconstruction job receives:

1. RGB keyframes
2. camera timestamps
3. ARKit poses
4. camera intrinsics
5. optional depth maps
6. RoomPlan export
7. local observations

### 19.2 Reconstruction Stages

Run these stages:

1. keyframe filtering
2. pose validation and correction
3. geometry reconstruction
4. dense representation generation
5. semantic segmentation and tagging
6. scene graph materialization

### 19.3 Geometry Stack

Use this priority order:

1. `ARKit + RoomPlan` as fast parametric scaffold
2. `DA3` for geometry-consistent delayed reconstruction from arbitrary views
3. `COLMAP`-class SfM only when pose recovery or validation is needed
4. `3D Gaussian Splatting` for high-fidelity saved-room viewing

### 19.4 Output Assets

Persist:

1. refined mesh or point representation
2. Gaussian Splat scene if generated
3. semantic masks and instance records
4. scene graph
5. object embedding index
6. hidden-location hypotheses

## 20. Scene Representation

The system must maintain four scene representations in parallel.

### 20.1 Parametric Room Representation

Source:

1. RoomPlan

Contains:

1. walls
2. openings
3. major furniture
4. sections
5. dimensions

### 20.2 AR Spatial Memory

Source:

1. ARWorldMap
2. AR mesh
3. persistent object anchors

Contains:

1. relocalization state
2. local world coordinates
3. current session anchors

### 20.3 Dense Visual Representation

Source:

1. delayed reconstruction

Contains:

1. refined geometry
2. dense visual detail
3. view synthesis assets

### 20.4 Semantic Scene Graph

Source:

1. RoomPlan
2. local observations
3. backend detections
4. inferred spatial relations

Contains nodes:

1. room
2. section
3. surface
4. furniture
5. container
6. personal object
7. occluder
8. hypothesis

Contains edges:

1. `contains`
2. `supports`
3. `inside`
4. `near`
5. `leftOf`
6. `rightOf`
7. `inFrontOf`
8. `behind`
9. `under`
10. `occludes`

## 21. Hidden Object Engine

This subsystem has three implementation paths.

### 21.1 Path A: Cooperative Hidden Search

Use a second iPhone or cooperative peer device.

Implementation:

1. discover peer over `MultipeerConnectivity`
2. exchange discovery tokens
3. start `NISession`
4. enable camera assistance where supported
5. transform direction and distance into estimated world-space target
6. render a `signal-derived` beacon in AR

### 21.2 Path B: Tagged Object Search

Use a custom object tag or accessory.

Preferred implementation:

1. custom UWB accessory if available
2. BLE fallback if UWB is unavailable

Behavior:

1. object prototype is associated with a persistent tag ID
2. search planner resolves query to signal path
3. result is returned as `signal-confirmed` or `signal-estimated`

### 21.3 Path C: Non-Cooperative Hidden Search

This path is inference-only.

The engine must compute likelihood over candidate locations from:

1. last-seen position
2. user motion path
3. room topology
4. support surfaces
5. containment priors
6. occlusion reasoning
7. object affordances
8. temporal decay

Example reasoning:

1. last seen on bed
2. blanket or clothes pile now occludes last-seen region
3. wallet-sized object not visible in current frame
4. probability mass increases for:
   - under blanket near last-seen point
   - on floor next to bed edge
   - inside nearby nightstand if recent motion suggests pickup

Return:

1. ranked hypotheses
2. confidence values
3. explanation strings
4. heatmap or glow regions in AR and in room viewer

This path must never be labeled as direct detection.

## 22. Search Planning

Every query goes through a planner.

Planner inputs:

1. query text
2. voice transcript
3. room context
4. known object prototypes
5. available sensors and tags
6. current session state

Planner outputs:

1. search class
2. execution path
3. evidence sources
4. response type

Planner order:

1. if tagged or cooperative target exists, prefer signal path
2. else if closed-set local model supports target, run local visible search
3. else if backend is available, run open-vocabulary visible search
4. else if prior observation exists, run last-seen retrieval
5. always compute hidden-object likelihood if target remains unresolved

## 23. Query System

Use a layered query engine.

### 23.1 Layer 1: Intent Parsing

Supported intent families:

1. `findObject`
2. `findLikelyObjectLocation`
3. `countObjects`
4. `listObjectsInSection`
5. `showNearest`
6. `showSupportingSurface`
7. `showContainedItems`
8. `explainWhy`

### 23.2 Layer 2: Query DSL

Normalize parsed queries into a structured internal form:

```text
FIND object="wallet" mode=best_available
FIND object="airpods case" mode=visible_or_last_seen
COUNT category="chair"
SHOW_NEAREST object="remote" anchor="couch"
EXPLAIN hypothesis_id="..."
```

### 23.3 Layer 3: Executors

Executors:

1. local observation executor
2. scene graph executor
3. signal executor
4. backend retrieval executor
5. hidden inference executor

### 23.4 Layer 4: Response Renderer

Render responses as:

1. AR guidance overlay
2. room viewer annotation
3. ranked result cards
4. textual explanation

## 24. Voice and Text Input

Implement voice input with `Speech`.

Behavior:

1. tap mic
2. stream transcript to input field
3. parse final transcript
4. preserve transcript as query history

If speech is unavailable:

1. fall back to text immediately

## 25. UI Rules

The UI must make evidence type obvious.

### 25.1 Overlay Types

1. `solid highlight`
   - confirmed visible
2. `anchored marker`
   - last seen
3. `signal beacon`
   - UWB/BLE derived
4. `heat region`
   - estimated likely hidden location

### 25.2 Labels

Use these labels only:

1. `Detected`
2. `Last seen`
3. `Signal estimate`
4. `Likely here`

Do not use:

1. `thermal`
2. `x-ray`
3. `through-wall`
4. `confirmed` for inference-only results

## 26. Saved Room Viewer

The viewer is a first-class feature, not a fallback.

Viewer requirements:

1. inspect room in 3D
2. rotate
3. zoom
4. jump to object
5. show hypothesis heat regions
6. toggle layers:
   - RoomPlan scaffold
   - object observations
   - hidden-object heatmap
   - delayed dense reconstruction

Implementation path:

1. `Quick Look` for immediate USDZ support
2. custom RealityKit viewer for layered annotations
3. optional web or native Gaussian Splat viewer for dense delayed scenes

## 27. Backend API Surface

Define these backend operations:

1. `POST /rooms`
2. `POST /rooms/{id}/frame-bundles`
3. `POST /rooms/{id}/reconstruct`
4. `POST /rooms/{id}/index`
5. `POST /rooms/{id}/query`
6. `POST /rooms/{id}/open-vocab-search`
7. `GET /rooms/{id}/scene-graph`
8. `GET /rooms/{id}/hypotheses`
9. `GET /rooms/{id}/assets`

Required API result fields:

1. `resultType`
2. `confidence`
3. `worldTransform`
4. `evidence`
5. `explanation`

## 28. Backend ML Stack

### 28.1 Open-Vocabulary Detection

Primary stack:

1. `Grounding DINO` for text-conditioned region proposals
2. `SAM 2` or equivalent for mask refinement and propagation

### 28.2 Embedding Retrieval

Maintain embeddings for:

1. object crops
2. frame regions
3. query text

Use them for:

1. phrase-based search
2. visual nearest-neighbor retrieval
3. re-ranking detection candidates

### 28.3 Reconstruction

Primary stack:

1. `DA3` for geometry-consistent reconstruction from arbitrary views
2. `3D Gaussian Splatting` for high-fidelity room rendering
3. `COLMAP`-class SfM when additional pose solving is required

### 28.4 Hidden Inference Models

Implement a probabilistic reasoning layer over:

1. scene graph
2. object priors
3. occlusion map
4. user interaction history

The hidden inference layer may begin as rule-based and later evolve into learned ranking.

## 29. Real-Time vs Delayed Paths

Support both paths explicitly.

### 29.1 Real-Time Path

Constraints:

1. low latency
2. stable AR tracking
3. limited model size

Responsibilities:

1. room relocalization
2. on-device closed-set visible search
3. local last-seen retrieval
4. live AR guidance

### 29.2 Delayed Path

Constraints:

1. may take seconds to minutes
2. can use backend GPU

Responsibilities:

1. open-vocabulary search
2. dense reconstruction
3. semantic indexing
4. hidden-location reasoning
5. richer saved-room exploration

## 30. Performance Targets

These are engineering targets, not scope reducers.

### 30.1 Mobile Targets

1. relocalization target under `10s`
2. on-device detector target `2-10 fps`
3. query parse under `300ms`
4. AR overlay update under `100ms` after local result resolution

### 30.2 Backend Targets

1. open-vocabulary single-query response under `3-10s`
2. delayed reconstruction initial result under `1-5 min`
3. semantic indexing under `1 min` after reconstruction assets are ready

## 31. Testing Matrix

Test these environments:

1. clean bedroom
2. cluttered bedroom
3. living room
4. low-light indoor room
5. room with blankets, cushions, drawers, and clothing piles

Test these search types:

1. visible known object
2. visible arbitrary object phrase
3. last-seen retrieval
4. cooperative hidden target
5. tagged hidden target
6. probabilistic hidden-object estimate

## 32. Acceptance Criteria

The full system is acceptable when all of these are true:

1. A room can be scanned, saved, reopened, and relocalized.
2. The app supports both live search and delayed search.
3. Known personal objects can be detected and localized in 3D on-device.
4. Arbitrary query phrases can be resolved by the backend open-vocabulary path.
5. The saved room viewer supports object and hypothesis inspection.
6. Cooperative hidden-target mode works with a second iPhone.
7. Tagged-object mode works with a custom signal source.
8. Non-cooperative hidden-object mode returns ranked likely locations with explanation and does not present inference as direct detection.

## 33. Build Order

Implement in this order:

1. spatial foundation
2. room persistence and relocalization
3. on-device closed-set search
4. AR result overlays
5. room graph and query DSL
6. saved room viewer with annotations
7. backend frame ingestion
8. delayed reconstruction
9. backend open-vocabulary search
10. hidden-object likelihood engine
11. cooperative UWB path
12. tagged-object path
13. dense viewer and advanced explanation layer

This order is mandatory for dependency reasons, not for scope reduction.

## 34. Explicit Decisions

These decisions are locked unless revised:

1. The client is native iOS, not cross-platform.
2. RoomPlan is the room-structure foundation.
3. ARWorldMap is the relocalization foundation.
4. The system has both local and backend search paths.
5. Hidden-object support is implemented as:
   - cooperative sensing
   - tagged sensing
   - probabilistic inference
6. Dense delayed reconstruction is part of the architecture.
7. The system must preserve evidence provenance in every result.

## 35. Explicit Non-Goals

These are not part of the system unless future hardware changes:

1. true thermal sensing on iPhone 15 Pro Max
2. non-cooperative direct sensing through opaque occluders on stock iPhone hardware
3. unsupported private Apple APIs for AirPods location access

## 36. References

Primary references used for this spec:

1. Apple RoomPlan overview: <https://developer.apple.com/augmented-reality/roomplan/>
2. Apple RoomPlan captured room model provider note that observed objects are approximated with bounding boxes: <https://developer.apple.com/documentation/roomplan/capturedroom/modelprovider>
3. Apple custom models and structure exports for RoomPlan: <https://developer.apple.com/documentation/roomplan/providing-custom-models-for-captured-rooms-and-structure-exports>
4. Apple ARKit saving and loading world data: <https://developer.apple.com/documentation/arkit/saving-and-loading-world-data>
5. Apple ARKit reconstructed scene interaction: <https://developer.apple.com/documentation/arkit/world_tracking/visualizing_and_interacting_with_a_reconstructed_scene>
6. Apple RealityKit scene understanding: <https://developer.apple.com/documentation/realitykit/realitykit-scene-understanding>
7. Apple Nearby Interaction overview: <https://developer.apple.com/nearby-interaction/>
8. Apple Find My network overview: <https://developer.apple.com/find-my/>
9. Apple Speech framework: <https://developer.apple.com/documentation/speech>
10. Apple Natural Language framework: <https://developer.apple.com/documentation/naturallanguage>
11. Apple iPhone 15 Pro Max technical specs: <https://support.apple.com/kb/SP904>
12. Depth Anything 3 paper: <https://arxiv.org/abs/2511.10647>
13. Depth Anything 3 official repository: <https://github.com/ByteDance-Seed/Depth-Anything-3>
14. Grounding DINO paper: <https://arxiv.org/abs/2303.05499>
15. Grounding DINO official repository: <https://github.com/IDEA-Research/GroundingDINO>
16. Segment Anything 2 paper link from official Meta repository: <https://arxiv.org/abs/2408.00714>
17. Segment Anything official repository linking to SAM 2 resources: <https://github.com/facebookresearch/segment-anything>
18. 3D Gaussian Splatting paper: <https://arxiv.org/abs/2308.04079>
19. 3D Gaussian Splatting official repository: <https://github.com/graphdeco-inria/gaussian-splatting>
20. COLMAP official documentation: <https://colmap.github.io/>
