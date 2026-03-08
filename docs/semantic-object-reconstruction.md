# Semantic Object Reconstruction

## Goal

Turn a saved room scan into **persistent semantic 3D object instances**, not just:

- RoomPlan boxes
- raw point clouds
- frame-local 2D detections

Each reconstructed object should have:

- canonical label
- stable world transform
- size estimate
- support anchor
- support relation
- low-poly mesh asset
- scene-level JSON record

## Current backend implementation

After room-level reconstruction, the backend now runs an object-centric sidecar in:

- [semantic_scene.py](/Users/rithvikr/projects/hacktj2026/ml/reconstruction/objects/semantic_scene.py)

Pipeline:

1. choose a pose-diverse subset of LiDAR-backed frames
2. run open-vocabulary detection
3. refine detections with SAM 2 when available
4. project mask or bbox pixels through LiDAR depth into world coordinates
5. cluster cross-view observations by label and 3D proximity
6. fit an upright low-poly oriented box per cluster
7. infer support relation
8. export:
   - `semantic_scene.json`
   - one `.obj` per object

## Scene JSON

The backend writes:

- `data/rooms/<room_id>/reconstruction/semantic_scene.json`

And exposes it at:

- `GET /rooms/{room_id}/semantic-objects`

Asset discovery also includes:

- `semanticSceneURL`
- `semanticObjectCount`

## Object record fields

Each object in `semantic_scene.json` contains:

- `id`
- `label`
- `confidence`
- `world_transform16`
- `center_xyz`
- `extent_xyz`
- `axis_aligned_min_xyz`
- `axis_aligned_max_xyz`
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
- `observed_frame_ids`
- `mask_supported_views`
- `bbox_fallback_views`
- `support_relation`

## Support relation semantics

Current support relation types:

- `self_surface`
- `supported_by`
- `supported_by_floor`

This is designed to answer questions like:

- what is this object resting on
- where is its base anchor
- where should the mesh sit in the room

## Why this architecture is better

The old room pipeline only produced room-scale geometry. That is insufficient for semantic object display.

This object-centric layer follows the right structure:

- detection gives semantic identity
- segmentation gives cleaner object support
- LiDAR depth gives metric geometry
- multi-view clustering gives persistence across viewpoints

That is the minimum viable architecture for “show me the objects in the room as 3D semantic instances.”

## Limits

This is still a fast low-poly semantic representation, not a perfect object replica.

Current mesh quality is:

- low-poly oriented box
- good for placement and semantic display
- not a detailed watertight mesh

If you want higher object fidelity later, the next step is object-local multi-view meshing instead of an oriented-box mesh export.

## Research sources

- Apple RoomPlan captured room objects are approximate bounding boxes, not fine semantic meshes: https://developer.apple.com/documentation/roomplan/capturedroom/modelprovider
- Apple ARKitScenes uses RGB + LiDAR depth + pose for indoor scene reconstruction: https://machinelearning.apple.com/research/arkitscenes
- ScanNet++ documents iPhone RGB, depth, and ARKit camera parameters for indoor reconstruction: https://scannetpp.mlsg.cit.tum.de/scannetpp/documentation
- OpenMask3D shows open-vocabulary 3D instance segmentation from 2D features projected into 3D: https://openmask3d.github.io/
- 3D Gaussian Splatting official project: https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/
- TMO demonstrates object reconstruction on mobile devices from AR-style captures: https://openaccess.thecvf.com/content/CVPR2023/html/Goel_TMO_Textured_Mesh_Acquisition_of_Objects_With_a_Mobile_Device_CVPR_2023_paper.html
