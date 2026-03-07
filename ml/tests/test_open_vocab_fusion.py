import numpy as np

from open_vocab.fusion import (
    GroundedObservation,
    cluster_grounded_observations,
    robust_depth_from_bbox,
)


def test_robust_depth_from_bbox_prefers_front_surface():
    depth_map = np.full((10, 10), 2.0, dtype=np.float32)
    depth_map[4, 4] = 0.7
    depth_map[4, 5] = 0.72
    depth_map[5, 4] = 0.69
    depth_map[5, 5] = 0.71

    depth_m, uv_norm = robust_depth_from_bbox(depth_map, [0.2, 0.2, 0.8, 0.8])

    assert depth_m is not None
    assert 0.65 <= depth_m <= 0.8
    assert uv_norm == (0.5, 0.5)


def test_cluster_grounded_observations_merges_close_views():
    observations = [
        GroundedObservation(
            detection_idx=0,
            image_path="frame-1.jpg",
            frame_id="frame-1",
            label="phone",
            bbox_xyxy_norm=[0.1, 0.1, 0.2, 0.2],
            world_xyz=np.array([1.00, 0.75, 2.00], dtype=np.float32),
            score=0.82,
            stability_score=0.9,
            support_count=24,
            mask_ref="sam2:frame-1:0",
            evidence=["groundingDINO", "sam2"],
        ),
        GroundedObservation(
            detection_idx=1,
            image_path="frame-2.jpg",
            frame_id="frame-2",
            label="phone",
            bbox_xyxy_norm=[0.11, 0.1, 0.21, 0.21],
            world_xyz=np.array([1.04, 0.76, 2.03], dtype=np.float32),
            score=0.79,
            stability_score=0.88,
            support_count=20,
            mask_ref="sam2:frame-2:1",
            evidence=["groundingDINO", "sam2"],
        ),
        GroundedObservation(
            detection_idx=2,
            image_path="frame-3.jpg",
            frame_id="frame-3",
            label="phone",
            bbox_xyxy_norm=[0.1, 0.12, 0.19, 0.22],
            world_xyz=np.array([0.98, 0.74, 1.97], dtype=np.float32),
            score=0.76,
            stability_score=0.84,
            support_count=19,
            mask_ref="sam2:frame-3:2",
            evidence=["groundingDINO", "sam2"],
        ),
        GroundedObservation(
            detection_idx=3,
            image_path="frame-4.jpg",
            frame_id="frame-4",
            label="phone",
            bbox_xyxy_norm=[0.45, 0.45, 0.70, 0.80],
            world_xyz=np.array([2.5, 0.75, 3.0], dtype=np.float32),
            score=0.60,
            stability_score=0.7,
            support_count=8,
            mask_ref=None,
            evidence=["groundingDINO"],
        ),
    ]

    clusters = cluster_grounded_observations(observations)

    assert len(clusters) == 2
    assert len(clusters[0].observations) == 3
    assert clusters[0].score > clusters[1].score
