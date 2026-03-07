from datetime import UTC, datetime, timedelta

from serving.storage.home_store import HomeStore
from serving.storage.room_store import RoomStore

def test_home_store_search_returns_route_hint_and_room_context():
    RoomStore.reset()
    HomeStore.reset()

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
