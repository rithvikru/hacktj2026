from __future__ import annotations

from collections import Counter, defaultdict, deque
from datetime import UTC, datetime

from serving.storage.wearable_store import WearableFrameEvent, WearableSessionState

def build_topology_graph(
    sessions: list[WearableSessionState],
    room_aliases: dict[str, str] | None = None,
) -> dict:
    room_aliases = room_aliases or {}
    ordered_events = sorted(
        (
            (session.session_id, event)
            for session in sessions
            for event in session.frame_events
        ),
        key=lambda item: _parse_timestamp(item[1].timestamp),
    )

    if not ordered_events:
        return {"nodes": [], "edges": [], "segments": [], "updatedAt": datetime.now(UTC).isoformat()}

    segments: list[dict] = []
    current_segment: dict | None = None
    previous_timestamp: datetime | None = None

    for session_id, event in ordered_events:
        event_time = _parse_timestamp(event.timestamp)
        place_key, display_name = infer_place_identity(event, room_aliases)
        labels = [observed.label for observed in event.observed_objects]
        should_split = (
            current_segment is None
            or current_segment["placeId"] != place_key
            or (
                previous_timestamp is not None
                and (event_time - previous_timestamp).total_seconds() > 90
            )
        )
        if should_split:
            current_segment = {
                "segmentId": f"segment-{len(segments) + 1}",
                "placeId": place_key,
                "displayName": display_name,
                "sessionId": session_id,
                "start": event.timestamp,
                "end": event.timestamp,
                "frameCount": 0,
                "labels": [],
                "roomId": room_aliases.get(place_key),
            }
            segments.append(current_segment)

        current_segment["end"] = event.timestamp
        current_segment["frameCount"] += 1
        current_segment["labels"].extend(labels)
        previous_timestamp = event_time

    node_counters: dict[str, Counter] = defaultdict(Counter)
    node_frame_count: Counter = Counter()
    node_room_ids: dict[str, str | None] = {}

    for segment in segments:
        node_counters[segment["placeId"]].update(segment["labels"])
        node_frame_count[segment["placeId"]] += segment["frameCount"]
        node_room_ids[segment["placeId"]] = segment.get("roomId")

    nodes = []
    for place_id, count in node_frame_count.items():
        top_labels = [label for label, _ in node_counters[place_id].most_common(5)]
        display_name = next(
            segment["displayName"]
            for segment in segments
            if segment["placeId"] == place_id
        )
        nodes.append(
            {
                "id": place_id,
                "displayName": display_name,
                "frameCount": count,
                "roomId": node_room_ids.get(place_id),
                "topLabels": top_labels,
            }
        )

    edge_counts: Counter[tuple[str, str]] = Counter()
    for previous, current in zip(segments, segments[1:]):
        if previous["placeId"] == current["placeId"]:
            continue
        edge_key = tuple(sorted((previous["placeId"], current["placeId"])))
        edge_counts[edge_key] += 1

    edges = [
        {
            "id": f"edge-{index + 1}",
            "sourcePlaceId": edge_key[0],
            "targetPlaceId": edge_key[1],
            "transitionCount": count,
            "weight": float(count),
        }
        for index, (edge_key, count) in enumerate(edge_counts.items())
    ]

    return {
        "nodes": nodes,
        "edges": edges,
        "segments": segments,
        "updatedAt": datetime.now(UTC).isoformat(),
    }

def infer_place_identity(
    event: WearableFrameEvent,
    room_aliases: dict[str, str] | None = None,
) -> tuple[str, str]:
    room_aliases = room_aliases or {}
    if event.place_hint:
        normalized_hint = _normalize(event.place_hint)
        if normalized_hint:
            return normalized_hint, event.place_hint

    labels = [observed.label for observed in event.observed_objects]
    if labels:
        counter = Counter(_normalize(label) for label in labels if _normalize(label))
        top = [label for label, _ in counter.most_common(3)]
        place_id = "cluster:" + "+".join(top)
        display_name = " / ".join(label.replace("_", " ").title() for label in top)
        return place_id, display_name

    return "unknown", "Unknown Place"

def route_between_places(graph: dict, start_place_id: str, target_place_id: str) -> list[str]:
    if start_place_id == target_place_id:
        return [start_place_id]

    adjacency: dict[str, set[str]] = defaultdict(set)
    for edge in graph.get("edges", []):
        source = edge["sourcePlaceId"]
        target = edge["targetPlaceId"]
        adjacency[source].add(target)
        adjacency[target].add(source)

    queue = deque([(start_place_id, [start_place_id])])
    visited = {start_place_id}
    while queue:
        current, path = queue.popleft()
        for neighbor in adjacency.get(current, set()):
            if neighbor in visited:
                continue
            next_path = path + [neighbor]
            if neighbor == target_place_id:
                return next_path
            visited.add(neighbor)
            queue.append((neighbor, next_path))
    return []

def _parse_timestamp(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)

def _normalize(text: str) -> str:
    return " ".join("".join(ch.lower() if ch.isalnum() else " " for ch in text).split())
