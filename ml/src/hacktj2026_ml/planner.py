from __future__ import annotations

import re
from uuid import uuid4

from hacktj2026_ml.query_contracts import (
    ExecutorName,
    PlannerAmbiguity,
    PlannerPlan,
    PlannerRelation,
    PlannerRequest,
)

_RELATION_MARKERS: tuple[tuple[str, str], ...] = (
    ("in front of", "in_front_of"),
    ("next to", "near"),
    ("inside", "inside"),
    ("behind", "behind"),
    ("under", "under"),
    ("near", "near"),
    (" on ", "on"),
)

_ATTRIBUTE_TOKENS = {
    "black",
    "blue",
    "white",
    "red",
    "green",
    "small",
    "large",
    "left",
    "right",
    "silver",
    "brown",
}

_FILLER_PREFIXES = (
    "please ",
    "can you ",
    "could you ",
    "would you ",
    "show me ",
    "find me ",
    "locate ",
    "find ",
    "where is ",
    "where are ",
    "tell me ",
)

_LEADING_NOISE = {
    "my",
    "the",
    "a",
    "an",
    "please",
}

_ALIAS_MAP = {
    "airpods": "airpods case",
    "airpod": "airpods case",
    "earbuds": "airpods case",
    "earbud case": "airpods case",
    "cell phone": "phone",
    "iphone": "phone",
    "spectacles": "glasses",
}

_AMBIGUITY_MAP = {
    "charger": (
        "phone charger",
        "laptop charger",
        "charging cable",
    ),
    "headphones": (
        "airpods case",
        "loose earbuds",
        "over-ear headphones",
    ),
    "bag": (
        "backpack",
        "duffel bag",
        "shopping bag",
    ),
    "remote": (
        "tv remote",
        "garage remote",
        "presentation remote",
    ),
}

def build_planner_plan(request: PlannerRequest) -> PlannerPlan:
    normalized_query = normalize_query(request.query_text)
    intent = detect_intent(request.query_text, normalized_query)
    relations = extract_relations(normalized_query)
    target_phrase = extract_target_phrase(normalized_query, intent, relations)
    target_phrase = apply_user_aliases(target_phrase, request.user_aliases)
    attributes = extract_attributes(target_phrase)
    canonical_query_label = canonicalize_target_phrase(
        target_phrase=target_phrase,
        room_request=request,
    )
    ambiguities = detect_ambiguities(canonical_query_label, request)
    search_class, executor_order = determine_execution_policy(
        request=request,
        intent=intent,
        canonical_query_label=canonical_query_label,
        ambiguities=ambiguities,
    )
    can_use_local_accelerator = supports_local_acceleration(
        canonical_query_label,
        request.local_capabilities.supported_labels,
    )

    notes: list[str] = []
    if attributes:
        notes.append("Preserve extracted attributes during grounding and retrieval.")
    if relations:
        notes.append("Use extracted relations during scene-graph filtering and re-ranking.")
    if ambiguities:
        notes.append("Ambiguity detected; preserve alternatives and avoid overcommitting.")
    if request.prior_query_history:
        notes.append("Recent room query history is available for disambiguation.")
    if intent == "findLikelyObjectLocation":
        notes.append("Likely-location query should preserve probabilistic fallback output.")

    return PlannerPlan(
        query_id=str(uuid4()),
        query_text=request.query_text,
        normalized_query=normalized_query,
        intent=intent,
        target_phrase=target_phrase,
        canonical_query_label=canonical_query_label,
        attributes=attributes,
        relations=relations,
        search_class=search_class,
        executor_order=executor_order,
        requires_backend=request.backend_available,
        can_use_local_accelerator=can_use_local_accelerator,
        should_compute_hidden_fallback=True,
        ambiguities=ambiguities,
        notes=notes,
    )

def normalize_query(query_text: str) -> str:
    cleaned = re.sub(r"[?!.,]+", " ", query_text.lower())
    cleaned = " ".join(cleaned.split())
    for prefix in _FILLER_PREFIXES:
        if cleaned.startswith(prefix):
            cleaned = cleaned.removeprefix(prefix).strip()
            break
    return strip_leading_noise(cleaned)

