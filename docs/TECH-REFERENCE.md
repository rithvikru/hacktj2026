# Technical Reference: Verified Implementation Details

Source: architectural analysis of the v2.0 spec, filtered to verified/accurate content only.
Unverified claims (NOAM, ILGS, specific benchmark numbers) are excluded.

## 1. Three-Plane Architecture

| Plane | Responsibilities |
|-|-|
| iPhone Client | AR session, RoomPlan scan, relocalization, AR overlays, local object memory, query input, optional local acceleration, peer discovery |
| Backend Compute | Query planning, delayed reconstruction, frame indexing, open-vocabulary search, segmentation, scene graph, hidden-object inference, embeddings |
| Persistence | Room assets, frame bundles, embeddings, scene graph, object observations, hypotheses, query results |

## 2. Four Result Confidence Classes

| Class | Source | Epistemic State | AR Overlay |
|-|-|-|-|
| Visible Confirmed | Live RGB + inference | High certainty, current | Solid highlight / bounded box |
| Previously Confirmed | Local persistence | High certainty, historical | Anchored marker at last 3D coord |
| Signal Confirmed | UWB / BLE | Medium-high certainty, current | Floating signal beacon |
| Likely Hidden | Probabilistic model | Variable probability, inferred | Volumetric heat region / glow mesh |

## 3. Visible Search Stack

- Natural-language planner layer resolves the user query before search execution
- Primary visible-search path is backend open-vocabulary grounding plus segmentation plus retrieval
- Optional local `Core ML` detector may be used as an accelerator for a small label pack
- Detection flow remains: 2D region -> depth estimation (LiDAR scene depth preferred, raycast against AR mesh as fallback) -> camera-space 3D point -> world-space transform
- Observation fusion: merge same-label detections within 0.4m radius and 2s window
- Preserve highest-confidence evidence per track
- Downgrade stable observations to "Last Seen" when object leaves frustum or becomes occluded

## 4. Relocalization

- Serialize `ARWorldMap` via `NSKeyedArchiver` during scan
- On re-entry: load saved world map as `initialWorldMap` on new `ARWorldTrackingConfiguration`
- UI holds "Relocalizing" state until tracking stabilizes
- Only restore persistent overlays after stable tracking
- Graceful degradation: if relocalization fails, offer live-only mode; saved room viewer and backend queries remain available
- Prune historical feature points aggressively before persistence to keep map size manageable

## 5. Keyframe Extraction and Frame Bundles

Each bundle contains:
- High-resolution RGB images
- Nanosecond timestamps
- Camera extrinsics (4x4 transform, 16 column-major floats)
- Camera intrinsics (3x3, 9 floats)
- Tracking state per frame
- Dense scene depth + confidence maps (when available)
- Device metadata

Selection heuristic: prioritize frames with high translational movement or significant rotational disparity relative to previously saved frames.

## 6. Delayed Reconstruction Pipeline

### 6.1 Geometry Stack Priority Order

1. **ARKit + RoomPlan** — fast parametric scaffold (immediate, on-device)
2. **DA3 (Depth Anything 3)** — feed-forward metric depth estimation from arbitrary views
3. **COLMAP-class SfM** — only when pose recovery or validation is needed
4. **3D Gaussian Splatting** — high-fidelity saved-room viewing

### 6.2 DA3 (Depth Anything 3)

- Source: ByteDance-Seed, arxiv 2511.10647
- Predicts metric-scale, spatially consistent depth from monocular or multi-view input
- Uses DINOv2 vision transformer backbone
- Can incorporate ARKit poses as conditioning when they are reliable
- Can operate pose-free when mobile poses exhibit drift (e.g., feature-poor walls)
- Eliminates the need for iterative bundle adjustment, producing dense point clouds directly
- Massive speedup over traditional SfM for the delayed reconstruction SLA (1-5 min target)

### 6.3 3D Gaussian Splatting (3DGS)

- Source: arxiv 2308.04079, graphdeco-inria
- Represents scene as explicit collection of anisotropic 3D Gaussians
- Each Gaussian stores: 3D position, covariance (scale + rotation), opacity, spherical harmonics (view-dependent color)
- DA3-generated point cloud serves as initialization for Gaussian positions
- Optimized via gradient descent against RGB keyframes
- Renders via tile-based rasterization (designed for desktop GPU; mobile rendering requires significant optimization/quality tradeoff)

### 6.4 Semantic Embedding in 3D

The spec requires CLIP-like embeddings attached to the 3D representation for open-vocabulary queries in the saved room viewer. Verified approaches in the literature:

- **LangSplat** — language-embedded Gaussian splatting
- **LEGaussians** — language-embedded 3D Gaussians
- **Feature 3DGS** — feature field distillation into Gaussians

General approach: use pre-trained 2D vision-language models (CLIP, OpenSeg, LSeg) to compute per-pixel feature maps, then project/distill those features onto the 3D Gaussians. This avoids training a 3D semantic network from scratch.

**Key challenge:** view inconsistency — different language embeddings assigned to the same object from different angles due to alpha-blending ambiguity. Solutions involve cross-frame identity tracking (e.g., SAM 2 for consistent segmentation across views) and contrastive losses to enforce embedding consistency.

## 7. Open-Vocabulary Search (Primary Visible Path)

