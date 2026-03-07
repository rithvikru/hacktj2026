from __future__ import annotations

from typing import Literal

from pydantic import Field

from hacktj2026_ml.query_contracts import APIDTOModel, QueryResponseDTO


ChatRole = Literal["system", "user", "assistant", "tool"]


class ChatMessageDTO(APIDTOModel):
    role: ChatRole
    content: str = Field(min_length=1)


class ChatRequestDTO(APIDTOModel):
    query_text: str = Field(min_length=1)
    room_id: str
    messages: list[ChatMessageDTO] = Field(default_factory=list)
    include_planner_context: bool = True
    include_query_result: bool = True


class ChatResponseDTO(APIDTOModel):
    room_id: str
    reply: ChatMessageDTO
    planner_summary: str | None = None
    query_response: QueryResponseDTO | None = None
    provider: str
    model: str
