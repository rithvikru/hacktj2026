# Reconstruction Research And Fixes

## Why the old pipeline was fundamentally limited

### 1. It treated LiDAR depth like an optional hint instead of the primary geometry signal

The iPhone pipeline already uploads:

- RGB frames
- metric LiDAR depth maps
- ARKit confidence maps
- camera poses
- camera intrinsics

That should make reconstruction a **depth-first multi-view fusion problem**, not a **run monocular depth on every image** problem.

Before this fix, the backend:

- ran a monocular depth model over every frame
- looked for the wrong ARKit depth filenames
- only used ARKit depth for scale alignment

That cost a large amount of time and also threw away the strongest geometry signal already provided by the phone.

### 2. It used the wrong camera calibration at the depth-map resolution

The stored RGB frames are `1920x1440`, but the ARKit depth maps are `256x192`.

The old point-cloud stage unprojected the low-resolution depth map using the full-resolution RGB intrinsics without scaling them to depth resolution. That warps geometry and hurts object shape and size accuracy.

### 3. It fused too many redundant frames

Users sweep the same room repeatedly from nearby viewpoints. The old pipeline attempted to reconstruct from every frame in the bundle. That is wasted work for:

- depth inference
- point unprojection
- later dense export

It also increases blur/noise instead of improving object fidelity when the extra frames are nearly duplicates.

### 4. The current “3DGS” stage is not a true image-supervised Gaussian Splatting reconstruction

The repo’s current gaussian export is a placeholder/fallback. It is useful as an intermediate dense asset, but it is not the same as a real image-optimized 3D Gaussian Splatting pipeline.

That means the current stack can produce:

- better point clouds
- better spatial memory
- better room/object geometry

But it should not be expected to produce a perfect photoreal twin.

## What the code now does

The backend reconstruction pipeline was changed to:

1. select a smaller pose-diverse subset of reconstruction frames
2. use direct ARKit LiDAR depth and confidence maps whenever available
3. fall back to monocular depth only for frames without ARKit depth
4. scale intrinsics correctly from RGB resolution to depth resolution
5. filter low-confidence depth
6. cap points per frame before global voxel downsampling
7. fail soft if gaussian export fails, while still returning the point cloud

Concretely, the main code paths are now:

- [run_pipeline.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/da3/run_pipeline.py)
- [generate.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/pointcloud/generate.py)
- [reconstruct_room.py](/Users/rithvikr/projects/hacktj2026/ml/serving/workers/reconstruct_room.py)

## Research-backed architecture conclusions

### Apple / ARKit-first conclusion

For iPhone indoor capture, the strongest immediate geometry prior is still the phone’s own:

- ARKit camera poses
- LiDAR depth
- confidence

Apple’s own ARKitScenes dataset is built around exactly those ingredients: mobile RGB, LiDAR depth, and camera pose for indoor scene understanding and reconstruction.

### Why your current stack was slower than it should be

Feed-forward monocular depth is useful when depth is missing. It is the wrong default when the phone already provides metric depth for every frame.

That is why the first architecture fix is **ARKit-depth-first**, not “swap in an even bigger monocular model.”

### What newer reconstruction research suggests

Recent multi-view systems such as DUSt3R, MASt3R, Matrix3D, VGGT, and Depth Anything 3 point in the same direction:

- use cross-view geometric consistency
- do not treat each frame as an isolated monocular prediction
- leverage pose/multi-view structure early

Those systems are promising for a later backend upgrade, especially for:

- filling depth gaps
- improving thin structures
- repairing poorly observed regions
- producing stronger dense geometry from a sparse image subset

But even before adopting them, the current repo needed to stop wasting the ARKit depth it already had.

### Why you are not getting a “perfect replica” yet

A perfect realistic room twin would require at least:

- stronger multi-view dense reconstruction than the current point-cloud fusion
- a true image-supervised Gaussian Splatting or neural rendering backend
- a real splat or neural viewer on mobile instead of a fallback point-cloud renderer

That is a later architecture step, not something the old pipeline could achieve by small tuning changes.

## Recommended next upgrades after this patch

1. Replace the placeholder gaussian export with a true image-supervised 3DGS backend.
2. Add an object-centric dense stage:
   - detect candidate object regions
   - fuse depth locally around those objects
   - export object meshes / tight boxes / low-poly proxies
3. Evaluate a modern multi-view geometry model as a backend refinement stage:
   - DUSt3R / MASt3R / Matrix3D / VGGT / DA3
4. Add a real mobile splat renderer if photoreal room twins are a product requirement.

## Sources

- Apple RoomPlan: https://developer.apple.com/augmented-reality/roomplan/
- Apple ARKitScenes: https://machinelearning.apple.com/research/arkitscenes
- ScanNet++ documentation: https://scannetpp.mlsg.cit.tum.de/scannetpp/documentation
- 3D Gaussian Splatting official project: https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/
- DUSt3R official repo: https://github.com/naver/dust3r
- MASt3R official repo: https://github.com/naver/mast3r
- VGGT official repo: https://github.com/facebookresearch/vggt
- Matrix3D official repo: https://github.com/prs-eth/Matrix3D
- Depth Anything 3 paper: https://arxiv.org/abs/2511.10647
