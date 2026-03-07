from pathlib import Path

ML_ROOT = Path(__file__).resolve().parents[2]
DATASET_SCHEMA_DIR = ML_ROOT / "datasets" / "schemas"
DATASET_MANIFEST_DIR = ML_ROOT / "datasets" / "manifests"
SERVING_MANIFEST_DIR = ML_ROOT / "serving" / "manifests"
