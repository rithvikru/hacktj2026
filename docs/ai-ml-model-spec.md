# AI/ML Model Specification

Status: source of truth for AI/ML implementation  
Version: `v1.1`  
Last updated: `2026-03-07`  
Owner: `AI/ML lead`

Related system spec:

- `docs/technical-implementation-spec.md`

## 1. Purpose

This document defines exactly what the AI/ML workstream owns for the app.

You are responsible for:

1. model selection
2. dataset definition
3. training and evaluation
4. backend inference design
5. on-device model packaging
6. output contracts that the app consumes
7. evidence provenance for every result

This document is prescriptive. Follow it unless a later revision changes it.

## 2. Ownership Boundary

The AI/ML workstream owns these problem areas:

1. natural-language query planning and normalization
2. open-vocabulary visible object search on the backend
3. mask refinement and object region extraction
4. multimodal retrieval embeddings
5. delayed 3D reconstruction and dense room assets
6. optional on-device acceleration models
7. hidden-object likelihood inference
8. dataset curation and evaluation suites

The AI/ML workstream does not own:

1. ARKit session management
2. RoomPlan integration
3. RealityKit overlay rendering
4. app navigation and SwiftUI screens
5. UWB peer discovery plumbing

The AI/ML workstream does define the outputs that those systems consume.

## 3. Hard Constraints

These constraints are fixed:

1. iPhone 15 Pro Max provides RGB, LiDAR-assisted depth, AR tracking, and UWB, but not thermal sensing.
2. The app cannot use public APIs to fetch AirPods location or Precision Finding from a custom app.
3. Non-cooperative hidden-object results on stock iPhone hardware are inference-only, not direct sensing.
4. Every model result must declare its evidence class:
   - `detected`
   - `last_seen`
   - `signal_estimated`
   - `likely_hidden`
5. Any model output presented to the user must preserve confidence and provenance.

## 4. Deliverables

The AI/ML workstream must produce these artifacts:

1. natural-language planner contract and orchestration logic
2. backend open-vocabulary detector service
3. backend segmentation service
4. embedding extraction service and vector index
5. delayed reconstruction pipeline
6. hidden-object ranking engine
7. optional on-device closed-set Core ML model package
8. dataset schemas and labeling guide
9. benchmark suite and evaluation reports
10. model manifests for app/backend integration

## 5. Locked Model Portfolio

These are the default model choices.

The system is natural-language-first.

Natural-language understanding and planner selection happen before any detector call. Use a GPT-class multimodal reasoning model or equivalent frontier LLM for:

1. target phrase extraction
2. attribute and relation parsing
3. ambiguity handling
4. search-path selection
5. explanation generation from downstream evidence

This planner layer is required. It is not the detection or localization engine.

### 5.1 `M1` On-Device Closed-Set Detector

Purpose:

1. optional low-latency accelerator for a small set of high-frequency objects
2. degraded offline path when the backend is unavailable

Primary implementation:

1. custom object detector exported to `Core ML`

Mandatory baseline:

1. `Create ML` object detector baseline to establish integration quickly

Allowed production implementation:

1. PyTorch-trained detector converted with `coremltools`

Requirements:

1. runtime on iPhone only
2. no network dependency
3. supports `2-10 fps` depending on thermal budget
4. emits boxes, labels, and confidence
5. integrates cleanly with `Vision`

Rule:

1. `M1` is optional and must not define the product vocabulary
2. if implemented, keep the local label pack intentionally small and justified by benchmark data
3. product search capability comes from natural-language planning plus the `M2-M4` stack, not from `M1`

### 5.2 `M2` Backend Open-Vocabulary Detector

Purpose:

1. arbitrary phrase-based object search
2. primary visible-object search path for the product

Primary implementation:

1. `Grounding DINO`

Deployment mode:

1. self-hosted backend inference

Responsibilities:

1. text-conditioned bounding box proposal
2. phrase-sensitive region grounding
3. candidate generation for delayed search

Rule:

Do not depend on a hosted third-party API for the core search path.

