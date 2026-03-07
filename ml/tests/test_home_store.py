from datetime import UTC, datetime, timedelta

from serving.storage.home_store import HomeStore
from serving.storage.room_store import RoomStore
from serving.storage.wearable_store import ObservedObjectEvent, WearableFrameEvent, WearableStore

def test_home_store_search_returns_route_hint_and_room_context():
    RoomStore.reset()
    HomeStore.reset()
    WearableStore.reset()

    rooms = RoomStore()
    living = rooms.create("room-1", "Living Room")
    kitchen = rooms.create("room-2", "Kitchen")
    living.observations = [
        {
            "id": "obs-wallet",
            "label": "wallet",
            "confidence": 0.84,
            "observed_at": datetime.now(UTC).isoformat(),
        }
    ]
    kitchen.observations = [
        {
            "id": "obs-keys",
            "label": "keys",
            "confidence": 0.68,
            "observed_at": datetime.now(UTC).isoformat(),
        }
    ]

    homes = HomeStore()
    home = homes.create("Home")
    homes.attach_room(home.home_id, living.room_id)
    homes.attach_room(home.home_id, kitchen.room_id)

    response = homes.search(home.home_id, "where is my wallet", current_room_id=kitchen.room_id)

    assert response["resultType"] == "detected"
    assert response["results"][0]["roomName"] == "Living Room"
    assert "Living Room" in response["results"][0]["routeHint"]

def test_home_store_change_events_flags_stale_memory():
    RoomStore.reset()
    HomeStore.reset()
    WearableStore.reset()

    rooms = RoomStore()
    bedroom = rooms.create("room-3", "Bedroom")
    bedroom.observations = [
        {
            "id": "obs-remote",
            "label": "remote",
            "confidence": 0.59,
            "observed_at": (datetime.now(UTC) - timedelta(days=3)).isoformat(),
        }
    ]

    homes = HomeStore()
    home = homes.create("Apartment")
    homes.attach_room(home.home_id, bedroom.room_id)

    events = homes.change_events(home.home_id)

    assert len(events) == 1
    assert events[0]["eventType"] == "stale_memory"

def test_home_store_rebuilds_topology_from_wearable_frames():
    RoomStore.reset()
    HomeStore.reset()
    WearableStore.reset()

    homes = HomeStore()
    home = homes.create("House")
    session = WearableStore().create_session(
        session_id="session-1",
        home_id=home.home_id,
        device_name="Ray-Ban Meta",
        source="rayban_meta",
        status="streaming",
    )
    WearableStore().append_frames(
        session.session_id,
        [
            WearableFrameEvent(
                frame_id="frame-1",
                timestamp="2026-03-07T12:00:00Z",
                place_hint="Kitchen",
                observed_objects=[ObservedObjectEvent(label="wallet", confidence=0.88)],
            ),
            WearableFrameEvent(
                frame_id="frame-2",
                timestamp="2026-03-07T12:00:20Z",
                place_hint="Hallway",
                observed_objects=[ObservedObjectEvent(label="plant", confidence=0.55)],
            ),
            WearableFrameEvent(
                frame_id="frame-3",
                timestamp="2026-03-07T12:00:40Z",
                place_hint="Bedroom",
                observed_objects=[ObservedObjectEvent(label="lamp", confidence=0.62)],
            ),
        ],
    )

    graph = homes.rebuild_map(home.home_id)

    assert len(graph["nodes"]) == 3
    assert len(graph["edges"]) == 2

    route = homes.route(home.home_id, target_place_id="bedroom", current_place_id="kitchen")
    assert [item["placeId"] for item in route["placeSequence"]] == ["kitchen", "hallway", "bedroom"]

def test_home_store_search_uses_wearable_memories():
    RoomStore.reset()
    HomeStore.reset()
    WearableStore.reset()

    homes = HomeStore()
    home = homes.create("Apartment")
    session = WearableStore().create_session(
        session_id="session-2",
        home_id=home.home_id,
        device_name="Ray-Ban Meta",
        source="rayban_meta",
        status="streaming",
    )
    WearableStore().append_frames(
        session.session_id,
        [
            WearableFrameEvent(
                frame_id="frame-10",
                timestamp=datetime.now(UTC).isoformat(),
                place_hint="Office",
                observed_objects=[ObservedObjectEvent(label="passport", confidence=0.91)],
            )
        ],
    )

    homes.rebuild_map(home.home_id)
    response = homes.search(home.home_id, "where is my passport", current_place_id="office")

    assert response["resultType"] == "detected"
    assert response["results"][0]["placeId"] == "office"
    assert response["results"][0]["roomName"] == "Office"
