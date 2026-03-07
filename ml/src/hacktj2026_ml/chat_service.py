from __future__ import annotations

import json
import os
from dataclasses import dataclass
from urllib import error, request

from hacktj2026_ml.chat_contracts import ChatMessageDTO, ChatRequestDTO, ChatResponseDTO
from hacktj2026_ml.query_contracts import QueryRequest
from hacktj2026_ml.query_engine import QueryEngine, build_planner_request
from hacktj2026_ml.toolkit import DefaultQueryToolkit

_DEFAULT_SYSTEM_PROMPT = """You are the backend conversational interface for a spatial search system.
You help users ask questions about objects, rooms, search results, and hypotheses.
You must stay grounded in structured evidence supplied by the backend.
Do not claim direct detection when the evidence is probabilistic.
Be concise, factual, and useful."""


@dataclass(slots=True)
class ChatService:
    query_engine: QueryEngine | None = None
    provider: str = "mock"
    model: str = "mock-chat"

    def chat(self, payload: ChatRequestDTO) -> ChatResponseDTO:
        engine = self.query_engine or QueryEngine(toolkit=DefaultQueryToolkit())
        query_request = QueryRequest(query_text=payload.query_text)
        planner_request = build_planner_request(room_id=payload.room_id, request=query_request)
        query_response = engine.execute_query(planner_request=planner_request, query_request=query_request)

        planner_summary = build_planner_summary(query_response) if payload.include_planner_context else None
        system_prompt = build_system_prompt(planner_summary, query_response if payload.include_query_result else None)
        messages = build_llm_messages(
            prior_messages=payload.messages,
            user_query=payload.query_text,
            system_prompt=system_prompt,
        )

        provider, model, assistant_text = self._generate_reply(
            messages=messages,
            planner_summary=planner_summary,
            query_response=query_response,
        )

        return ChatResponseDTO(
            room_id=payload.room_id,
            reply=ChatMessageDTO(role="assistant", content=assistant_text),
            planner_summary=planner_summary,
            query_response=query_response if payload.include_query_result else None,
            provider=provider,
            model=model,
        )

    def _generate_reply(self, messages, planner_summary, query_response):
        api_key = os.getenv("OPENAI_API_KEY")
        model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
        if api_key:
            try:
                reply = call_openai_responses_api(
                    api_key=api_key,
                    model=model,
                    messages=messages,
                )
                return "openai", model, reply
            except Exception as exc:  # pragma: no cover - fallback path
                fallback = build_mock_reply(
                    user_query=messages[-1]["content"],
                    planner_summary=planner_summary,
                    query_response=query_response,
                    failure_reason=str(exc),
                )
                return "mock-fallback", model, fallback

        fallback = build_mock_reply(
            user_query=messages[-1]["content"],
            planner_summary=planner_summary,
            query_response=query_response,
            failure_reason=None,
        )
        return self.provider, self.model, fallback


def build_planner_summary(query_response) -> str:
    plan = query_response.planner_plan
    relations = ", ".join(f"{item.relation}:{item.reference}" for item in plan.relations) or "none"
    ambiguities = ", ".join(
        f"{item.ambiguity_type}={';'.join(item.candidates)}" for item in plan.ambiguities
    ) or "none"
    return (
        f"intent={plan.intent}; "
        f"target={plan.canonical_query_label}; "
        f"search_class={plan.search_class}; "
        f"executors={','.join(plan.executor_order)}; "
        f"relations={relations}; "
        f"ambiguities={ambiguities}; "
        f"result_type={query_response.result_type}"
    )


def build_system_prompt(planner_summary: str | None, query_response) -> str:
    parts = [_DEFAULT_SYSTEM_PROMPT]
    if planner_summary:
        parts.append(f"Planner summary: {planner_summary}")
    if query_response is not None:
        parts.append(f"Structured query response: {query_response.model_dump_json()}")
    return "\n".join(parts)


def build_llm_messages(prior_messages, user_query: str, system_prompt: str):
    messages = [{"role": "system", "content": system_prompt}]
    safe_prior_messages = [
        {"role": item.role, "content": item.content}
        for item in prior_messages
        if item.role in {"user", "assistant"}
    ]
    messages.extend(safe_prior_messages)
    if not safe_prior_messages or safe_prior_messages[-1]["content"].strip() != user_query.strip():
        messages.append({"role": "user", "content": user_query})
    return messages


def call_openai_responses_api(api_key: str, model: str, messages) -> str:
    body = json.dumps(
        {
            "model": model,
            "input": messages,
        }
    ).encode("utf-8")
    http_request = request.Request(
        "https://api.openai.com/v1/responses",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with request.urlopen(http_request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except error.HTTPError as exc:  # pragma: no cover - network dependent
        detail = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"OpenAI request failed: {exc.code} {detail}") from exc

    output = payload.get("output", [])
    content_parts: list[str] = []
    for item in output:
        for content in item.get("content", []):
            if content.get("type") == "output_text":
                content_parts.append(content.get("text", ""))
    if content_parts:
        return "\n".join(part for part in content_parts if part).strip()
    raise RuntimeError("OpenAI response did not contain output_text.")


def build_mock_reply(user_query: str, planner_summary: str | None, query_response, failure_reason: str | None) -> str:
    lines = []
    if query_response.primary_result is not None:
        result = query_response.primary_result
        lines.append(
            f"I found a {result.result_type.replace('_', ' ')} result for '{result.label}' with confidence {result.confidence:.2f}."
        )
        lines.append(result.explanation)
    elif query_response.hypotheses:
        hypothesis = query_response.hypotheses[0]
        lines.append(
            f"I do not have a direct detection for '{hypothesis.query_label}', but I have a likely-hidden hypothesis."
        )
        lines.append(hypothesis.explanation)
    else:
        lines.append(f"I do not have confirmed evidence for '{user_query}'.")
        lines.append(query_response.explanation)

    if planner_summary:
        lines.append(f"Planner: {planner_summary}")
    if failure_reason:
        lines.append(f"LLM provider fallback activated: {failure_reason}")
    return " ".join(lines)
