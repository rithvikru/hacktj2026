# ML Workspace

This directory contains the AI/ML scaffolding for the spatial search system.

## Quick Start

Create the environment:

```bash
cd ml
uv sync --group dev
```

Add the groups you need for a given track:

```bash
uv sync --group dev --group training
uv sync --group dev --group training --group export
uv sync --group dev --group serving
uv sync --group dev --group query-serving
uv sync --group dev --group retrieval --group vision
```

Run starter entrypoints:

```bash
uv run python closed_set/training/train.py --config closed_set/configs/baseline.yaml
uv run python closed_set/eval/evaluate.py --config closed_set/configs/baseline.yaml --checkpoint outputs/closed_set/train/.../checkpoints/last.ckpt
uv run python datasets/tools/validate_closed_set_dataset.py --frame-records datasets/records/frame-records.jsonl --annotations datasets/records/detection-annotations.jsonl
uv run --group export python closed_set/export/export_coreml.py --config closed_set/configs/baseline.yaml --checkpoint outputs/closed_set/train/.../checkpoints/last.ckpt
uv run python datasets/tools/download_open_images_bootstrap.py --output-root datasets/external/public/open-images-v7 --subset validation --class-name "Glasses" --class-name "Mobile phone" --class-name "Remote control" --max-images-per-class 250
uv run python datasets/tools/download_coco_2017.py --output-root datasets/external/public/coco --verify-urls --allow-http-fallback
uv run python open_vocab/grounding_dino/run_grounding.py --prompt "wallet"
uv run python reconstruction/da3/run_pipeline.py --room-id demo-room --frame-bundle ../docs
uv run python hidden_inference/rules/rank.py --query-label wallet
uv run --group serving python serving/tools/export_contract_schemas.py
uv run --group query-serving uvicorn serving.api.app:app --app-dir . --reload
```

Open-vocab query serving:

- Use `uv sync --group dev --group query-serving` for the backend that serves natural-language visual search.
- `SAM 2` mask refinement is optional and requires explicit local setup.
- Set `SAM2_CONFIG_PATH` and `SAM2_CHECKPOINT_PATH` before starting the server to enable it.
- If those variables are missing, the backend will fall back to bbox-only masks instead of failing startup.

Chat layer:

```bash
# optional: enable OpenAI-backed chat replies
set OPENAI_API_KEY=your_key_here
set OPENAI_MODEL=gpt-4.1-mini

# backend chat endpoint
POST /rooms/{room_id}/chat
```

Dataset bootstrap notes:

- `datasets/tools/download_open_images_bootstrap.py` downloads official Open Images metadata, filters the target classes, and can fetch the matching subset images into `datasets/external/public/open-images-v7/`
- `datasets/tools/download_coco_2017.py` downloads the official COCO 2017 archives into `datasets/external/public/coco/`
- In this environment, `images.cocodataset.org` currently needs `--allow-http-fallback` because HTTPS certificate verification fails against the official host
- The broader acquisition sequence and storage contract live in `../docs/dataset-acquisition-plan.md`

## Layout

- `datasets/`: schemas, ontologies, and split manifests
- `closed_set/`: on-device detector configs, training, export, and evaluation
- `open_vocab/`: grounding, masking, retrieval, and evaluation
- `reconstruction/`: delayed reconstruction and dense asset generation
- `hidden_inference/`: candidate features, ranking, and evaluation
- `serving/`: API, contract schemas, worker stubs, and model manifests
- `src/hacktj2026_ml/`: shared Python utilities and contracts

Acquisition and collection planning lives in:

- `../docs/dataset-source-research.md`
- `../docs/dataset-acquisition-plan.md`
- `datasets/manifests/public-dataset-acquisition.yaml`
- `datasets/manifests/private-dataset-collection-plan.yaml`
