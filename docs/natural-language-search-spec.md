# Natural-Language Search System Spec

Status: source of truth for planner and query-orchestration implementation  
Version: `v1.0`  
Last updated: `2026-03-07`  
Owner: `natural-language search lead`

Related specs:

- `docs/technical-implementation-spec.md`
- `docs/ai-ml-model-spec.md`
- `docs/frontend-ml-contract-map.md`

## 1. Purpose

This document defines the natural-language search system for the app.

This system is the front door for user search.

It is responsible for:

1. understanding arbitrary user queries
2. extracting target object phrases, attributes, and spatial constraints
3. selecting the correct search path
4. sequencing fallback behavior
5. turning raw search evidence into app-facing responses

It is not responsible for:

1. visual grounding itself
2. segmentation itself
3. embedding extraction itself
4. reconstruction itself
5. AR overlay rendering

Those are downstream systems.

## 2. Hard Rules

Apply these rules exactly.

1. The product query surface is natural language, not a fixed label list.
2. The planner must not assume the object vocabulary is limited to `M1`.
3. The planner may normalize phrases, but it must preserve useful user intent.
4. The planner must never fabricate evidence.
5. The planner must not present inference-only output as direct detection.
6. Every final response must preserve evidence provenance:
   - `detected`
   - `last_seen`
   - `signal_estimated`
   - `likely_hidden`
7. If ambiguity remains unresolved, the planner must expose that ambiguity instead of silently collapsing it.

## 3. Position In The System

The natural-language search system sits above all search executors.

Execution order:

1. user query arrives
2. planner parses and normalizes query
3. planner selects executor order
4. downstream systems run
5. planner aggregates evidence
6. planner returns app-facing response

Primary downstream systems:

1. signal executor
2. local observation executor
3. backend open-vocabulary executor
4. scene graph executor
5. hidden inference executor

## 4. Responsibilities

The natural-language search system owns:

1. query understanding
2. phrase normalization
3. attribute extraction
4. spatial relation extraction
5. intent classification
6. executor selection
7. fallback sequencing
8. evidence aggregation
9. explanation generation constrained by evidence
10. structured response generation

It does not own:

1. low-level model inference
2. object storage
3. GPU job orchestration
4. SwiftUI view logic
5. RealityKit rendering

## 5. Model Role

Use a GPT-class multimodal reasoning model or equivalent frontier LLM as the planner.

Recommended use:

1. query rewrite
2. object phrase extraction
3. relation parsing
4. ambiguity analysis
5. executor selection
6. explanation drafting from structured evidence

Do not use the planner as:

1. the sole object detector
2. the sole localizer
3. the sole hidden-object engine

The planner decides what to run. The search stack finds the object.

## 6. Inputs

The planner input must be structured. Do not pass only the raw query string.

### 6.1 Required Inputs

1. `queryText`
2. `roomID`
3. `sessionMode`
   - `live`
   - `saved`
4. `backendAvailable`
5. `signalCapabilities`
   - cooperative available or not
   - tag support available or not
6. `localCapabilities`
   - optional local accelerator available or not
7. `recentObservationsSummary`
8. `sceneGraphSummary`
9. `roomMetadataSummary`

### 6.2 Optional Inputs

1. voice transcript confidence
2. prior query history for the same room
3. object prototype catalog
4. user-specific aliases
5. recent hidden hypotheses

## 7. Planner Output Contract

The planner must emit structured JSON, not free text.

```json
{
  "query_id": "uuid",
  "query_text": "where is my black wallet near the bed",
  "normalized_query": "black wallet near the bed",
  "intent": "findObject",
  "target_phrase": "black wallet",
  "canonical_query_label": "black wallet",
  "attributes": ["black"],
  "relations": [
    {
      "relation": "near",
      "reference": "bed"
    }
  ],
  "search_class": "planner_led_open_vocab_visible_search",
  "executor_order": [
    "signal",
    "backend_open_vocab",
    "local_observation",
    "scene_graph",
    "hidden_inference"
  ],
  "requires_backend": true,
  "can_use_local_accelerator": false,
  "should_compute_hidden_fallback": true,
  "ambiguities": [],
  "notes": [
    "Preserve color attribute during grounding.",
    "Use room relation constraint near=bed during re-ranking."
  ]
}
```

