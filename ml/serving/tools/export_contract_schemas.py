from __future__ import annotations

import json
from pathlib import Path

from hacktj2026_ml.chat_contracts import ChatRequestDTO, ChatResponseDTO
from hacktj2026_ml.query_contracts import (
    OpenVocabSearchRequest,
    OpenVocabSearchResponseDTO,
    PlannerPlan,
    PlannerRequest,
    QueryRequest,
    QueryResponseDTO,
    SearchResultDTO,
)
from serving.api.app import RouteRequestDTO, RouteResponseDTO
from hacktj2026_ml.contracts import HiddenHypothesisResult


SCHEMA_ROOT = Path(__file__).resolve().parents[1] / "schemas"


def main() -> None:
    SCHEMA_ROOT.mkdir(parents=True, exist_ok=True)

    model_map = {
        "planner-request.schema.json": PlannerRequest,
        "planner-plan.schema.json": PlannerPlan,
        "query-request.schema.json": QueryRequest,
        "query-response.schema.json": QueryResponseDTO,
        "chat-request.schema.json": ChatRequestDTO,
        "chat-response.schema.json": ChatResponseDTO,
        "route-request.schema.json": RouteRequestDTO,
        "route-response.schema.json": RouteResponseDTO,
        "open-vocab-search-request.schema.json": OpenVocabSearchRequest,
        "open-vocab-search-response.schema.json": OpenVocabSearchResponseDTO,
        "search-result.schema.json": SearchResultDTO,
        "hidden-hypothesis-result.schema.json": HiddenHypothesisResult,
    }

    for filename, model in model_map.items():
        schema = model.model_json_schema(by_alias=True)
        schema["$schema"] = "https://json-schema.org/draft/2020-12/schema"
        output_path = SCHEMA_ROOT / filename
        with output_path.open("w", encoding="utf-8") as handle:
            json.dump(schema, handle, indent=2, sort_keys=True)
            handle.write("\n")
        print(f"Wrote {output_path}")


if __name__ == "__main__":
    main()
