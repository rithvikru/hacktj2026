from pathlib import Path

from serving.storage.room_store import RoomStore

def test_room_store_persists_rows_across_singleton_reset(tmp_path: Path, monkeypatch):
    db_path = tmp_path / "room-store.sqlite3"
    monkeypatch.setenv("HACKTJ2026_ROOM_STORE", str(db_path))
    RoomStore.reset()

    store = RoomStore()
    store.create("room-1", "Bedroom")
    store.update(
        "room-1",
        frame_dir=tmp_path / "frames",
        reconstruction_status="complete",
        reconstruction_assets={"denseAssetURL": "/rooms/room-1/assets/scene.splat"},
        observations=[{"label": "wallet", "confidence": 0.9}],
        scene_graph={"nodes": [{"id": "n1", "label": "desk"}], "edges": []},
    )

    RoomStore.reset()
    reloaded_store = RoomStore()
    room = reloaded_store.get("room-1")

    assert room is not None
    assert room.name == "Bedroom"
    assert room.frame_dir == tmp_path / "frames"
    assert room.reconstruction_status == "complete"
    assert room.reconstruction_assets["denseAssetURL"] == "/rooms/room-1/assets/scene.splat"
    assert room.observations[0]["label"] == "wallet"
    assert room.scene_graph["nodes"][0]["label"] == "desk"

    RoomStore.reset()
