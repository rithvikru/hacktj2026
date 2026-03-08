from __future__ import annotations

import json
import os
import sqlite3
import threading
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
            cls._instance._initialize()
        return cls._instance

    def _initialize(self) -> None:
        self._lock = threading.RLock()
        db_path = Path(os.getenv("HACKTJ2026_ROOM_STORE", "data/room_store.sqlite3"))
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self._db_path = db_path
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._ensure_schema()

    def _ensure_schema(self) -> None:
        with self._lock:
            self._conn.execute(
                """
                CREATE TABLE IF NOT EXISTS rooms (
                    room_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    frame_dir TEXT,
                    frames_json TEXT NOT NULL DEFAULT '[]',
                    reconstruction_status TEXT NOT NULL DEFAULT 'pending',
                    reconstruction_assets_json TEXT NOT NULL DEFAULT '{}',
                    observations_json TEXT NOT NULL DEFAULT '[]',
                    scene_graph_json TEXT
                )
                """
            )
            self._conn.commit()

    def create(self, room_id: str, name: str) -> RoomState:
        with self._lock:
            room = self._get_locked(room_id)
            if room is None:
                room = RoomState(room_id=room_id, name=name)
            else:
                room.name = name
            self._upsert_locked(room)
            return room

    def get(self, room_id: str) -> RoomState | None:
        with self._lock:
            return self._get_locked(room_id)

    def list_all(self) -> list[RoomState]:
        with self._lock:
            rows = self._conn.execute("SELECT * FROM rooms ORDER BY room_id").fetchall()
            return [self._row_to_state(row) for row in rows]

    def update(self, room_id: str, **kwargs) -> RoomState | None:
        with self._lock:
            room = self._get_locked(room_id)
            if room is None:
                return None
            for key, value in kwargs.items():
                if hasattr(room, key):
                    setattr(room, key, value)
            self._upsert_locked(room)
            return room

    def _get_locked(self, room_id: str) -> RoomState | None:
        row = self._conn.execute(
            "SELECT * FROM rooms WHERE room_id = ?",
            (room_id,),
        ).fetchone()
        if row is None:
            return None
        return self._row_to_state(row)

    def _upsert_locked(self, room: RoomState) -> None:
        self._conn.execute(
            """
            INSERT INTO rooms (
                room_id,
                name,
                frame_dir,
                frames_json,
                reconstruction_status,
                reconstruction_assets_json,
                observations_json,
                scene_graph_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(room_id) DO UPDATE SET
                name = excluded.name,
                frame_dir = excluded.frame_dir,
                frames_json = excluded.frames_json,
                reconstruction_status = excluded.reconstruction_status,
                reconstruction_assets_json = excluded.reconstruction_assets_json,
                observations_json = excluded.observations_json,
                scene_graph_json = excluded.scene_graph_json
            """,
            (
                room.room_id,
                room.name,
                str(room.frame_dir) if room.frame_dir is not None else None,
                json.dumps(room.frames),
                room.reconstruction_status,
                json.dumps(room.reconstruction_assets),
                json.dumps(room.observations),
                json.dumps(room.scene_graph) if room.scene_graph is not None else None,
            ),
        )
        self._conn.commit()

    def _row_to_state(self, row: sqlite3.Row) -> RoomState:
        frame_dir = row["frame_dir"]
        scene_graph_json = row["scene_graph_json"]
        return RoomState(
            room_id=row["room_id"],
            name=row["name"],
            frame_dir=Path(frame_dir) if frame_dir else None,
            frames=json.loads(row["frames_json"] or "[]"),
            reconstruction_status=row["reconstruction_status"] or "pending",
            reconstruction_assets=json.loads(row["reconstruction_assets_json"] or "{}"),
            observations=json.loads(row["observations_json"] or "[]"),
            scene_graph=json.loads(scene_graph_json) if scene_graph_json else None,
        )

    @classmethod
    def reset(cls) -> None:
        if cls._instance is not None:
            cls._instance._conn.close()
        cls._instance = None