def detect_intent(query_text: str, normalized_query: str):
    lowered = query_text.lower().strip()
    if lowered.startswith("how many") or lowered.startswith("count "):
        return "countObjects"
    if lowered.startswith("show nearest") or " nearest " in f" {lowered} ":
        return "showNearest"
    if lowered.startswith("show supporting surface") or " supporting surface " in f" {lowered} ":
        return "showSupportingSurface"
    if lowered.startswith("what is inside") or lowered.startswith("what's inside") or lowered.startswith("show contained"):
        return "showContainedItems"
    if lowered.startswith("explain why") or lowered.startswith("why did"):
        return "explainWhy"
    if any(marker in lowered for marker in ("likely", "probably", "most likely")):
        return "findLikelyObjectLocation"
    return "findObject"

def extract_attributes(text: str) -> list[str]:
    return [token for token in text.split() if token in _ATTRIBUTE_TOKENS]

def extract_relations(normalized_query: str) -> list[PlannerRelation]:
    relations: list[PlannerRelation] = []
    padded_query = f" {normalized_query} "
    for marker, normalized_relation in _RELATION_MARKERS:
        padded_marker = marker if marker.startswith(" ") else f" {marker} "
        if padded_marker not in padded_query:
            continue
        raw_reference = padded_query.split(padded_marker, maxsplit=1)[1].strip()
        reference = strip_leading_noise(raw_reference)
        if reference:
            relations.append(PlannerRelation(relation=normalized_relation, reference=reference))
            break
    return relations

def extract_target_phrase(normalized_query: str, intent: str, relations: list[PlannerRelation]) -> str:
    if intent == "countObjects":
        for prefix in ("how many ", "count "):
            if normalized_query.startswith(prefix):
                return strip_leading_noise(normalized_query.removeprefix(prefix).strip())

    if intent == "showNearest":
        prefix = "show nearest "
        if normalized_query.startswith(prefix):
            return strip_leading_noise(normalized_query.removeprefix(prefix).strip())

    if intent == "findLikelyObjectLocation":
        for marker in ("likely places i left ", "likely place i left ", "probably ", "likely "):
            if normalized_query.startswith(marker):
                return strip_leading_noise(normalized_query.removeprefix(marker).strip())

    if not relations:
        return strip_leading_noise(normalized_query)

    relation = relations[0]
    for marker, normalized_relation in _RELATION_MARKERS:
        if normalized_relation != relation.relation:
            continue
        split_marker = marker.strip()
        if split_marker in normalized_query:
            return strip_leading_noise(normalized_query.split(split_marker, maxsplit=1)[0].strip())
    return strip_leading_noise(normalized_query)

def canonicalize_target_phrase(target_phrase: str, room_request: PlannerRequest) -> str:
    phrase = replace_known_aliases(target_phrase)
    phrase = canonicalize_from_catalog(phrase, room_request.object_prototype_catalog)

    if phrase == "remote":
        context = {item.lower() for item in room_request.room_metadata_summary.prominent_furniture}
        context.update(item.lower() for item in room_request.room_metadata_summary.sections)
        if {"tv", "television", "living room", "couch"} & context:
            return "tv remote"

    return phrase

def replace_known_aliases(text: str) -> str:
    updated = text
    for alias, canonical in _ALIAS_MAP.items():
        updated = re.sub(rf"\b{re.escape(alias)}\b", canonical, updated)
    return updated

def apply_user_aliases(target_phrase: str, user_aliases: dict[str, list[str]]) -> str:
    phrase = target_phrase
    for canonical_label, aliases in user_aliases.items():
        for alias in aliases:
            if re.search(rf"\b{re.escape(alias.lower())}\b", phrase):
                phrase = re.sub(rf"\b{re.escape(alias.lower())}\b", canonical_label.lower(), phrase)
    return phrase

def canonicalize_from_catalog(text: str, catalog: list[str]) -> str:
    lowered_catalog = {item.lower(): item.lower() for item in catalog}
    if text in lowered_catalog:
        return text

    tokens = text.split()
    for size in range(len(tokens), 0, -1):
        suffix = " ".join(tokens[-size:])
        if suffix in lowered_catalog:
            prefix = " ".join(tokens[:-size])
            return " ".join(part for part in (prefix, suffix) if part)
    return text