### 7.1 Required Fields

1. `query_id`
2. `query_text`
3. `normalized_query`
4. `intent`
5. `target_phrase`
6. `canonical_query_label`
7. `attributes`
8. `relations`
9. `search_class`
10. `executor_order`
11. `requires_backend`
12. `can_use_local_accelerator`
13. `should_compute_hidden_fallback`
14. `ambiguities`

### 7.2 Intent Enum

Allowed intents:

1. `findObject`
2. `findLikelyObjectLocation`
3. `countObjects`
4. `listObjectsInSection`
5. `showNearest`
6. `showSupportingSurface`
7. `showContainedItems`
8. `explainWhy`

### 7.3 Search Class Enum

Allowed search classes:

1. `planner_led_open_vocab_visible_search`
2. `local_accelerated_visible_search`
3. `last_seen_retrieval`
4. `signal_based_localization`
5. `hidden_object_likelihood_inference`

## 8. Normalization Rules

Normalize only enough to improve search quality.

Preserve:

1. object attributes
2. colors
3. materials
4. spatial relations
5. comparative language when useful
6. possessive context if needed for disambiguation

Allowed normalization:

1. strip filler words such as `please`
2. rewrite pronouns when reference is obvious
3. convert voice disfluencies into a clean phrase
4. canonicalize obvious aliases:
   - `airpods` -> `airpods case`
   - `remote` -> `tv remote` only when context supports it

Forbidden normalization:

1. removing discriminative attributes like `black`, `blue`, `small`, `left`
2. collapsing every query to a fixed canonical label pack
3. rewriting a user query into a different object category without evidence

## 9. Ambiguity Handling

The planner must explicitly detect ambiguity.

Examples:

1. `where is my charger`
   - could mean phone charger, laptop charger, cable, brick
2. `where are my headphones`
   - could mean over-ear headphones, earbuds case, loose earbuds
3. `show me the bag`
   - multiple bags may exist in room memory

Rules:

1. if ambiguity is low, proceed with one primary target phrase and record alternatives
2. if ambiguity is medium, run broad search and re-rank using room context
3. if ambiguity is high and likely user-visible, return a clarification-ready response
4. do not silently overfit to one interpretation when multiple likely meanings exist

## 10. Executor Selection Rules

Planner order must be:

1. signal path if the target is known to have cooperative or tagged capability
2. backend open-vocabulary search if backend is available
3. optional local accelerator if it supports the target and backend is unavailable or low-latency confirmation is useful
4. last-seen retrieval if prior observation exists
5. hidden inference if the target remains unresolved

Interpretation:

1. the planner prefers the strongest evidence path
2. the planner prefers open-vocabulary search over closed-set local acceleration
3. local acceleration is optimization, not the primary route

## 11. Backend Open-Vocabulary Query Contract

When the planner chooses backend visible search, it must send both the original query and the normalized phrase.

Required payload fields:

1. `queryText`
2. `normalizedQuery`
3. `targetPhrase`
4. `attributes`
5. `relations`
6. `roomID`
7. `frameSelectionMode`
8. `frameRefs` if preselected

Example:

```json
{
  "queryText": "where is my black wallet near the bed",
  "normalizedQuery": "black wallet near the bed",
  "targetPhrase": "black wallet",
  "attributes": ["black"],
  "relations": [
    {
      "relation": "near",
      "reference": "bed"
    }
  ],
  "roomID": "uuid",
  "frameSelectionMode": "live_priority"
}
```

## 12. Result Aggregation Rules

