from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from uuid import uuid4

from serving.storage.room_store import RoomState, RoomStore
from serving.storage.wearable_store import WearableStore
from serving.topology.builder import build_topology_graph, route_between_places

@dataclass
class ItemMemoryState:
    id: str
    label: str
    room_id: str
    room_name: str
    confidence: float
    observed_at: str
    world_transform16: list[float] | None = None
    place_id: str | None = None
    evidence: list[str] = field(default_factory=list)

    @property
    def recency_seconds(self) -> float:
        parsed = datetime.fromisoformat(self.observed_at.replace("Z", "+00:00"))
        return max((datetime.now(UTC) - parsed.astimezone(UTC)).total_seconds(), 0.0)

    @property
    def memory_freshness(self) -> float:
        freshness = 1.0 - (self.recency_seconds / 604800.0)
        return max(0.0, min(freshness, 1.0))

    @property
    def confidence_state(self) -> str:
        if self.recency_seconds <= 300:
            return "live_seen"
        if self.recency_seconds <= 86400:
            return "last_seen"
        return "stale_memory"

    @property
    def result_type(self) -> str:
        return "detected" if self.confidence_state == "live_seen" else self.confidence_state

@dataclass
class HomeState:
    home_id: str
    name: str
    room_ids: list[str] = field(default_factory=list)
    metadata: dict = field(default_factory=dict)
    topology_graph: dict = field(default_factory=dict)
    created_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())
    updated_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())

