from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

@dataclass
class RoomState:
    room_id: str
    name: str
    frame_dir: Path | None = None
    frames: list[dict] = field(default_factory=list)
    reconstruction_status: str = "pending"
    reconstruction_assets: dict = field(default_factory=dict)
    observations: list[dict] = field(default_factory=list)
    scene_graph: dict | None = None

class RoomStore:
    _instance: RoomStore | None = None

    def __new__(cls) -> RoomStore:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._rooms: dict[str, RoomState] = {}
        return cls._instance

    def create(self, room_id: str, name: str) -> RoomState:
        room = RoomState(room_id=room_id, name=name)
        self._rooms[room_id] = room
        return room

    def get(self, room_id: str) -> RoomState | None:
        return self._rooms.get(room_id)

    def list_all(self) -> list[RoomState]:
        return list(self._rooms.values())

    def update(self, room_id: str, **kwargs) -> RoomState | None:
        room = self._rooms.get(room_id)
        if room is None:
            return None
        for key, value in kwargs.items():
            if hasattr(room, key):
                setattr(room, key, value)
        return room

    @classmethod
    def reset(cls) -> None:
        cls._instance = None
