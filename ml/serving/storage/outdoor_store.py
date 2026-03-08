from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

DEFAULT_OUTDOOR_VOCAB = [
    "car", "bag", "backpack", "bicycle", "umbrella", "phone",
    "keys", "wallet", "suitcase", "dog", "bench", "sign",
]

@dataclass
class OutdoorFrame:
    frame_id: str
    lat: float
    lng: float
    accuracy: float
    timestamp: float
    has_image: bool = False
    detections: list[dict[str, Any]] = field(default_factory=list)

@dataclass
class OutdoorSession:
    session_id: str
    created_at: float = 0.0
    frames: dict[str, OutdoorFrame] = field(default_factory=dict)

    @property
    def all_detections(self) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for frame in self.frames.values():
            for det in frame.detections:
                results.append({
                    **det,
                    "lat": frame.lat,
                    "lng": frame.lng,
                    "frame_id": frame.frame_id,
                })
        return results

class OutdoorStore:
    _instance: OutdoorStore | None = None

    def __new__(cls) -> OutdoorStore:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._sessions: dict[str, OutdoorSession] = {}
        return cls._instance

    def create(self, session_id: str) -> OutdoorSession:
        import time
        session = OutdoorSession(session_id=session_id, created_at=time.time())
        self._sessions[session_id] = session
        return session

    def get(self, session_id: str) -> OutdoorSession | None:
        return self._sessions.get(session_id)

    def list_all(self) -> list[OutdoorSession]:
        return list(self._sessions.values())

    def add_frame(self, session_id: str, frame: OutdoorFrame) -> OutdoorFrame | None:
        session = self._sessions.get(session_id)
        if session is None:
            return None
        session.frames[frame.frame_id] = frame
        return frame

    @classmethod
    def reset(cls) -> None:
        cls._instance = None