1. Client sends keyframes to backend
2. **Grounding DINO** (arxiv 2303.05499): text-conditioned region proposals from arbitrary query strings
3. **SAM 2** (arxiv 2408.00714): refines bounding boxes into precise instance masks
4. Back-projection: 2D masks -> 3D world coords using DA3 depth maps + camera poses
5. Return ranked candidates with confidence + explanation to client
6. Target latency: 3-10s (requires pre-warmed GPU instances)

## 8. Scene Graph Structure

### Node Types
- Room, section, surface (from RoomPlan)
- Furniture, container, personal object (from detection)
- Occluder (from segmentation)
- Hypothesis (from inference engine)

### Edge Types and Computation

| Edge | Computation Method |
|-|-|
| `contains`, `inside` | 3D bounding box intersection — object fully encapsulated within container volume |
| `supports`, `under` | Vertical raycasting + proximity threshold — object rests above horizontal surface |
| `near`, `leftOf`, `rightOf`, `inFrontOf`, `behind` | Euclidean distance + camera-relative directional vectors |

### Node Fields
- `worldTransform16`: 16 column-major floats (homogeneous 4x4 matrix)
- `extentXYZ`: 3 floats defining bounding box dimensions
- `parentID`: optional hierarchical relationship
- `attributesJSON`: flexible metadata

## 9. Hidden Object Engine

### Path A: Cooperative (Second iPhone)
- `MultipeerConnectivity` for discovery
- Token exchange -> `NISession` (UWB via Nearby Interaction)
- Camera assistance where supported
- Transform direction + distance into world-space target
- Result class: `Signal Confirmed`

### Path B: Tagged (Custom UWB/BLE accessory)
- Associate object prototype with persistent tag ID
- UWB preferred, BLE RSSI fallback
- Result class: `Signal Estimated`

### Path C: Non-Cooperative Probabilistic Inference
- Inputs: last-seen position, user motion path, room topology, support surfaces, containment priors, occlusion reasoning, object affordances, temporal decay
- The spec explicitly allows starting rule-based and evolving to learned ranking
- Output: ranked hypotheses with confidence values, explanation strings, heatmap regions
- Visualization: volumetric heatmap via custom Metal shader (warm colors = high probability, cool = low)
- **Must** be labeled "Likely here" — never presented as direct detection

## 10. Query System

### Intent Families
`findObject`, `findLikelyObjectLocation`, `countObjects`, `listObjectsInSection`, `showNearest`, `showSupportingSurface`, `showContainedItems`, `explainWhy`

### Query DSL Examples
```
FIND object="wallet" mode=best_available
COUNT category="chair"
SHOW_NEAREST object="remote" anchor="couch"
EXPLAIN hypothesis_id="..."
```

### Executor Priority Order
1. Signal executor (check for active hardware tag)
2. Local observation executor (recent on-device observations)
3. Backend retrieval executor (open-vocabulary pipeline)
4. Scene graph executor (traverse relational graph)
5. Hidden inference executor (probabilistic pipeline)

## 11. Performance Targets

### Mobile
| Metric | Target |
|-|-|
| Relocalization | < 10s |
| Optional local accelerator | 2-10 fps (thermal-dependent) |
| Query parse | < 300ms |
| AR overlay update after local result | < 100ms |

### Backend
| Metric | Target |
|-|-|
| Open-vocabulary single query | 3-10s |
| Delayed reconstruction initial result | 1-5 min |
| Semantic indexing after reconstruction | < 1 min |

## 12. Persistence Rules

- Heavy assets in files/object storage, never inline in SwiftData
- `ARWorldMap` archived with `NSKeyedArchiver`
- All transforms stored as 16 column-major floats
- Every room save: RoomPlan export + preview image + world map
- Every reconstruction upload: RGB keyframes + timestamps + poses + intrinsics + device metadata

## 13. UI Constraints (Non-Negotiable)

### Allowed Labels
- `Detected`
- `Last seen`
- `Signal estimate`
- `Likely here`

### Banned Terminology
- `thermal`, `x-ray`, `through-wall`
- `confirmed` for inference-only results

## 14. Backend API Surface

```
POST /rooms
POST /rooms/{id}/frame-bundles
POST /rooms/{id}/reconstruct
POST /rooms/{id}/index
POST /rooms/{id}/query
POST /rooms/{id}/open-vocab-search
GET  /rooms/{id}/scene-graph
GET  /rooms/{id}/hypotheses
GET  /rooms/{id}/assets
```

All responses must include: `resultType`, `confidence`, `worldTransform`, `evidence`, `explanation`

## 15. Build Order (Mandatory)

1. Spatial foundation (AR + RoomPlan scan)
2. Room persistence and relocalization
3. Backend frame ingestion
4. Planner-led open-vocabulary search
5. AR result overlays
6. Room graph and query DSL
7. Saved room viewer with annotations
8. Hidden-object likelihood engine
9. Delayed reconstruction
10. Cooperative UWB path
11. Tagged-object path
12. Dense viewer and advanced explanation layer
13. Optional local accelerator

## 16. Open Implementation Questions

These areas are left deliberately flexible by the spec:

- Specific hidden-object inference approach (rule-based vs. LLM vs. learned ranking)
- Specific semantic Gaussian splatting variant (LangSplat vs. LEGaussians vs. other)
- Mobile 3DGS rendering strategy (quality/performance tradeoff unspecified)
- Backend infrastructure provisioning (GPU type, scaling strategy)
- Privacy model for uploaded room data
- Offline/degraded-network behavior beyond "live-only mode"
- Data retention and deletion policies
