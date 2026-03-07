# Dataset Acquisition Plan

Status: execution plan  
Date: `2026-03-07`  
Owner: `AI/ML lead`

This document converts [dataset-source-research.md](/Users/rithvikr/projects/hacktj2026/docs/dataset-source-research.md) into an acquisition plan the team can execute.

## 1. Outcome

At the end of this plan, the repo should have:

1. all required public bootstrap datasets downloaded or access-requested
2. the private dataset directory tree created
3. the private collection checklist assigned
4. the first visible-object capture sessions scheduled
5. the first room-sweep and hidden-search sessions scheduled

## 2. Storage Layout

Use this exact storage layout under `ml/datasets/`.

```text
ml/datasets/
  external/
    public/
      open-images-v7/
        raw/
        annotations/
        subsets/
        manifests/
      coco/
        raw/
        annotations/
        manifests/
      objects365/
        raw/
        annotations/
        manifests/
      lvis/
        annotations/
        manifests/
      visual-genome/
        raw/
        annotations/
        manifests/
      flickr30k-entities/
        raw/
        annotations/
        manifests/
      refcoco/
        raw/
        annotations/
        manifests/
      arkitscenes/
        raw/
        manifests/
      scannetpp/
        raw/
        manifests/
      scannet/
        raw/
        manifests/
      matterport3d/
        raw/
        manifests/
      hm3d/
        raw/
        manifests/
      synthetic/
        objaverse/
        procthor/
        blenderproc/
    private/
      visible-objects/
        raw/
          room_*/
            session_*/
              rgb/
              depth/
              metadata/
        labels/
        exports/
      room-sweeps/
        raw/
          room_*/
            session_*/
              rgb/
              depth/
              metadata/
              roomplan/
              worldmap/
        labels/
        exports/
      hidden-episodes/
        raw/
          room_*/
            episode_*/
              rgb/
              depth/
              metadata/
              roomplan/
              notes/
        labels/
        exports/
      cooperative-signal/
        raw/
        labels/
        exports/
```

## 3. Execution Order

### Phase 0: Prepare Storage

1. create the `ml/datasets/external/public` tree
2. create the `ml/datasets/external/private` tree
3. assign one owner for public downloads and one owner for private collection ops
4. ensure enough storage for large indoor 3D datasets before starting `ScanNet++`, `ScanNet`, `Matterport3D`, or `HM3D`

### Phase 1: Required Public Bootstrap

Acquire in this order:

1. `Open Images V7`
2. `COCO`
3. `Objects365`
4. `LVIS`
5. `Visual Genome`
6. `Flickr30k Entities`
7. `RefCOCO`
8. `ARKitScenes`
9. `ScanNet++`

### Phase 2: Start Private Capture Immediately

Do not wait for all public downloads to finish.

Start:

1. visible-object capture
2. room sweeps
3. hidden episodes

### Phase 3: Secondary Public Sources

Request or download only if needed:

1. `ScanNet`
2. `Matterport3D`
3. `HM3D`
4. synthetic stack: `Objaverse`, `ProcTHOR`, `BlenderProc`
5. egocentric priors: `Ego4D`, `EPIC-KITCHENS`

## 4. Immediate Public Acquisition

### 4.1 Open Images V7

Official pages:

1. <https://storage.googleapis.com/openimages/web/index.html>
2. <https://storage.googleapis.com/openimages/web/download_v7.html>

Acquire:

1. class descriptions
2. bounding box annotations
3. instance segmentation annotations
4. subset images for the target classes and context classes

Initial class subset:

1. `Remote control`
2. `Mobile phone`
3. `Glasses`
4. `Backpack`
5. `Drawer`
6. `Bed`
7. `Couch`
8. `Headphones`

Target path:

1. `ml/datasets/external/public/open-images-v7/`

Execution command:

```bash
cd ml
uv run python datasets/tools/download_open_images_bootstrap.py \
  --output-root datasets/external/public/open-images-v7 \
  --subset validation \
  --class-name "Remote control" \
  --class-name "Mobile phone" \
  --class-name "Glasses" \
  --class-name "Backpack" \
  --class-name "Drawer" \
  --class-name "Bed" \
  --class-name "Couch" \
  --class-name "Headphones" \
  --max-images-per-class 250
```

Notes:

1. this script downloads official Open Images metadata first, then writes filtered subset CSVs and matching images
2. start with `validation`, verify label quality, then expand to `train`
3. use `--metadata-only` if you only want the manifests and filtered annotation slices before downloading images

### 4.2 COCO

Official pages:

1. <https://cocodataset.org/#home>
2. <https://cocodataset.org/#download>

Acquire:

1. `train2017`
2. `val2017`
3. `annotations_trainval2017`
4. optionally `panoptic` and `stuff` only if needed for segmentation or room-context ablations

Target path:

1. `ml/datasets/external/public/coco/`

Execution command:

```bash
cd ml
uv run python datasets/tools/download_coco_2017.py \
  --output-root datasets/external/public/coco \
  --verify-urls \
  --allow-http-fallback
```

Notes:

1. `--verify-urls` checks the official archive endpoints before starting the full download
2. in the current environment, `images.cocodataset.org` requires `--allow-http-fallback` because HTTPS certificate validation fails against the official host
3. add `--skip-extract` if you want to separate archive download from extraction

### 4.3 Objects365

Official page:

1. <https://www.objects365.org/download.html>

Acquire:

1. training images
2. validation images
3. annotation files

Target path:

1. `ml/datasets/external/public/objects365/`

Constraint:

