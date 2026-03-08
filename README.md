# hacktj2026

Read this first:

- `docs/current-system-overview.md`
- `docs/experimentation-log.md`

Source-of-truth implementation spec:

- `docs/technical-implementation-spec.md`
- `docs/ai-ml-model-spec.md`
- `docs/natural-language-search-spec.md`
- `docs/execution-checklist.md`
- `docs/dataset-source-research.md`
- `docs/dataset-acquisition-plan.md`
- `docs/reconstruction-research-and-fixes.md`
- `docs/semantic-object-reconstruction.md`
- `docs/frontend-semantic-room-spec.md`
- `docs/frontend-photoreal-dense-spec.md`

ML workspace:

- `ml/README.md`

Device backend:

- `./scripts/start-device-backend.sh`
- `./scripts/print-device-backend-url.sh`

H100 backend:

- `docs/h100-setup.md`
- `./scripts/bootstrap-h100.sh`
- `./scripts/verify-h100-stack.sh`
- `./scripts/start-h100-backend.sh`
- `./scripts/run-nerfstudio-splatfacto.sh`

SAM2 quality mode:

- The backend launcher auto-enables SAM2 if it finds:
  - repo: `/Users/rithvikr/projects/sam2`
  - checkpoint: `/Users/rithvikr/models/sam2/sam2.1_hiera_small.pt`
- You can override those with `SAM2_REPO_DIR`, `SAM2_MODEL_DIR`, `SAM2_CONFIG_PATH`, and `SAM2_CHECKPOINT_PATH`.

---

## CRITICAL: Before Production

**The `findit-live` branch contains the Meta Ray-Ban wearables integration code (`WearablesBridge`, `MetaWearablesBridge`, `WearableFrameSampler`, `WearablePersistenceService`, etc.) that is NOT on the `ml` branch.** The outdoor mode currently uses a simulated 1 FPS timer instead of real glasses frame capture.

**You MUST merge `findit-live` into `ml` before shipping.** Without this merge, the outdoor capture pipeline records GPS-stamped placeholder frames instead of actual glasses camera images. The indoor mode's room scanning also depends on this wearables code.

Files that need to come from `findit-live`:
- `mobile/Sources/Geolocate3D/Services/Wearables/WearablesBridge.swift`
- `mobile/Sources/Geolocate3D/Services/Wearables/MetaWearablesBridge.swift`
- `mobile/Sources/Geolocate3D/Services/Wearables/SimulatedWearablesBridge.swift`
- `mobile/Sources/Geolocate3D/Services/Wearables/WearableStreamSessionManager.swift`
- `mobile/Sources/Geolocate3D/Services/Wearables/WearableFrameSampler.swift`
- `mobile/Sources/Geolocate3D/Services/Wearables/WearablePersistenceService.swift`
- `mobile/Sources/Geolocate3D/Models/Wearables/WearableStreamState.swift`
- `mobile/Sources/Geolocate3D/Models/Wearables/WearableBridgeMode.swift`

Then wire `OutdoorCaptureCoordinator` to use `WearablesBridge` instead of `Timer`.
