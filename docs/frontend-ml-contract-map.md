# Frontend-ML Contract Map

Status: mapping only, no implementation sync  
Date: `2026-03-07`  
Owners: `iOS lead`, `backend lead`, `AI/ML lead`

This document maps the current iOS frontend contracts to the ML/backend outputs without changing either side yet.

Use this as the bridge between:

1. [docs/TECH-REFERENCE.md](/Users/rithvikr/projects/hacktj2026/docs/TECH-REFERENCE.md)
2. [docs/technical-implementation-spec.md](/Users/rithvikr/projects/hacktj2026/docs/technical-implementation-spec.md)
3. [docs/ai-ml-model-spec.md](/Users/rithvikr/projects/hacktj2026/docs/ai-ml-model-spec.md)
4. the current Swift client in `mobile/`
5. the current FastAPI and ML contracts in `ml/`

## 1. Purpose

The repo currently has three different contract layers:

1. `ML internal model outputs`
2. `backend HTTP responses`
3. `frontend Swift models`

Those layers are not aligned yet.

The main conflict is naming and shape:

1. the AI/ML spec and Python contracts use `snake_case`
2. the technical reference and Swift client expect `camelCase`
3. the current Swift search DTOs are much thinner than the ML outputs the app will eventually need

This document resolves that conflict by defining a strict adapter boundary.

## 2. Contract Decision

Apply these rules exactly:

1. `ML internal contracts` stay in `snake_case` and follow [contracts.py](/Users/rithvikr/projects/hacktj2026/ml/src/hacktj2026_ml/contracts.py).
2. `Mobile-facing HTTP contracts` use `camelCase`.
3. The `backend adapter layer` converts between the two.
4. The frontend must never decode raw model-native payloads directly into UI models.
5. `POST /rooms/{id}/query` is the app-ready search endpoint.
6. `POST /rooms/{id}/open-vocab-search` is a lower-level backend search endpoint for debugging, offline tooling, and optional power-user UI.

## 3. Naming Normalization

Use this mapping consistently.

| Mobile HTTP | ML internal | Notes |
| --- | --- | --- |
| `resultType` | `result_type` | query/search outcome |
| `queryText` | `query_text` | user prompt |
| `queryLabel` | `query_label` | normalized label after intent/entity resolution |
| `modelID` | `model_id` | versioned model identity |
| `modelVersion` | `model_version` | semantic version string |
| `frameID` | `frame_id` | frame reference |
| `maskRef` | `mask_ref` | mask asset reference |
| `bboxXYXYNorm` | `bbox_xyxy_norm` | normalized image-space box |
| `worldTransform16` | `world_transform16` | flattened 4x4 transform |
| `reasonCodes` | `reason_codes` | hidden inference explanations |
| `sceneGraphVersion` | `scene_graph_version` | scene graph materialization version |
| `reconstructionStatus` | `reconstruction_status` | room job state |

## 4. Canonical Enums

### 4.1 Query Result Type

This is the canonical app-facing query outcome enum.

```text
detected
lastSeen
signalEstimated
likelyHidden
notFound
```

Rules:

1. `detected` means currently visible or directly localized from recent visual evidence.
2. `lastSeen` means previously observed and anchored, not currently confirmed.
3. `signalEstimated` covers cooperative or tagged signal paths.
4. `likelyHidden` means probabilistic inference only.
5. `notFound` means no usable evidence was found.

Mapping from current ML/internal result families:

| ML/internal state | App-facing `resultType` |
| --- | --- |
| `detected` | `detected` |
| `last_seen` | `lastSeen` |
| `signal_estimated` | `signalEstimated` |
| `likely_hidden` | `likelyHidden` |
| zero candidates / unresolved query | `notFound` |

Important:

1. `confirmedHigh`, `confirmedMedium`, and similar confidence buckets are not query result types.
2. Confidence buckets may still exist in UI, but they are presentation state, not transport state.

### 4.2 Observation Source

Use this canonical mapping:

| Mobile local enum | Backend source |
| --- | --- |
| `closedSet` | `m1.closed_set.detector` |
| `openVocabulary` | `m2.open_vocab.detector` plus `m3` and `m4` post-processing |
| `signal` | cooperative or tagged signal subsystem |
| `manual` | human annotation or manual correction only |

### 4.3 Hypothesis Type

The app needs per-hypothesis type even though the current `M7` contract only guarantees `likely_hidden`.

Canonical hypothesis types:

```text
cooperative
tagged
inferred
```

Rules:

1. `M7` hidden-ranker outputs map to `inferred`.
2. Nearby/cooperative signal results map to `cooperative`.
3. tag-based results map to `tagged`.

## 5. Canonical App-Facing DTOs

These are the DTOs the iOS app should eventually consume.

### 5.1 `SearchResultDTO`

This is the main result card and overlay payload.

```json
{
  "id": "uuid",
  "label": "wallet",
  "resultType": "detected",
  "confidence": 0.91,
  "worldTransform16": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
  "bboxXYXYNorm": [0.21, 0.34, 0.48, 0.62],
  "frameID": "uuid",
  "maskRef": null,
  "modelID": "m1.closed_set.detector",
  "modelVersion": "1.0.0",
  "evidence": ["localClosedSet", "recentFrame", "roomAlignedProjection"],
  "explanation": "Detected wallet in the current camera sweep.",
  "timestamp": "2026-03-07T12:00:00Z"
}
```

Rules:

1. `worldTransform16` is required for `detected`, `lastSeen`, and `signalEstimated`.
2. `worldTransform16` is optional for `notFound`.
3. `bboxXYXYNorm`, `frameID`, and `maskRef` are optional when the result is not frame-derived.
4. `evidence` must always be present, even if empty.
5. `explanation` must always be present.

### 5.2 `QueryResponseDTO`

This is the response from `POST /rooms/{id}/query`.

```json
{
  "queryID": "uuid",
  "queryText": "Where are my AirPods?",
  "queryLabel": "airpods_case",
  "resultType": "lastSeen",
  "primaryResult": {
    "id": "uuid",
    "label": "airpods_case",
    "resultType": "lastSeen",
    "confidence": 0.73,
    "worldTransform16": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
    "bboxXYXYNorm": null,
    "frameID": "uuid",
    "maskRef": null,
    "modelID": "memory.last_seen",
    "modelVersion": "1.0.0",
    "evidence": ["lastSeenMemory", "roomRelocalized"],
    "explanation": "AirPods case was last observed on the bed-side table.",
    "timestamp": "2026-03-07T12:00:00Z"
  },
  "results": [],
  "hypotheses": [],
  "explanation": "Returned the strongest available result using planner fallback order.",
  "generatedAt": "2026-03-07T12:00:01Z"
}
```

Rules:

1. `primaryResult` may be `null` only when `resultType = notFound`.
2. `results` contains additional ranked visible or last-seen candidates.
3. `hypotheses` is used when `resultType = likelyHidden` or when the planner wants to surface fallback hidden candidates.
4. `queryLabel` is the normalized label after intent parsing and synonym resolution.

### 5.3 `OpenVocabSearchResponseDTO`

This is the response from `POST /rooms/{id}/open-vocab-search`.

```json
{
  "queryText": "blue notebook",
  "resultType": "detected",
  "modelID": "m2.open_vocab.detector",
  "modelVersion": "1.0.0",
  "candidates": [
    {
      "id": "uuid",
      "confidence": 0.78,
      "bboxXYXYNorm": [0.11, 0.18, 0.36, 0.55],
      "maskRef": "mask://uuid",
      "frameID": "uuid",
      "worldTransform16": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
      "evidence": ["backendOpenVocab", "samMask", "3dProjection"],
      "explanation": "Projected open-vocabulary candidate into room coordinates."
    }
  ]
}
```

Rules:

1. This endpoint is not the main UI contract for query cards.
2. It is acceptable for `worldTransform16` to be absent when the candidate cannot yet be projected into room coordinates.
3. The backend adapter is responsible for adding `id`, `evidence`, and `explanation` on top of raw `M2/M3` outputs.