1. official page states academic-purpose usage and image-use restrictions tied to Flickr terms

### 4.4 LVIS

Official page:

1. <https://www.lvisdataset.org/>

Acquire:

1. annotations
2. category metadata

Dependency:

1. `LVIS` rides on `COCO` images, so `COCO` must already be present

Target path:

1. `ml/datasets/external/public/lvis/`

### 4.5 Visual Genome

Official page:

1. <https://visualgenome.org/>

Acquire:

1. images
2. region descriptions
3. object annotations
4. relationships
5. attributes

Target path:

1. `ml/datasets/external/public/visual-genome/`

Operational note:

1. the official site can be flaky; do not use unofficial mirrors unless the team explicitly approves them

### 4.6 Flickr30k Entities

Official page:

1. <https://bryanplummer.com/Flickr30kEntities/>

Acquire:

1. annotation package
2. corresponding Flickr30k image set

Target path:

1. `ml/datasets/external/public/flickr30k-entities/`

### 4.7 RefCOCO

Official page:

1. <https://www.tensorflow.org/datasets/catalog/ref_coco>

Acquire:

1. dataset via the documented TFDS source or the underlying official release source referenced there

Target path:

1. `ml/datasets/external/public/refcoco/`

### 4.8 ARKitScenes

Official pages:

1. <https://machinelearning.apple.com/research/arkitscenes>
2. the official GitHub link referenced from the Apple research page

Acquire:

1. room RGB-D data
2. poses and metadata
3. geometry assets needed for reconstruction experiments

Target path:

1. `ml/datasets/external/public/arkitscenes/`

### 4.9 ScanNet++

Official page:

1. <https://scannetpp.mlsg.cit.tum.de/scannetpp/documentation>

Acquire first:

1. default download only
2. iPhone data
3. meshes and semantics
4. official toolbox

Target path:

1. `ml/datasets/external/public/scannetpp/`

Operational note:

1. official docs say the default download already includes iPhone data and is large, so do not fetch it casually on laptops with limited disk

## 5. Secondary Public Acquisition

### 5.1 ScanNet

Official page:

1. <https://github.com/ScanNet/ScanNet>

Action:

1. submit access request and signed terms if needed

### 5.2 Matterport3D

Official page:

1. <https://niessner.github.io/Matterport/>

Action:

1. complete access request and signed terms if needed

### 5.3 HM3D

Official page:

1. <https://aihabitat.org/datasets/hm3d/>

Action:

1. request access only if room-prior or embodied-search work justifies it

### 5.4 Synthetic Stack

Official pages:

1. <https://objaverse.allenai.org/>
2. <https://procthor.allenai.org/>
3. <https://dlr-rm.github.io/BlenderProc/index.html>

Use only for:

1. augmentation
2. synthetic hard negatives
3. rare-object rendering

Do not use synthetic data as the primary `M1` benchmark.

## 6. Private Collection Plan

### 6.1 Visible-Object Capture

Target:

1. `500+` labeled images per locked label
2. `20+` physical instances per label where possible
3. `10+` rooms

Collection checklist:

1. capture each object on `bed`, `desk`, `couch`, `floor`, `nightstand`, `drawer`, and `backpack` where relevant
2. capture daylight, warm lamp light, dim light, and mixed light
3. capture clean and cluttered scenes
4. capture front, side, high-angle, and low-angle views
5. capture partial occlusion by blanket, clothes, books, pillows, or cables
6. capture hard negatives in the same frame families

### 6.2 Room Sweeps

Target:

1. at least `10` rooms
2. multiple sessions per room
3. multiple clutter states per room

Per-session checklist:

1. start RoomPlan scan
2. sweep full room perimeter
3. scan support surfaces and containers closely
4. preserve ARKit poses, timestamps, intrinsics, depth, and tracking state
5. save RoomPlan export
6. save preview image
7. save world map when relocalization testing is needed

### 6.3 Hidden Episodes

Target:

1. at least `50` episodes per locked label as soon as feasible
2. at least `7` required scenario types from the spec
3. multiple rooms and multiple concealment materials

Per-episode checklist:

1. capture last clearly visible frame
2. record object movement path if possible
3. record final hidden location precisely
4. label true support surface or container
5. save candidate regions even when the final target is uncertain in the live pass

### 6.4 Cooperative Signal Capture

Only if implemented.

Checklist:

1. record paired-device or tag ID
2. record timestamped signal samples
3. record room/world alignment reference
4. record ground-truth target transform

## 7. Locked Label Priority

Highest private-capture priority:

1. `airpods_case`
2. `wallet`
3. `keys`
4. `charger`

Lower bootstrap risk because public data exists:

1. `tv_remote`
2. `phone`
3. `glasses`

## 8. First Week Execution

Day 1:

1. create the storage tree
2. download `Open Images V7` metadata and start subset pulls
3. download `COCO`
4. request or queue `Objects365`, `ARKitScenes`, and `ScanNet++`

Day 2:

1. prepare the private capture checklist
2. run the first visible-object collection session
3. run the first room-sweep session

Day 3:

1. run the first hidden-episode session
2. ingest records into `ml/datasets/records/`
3. validate them with the dataset validator

Day 4-7:

1. continue collection
2. label the first batch
3. train the first real `M1` baseline
4. evaluate on held-out room splits

## 9. Hard Rules

1. do not block private collection on public download completion
2. do not split data randomly by frame
3. do not rely on public data to solve hidden-object inference
4. do not claim `M1` stability until the locked per-label and per-room thresholds are met
5. do not import unofficial mirrors without team approval
