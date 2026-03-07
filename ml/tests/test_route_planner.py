from serving.storage.room_store import RoomState
from hacktj2026_ml.route_planner import plan_route


def tf(x, y, z):
    return [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        x, y, z, 1.0,
    ]


def test_plan_route_returns_waypoints():
    room = RoomState(room_id="room-1", name="demo")
    room.scene_graph = {
        "nodes": [
            {
                "id": "desk-1",
                "nodeType": "surface",
                "label": "desk",
                "worldTransform16": tf(2.0, 0.0, 0.0),
                "extentXyz": [0.8, 0.7, 0.8],
            }
        ],
        "edges": [],
    }

    result = plan_route(
        room=room,
        start_world_transform16=tf(0.0, 0.0, 0.0),
        target_world_transform16=tf(4.0, 0.0, 0.0),
        grid_resolution_m=0.25,
        obstacle_inflation_radius_m=0.10,
    )

    assert result["reachable"] is True
    assert result["waypoints"]