### 5.3 `M3` Backend Segmenter

Purpose:

1. refine open-vocabulary detections into masks
2. extract clean object regions for embeddings and 3D projection

Primary implementation:

1. `SAM 2`

Responsibilities:

1. mask refinement from `M2` boxes
2. mask propagation across adjacent saved frames when needed
3. region extraction for embedding generation

### 5.4 `M4` Embedding Encoder

Purpose:

1. image-text retrieval
2. candidate re-ranking
3. phrase-to-region lookup across saved room frames

Primary implementation:

1. `OpenCLIP`

Default model family:

1. `ViT-L-14` class encoder on backend

Responsibilities:

1. encode cropped object regions
2. encode full-frame regions
3. encode user text queries
4. populate vector index

### 5.5 `M5` Delayed Reconstruction Model

Purpose:

1. reconstruct geometry-consistent room structure from saved room frames
2. improve over RoomPlan-only structure for delayed analysis

Primary implementation:

1. `Depth Anything 3`

Default mode:

1. pose-conditioned or multi-view reconstruction using ARKit camera poses when available

Fallback mode:

1. DA3 pose estimation path when pose quality is insufficient

### 5.6 `M6` Dense View Representation

Purpose:

1. high-fidelity saved room viewing
2. geometry-aware rendering for delayed analysis

Primary implementation:

1. `3D Gaussian Splatting`

Input source:

1. calibrated room frames and validated poses

Rule:

Use this for delayed inspection and viewing, not for live mobile inference.

### 5.7 `M7` Hidden-Object Ranking Engine

Purpose:

1. rank likely hidden locations when no direct visual or signal confirmation exists

Primary implementation:

1. probabilistic feature-based ranker

Initial implementation:

1. rule-based scorer over candidate locations

Next implementation:

1. learned re-ranker using collected hide-and-seek supervision

Rule:

This engine must output ranked hypotheses with explanation codes. It must never claim direct detection.

## 6. What Is Locked vs Flexible

Locked:

1. natural-language-first query surface
2. model roles `M1-M7`
3. `M2-M4` as the primary visible-search stack
4. output contracts
5. evidence classes
6. evaluation metrics
7. backend self-hosting requirement for core models

Flexible:

1. exact planner model family
2. whether `M1` ships in the first production-ready build
3. exact `M1` detector architecture
4. exact feature engineering for `M7`
5. exact vector database choice
6. exact orchestration framework for backend workers

If you swap a model family, the replacement must preserve the same input/output contract and beat the current acceptance gate.

## 7. ML Problem Map

### 7.1 Natural-Language Search

Owned components:

1. planner layer
2. `M2`
3. `M3`
4. `M4`
5. optional `M1`

Inputs:

1. query text or voice transcript
2. live frame selection or saved room frames
3. camera poses
4. optional depth maps
5. room context and prior observations

Outputs:

1. grounded candidates
2. masks
3. embeddings and ranked retrieval results
4. detections in room coordinates
5. planner-selected response type and explanation

### 7.2 Reconstruction

Owned models:

1. `M5`
2. `M6`

Inputs:

1. room frame bundle
2. poses and intrinsics
3. optional depth
4. RoomPlan export

Outputs:

1. dense geometry asset
2. room-aligned point or mesh representation
3. Gaussian scene if generated

### 7.3 Hidden Inference

Owned models:

1. `M7`

Inputs:

1. last-seen observations
2. room graph
3. occlusion map
4. object priors
5. user interaction history

Outputs:

1. top-k hypotheses
2. confidence values
3. explanation codes
4. optional heatmap over candidate regions

## 8. Directory Layout For ML Work

Use this repo layout when code is added:

```text
ml/
  datasets/
    schemas/
    labeling-guide/
    manifests/
  closed_set/
    configs/
    training/
    export/
    eval/
  open_vocab/
    grounding_dino/
    sam2/
    retrieval/
    eval/
  reconstruction/
    da3/
    gaussian/
    pose_validation/
    eval/
  hidden_inference/
    features/
    training/
    rules/
    eval/
  serving/
    api/
    workers/
    manifests/
    docker/
```