def detect_ambiguities(canonical_query_label: str, request: PlannerRequest) -> list[PlannerAmbiguity]:
    ambiguities: list[PlannerAmbiguity] = []

    lowered = canonical_query_label.lower()
    for ambiguous_key, candidates in _AMBIGUITY_MAP.items():
        if ambiguous_key in lowered and lowered not in candidates:
            ambiguities.append(
                PlannerAmbiguity(
                    ambiguity_type="target",
                    candidates=list(candidates),
                    explanation=f'"{ambiguous_key}" can refer to multiple object variants.',
                )
            )
            break

    if request.user_aliases:
        matching_alias_sets = [
            [canonical, *aliases]
            for canonical, aliases in request.user_aliases.items()
            if lowered == canonical.lower() and len(aliases) > 1
        ]
        if matching_alias_sets:
            ambiguities.append(
                PlannerAmbiguity(
                    ambiguity_type="target",
                    candidates=matching_alias_sets[0],
                    explanation="Multiple user alias mappings could match this query.",
                )
            )

    return ambiguities

def determine_execution_policy(
    request: PlannerRequest,
    intent: str,
    canonical_query_label: str,
    ambiguities: list[PlannerAmbiguity],
) -> tuple[str, list[ExecutorName]]:
    if has_signal_affordance(canonical_query_label, request):
        base_order: list[ExecutorName] = [
            "signal",
            "backend_open_vocab",
            "local_observation",
            "scene_graph",
            "hidden_inference",
        ]
        return "signal_based_localization", filter_executor_order(base_order, request)

    if intent == "findLikelyObjectLocation":
        base_order = [
            "signal",
            "backend_open_vocab",
            "local_observation",
            "scene_graph",
            "hidden_inference",
        ]
        return "hidden_object_likelihood_inference", filter_executor_order(base_order, request)

    if request.backend_available:
        base_order = [
            "signal",
            "backend_open_vocab",
            "local_observation",
            "scene_graph",
            "hidden_inference",
        ]
        return "planner_led_open_vocab_visible_search", filter_executor_order(base_order, request)

    if supports_local_acceleration(
        canonical_query_label,
        request.local_capabilities.supported_labels,
    ):
        base_order = ["signal", "local_observation", "scene_graph", "hidden_inference"]
        return "local_accelerated_visible_search", filter_executor_order(base_order, request)

    if ambiguities:
        base_order = ["signal", "local_observation", "scene_graph", "hidden_inference"]
        return "last_seen_retrieval", filter_executor_order(base_order, request)

    base_order = ["signal", "local_observation", "scene_graph", "hidden_inference"]
    return "last_seen_retrieval", filter_executor_order(base_order, request)

def filter_executor_order(
    executors: list[ExecutorName],
    request: PlannerRequest,
) -> list[ExecutorName]:
    filtered: list[ExecutorName] = []
    for executor in executors:
        if executor == "signal" and not (
            request.signal_capabilities.cooperative_available
            or request.signal_capabilities.tag_support_available
        ):
            continue
        if executor == "backend_open_vocab" and not request.backend_available:
            continue
        filtered.append(executor)
    return filtered or ["local_observation", "hidden_inference"]

def supports_local_acceleration(query_label: str, supported_labels: list[str]) -> bool:
    if not supported_labels:
        return False
    normalized_labels = {label.lower() for label in supported_labels}
    return query_label.lower() in normalized_labels or query_label.split()[-1].lower() in normalized_labels

def has_signal_affordance(query_label: str, request: PlannerRequest) -> bool:
    if not (
        request.signal_capabilities.cooperative_available
        or request.signal_capabilities.tag_support_available
    ):
        return False

    signal_terms = {"tag", "tracker", "tagged", "beacon"}
    tokens = set(query_label.lower().split())
    return bool(tokens & signal_terms)

def strip_leading_noise(text: str) -> str:
    tokens = text.split()
    while tokens and tokens[0] in _LEADING_NOISE:
        tokens.pop(0)
    return " ".join(tokens)
