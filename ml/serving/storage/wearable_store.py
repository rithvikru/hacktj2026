from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path

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
            cls._instance._root = Path(os.environ.get("HACKTJ_WEARABLES_DIR", "data/wearables"))
            cls._instance._root.mkdir(parents=True, exist_ok=True)
            cls._instance._sessions = cls._instance._load_sessions()
        return cls._instance

    def _load_sessions(self) -> dict[str, WearableSessionState]:
        sessions: dict[str, WearableSessionState] = {}
        for state_path in sorted(self._root.glob("*/session.json")):
            session = self._read_session_file(state_path)
            if session is not None:
                sessions[session.session_id] = session
        return sessions

    def _session_dir(self, session_id: str) -> Path:
        return self._root / session_id

    def _session_state_path(self, session_id: str) -> Path:
        return self._session_dir(session_id) / "session.json"

    def _frames_dir(self, session_id: str) -> Path:
        return self._session_dir(session_id) / "frames"

    def frames_directory(self, session_id: str) -> Path:
        directory = self._frames_dir(session_id)
        directory.mkdir(parents=True, exist_ok=True)
        return directory

    def _read_session_file(self, path: Path) -> WearableSessionState | None:
        try:
            payload = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            return None
        return self._session_from_payload(payload)

    def _session_from_payload(self, payload: dict) -> WearableSessionState:
        return WearableSessionState(
            session_id=payload["session_id"],
            home_id=payload["home_id"],
            device_name=payload["device_name"],
            source=payload["source"],
            status=payload.get("status", "created"),
            sampling_fps=float(payload.get("sampling_fps", 1.0)),
            created_at=payload.get("created_at", datetime.now(UTC).isoformat()),
            updated_at=payload.get("updated_at", datetime.now(UTC).isoformat()),
            frame_events=[
                WearableFrameEvent(
                    frame_id=event["frame_id"],
                    timestamp=event["timestamp"],
                    sample_reason=event.get("sample_reason", "interval"),
                    place_hint=event.get("place_hint"),
                    image_path=event.get("image_path"),
                    image_width=event.get("image_width"),
                    image_height=event.get("image_height"),
                    observed_objects=[
                        ObservedObjectEvent(
                            label=obj["label"],
                            confidence=float(obj["confidence"]),
                        )
                        for obj in event.get("observed_objects", [])
                    ],
                    metadata=event.get("metadata", {}),
                )
                for event in payload.get("frame_events", [])
            ],
        )

    def _write_session(self, session: WearableSessionState) -> None:
        session_dir = self._session_dir(session.session_id)
        session_dir.mkdir(parents=True, exist_ok=True)
        self._frames_dir(session.session_id).mkdir(parents=True, exist_ok=True)
        self._session_state_path(session.session_id).write_text(
            json.dumps(asdict(session), indent=2, sort_keys=True)
        )

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
        self._write_session(session)
        return session

    def get(self, session_id: str) -> WearableSessionState | None:
        session = self._sessions.get(session_id)
        if session is not None:
            return session
        path = self._session_state_path(session_id)
        if not path.exists():
            return None
        loaded = self._read_session_file(path)
        if loaded is not None:
            self._sessions[session_id] = loaded
        return loaded

    def list_sessions(self, home_id: str | None = None) -> list[WearableSessionState]:
        sessions = list(self._sessions.values())
        if home_id is None:
            return sessions
        return [session for session in sessions if session.home_id == home_id]

    def append_frames(self, session_id: str, frame_events: list[WearableFrameEvent]) -> WearableSessionState | None:
        session = self._sessions.get(session_id)
        if session is None:
            return None
        existing_by_id = {frame.frame_id: frame for frame in session.frame_events}
        for frame in frame_events:
            existing_by_id[frame.frame_id] = frame
        session.frame_events = sorted(existing_by_id.values(), key=lambda frame: frame.timestamp)
        session.updated_at = datetime.now(UTC).isoformat()
        if session.status == "created":
            session.status = "streaming"
        self._write_session(session)
        return session

    def update_status(self, session_id: str, status: str) -> WearableSessionState | None:
        session = self._sessions.get(session_id)
        if session is None:
            return None
        session.status = status
        session.updated_at = datetime.now(UTC).isoformat()
        self._write_session(session)
        return session

    @classmethod
    def reset(cls) -> None:
        cls._instance = None
