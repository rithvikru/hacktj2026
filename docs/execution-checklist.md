# Execution Checklist

Status: active implementation checklist  
Purpose: strict team execution order for app, backend, planner, and ML work  
Primary references:
- `docs/technical-implementation-spec.md`
- `docs/ai-ml-model-spec.md`
- `docs/natural-language-search-spec.md`

## Owner Map

Use these role names unless you want to rename them later.

- `APP`: iOS / SwiftUI / ARKit / RoomPlan owner
- `PLANNER`: natural-language planner and query-orchestration owner
- `ML`: perception, retrieval, reconstruction, and hidden-inference owner
- `BACKEND`: API, storage, database, job execution owner

Current assumption:
- you = `ML`
- teammate handling natural-language search = `PLANNER`
- frontend/mobile teammate = `APP`
- if no dedicated infra person exists, `PLANNER` and `ML` split `BACKEND`

## What Exists Already

- room scan, room save, local SwiftData persistence
- frame-bundle generation and backend upload trigger
- AR live search screen
- query console UI
- hidden search UI
- room twin viewer with dense asset toggle
- backend routes for query, chat, route, frame-bundle upload, reconstruction, and assets

## Main Gaps

- device-ready backend connectivity and configuration
- remaining placeholder app screens
- real backend database and durable room state
- production LLM planner integration
- production-quality `M2-M4` inference over real room bundles
- stronger delayed reconstruction and dense asset generation
- full device validation on iPhone 15 Pro Max

## Strict Execution Order

### Phase 1: Make The Current Product Loop Reliable

Goal: scan a room on iPhone, upload it, reconstruct it, query it, and view results on device.

- `APP` add configurable backend base URL and stop relying on `localhost`
- `APP` replace placeholder `CompanionTarget`, `ScanResults`, `ObjectDetail`, and `Settings`
- `APP` add backend health / connection status in settings or top-level diagnostics
- `APP` test full scan -> save -> upload -> reconstruct -> room twin flow on a real iPhone
- `BACKEND` replace in-memory room store with SQLite or Postgres
- `BACKEND` persist room metadata, bundle paths, reconstruction status, and asset metadata
- `BACKEND` make reconstruction jobs resumable across process restarts
- `PLANNER` wire the real GPT-class planner provider into the `/planner/parse` and `/chat` path
- `PLANNER` implement structured planner input assembly from room metadata, scene graph summaries, and recent observations
- `ML` make sure `M2-M4` can run against uploaded frame bundles from the real app output format

Phase 1 exit criteria:
- app works on physical iPhone 15 Pro Max
- backend survives restart without losing room state
- query returns real planner-backed results instead of only fallback behavior

### Phase 2: Make Search Quality Real

Goal: natural-language object search works well enough to demo repeatedly.

- `PLANNER` finalize planner executor ordering from `docs/natural-language-search-spec.md`
- `ML` productionize `M2` Grounding DINO execution
- `ML` productionize `M3` SAM 2 mask refinement
- `ML` productionize `M4` OpenCLIP embedding generation and retrieval index build
- `ML` improve 2D -> 3D projection and cross-frame fusion for stable world transforms
- `BACKEND` return stronger evidence payloads including mask refs, frame refs, and confidence provenance
- `APP` improve live search UX for relocalization failures, backend failure states, and no-result states
- `APP` show route guidance only when the target has a stable world transform

Phase 2 exit criteria:
- freeform text query finds visible objects from saved scans
- live search returns stable AR overlays and route waypoints
- query console answers with grounded evidence and explanations

### Phase 3: Make Hidden Search Good

Goal: when the object is not directly visible, the app still gives useful ranked search regions.

- `ML` keep current rule-based `M7` working as baseline
- `ML` define hidden-object benchmark episodes from private room data
- `ML` engineer hidden-search features: last seen, support surfaces, containers, occlusion priors, temporal decay
- `ML` train learned `M7` only after the benchmark exists and rule-based baseline is measured
- `BACKEND` serve hidden hypotheses with explicit confidence and reason codes
- `APP` improve hidden-search explanations and heatmap interaction

Phase 3 exit criteria:
- hidden search produces ranked hypotheses that are better than random/manual guessing
- the app clearly labels these as inferred, not detected

