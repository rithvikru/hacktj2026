# Dataset Source Research

Status: source of truth for dataset sourcing  
Date: `2026-03-07`  
Scope: `all data sources required to make the project work`

This document maps the project requirements in [ai-ml-model-spec.md](/Users/rithvikr/projects/hacktj2026/docs/ai-ml-model-spec.md) and [TECH-REFERENCE.md](/Users/rithvikr/projects/hacktj2026/docs/TECH-REFERENCE.md) to concrete data sources.

The main conclusion is simple:

1. public datasets are necessary for bootstrap
2. public datasets are not sufficient for the target product
3. self-collected iPhone room data is mandatory
4. hidden-object training data is almost entirely a private-data problem

## 1. What The Project Needs

The specs require data for these workstreams:

1. `M1` on-device closed-set visible object detection
2. `M2` open-vocabulary phrase grounding
3. `M3` mask refinement and object region extraction
4. `M4` image-text retrieval and region embeddings
5. `M5` delayed room reconstruction from iPhone room sweeps
6. `M6` dense room viewing assets
7. `M7` hidden-object ranking

The specs also lock these private data requirements:

1. at least `500` images per canonical label before claiming `M1` stability
2. at least `20` physical instances per label where possible
3. at least `10` real rooms across clutter levels
4. full room sweeps with synchronized frame metadata
5. staged hidden-object episodes with the required scenarios

## 2. Bottom-Line Recommendation

Use a two-layer data strategy.

Layer A: public bootstrap data

1. start `M1` from `Open Images V7`, `COCO`, `Objects365`, and `LVIS`
2. start `M2-M4` from `Visual Genome`, `Flickr30k Entities`, and `RefCOCO`
3. start `M5-M6` from `ARKitScenes`, `ScanNet++`, `ScanNet`, and `Matterport3D/HM3D`
4. use `ProcTHOR + Objaverse + BlenderProc` for synthetic augmentation only

Layer B: private product data

1. collect the seven locked labels in real iPhone room captures
2. collect saved-room sweeps with ARKit poses, intrinsics, depth, and RoomPlan exports
3. collect staged hide-and-seek episodes for hidden-object inference
4. if using cooperative or tagged paths, collect UWB/BLE paired sessions too

The system will not meet product goals without Layer B.

## 3. Mandatory Private Data Sources

### 3.1 Private Visible-Object Dataset

Purpose:

1. train and validate `M1`
2. adapt public models to real iPhone indoor clutter
3. cover the labels that public datasets miss

Must include:

1. `airpods_case`
2. `wallet`
3. `keys`
4. `tv_remote`
5. `glasses`
6. `phone`
7. `charger`

Must capture:

1. multiple lighting conditions
2. cluttered beds, desks, couches, floors, drawers, and backpacks
3. partial occlusion
4. hard negatives:
   - earbuds without case
   - patterned fabric that looks wallet-like
   - metallic remote-like objects
   - chargers and cables near phones

This dataset is mandatory because public coverage is weak for `airpods_case`, `wallet`, `keys`, and `charger`.

### 3.2 Private Room-Sweep Dataset

Purpose:

1. train and evaluate delayed room reconstruction and relocalized search
2. provide realistic room geometry, device motion, and occlusion patterns
3. build room-level retrieval and scene graph benchmarks

Capture format:

1. iPhone 15 Pro Max RGB
2. ARKit poses
3. intrinsics
4. depth when available
5. RoomPlan export
6. frame timestamps
7. saved `ARWorldMap` where possible

### 3.3 Private Hidden-Search Dataset

Purpose:

1. train and evaluate `M7`
2. validate whether hidden-location ranking works in actual rooms

Required scenarios from the spec:

1. under blanket
2. under clothes pile
3. inside drawer
4. inside backpack
5. under couch cushion
6. under bed edge
7. dropped next to support furniture

This dataset is mandatory. There is no public dataset that directly matches this task.

### 3.4 Private Cooperative-Signal Dataset

Purpose:

1. calibrate the cooperative hidden-search path
2. align `Nearby Interaction` or tagged-signal readings with room coordinates

Needed only if you implement:

1. second-iPhone cooperative hidden search
2. custom UWB/BLE tagged object search

## 4. Public Bootstrap Data By Requirement

### 4.1 `M1` Closed-Set Visible Detection

Use these public sources first:

| Source | What it gives you | Why it matters |
|---|---|---|
| [Open Images V7](https://storage.googleapis.com/openimages/web/index.html) | large-scale boxes, masks, image labels | best first-stop public source for household object detection |
| [COCO](https://cocodataset.org/#home) | standard detection baseline | strong baseline for phones, remotes, beds, couches, backpacks, clutter |
| [Objects365](https://www.objects365.org/download.html) | large-scale detection set | useful for stronger detection pretraining and hard negatives |
| [LVIS](https://www.lvisdataset.org/) | long-tail instance categories | useful for rare-object robustness and long-tail negatives |

Open Images is especially useful because its official V7 page lists:

1. boxes
2. instance segmentations
3. image-level labels
4. localized narratives

Open Images class coverage checked on `2026-03-07` from the official boxable class list:

| Locked label | Public boxable match found | Result |
|---|---|---|
| `airpods_case` | no | private capture required |
| `wallet` | no | private capture required |
| `keys` | no | private capture required |
| `tv_remote` | `Remote control` | public bootstrap available |
| `glasses` | `Glasses` | public bootstrap available |
| `phone` | `Mobile phone` | public bootstrap available |
| `charger` | no | private capture required |

Open Images also has useful contextual/container classes for priors and negatives:

1. `Backpack`
2. `Drawer`
3. `Bed`
4. `Couch`

Decision:

1. use public data to bootstrap `tv_remote`, `glasses`, and `phone`
2. do not expect public data alone to solve `airpods_case`, `wallet`, `keys`, or `charger`

### 4.2 `M2` Open-Vocabulary Phrase Grounding

Recommended public sources:

| Source | What it gives you | Why it matters |
|---|---|---|
| [Visual Genome](https://visualgenome.org/) | region descriptions, objects, attributes, relationships | best general-purpose grounding and relation data |
| [Flickr30k Entities](https://bryanplummer.com/Flickr30kEntities/) | phrase-to-box correspondences | direct phrase grounding benchmark |
| [RefCOCO](https://www.tensorflow.org/datasets/catalog/ref_coco) | referring expressions to regions | direct benchmark for phrase-based object localization |
| [GQA](https://cs.stanford.edu/people/dorarad/gqa/about.html) | compositional scene questions grounded in images | useful for relation-heavy query evaluation |

Decision:

1. use `Visual Genome + Flickr30k Entities + RefCOCO` as the primary public grounding bootstrap
2. use private room sweeps later for domain adaptation to bedrooms, desks, couches, and clutter

### 4.3 `M3` Mask Refinement

Recommended public sources:

| Source | What it gives you | Why it matters |
|---|---|---|
| [Open Images V7](https://storage.googleapis.com/openimages/web/index.html) | instance masks | broad object coverage |
| [LVIS](https://www.lvisdataset.org/) | high-quality instance masks | long-tail instance quality |
| [COCO](https://cocodataset.org/#home) | standard instance segmentation | baseline mask supervision |
| [ADE20K](https://ade20k.csail.mit.edu/request_data) | scene parsing for furniture/surfaces | useful for container/support priors and room semantics |

Decision:

1. use public masks to bootstrap `M3`
2. use `SAM 2` plus human QA to generate masks on private room sweeps

### 4.4 `M4` Retrieval Embeddings

Recommended public sources:

| Source | What it gives you | Why it matters |
|---|---|---|
| [Visual Genome](https://visualgenome.org/) | object regions plus attributes | good phrase-to-region supervision |
| [Flickr30k Entities](https://bryanplummer.com/Flickr30kEntities/) | phrase-region pairs | direct retrieval benchmark |
| [RefCOCO](https://www.tensorflow.org/datasets/catalog/ref_coco) | referring expressions | phrase grounding and retrieval evaluation |
| private room sweeps | exact target domain | required for real product retrieval quality |

Decision:

1. do not train a bespoke embedding space from scratch
2. use public phrase-region data for evaluation and tuning
3. use private room sweeps as the canonical product-domain index

### 4.5 `M5` Delayed Reconstruction

Recommended public sources:

| Source | What it gives you | Why it matters |
|---|---|---|
| [ARKitScenes](https://machinelearning.apple.com/research/arkitscenes) | mobile RGB-D indoor data from Apple devices | closest public match to the target capture stack |
| [ScanNet++](https://scannetpp.mlsg.cit.tum.de/scannetpp/documentation) | high-fidelity indoor scenes with iPhone RGB, depth, and metadata | excellent for dense reconstruction and alignment work |
| [ScanNet](https://github.com/ScanNet/ScanNet) | large RGB-D indoor reconstructions | useful baseline indoor geometry and semantics |
| [Matterport3D](https://niessner.github.io/Matterport/) | large real indoor RGB-D dataset | useful for room-scale reconstruction and semantics |
| [HM3D](https://aihabitat.org/datasets/hm3d/) | large-scale indoor 3D environments | useful for room priors and embodied-search context |

Important fit notes:

1. `ARKitScenes` is the closest public fit because it is explicitly mobile RGB-D and Apple-centered
2. `ScanNet++` is highly relevant because its docs explicitly include iPhone RGB, depth, and metadata
3. `Matterport3D` and `HM3D` are useful, but less matched to iPhone ARKit capture

Decision:

1. bootstrap reconstruction and room semantics from `ARKitScenes + ScanNet++`
2. use `ScanNet + Matterport3D/HM3D` as supplemental indoor geometry data
3. still collect private room sweeps because product queries depend on your exact capture behavior

### 4.6 `M6` Dense Room Viewing

Recommended public sources:

1. the same reconstruction sources as `M5`
2. especially `ScanNet++` because it already supports high-fidelity indoor rendering workflows in its official tooling

This track depends more on good calibrated room sweeps than on broad public diversity.

### 4.7 `M7` Hidden-Object Ranking

Public sources can only help indirectly.

Indirectly useful public sources:

| Source | What it gives you | Why it matters |
|---|---|---|
| [Ego4D](https://ego4d-data.org/) | egocentric human-object interaction video | useful for motion and object handling priors |
| [EPIC-KITCHENS](https://epic-kitchens.github.io/2023) | egocentric manipulation sequences | useful for interaction priors, less useful for bedroom search |
| [ProcTHOR](https://procthor.allenai.org/) | procedurally generated houses | useful for synthetic candidate-region generation |
| [HM3D](https://aihabitat.org/datasets/hm3d/) | large real 3D indoor layouts | useful for support/container priors |

Decision:

1. public data can help with priors and ablations
2. the actual hidden-search model must be trained and evaluated on private staged hide-and-seek data

## 5. Synthetic Data Sources

Use synthetic data only as a supplement, not the core dataset.

Recommended synthetic stack:

| Source | Role |
|---|---|
| [Objaverse](https://objaverse.allenai.org/) | large-scale 3D object assets |
| [Objectron](https://github.com/google-research-datasets/Objectron) | object-centric video with AR metadata and 3D boxes |
| [ProcTHOR](https://procthor.allenai.org/) | synthetic room layouts and object placements |
| [BlenderProc](https://dlr-rm.github.io/BlenderProc/index.html) | render synthetic images, masks, and annotations |

Recommended synthetic use cases:

1. create many views of rare target objects like `airpods_case`, `wallet`, `keys`, and `charger`
2. simulate partial occlusion and clutter
3. generate hard negatives in drawers, backpacks, beds, and couches
4. create mask-rich data cheaply for segmentation debugging

Do not rely on synthetic-only training for final `M1`.

## 6. Access And Licensing Notes

These matter operationally.

| Source | Access note |
|---|---|
| [Open Images V7](https://storage.googleapis.com/openimages/web/download_v7.html) | easy public download with official subset tooling |
| [COCO](https://cocodataset.org/#download) | easy public download |
| [Objects365](https://www.objects365.org/download.html) | academic-purpose only; official page says images remain subject to Flickr terms |
| [LVIS](https://www.lvisdataset.org/) | public, but verify current terms before internal redistribution |
| [ADE20K](https://ade20k.csail.mit.edu/request_data) | registration required |
| [ScanNet](https://github.com/ScanNet/ScanNet) | official repo states download requires signed terms sent from institutional email |
| [Matterport3D](https://niessner.github.io/Matterport/) | official project page states signed terms are required |
| [HM3D](https://aihabitat.org/datasets/hm3d/) | check the Habitat/Matterport access terms before use |
| [Ego4D](https://ego4d-data.org/) | check current data-use agreement and access process |

## 7. Recommended Acquisition Order

### Phase 1: Immediate Bootstrap

Download:

1. `Open Images V7`
2. `COCO`
3. `Objects365`
4. `LVIS`
5. `Visual Genome`
6. `Flickr30k Entities`
7. `RefCOCO`
8. `ARKitScenes`
9. `ScanNet++`

### Phase 2: Mandatory Private Capture

Collect:

1. visible closed-set label captures
2. room sweeps with ARKit metadata
3. hidden-search episodes

### Phase 3: Supplemental Sources

Add if needed:

1. `ScanNet`
2. `Matterport3D`
3. `HM3D`
4. `ProcTHOR`
5. `Objaverse`
6. `BlenderProc`
7. `Ego4D`
8. `EPIC-KITCHENS`

## 8. Label-Level Sourcing Decision

| Locked label | Public bootstrap | Private capture required | Synthetic recommended |
|---|---|---|---|
| `airpods_case` | weak | yes | yes |
| `wallet` | weak | yes | yes |
| `keys` | weak | yes | yes |
| `tv_remote` | strong | yes | optional |
| `glasses` | medium | yes | optional |
| `phone` | strong | yes | optional |
| `charger` | weak | yes | yes |

Interpretation:

1. every label still needs private capture
2. only `tv_remote`, `phone`, and `glasses` have good public bootstrap value
3. `airpods_case`, `wallet`, `keys`, and `charger` are the highest-risk categories

## 9. Final Recommendation

If the question is “what data sources do we need for the project to work,” the answer is:

Required:

1. private iPhone visible-object dataset
2. private iPhone room-sweep dataset
3. private hidden-search staged dataset
4. `Open Images V7`
5. `COCO`
6. `Objects365`
7. `LVIS`
8. `Visual Genome`
9. `Flickr30k Entities`
10. `RefCOCO`
11. `ARKitScenes`
12. `ScanNet++`

Strongly recommended:

1. `ScanNet`
2. `Matterport3D`
3. `HM3D`
4. `ProcTHOR`
5. `Objaverse`
6. `BlenderProc`
7. `Ego4D`
8. `EPIC-KITCHENS`

Non-negotiable product truth:

1. the project does not work from public datasets alone
2. the hidden-search feature does not work without private staged supervision
3. the current locked label set requires private capture for long-tail objects