The planner is responsible for merging downstream evidence into one response.

Priority order:

1. `detected`
2. `signal_estimated`
3. `last_seen`
4. `likely_hidden`
5. `not_found`

Rules:

1. `detected` wins over all weaker evidence classes
2. `signal_estimated` may outrank `last_seen` if active and reliable
3. `last_seen` wins over `likely_hidden`
4. hidden hypotheses may still be included as secondary fallback context
5. explanations must cite the strongest actual evidence source

## 13. Explanation Rules

The planner may generate natural-language explanations only from structured evidence.

Allowed explanation sources:

1. planner parse output
2. visible detection result metadata
3. scene graph facts
4. last-seen records
5. signal metadata
6. hidden hypothesis reason codes

Forbidden explanation behavior:

1. inventing occluders that were not observed
2. stating `it is under the blanket` when the result is only probabilistic
3. implying thermal or through-occluder sensing

Examples:

1. allowed:
   - `Detected a black wallet candidate near the bed in the current room sweep.`
2. allowed:
   - `Last seen on the nightstand during the saved room scan.`
3. allowed:
   - `Likely under soft clutter near the bed because the item was last seen there and that region is now occluded.`
4. forbidden:
   - `The phone is definitely under the blanket.`

## 14. App-Facing Response Contract

The natural-language search system ultimately feeds `POST /rooms/{id}/query`.

It must return:

1. `queryID`
2. `queryText`
3. `queryLabel`
4. `resultType`
5. `primaryResult`
6. `results`
7. `hypotheses`
8. `explanation`
9. `generatedAt`

This must remain compatible with [frontend-ml-contract-map.md](/Users/rithvikr/projects/hacktj2026/docs/frontend-ml-contract-map.md).

## 15. Context Assembly

The planner must not receive raw unbounded room state.

Build a compact context packet:

1. top recent observations by confidence and recency
2. top scene graph nodes relevant to extracted relations
3. active signal capabilities
4. room sections and prominent furniture
5. last `N` query history items for the same room

Rules:

1. cap prompt context aggressively
2. summarize repeated observations
3. include structured facts before prose

## 16. Evaluation

Measure the planner separately from the visual stack.

### 16.1 Planner Benchmark Tasks

1. target phrase extraction accuracy
2. attribute extraction accuracy
3. relation extraction accuracy
4. intent classification accuracy
5. executor selection accuracy
6. ambiguity detection quality
7. evidence-safe explanation quality

### 16.2 Acceptance Gates

Use these minimum gates:

1. target phrase extraction accuracy `>= 0.95` on internal benchmark
2. intent classification accuracy `>= 0.95`
3. executor selection accuracy `>= 0.95`
4. zero tolerance for explanations that overstate evidence class on audited eval subset

## 17. Implementation Deliverables

Your friend should deliver:

1. planner input schema
2. planner output schema
3. prompt template set
4. executor-order decision rules
5. ambiguity policy
6. evidence-safe explanation layer
7. benchmark suite and eval script
8. backend integration contract for `POST /rooms/{id}/query`

## 18. Build Order

Implement in this order:

1. planner input schema
2. planner structured output schema
3. prompt templates for `findObject` and `findLikelyObjectLocation`
4. executor-order logic
5. result aggregation logic
6. explanation layer
7. benchmark suite
8. integration with backend query endpoint

## 19. Explicit Decisions

These decisions are locked:

1. natural language is the product interface
2. the planner runs before any detector
3. backend open-vocabulary search is the primary visible-search path
4. optional local acceleration does not define the product vocabulary
5. the planner must preserve evidence provenance in the final answer
6. hidden-object output must remain explicitly probabilistic

## 20. Explicit Non-Goals

Do not spend time on:

1. building a chatbot persona
2. letting the LLM hallucinate object locations without downstream evidence
3. mapping all queries into a fixed seven-label detector
4. using the planner as the detector itself