### Phase 4: Make Dense Saved-Room Viewing Good

Goal: the room twin becomes a genuinely useful saved-room inspection mode.

- `ML` harden `M5` Depth Anything 3 pipeline on real uploaded room bundles
- `ML` improve point-cloud generation quality and pose validation
- `ML` harden `M6` 3D Gaussian Splatting generation from real room scans
- `BACKEND` version and store dense assets cleanly per room and reconstruction run
- `APP` support downloading, caching, and invalidating dense assets
- `APP` improve dense/scaffold/heatmap/object layer controls in the room twin

Phase 4 exit criteria:
- at least one real room reconstructs into a useful dense twin
- the dense twin loads from backend assets in the app reliably

## App Checklist

Owner: `APP`

- add `backendBaseURL` configuration
- confirm device-friendly ATS / local-network setup if backend is on LAN
- replace all remaining stub views
- improve scan completion UX
- improve object-detail view from real observation data
- add reconstruction progress states in room cards and room viewer
- add retry actions for upload, reconstruction fetch, and search failures
- test world-map relocalization repeatedly in the same room
- test memory / thermal behavior on iPhone 15 Pro Max

## Backend Checklist

Owner: `BACKEND`

- add real persistent DB
- migrate room store off in-memory state
- make room creation, upload, reconstruction, and asset fetch idempotent
- add job records and failure reasons
- persist planner responses and query audit logs if useful for debugging
- add versioning for planner, `M2`, `M3`, `M4`, `M5`, and `M7`
- add request logging and timing metrics
- add auth only if you need multi-user or external demo exposure

## Planner Checklist

Owner: `PLANNER`

- implement the real planner provider
- keep planner output structured JSON only
- preserve query text, normalized phrase, attributes, and spatial relations
- resolve ambiguity explicitly instead of collapsing it silently
- select executor order exactly per `docs/natural-language-search-spec.md`
- merge search evidence into one grounded response
- keep explanation generation grounded in structured evidence only
- add planner eval set and measure parse quality separately from visual quality

## ML Checklist

Owner: `ML`

- make `M2` run reliably on saved room keyframes
- make `M3` run reliably from `M2` box prompts
- make `M4` build and query retrieval indexes from room frames
- improve world-transform derivation from depth + pose + masks
- keep current rule-based `M7` working as baseline
- collect private benchmark data for visible, partially occluded, and hidden cases
- measure visible search, hidden search, and reconstruction separately
- upgrade delayed reconstruction quality using real room bundles

## What Models Need Training

Train now only where it actually helps.

- `Planner`: no model training required initially; use a GPT-class provider with good prompting and strict schemas
- `M2` Grounding DINO: start pretrained
- `M3` SAM 2: start pretrained
- `M4` OpenCLIP: start pretrained; optional fine-tune later if retrieval quality is weak on your domain
- `M5` Depth Anything 3: start pretrained
- `M6` 3D Gaussian Splatting: per-room optimization, not a normal global training job
- `M7` hidden-object ranker: rule-based first, train later after benchmark data exists
- `M1` on-device closed-set detector: optional only; do not treat as core product work

## Models To Use Right Now

- planner layer: GPT-class model
- `M2`: Grounding DINO
- `M3`: SAM 2
- `M4`: OpenCLIP
- `M5`: Depth Anything 3
- `M6`: 3D Gaussian Splatting
- `M7`: hidden-object ranker
- `M1`: optional accelerator only

## Recommended Immediate Sprint

This is the highest-leverage next sprint.

- `APP` make device backend URL configurable and replace the remaining stub views
- `BACKEND` add SQLite persistence for rooms, frame bundles, and reconstruction status
- `PLANNER` wire the real planner provider into the current API contracts
- `ML` get `M2-M4` producing real results on uploaded frame bundles from one room end to end
- `ALL` run one real-room demo path start to finish on iPhone 15 Pro Max

## Definition Of Done For The First Real Demo

- scan room on device
- save room locally
- upload room bundle automatically
- backend reconstruction completes
- user asks a natural-language query
- planner resolves it
- visible search returns grounded result or hidden search returns ranked hypothesis
- AR view or room twin visualizes the result correctly