### 5.4 `HypothesisDTO`

This is the app-facing hidden-hypothesis object.

```json
{
  "id": "uuid",
  "queryLabel": "wallet",
  "hypothesisType": "inferred",
  "rank": 1,
  "confidence": 0.66,
  "worldTransform16": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
  "regionID": null,
  "supportObjectID": "uuid",
  "occluderObjectID": "uuid",
  "reasonCodes": ["near_last_seen", "soft_occluder_present", "size_compatible_surface"],
  "explanation": "Most likely under the blanket near the bed edge.",
  "generatedAt": "2026-03-07T12:00:00Z"
}
```

Rules:

1. `hypothesisType` is required for the app even if the raw ML output does not provide it.
2. `worldTransform16` or `regionID` must be present.
3. `reasonCodes` must map directly from the hidden ranker output.

### 5.5 `SceneGraphResponseDTO`

```json
{
  "roomID": "uuid",
  "sceneGraphVersion": 3,
  "nodes": [
    {
      "id": "uuid",
      "nodeType": "surface",
      "label": "nightstand",
      "worldTransform16": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
      "extentXYZ": [0.5, 0.7, 0.4],
      "parentID": null,
      "attributesJSON": "{}"
    }
  ],
  "edges": [
    {
      "id": "uuid",
      "sourceNodeID": "uuid",
      "targetNodeID": "uuid",
      "edgeType": "supports",
      "weight": 0.9
    }
  ]
}
```

### 5.6 `RoomAssetsResponseDTO`

```json
{
  "roomID": "uuid",
  "reconstructionStatus": "processing",
  "roomUSDZURL": null,
  "denseAssetURL": null,
  "sceneGraphVersion": 0,
  "frameBundleURL": null,
  "updatedAt": "2026-03-07T12:00:00Z"
}
```

Rules:

1. `GET /rooms/{id}/assets` is the canonical status endpoint for room backend jobs.
2. The current frontend can keep using it for status polling.
3. The backend must add actual asset URLs or object-store references later.

## 6. Endpoint-Level Mapping

### 6.1 `POST /rooms`

App request:

```json
{
  "name": "Bedroom",
  "metadata": {
    "deviceModel": "iPhone16,2"
  }
}
```

App response:

```json
{
  "roomID": "uuid",
  "name": "Bedroom",
  "status": "created"
}
```

### 6.2 `POST /rooms/{id}/frame-bundles`

Canonical request:

1. `Content-Type: application/zip`
2. request body is a zipped frame bundle
3. bundle contains:
   - keyframes
   - optional depth maps
   - frame metadata
   - intrinsics
   - poses
   - RoomPlan export
   - world map if available

App response:

```json
{
  "roomID": "uuid",
  "bundleID": "uuid",
  "status": "accepted"
}
```

Important:

1. the backend must not require a local server-side file path from the client
2. the current FastAPI `bundle_path` request shape is only a placeholder and is not the real app contract

### 6.3 `POST /rooms/{id}/reconstruct`

App response:

```json
{
  "roomID": "uuid",
  "jobID": "uuid",
  "jobType": "reconstruct",
  "status": "queued"
}
```

### 6.4 `POST /rooms/{id}/index`

App response:

```json
{
  "roomID": "uuid",
  "jobID": "uuid",
  "jobType": "index",
  "status": "queued"
}
```

### 6.5 `POST /rooms/{id}/query`

App request:

```json
{
  "queryText": "Where is my wallet?"
}
```

App response:

1. `QueryResponseDTO`

Planner behavior:

1. local closed-set if supported and available
2. backend open-vocabulary if needed
3. last-seen fallback
4. hidden inference if unresolved

### 6.6 `POST /rooms/{id}/open-vocab-search`

App request:

```json
{
  "queryText": "blue notebook",
  "frameRefs": ["uuid", "uuid"]
}
```

App response:

1. `OpenVocabSearchResponseDTO`

### 6.7 `GET /rooms/{id}/scene-graph`

App response:

1. `SceneGraphResponseDTO`

### 6.8 `GET /rooms/{id}/hypotheses`

