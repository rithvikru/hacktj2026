# hacktj2026

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

SAM2 quality mode:

- The backend launcher auto-enables SAM2 if it finds:
  - repo: `/Users/rithvikr/projects/sam2`
  - checkpoint: `/Users/rithvikr/models/sam2/sam2.1_hiera_small.pt`
- You can override those with `SAM2_REPO_DIR`, `SAM2_MODEL_DIR`, `SAM2_CONFIG_PATH`, and `SAM2_CHECKPOINT_PATH`.
