from __future__ import annotations

import logging
from dataclasses import dataclass, field

import numpy as np

logger = logging.getLogger(__name__)

JUMP_THRESHOLD_M = 2.0  # meters


@dataclass
class PoseValidationReport:
    total_frames: int
    valid_frames: int
    pose_jump_count: int
    intrinsics_consistent: bool
    warnings: list[str] = field(default_factory=list)


def validate_poses(frame_metadata: list[dict]) -> PoseValidationReport:
    """Check frame poses for consistency. Returns report with warnings."""
    total = len(frame_metadata)
    warnings: list[str] = []
    valid = 0
    jumps = 0
    prev_pos = None
    fx_values = []

    for i, frame in enumerate(frame_metadata):
        extrinsics = frame.get(
            "cameraTransform16", frame.get("camera_transform16", [])
        )
        intrinsics = frame.get("intrinsics9", frame.get("intrinsics_9", []))

        # Check for valid transform
        if len(extrinsics) != 16:
            warnings.append(f"Frame {i}: missing or invalid extrinsics ({len(extrinsics)} values)")
            continue

        if len(intrinsics) != 9:
            warnings.append(f"Frame {i}: missing or invalid intrinsics ({len(intrinsics)} values)")
            continue

        valid += 1

        # Extract position from 4x4 column-major transform
        T = np.array(extrinsics, dtype=np.float32).reshape(4, 4, order="F")
        pos = T[:3, 3]

        # Check for pose jumps
        if prev_pos is not None:
            dist = np.linalg.norm(pos - prev_pos)
            if dist > JUMP_THRESHOLD_M:
                jumps += 1
                warnings.append(
                    f"Frame {i}: pose jump of {dist:.2f}m from previous frame"
                )
        prev_pos = pos

        # Track intrinsics
        K = np.array(intrinsics, dtype=np.float32).reshape(3, 3, order="F")
        fx_values.append(K[0, 0])

    # Check intrinsics consistency
    intrinsics_ok = True
    if len(fx_values) >= 2:
        fx_std = np.std(fx_values)
        fx_mean = np.mean(fx_values)
        if fx_mean > 0 and fx_std / fx_mean > 0.05:
            intrinsics_ok = False
            warnings.append(
                f"Intrinsics inconsistent: fx std/mean = {fx_std / fx_mean:.3f}"
            )

    if valid == 0 and total > 0:
        warnings.append("No valid frames found")

    return PoseValidationReport(
        total_frames=total,
        valid_frames=valid,
        pose_jump_count=jumps,
        intrinsics_consistent=intrinsics_ok,
        warnings=warnings,
    )