## 9. Data Specification

The AI/ML workstream owns the training and evaluation dataset schema.

### 9.1 Core Data Units

Use these primary units:

1. `room`
2. `session`
3. `frame`
4. `object_instance`
5. `observation`
6. `hypothesis_target`

### 9.2 Canonical Labeling Rules

Every object label must include:

1. `canonical_label`
2. `display_name`
3. `synonyms`
4. `category`
5. `size_class`
6. `support_priors`
7. `container_priors`

Example:

1. canonical label: `airpods_case`
2. display name: `AirPods case`
3. synonyms: `airpods`, `airpods case`, `earbuds case`
4. category: `small_personal_item`

Query mapping rule:

1. user query `Where are my AirPods?` maps to a canonical noun phrase such as `airpods case`
2. this canonical phrase is planner output for retrieval and grounding, not a requirement that the product be limited to a fixed closed-set label list

### 9.3 Visibility States

Every annotation must include one of:

1. `fully_visible`
2. `partially_occluded`
3. `soft_hidden`
4. `hard_hidden`
5. `inside_container`
6. `offscreen`
7. `removed`

### 9.4 Support and Containment Labels

Every annotated object instance should include, when known:

1. `support_surface`
2. `container`
3. `nearest_furniture`
4. `room_section`

### 9.5 Frame Metadata Schema

Every saved frame record must include:

1. `frame_id`
2. `room_id`
3. `session_id`
4. `timestamp`
5. `image_path`
6. `depth_path` if present
7. `camera_transform16`
8. `intrinsics9`
9. `tracking_state`
10. `selected_for_training`
11. `selected_for_eval`

### 9.6 Detection Annotation Schema

Each visible annotation record must include:

1. `frame_id`
2. `object_instance_id`
3. `canonical_label`
4. `bbox_xyxy_norm`
5. `mask_path` or `mask_rle`
6. `visibility_state`
7. `occluder_label` if applicable
8. `support_surface`
9. `confidence_source`

### 9.7 Hidden-Object Supervision Schema

Each hidden-target training example must include:

1. `room_id`
2. `query_label`
3. `last_seen_frame_id`
4. `last_seen_transform16`
5. `final_hidden_state`
6. `true_container`
7. `true_support_surface`
8. `true_world_transform16` if known
9. `candidate_regions`
10. `ground_truth_rank_target`

## 10. Dataset Collection Rules

### 10.1 Optional Local-Acceleration Dataset

Collect:

1. only if `M1` is shipped
2. at least `500` images per canonical local label before claiming model stability
3. at least `20` physical instances per label where possible
4. at least `10` rooms across different clutter levels
5. multiple lighting conditions
6. multiple floor and bedding textures
7. partial occlusions and clutter

### 10.2 Delayed Search Dataset

Collect:

1. full room sweeps with synchronized frame metadata
2. text query prompts for each target object
3. object masks for a subset of keyframes
4. negative rooms that do not contain the queried object

### 10.3 Hidden-Search Dataset

Collect staged hide-and-seek episodes:

1. object placed visibly
2. object moved under cloth, cushions, or into container
3. user path recorded when possible
4. final location labeled precisely

Required hidden scenarios:

1. under blanket
2. under clothes pile
3. inside drawer
4. inside backpack
5. under couch cushion
6. under bed edge
7. dropped next to support furniture

### 10.4 Split Rules

Do not split randomly by frame.

Split by:

1. room
2. object instance
3. capture session

This is mandatory to avoid leakage.

## 11. Model-Specific Specs

### 11.1 `M1` On-Device Closed-Set Detector

Role:

1. optional acceleration and degraded offline fallback
2. not the primary natural-language search path

Input contract:

1. RGB image
2. fixed square resolution, default `640x640`

Output contract:

1. top `N` detections
2. `label_id`
3. `label`
4. `score`
5. `bbox_xyxy_norm`

Training rules:

1. only implement if the backend natural-language path is already defined and benchmarked
2. start with `Create ML` object detection baseline
3. train a stronger custom model if the baseline misses the gate
4. include hard negatives:
   - earbuds without case
   - wallets embedded in fabric patterns
   - metallic remote-like objects
   - chargers and cables near phones
5. augment for:
   - motion blur
   - low light
   - partial occlusion
   - scale variation
   - clutter

Export rules:

1. export as `mlpackage`
2. support `Vision` inference path
3. ship `fp16` first
4. move to compressed or quantized variant only if accuracy loss is acceptable

Acceptance gate:

1. applies only if `M1` is shipped
2. mAP@50 on held-out room split `>= 0.75`
3. per-class recall@1 on held-out room split `>= 0.80`
4. runs on iPhone 15 Pro Max at `>= 2 fps` end-to-end with app integration

### 11.2 `M2` Open-Vocabulary Detector

Input contract:

1. image frame
2. natural-language prompt

Output contract:

1. candidate boxes
2. text relevance score per candidate
3. prompt text echoed in result metadata

Prompt rules:

1. preserve the user’s natural-language phrase whenever it contains meaningful attributes or relations
2. normalize only enough to improve grounding
3. keep both:
   - original user query
   - planner-produced canonical noun phrase
4. examples:
   - user query: `where is my black wallet near the bed`
   - canonical phrase: `black wallet`

Serving rules:

1. run on GPU backend
2. cache prompt embeddings if implementation allows
3. return top `K=20` raw candidates before masking and re-ranking

Acceptance gate:

1. recall@5 on held-out phrase-grounding benchmark `>= 0.85`
2. median single-query backend latency under `10s`

### 11.3 `M3` Segmenter

Input contract:

1. source frame
2. candidate boxes from `M2`

Output contract:

1. per-candidate mask
2. mask score
3. cropped region asset or reference

Rules:

1. use `M2` boxes as prompts first
2. keep original frame coordinate system
3. emit masks suitable for embedding extraction and 3D projection

Acceptance gate:

1. mask IoU on labeled eval subset `>= 0.75`

### 11.4 `M4` Embedding Encoder

Input contract:

1. cropped region image or whole frame
2. user text query

Output contract:

1. image embedding vector
2. text embedding vector
3. normalized similarity score

Rules:

1. use a single canonical embedding model for both indexing and query
2. do not mix embedding spaces in the same index
3. version the embedding model explicitly in every index build

Primary use cases:

1. search candidate crops by phrase
2. re-rank `M2` proposals
3. retrieve visually similar past observations

Acceptance gate:

1. text-to-region recall@10 `>= 0.90` on internal retrieval benchmark

### 11.5 `M5` Delayed Reconstruction

Input contract:

1. selected room keyframes
2. ARKit poses
3. intrinsics
4. optional depth maps

Output contract:

1. aligned geometry representation
2. per-frame depth or geometry outputs
3. room-coordinate transform back into ARKit world

Rules:

1. use ARKit poses as first-choice conditioning signal
2. validate pose consistency before heavy reconstruction
3. if pose quality is poor, run fallback pose validation or recovery
4. persist outputs in a format the viewer and query system can consume

Acceptance gate:

1. median alignment error to the RoomPlan scaffold on sampled structural surfaces `<= 0.25m`
2. backend completes an initial room job under `5 min` on target GPU hardware

### 11.6 `M6` Dense View Representation

Input contract:

1. calibrated frames and validated poses

Output contract:

1. renderable dense room asset
2. camera-path render support

Rules:

1. train only after pose quality is acceptable
2. keep this pipeline separate from live mobile inference
3. expose outputs for saved-room viewing, not local detection

Acceptance gate:

1. room renders are visually coherent and navigable
2. object hypothesis overlays remain spatially aligned

### 11.7 `M7` Hidden-Object Ranking Engine

Candidate generation:

1. last-seen neighborhood
2. support surfaces compatible with object size and category
3. nearby containers
4. occluded regions created after last-seen event
5. floor-drop candidates near support edges

Required features:

1. distance from last-seen point
2. support surface prior
3. container prior
4. object size compatibility
5. occlusion by soft materials
6. occlusion by hard containers
7. user motion path features
8. room-section prior
9. temporal decay
10. recent retrieval history

Output contract:

1. `hypothesis_id`
2. `query_label`
3. `rank`
4. `confidence`
5. `world_transform16` or region identifier
6. `reason_codes`
7. `evidence_class = likely_hidden`

Initial implementation:

1. weighted rule-based scorer

Next implementation:

1. learned ranker on staged hidden dataset

Acceptance gate:

1. top-3 region accuracy `>= 0.80` on staged hidden benchmark
2. every result includes at least one human-readable explanation code

## 12. Training Policy

### 12.1 Baseline First

For every model track:

1. ship an off-the-shelf or minimal-training baseline first
2. establish data and eval pipelines
3. only then fine-tune or replace the model

### 12.2 Fine-Tuning Policy

Allowed:

1. fine-tune `M1`
2. fine-tune `M4`
3. train a learned variant of `M7`

Not required initially:

1. fine-tuning `M2`
2. fine-tuning `M3`
3. fine-tuning `M5`

Rule:

Do not start costly fine-tuning until the benchmark suite exists.

### 12.3 Pseudo-Labeling Policy

Allowed pseudo-label sources:

1. `M2 + M3` generated labels on unlabeled room frames
2. human-corrected masks from saved room sessions

Rule:

Pseudo-labels must be reviewed on a sampled QA subset before being added to training.

## 13. Benchmark Suite

Maintain five benchmark sets.

### 13.1 Visible Detection Benchmark

Measures:

1. mAP@50
2. per-class recall
3. clutter robustness
4. low-light robustness

### 13.2 Open-Vocabulary Benchmark

Measures:

1. recall@k for phrase grounding
2. precision on negative rooms
3. latency

### 13.3 Retrieval Benchmark

Measures:

1. text-to-region recall@k
2. region-to-region nearest-neighbor quality

### 13.4 Reconstruction Benchmark

Measures:

1. pose-consistent geometry quality
2. room-alignment quality
3. job runtime

### 13.5 Hidden Benchmark

Measures:

1. top-1 region accuracy
2. top-3 region accuracy
3. calibration quality of confidence buckets

## 14. Model Manifests

Every shipped model artifact must include a manifest file with:

1. `model_id`
2. `model_family`
3. `version`
4. `training_data_manifest`
5. `eval_report_path`
6. `input_contract`
7. `output_contract`
8. `thresholds`
9. `owner`
10. `created_at`

## 15. App/Backend Output Contracts

### 15.1 Detection Result Contract

```json
{
  "result_type": "detected",
  "model_id": "m1.closed_set.detector",
  "model_version": "1.0.0",
  "label": "wallet",
  "score": 0.91,
  "bbox_xyxy_norm": [0.21, 0.34, 0.48, 0.62],
  "mask_ref": null,
  "frame_id": "uuid",
  "timestamp": "2026-03-07T12:00:00Z"
}
```

### 15.2 Open-Vocabulary Result Contract

```json
{
  "result_type": "detected",
  "model_id": "m2.open_vocab.detector",
  "model_version": "1.0.0",
  "query_text": "blue notebook",
  "candidates": [
    {
      "score": 0.78,
      "bbox_xyxy_norm": [0.11, 0.18, 0.36, 0.55],
      "mask_ref": "mask://uuid",
      "frame_id": "uuid"
    }
  ]
}
```

### 15.3 Hidden Hypothesis Contract

```json
{
  "result_type": "likely_hidden",
  "model_id": "m7.hidden_ranker",
  "model_version": "1.0.0",
  "query_label": "wallet",
  "hypotheses": [
    {
      "rank": 1,
      "confidence": 0.66,
      "world_transform16": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
      "reason_codes": ["near_last_seen", "soft_occluder_present", "size_compatible_surface"]
    }
  ]
}
```

## 16. Integration Rules

### 16.1 On-Device Integration

Rules:

1. if `M1` is shipped, ship it as a versioned `Core ML` artifact
2. run through `Vision` where practical
3. keep post-processing deterministic and versioned
4. preserve threshold config outside model weights when possible

### 16.2 Backend Integration

Rules:

1. serve planner, `M2`, `M3`, `M4`, `M5`, and `M7` behind versioned endpoints
2. make inference idempotent on saved frame bundles
3. log model version and latency for every request

### 16.3 Coordinate Integration

Rules:

1. every backend result must be convertible back into ARKit world coordinates
2. if world alignment is uncertain, flag the result as degraded
3. do not return unaligned reconstruction-derived detections as high-confidence spatial results

## 17. Build Order

Follow this order:

1. dataset schema and label ontology
2. planner contract and natural-language query normalization
3. frame-bundle ingestion and visible-search benchmark set
4. `M2 + M3` backend grounding and masking
5. `M4` embedding index and retrieval eval
6. `M7` rule-based hidden ranker
7. `M5` DA3 reconstruction pipeline
8. `M6` dense viewer asset generation
9. optional `M1` local accelerator
10. `M7` learned ranker if benchmark data justifies it

## 18. Explicit Decisions

These decisions are locked:

1. the product query surface is natural language, not a fixed label list
2. planner plus `M2-M4` is the primary visible-search path
3. `M1` is optional and on-device if shipped
4. `M2` is self-hosted and open-vocabulary
5. `M3` is segmentation for mask refinement
6. `M4` owns the canonical retrieval embedding space
7. `M5` is the primary delayed reconstruction model
8. `M7` returns ranked hypotheses, not direct detections
9. every result is versioned and attributable to a model artifact

## 19. Explicit Non-Goals

Do not spend time on:

1. AirPods private API work
2. treating `M1` labels as the product vocabulary
3. fake thermal-model research
4. trying to prove direct non-cooperative through-occluder sensing on stock iPhone hardware
5. training everything from scratch before baselines exist

## 20. References

Primary references used for this spec:

1. Apple Core ML overview: <https://developer.apple.com/documentation/CoreML>
2. Apple Create ML overview: <https://developer.apple.com/machine-learning/create-ml/>
3. Apple Core ML overview page: <https://developer.apple.com/machine-learning/core-ml/>
4. Apple Vision tracking request: <https://developer.apple.com/documentation/vision/vntrackingrequest>
5. Apple RoomPlan overview: <https://developer.apple.com/augmented-reality/roomplan/>
6. Apple RoomPlan model provider note on bounding-box approximation: <https://developer.apple.com/documentation/roomplan/capturedroom/modelprovider>
7. Apple custom models for captured rooms: <https://developer.apple.com/documentation/roomplan/providing-custom-models-for-captured-rooms-and-structure-exports>
8. Apple on-device model personalization example: <https://developer.apple.com/documentation/CoreML/personalizing-a-model-with-on-device-updates>
9. Grounding DINO official repository: <https://github.com/IDEA-Research/GroundingDINO>
10. Grounding DINO paper: <https://arxiv.org/abs/2303.05499>
11. Grounding DINO 1.5 paper: <https://arxiv.org/abs/2405.10300>
12. Segment Anything official repository linking to SAM 2: <https://github.com/facebookresearch/segment-anything>
13. Segment Anything 2 paper: <https://arxiv.org/abs/2408.00714>
14. OpenAI CLIP official repository: <https://github.com/openai/CLIP>
15. CLIP paper: <https://arxiv.org/abs/2103.00020>
16. OpenCLIP official repository: <https://github.com/mlfoundations/open_clip>
17. Depth Anything 3 paper: <https://arxiv.org/abs/2511.10647>
18. Depth Anything 3 official repository: <https://github.com/ByteDance-Seed/Depth-Anything-3>
19. 3D Gaussian Splatting paper: <https://arxiv.org/abs/2308.04079>
20. 3D Gaussian Splatting official repository: <https://github.com/graphdeco-inria/gaussian-splatting>
21. COLMAP official documentation: <https://colmap.github.io/>