App response:

```json
{
  "roomID": "uuid",
  "queryLabel": "wallet",
  "resultType": "likelyHidden",
  "modelID": "m7.hidden_ranker",
  "modelVersion": "1.0.0",
  "hypotheses": []
}
```

### 6.9 `GET /rooms/{id}/assets`

App response:

1. `RoomAssetsResponseDTO`

### 6.10 `GET /healthz`

Use this for app connectivity checks.

The app must not use `GET /rooms` as a health probe.

## 7. Mobile Model Mapping

This section maps the canonical DTOs to the current Swift models.

### 7.1 `SearchResultDTO` -> `SearchResult`

Current frontend issue:

1. [SearchResult.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Models/Query/SearchResult.swift#L3) does not store `worldTransform16`, `modelID`, `modelVersion`, `bboxXYXYNorm`, `frameID`, or `maskRef`.

Required future mapping:

| Canonical field | Current Swift field | Action when syncing |
| --- | --- | --- |
| `id` | `id` | keep |
| `queryText` | `query` | rename or adapt |
| `resultType` | `resultType` | replace enum type |
| `label` | `label` | keep |
| `confidence` | `confidence` | keep |
| `explanation` | `explanation` | keep |
| `evidence` | `evidence` | keep |
| `timestamp` | `timestamp` | keep |
| `worldTransform16` | none | add |
| `bboxXYXYNorm` | none | add |
| `frameID` | none | add |
| `maskRef` | none | add |
| `modelID` | none | add |
| `modelVersion` | none | add |

### 7.2 Detection Confidence Buckets

Current issue:

1. [SearchClass.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Models/Query/SearchClass.swift#L3) mixes presentation buckets with transport result types.

Decision:

1. keep a separate UI-only confidence enum if desired
2. do not use it as the backend wire enum

### 7.3 `SearchResultDTO` -> `ActiveObservation`

For live AR overlays:

1. decode `worldTransform16`
2. convert to `simd_float4x4`
3. create `ActiveObservation`
4. project into screen space for `ObjectTooltipOverlay`

### 7.4 `HypothesisDTO` -> `ObjectHypothesis`

Current frontend issue:

1. [ObjectHypothesis.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Models/HiddenSearch/ObjectHypothesis.swift#L5) is missing `supportObjectID`, `occluderObjectID`, `regionID`, and a clear stored transform helper.

Required future mapping:

| Canonical field | Current Swift field | Action when syncing |
| --- | --- | --- |
| `id` | `id` | keep |
| `queryLabel` | `queryLabel` | keep |
| `hypothesisType` | `hypothesisTypeRaw` | keep |
| `rank` | `rank` | keep |
| `confidence` | `confidence` | keep |
| `worldTransform16` | `transformData` | preserve with helper |
| `reasonCodes` | `reasonCodes` | keep |
| `generatedAt` | `generatedAt` | keep |
| `supportObjectID` | none | add |
| `occluderObjectID` | none | add |
| `regionID` | none | add |
| `explanation` | none | add |

### 7.5 `SceneGraphResponseDTO` -> `SceneNode` and `SceneEdge`

Current frontend issue:

1. [SceneNode.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Models/SceneGraph/SceneNode.swift#L5) exists, but the app has no backend DTO yet for scene graph hydration.

Decision:

1. backend returns full nodes and edges
2. frontend persists them into SwiftData
3. `attributesJSON` remains the flexible extension field

### 7.6 `RoomAssetsResponseDTO` -> `RoomRecord`

Current frontend issue:

1. [RoomRecord.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Models/Room/RoomRecord.swift#L6) stores `worldMapData` directly, while the main system spec defines a `worldMapPath`.

Decision:

1. local app storage may keep archived world-map bytes in SwiftData if needed
2. network contracts still refer to asset URLs/paths, not embedded blobs

## 8. ML Contract Mapping

### 8.1 `DetectionResult` -> `SearchResultDTO`

Source:

1. [contracts.py](/Users/rithvikr/projects/hacktj2026/ml/src/hacktj2026_ml/contracts.py#L18)

Adapter rules:

1. `score` -> `confidence`
2. `result_type` -> `resultType`
3. `bbox_xyxy_norm` -> `bboxXYXYNorm`
4. `frame_id` -> `frameID`
5. add `worldTransform16` after 3D projection
6. add `modelID`, `modelVersion`, `evidence`, `explanation`

### 8.2 `OpenVocabResult` -> `OpenVocabSearchResponseDTO`

Source:

1. [contracts.py](/Users/rithvikr/projects/hacktj2026/ml/src/hacktj2026_ml/contracts.py#L30)

Adapter rules:

1. keep `query_text`
2. map `candidates[*].score` -> `confidence`
3. add candidate IDs
4. add optional `worldTransform16` after projection
5. add `evidence` and `explanation`

### 8.3 `HiddenHypothesisResult` -> `HypothesisDTO`

Source:

1. [contracts.py](/Users/rithvikr/projects/hacktj2026/ml/src/hacktj2026_ml/contracts.py#L45)

Adapter rules:

1. `result_type = likely_hidden` -> top-level query `resultType = likelyHidden`
2. each hypothesis maps to `hypothesisType = inferred` unless a signal system overrides it
3. generate stable hypothesis IDs if the model output does not provide them
4. preserve `reason_codes`
5. add `explanation`

## 9. Current Mismatch Inventory

These are the current unsynced mismatches that must be fixed later.

### 9.1 Request/Response Shape Mismatches

1. [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift#L22) expects `roomID`, but [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py#L37) returns `room_id`.
2. [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift#L71) sends `query`, but [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py#L20) expects `query_text`.
3. [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift#L60) sends `query`, but [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py#L24) expects `query_text`.
4. [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift#L60) expects an array of `BackendSearchResult`, but [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py#L67) returns a structured `OpenVocabResult` object.
5. [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift#L51) expects `GET /assets` to include a top-level `status`, but [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py#L111) returns only `assets`.
6. [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift#L84) uses `GET /rooms` as a health probe, but the backend health endpoint is [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py#L32).
7. [BackendClient.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Backend/BackendClient.swift#L36) uploads raw bytes, while [app.py](/Users/rithvikr/projects/hacktj2026/ml/serving/api/app.py#L16) currently expects JSON with `bundle_path`.

### 9.2 Semantic Mismatches

1. [SearchResult.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Models/Query/SearchResult.swift#L3) is a UI model, not a transport-complete query result.
2. [SearchClass.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Models/Query/SearchClass.swift#L3) uses UI confidence labels where the transport layer needs semantic result types.
3. [QueryResultView.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Query/QueryResultView.swift#L62) assumes result state can be derived entirely from the current `DetectionConfidenceClass`.
4. [LiveSearchViewModel.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Features/Search/LiveSearchViewModel.swift#L117) is not wired to the planner or backend yet.
5. [SearchPlanner.swift](/Users/rithvikr/projects/hacktj2026/mobile/Sources/Geolocate3D/Services/Query/SearchPlanner.swift#L35) routes all plans to the local executor instead of the layered execution path required by the specs.

## 10. No-Sync Integration Order

When the team is ready to sync implementations, do it in this order:

1. define dedicated app DTOs separate from SwiftUI view models
2. update the FastAPI serializers to emit `camelCase` mobile responses
3. keep the ML contracts and Pydantic internals in `snake_case`
4. update `BackendClient` request keys and endpoint semantics
5. expand `SearchResult` into a transport-complete query result model
6. wire `QueryViewModel` and `LiveSearchViewModel` to the planner and backend
7. hydrate `SceneNode`, `SceneEdge`, and `ObjectHypothesis` from backend payloads
8. only then replace local stubs with real backend execution

## 11. Immediate Recommendation

Do not sync code yet.

First, agree on this exact contract split:

1. `snake_case` for ML internals
2. `camelCase` for mobile HTTP
3. `POST /query` as the app-ready result contract
4. `POST /open-vocab-search` as a lower-level debug/search contract

Once that is accepted, the backend and iOS teams can implement against the same map without guessing.
