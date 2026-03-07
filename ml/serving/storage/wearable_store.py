from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime

@dataclass
class ObservedObjectEvent:
    label: str
    confidence: float

@dataclass
class WearableFrameEvent:
    frame_id: str
    timestamp: str
    sample_reason: str = "interval"
    place_hint: str | None = None
    image_path: str | None = None
    image_width: int | None = None
    image_height: int | None = None
    observed_objects: list[ObservedObjectEvent] = field(default_factory=list)
    metadata: dict = field(default_factory=dict)

@dataclass
class WearableSessionState:
    session_id: str
    home_id: str
    device_name: str
    source: str
    status: str = "created"
    sampling_fps: float = 1.0
    created_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())
    updated_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())
    frame_events: list[WearableFrameEvent] = field(default_factory=list)

class WearableStore:
    _instance: WearableStore | None = None

    def __new__(cls) -> WearableStore:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._sessions: dict[str, WearableSessionState] = {}
        return cls._instance

    def create_session(
        self,
        session_id: str,
        home_id: str,
        device_name: str,
        source: str,
        sampling_fps: float = 1.0,
        status: str = "created",
    ) -> WearableSessionState:
        session = WearableSessionState(
            session_id=session_id,
            home_id=home_id,
            device_name=device_name,
            source=source,
            status=status,
            sampling_fps=sampling_fps,
        )
        self._sessions[session_id] = session
        return session

    def get(self, session_id: str) -> WearableSessionState | None:
        return self._sessions.get(session_id)

    def list_sessions(self, home_id: str | None = None) -> list[WearableSessionState]:
        sessions = list(self._sessions.values())
        if home_id is None:
            return sessions
        return [session for session in sessions if session.home_id == home_id]

    def append_frames(self, session_id: str, frame_events: list[WearableFrameEvent]) -> WearableSessionState | None:
        session = self._sessions.get(session_id)
        if session is None:
            return None
        session.frame_events.extend(frame_events)
        session.updated_at = datetime.now(UTC).isoformat()
        if session.status == "created":
            session.status = "streaming"
        return session

    def update_status(self, session_id: str, status: str) -> WearableSessionState | None:
        session = self._sessions.get(session_id)
        if session is None:
            return None
        session.status = status
        session.updated_at = datetime.now(UTC).isoformat()
        return session

    @classmethod
    def reset(cls) -> None:
        cls._instance = None
