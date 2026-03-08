# Closed-Set Dataset Records

Populate this directory with the record files used by the `M1` trainer:

- `frame-records.jsonl`
- `detection-annotations.jsonl`

Both files must follow the schemas in:

- `datasets/schemas/frame-record.schema.json`
- `datasets/schemas/detection-annotation.schema.json`

Use the templates in this directory as the starting point, then validate the populated files before training:

```bash
cd ml
uv run python datasets/tools/validate_closed_set_dataset.py \
  --frame-records datasets/records/frame-records.jsonl \
  --annotations datasets/records/detection-annotations.jsonl \
  --output outputs/datasets/closed_set_validation.json
```

Rules enforced by the trainer and validator:

- only `fully_visible` and `partially_occluded` annotations are valid for `M1`
- labels must come from `datasets/manifests/closed-set-labels.yaml`
- split assignment must remain grouped, not random by frame