class HomeStore:
    _instance: HomeStore | None = None

    def __new__(cls) -> HomeStore:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._homes: dict[str, HomeState] = {}
        return cls._instance

    def create(self, name: str, metadata: dict | None = None) -> HomeState:
        home = HomeState(home_id=str(uuid4()), name=name, metadata=metadata or {})
        self._homes[home.home_id] = home
        return home

    def get(self, home_id: str) -> HomeState | None:
        return self._homes.get(home_id)

    def list_all(self) -> list[HomeState]:
        return list(self._homes.values())

    def attach_room(self, home_id: str, room_id: str) -> HomeState | None:
        home = self._homes.get(home_id)
        if home is None:
            return None
        if room_id not in home.room_ids:
            home.room_ids.append(room_id)
            home.updated_at = datetime.now(UTC).isoformat()
        return home

    def rebuild_map(self, home_id: str) -> dict:
        home = self._require_home(home_id)
        rooms = self._ordered_rooms(home)
        wearable_sessions = WearableStore().list_sessions(home_id=home_id)
        room_aliases = {_normalize(room.name): room.room_id for room in rooms}
        if wearable_sessions:
            topology_graph = build_topology_graph(wearable_sessions, room_aliases=room_aliases)
            home.topology_graph = topology_graph
            home.updated_at = topology_graph["updatedAt"]
            return {
                "homeId": home.home_id,
                "name": home.name,
                "nodes": topology_graph["nodes"],
                "edges": topology_graph["edges"],
                "segments": topology_graph["segments"],
                "updatedAt": home.updated_at,
            }

        portals = []
        for idx in range(max(len(rooms) - 1, 0)):
            current = rooms[idx]
            nxt = rooms[idx + 1]
            portals.append(
                {
                    "id": f"portal-{idx + 1}",
                    "fromRoomId": current.room_id,
                    "toRoomId": nxt.room_id,
                    "label": f"{current.name} to {nxt.name}",
                    "distanceMeters": float(idx + 1),
                }
            )
        return {
            "homeId": home.home_id,
            "name": home.name,
            "rooms": [
                {
                    "roomId": room.room_id,
                    "name": room.name,
                    "observationCount": len(room.observations),
                    "status": room.reconstruction_status,
                }
                for room in rooms
            ],
            "portals": portals,
            "updatedAt": home.updated_at,
        }

    def list_memories(self, home_id: str) -> list[ItemMemoryState]:
        home = self._require_home(home_id)
        rooms = self._ordered_rooms(home)
        best_by_label: dict[str, ItemMemoryState] = {}
        for room in rooms:
            for memory in self._memories_for_room(room):
                current = best_by_label.get(memory.label.lower())
                if current is None or memory.recency_seconds < current.recency_seconds:
                    best_by_label[memory.label.lower()] = memory
        for memory in self._memories_from_wearable_sessions(home):
            current = best_by_label.get(memory.label.lower())
            if current is None or memory.recency_seconds < current.recency_seconds:
                best_by_label[memory.label.lower()] = memory
        return sorted(best_by_label.values(), key=lambda memory: (memory.recency_seconds, -memory.confidence))

    def search(
        self,
        home_id: str,
        query_text: str,
        current_room_id: str | None = None,
        current_place_id: str | None = None,
    ) -> dict:
        normalized = _normalize(query_text)
        memories = self.list_memories(home_id)
        matches = [
            memory
            for memory in memories
            if _matches(memory.label, normalized)
        ]
        results = []
        for memory in matches:
            route = self.route(
                home_id,
                target_room_id=memory.room_id if memory.place_id is None else None,
                current_room_id=current_room_id,
                target_place_id=memory.place_id,
                current_place_id=current_place_id or (_normalize(current_room_id) if current_room_id else None),
            )
            route_hint = route["summary"] if route["summary"] else None
            results.append(
                {
                    "id": memory.id,
                    "label": memory.label,
                    "resultType": memory.result_type,
                    "confidence": memory.confidence,
                    "confidenceState": memory.confidence_state,
                    "worldTransform16": memory.world_transform16,
                    "roomId": memory.room_id,
                    "roomName": memory.room_name,
                    "placeId": memory.place_id,
                    "recencySeconds": memory.recency_seconds,
                    "memoryFreshness": memory.memory_freshness,
                    "routeHint": route_hint,
                    "evidence": memory.evidence,
                    "explanation": _build_memory_explanation(memory, route_hint),
                }
            )
        result_type = results[0]["resultType"] if results else "not_found"
        explanation = (
            f"Found {len(results)} remembered match{'es' if len(results) != 1 else ''} in your home graph."
            if results
            else f"No home-memory match was found for '{query_text}'."
        )
        return {
            "queryText": query_text,
            "resultType": result_type,
            "results": results,
            "explanation": explanation,
        }

    def route(
        self,
        home_id: str,
        target_room_id: str | None = None,
        current_room_id: str | None = None,
        target_place_id: str | None = None,
        current_place_id: str | None = None,
    ) -> dict:
        home = self._require_home(home_id)
        if home.topology_graph:
            resolved_target_place = target_place_id or self._topology_place_for_room(home.topology_graph, target_room_id)
            resolved_current_place = current_place_id or self._topology_place_for_room(home.topology_graph, current_room_id)
            if resolved_target_place:
                start_place = resolved_current_place or self._default_topology_start(home.topology_graph)
                if start_place:
                    path = route_between_places(home.topology_graph, start_place, resolved_target_place)
                    if path:
                        names = {
                            node["id"]: node.get("displayName", node["id"])
                            for node in home.topology_graph.get("nodes", [])
                        }
                        return {
                            "homeId": home.home_id,
                            "targetPlaceId": resolved_target_place,
                            "currentPlaceId": start_place,
                            "placeSequence": [
                                {"placeId": place_id, "name": names.get(place_id, place_id)}
                                for place_id in path
                            ],
                            "summary": "Go through " + " -> ".join(names.get(place_id, place_id) for place_id in path),
                        }

        rooms = self._ordered_rooms(home)
        if not rooms:
            return {"roomSequence": [], "summary": ""}

        ordered_ids = [room.room_id for room in rooms]
        if target_room_id not in ordered_ids:
            return {"roomSequence": [], "summary": ""}

        if current_room_id in ordered_ids:
            start_idx = ordered_ids.index(current_room_id)
        else:
            start_idx = 0
        end_idx = ordered_ids.index(target_room_id)
        if start_idx <= end_idx:
            sequence = rooms[start_idx : end_idx + 1]
        else:
            sequence = list(reversed(rooms[end_idx : start_idx + 1]))

        summary = ""
        if sequence:
            if len(sequence) == 1:
                summary = f"You are already in {sequence[0].name}."
            else:
                summary = "Go through " + " -> ".join(room.name for room in sequence)

        return {
            "homeId": home.home_id,
            "targetRoomId": target_room_id,
            "currentRoomId": current_room_id,
            "roomSequence": [
                {"roomId": room.room_id, "name": room.name}
                for room in sequence
            ],
            "summary": summary,
        }

    def change_events(self, home_id: str) -> list[dict]:
        events = []
        for memory in self.list_memories(home_id):
            if memory.confidence_state == "stale_memory":
                events.append(
                    {
                        "memoryId": memory.id,
                        "label": memory.label,
                        "roomId": memory.room_id,
                        "roomName": memory.room_name,
                        "eventType": "stale_memory",
                        "explanation": f"{memory.label} has not been observed recently in {memory.room_name}.",
                    }
                )
        return events

    def _require_home(self, home_id: str) -> HomeState:
        home = self._homes.get(home_id)
        if home is None:
            raise KeyError(home_id)
        return home

    def _ordered_rooms(self, home: HomeState) -> list[RoomState]:
        store = RoomStore()
        rooms = [room for room_id in home.room_ids if (room := store.get(room_id)) is not None]
        return sorted(rooms, key=lambda room: room.name.lower())

    def _memories_for_room(self, room: RoomState) -> list[ItemMemoryState]:
        memories = []
        observations = list(room.observations)
        if not observations:
            for frame in room.frames:
                observations.extend(frame.get("observations", []))
        for index, observation in enumerate(observations):
            observed_at = observation.get("observedAt") or observation.get("observed_at") or datetime.now(UTC).isoformat()
            memories.append(
                ItemMemoryState(
                    id=observation.get("id", f"{room.room_id}-{index}"),
                    label=observation.get("label", "object"),
                    room_id=room.room_id,
                    room_name=room.name,
                    confidence=float(observation.get("confidence", 0.0)),
                    observed_at=observed_at,
                    world_transform16=observation.get("worldTransform16") or observation.get("world_transform16"),
                    place_id=None,
                    evidence=["home_memory", f"room:{room.name.lower().replace(' ', '_')}"],
                )
            )
        return memories

    def _memories_from_wearable_sessions(self, home: HomeState) -> list[ItemMemoryState]:
        memories: list[ItemMemoryState] = []
        for session in WearableStore().list_sessions(home.home_id):
            for frame in session.frame_events:
                place_id = _normalize(frame.place_hint or "") or None
                place_name = frame.place_hint or "Unknown Place"
                room_id = self._topology_room_for_place(home.topology_graph, place_id) or (place_id or "wearable")
                for index, observed in enumerate(frame.observed_objects):
                    memories.append(
                        ItemMemoryState(
                            id=f"{session.session_id}-{frame.frame_id}-{index}",
                            label=observed.label,
                            room_id=room_id,
                            room_name=place_name,
                            confidence=observed.confidence,
                            observed_at=frame.timestamp,
                            world_transform16=None,
                            place_id=place_id,
                            evidence=["wearable_stream", session.source, f"session:{session.session_id}"],
                        )
                    )
        return memories

    def _default_topology_start(self, graph: dict) -> str | None:
        nodes = graph.get("nodes", [])
        if not nodes:
            return None
        return nodes[0]["id"]

    def _topology_place_for_room(self, graph: dict, room_id: str | None) -> str | None:
        if room_id is None:
            return None
        for node in graph.get("nodes", []):
            if node.get("roomId") == room_id:
                return node["id"]
        return None

    def _topology_room_for_place(self, graph: dict, place_id: str | None) -> str | None:
        if place_id is None:
            return None
        for node in graph.get("nodes", []):
            if node["id"] == place_id:
                return node.get("roomId")
        return None

    @classmethod
    def reset(cls) -> None:
        cls._instance = None

def _normalize(text: str) -> str:
    return " ".join("".join(ch.lower() if ch.isalnum() else " " for ch in text).split())

def _matches(label: str, query_text: str) -> bool:
    normalized_label = _normalize(label)
    return normalized_label == query_text or normalized_label in query_text or query_text in normalized_label

def _build_memory_explanation(memory: ItemMemoryState, route_hint: str | None) -> str:
    if memory.confidence_state == "live_seen":
        prefix = f"'{memory.label}' was seen very recently in {memory.room_name}."
    elif memory.confidence_state == "last_seen":
        prefix = f"'{memory.label}' was last seen in {memory.room_name}."
    else:
        prefix = f"Memory for '{memory.label}' in {memory.room_name} is stale and may need revalidation."

    if route_hint:
        return f"{prefix} {route_hint}"
    return prefix
