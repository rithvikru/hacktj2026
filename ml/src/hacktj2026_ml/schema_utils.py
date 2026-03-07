from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from hacktj2026_ml.paths import DATASET_SCHEMA_DIR


def load_schema(schema_name: str) -> dict[str, Any]:
    schema_path = DATASET_SCHEMA_DIR / schema_name
    with schema_path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate_instance(instance: dict[str, Any], schema_name: str) -> list[str]:
    schema = load_schema(schema_name)
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(instance), key=lambda item: list(item.path))
    return [error.message for error in errors]


def read_json(path: str | Path) -> dict[str, Any]:
    json_path = Path(path)
    with json_path.open("r", encoding="utf-8") as handle:
        return json.load(handle)
