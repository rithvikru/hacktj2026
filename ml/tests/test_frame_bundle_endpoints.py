import json
from pathlib import Path

from fastapi.testclient import TestClient

import serving.api.app as app_module
from serving.storage.room_store import RoomStore


def test_upload_frame_bundle_persists_room_state_and_allows_reconstruct(tmp_path: Path, monkeypatch):
    db_path = tmp_path / "room-store.sqlite3"
    monkeypatch.setenv("HACKTJ2026_ROOM_STORE", str(db_path))
    monkeypatch.chdir(tmp_path)
    RoomStore.reset()

    client = TestClient(app_module.app)
    room_id = "room-1"

    create_response = client.post("/rooms", json={"roomId": room_id, "name": "Bedroom"})
    assert create_response.status_code == 200

    manifest = {
        "room_id": room_id,
        "session_id": "11111111-1111-1111-1111-111111111111",
        "created_at": "2026-03-07T20:00:00Z",
        "frame_count": 1,
        "device": {"model": "iPhone", "system_name": "iOS", "system_version": "18.0"},
        "asset_encoding": {"rgb": "jpeg", "depth": "png16_mm", "confidence": "png8"},
        "keyframe_selection": {
            "minimum_interval_seconds": 0.75,
            "maximum_interval_seconds": 2.0,
            "minimum_translation_meters": 0.12,
            "minimum_rotation_radians": 0.2,
        },
        "auxiliary_assets": [
            {
                "frame_id": "22222222-2222-2222-2222-222222222222",
                "confidence_map_path": "confidence/f1.png",
            }
        ],
        "frames": [
            {
                "frame_id": "22222222-2222-2222-2222-222222222222",
                "room_id": room_id,
                "session_id": "11111111-1111-1111-1111-111111111111",
                "timestamp": "2026-03-07T20:00:00Z",
                "image_path": "images/f1.jpg",
                "depth_path": "depth/f1.png",
                "confidence_map_path": "confidence/f1.png",
                "camera_transform16": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                "intrinsics9": [1, 0, 0, 0, 1, 0, 0, 0, 1],
                "tracking_state": "normal",
                "selected_for_training": False,
                "selected_for_eval": False,
            }
        ],
    }

    upload_response = client.post(
        f"/rooms/{room_id}/frame-bundles",
        files=[
            ("manifest", ("manifest.json", json.dumps(manifest), "application/json")),
            ("images", ("f1.jpg", b"jpg", "image/jpeg")),
            ("depth_files", ("f1.png", b"png", "image/png")),
            ("confidence_files", ("f1.png", b"png", "image/png")),
        ],
    )
    assert upload_response.status_code == 200
    payload = upload_response.json()
    assert payload["frameCount"] == 1

    store = RoomStore()
    room = store.get(room_id)
    assert room is not None
    assert room.frame_dir is not None
    assert room.frame_dir.name == "frames"
    assert len(room.frames) == 1
    assert room.frames[0]["image_path"] == "images/f1.jpg"

    enqueued_room_ids: list[str] = []

    def fake_enqueue_reconstruction(room_id: str) -> bool:
        enqueued_room_ids.append(room_id)
        return True

    monkeypatch.setattr(app_module, "enqueue_reconstruction", fake_enqueue_reconstruction)

    reconstruct_response = client.post(f"/rooms/{room_id}/reconstruct")
    assert reconstruct_response.status_code == 200
    assert reconstruct_response.json()["status"] == "queued"
    assert enqueued_room_ids == [room_id]

    queued_room = store.get(room_id)
    assert queued_room is not None
    assert queued_room.reconstruction_status in {"queued", "processing", "complete", "failed"}

    RoomStore.reset()
