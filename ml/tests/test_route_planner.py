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


def test_plan_route_targets_support_edge_for_object_on_surface():
    room = RoomState(room_id="room-2", name="demo")
    desk_id = "desk-1"
    room.observations = [
        {
            "id": desk_id,
            "label": "desk",
            "worldTransform16": tf(2.0, 0.75, 0.0),
            "center_xyz": [2.0, 0.75, 0.0],
            "extent_xyz": [1.2, 0.8, 0.8],
            "base_anchor_xyz": [2.0, 0.35, 0.0],
            "footprint_xyz": [
                [1.4, 0.35, -0.4],
                [2.6, 0.35, -0.4],
                [2.6, 0.35, 0.4],
                [1.4, 0.35, 0.4],
            ],
            "support_relation": {
                "type": "self_surface",
                "support_object_id": None,
                "support_label": "desk",
                "support_height_y": 1.15,
            },
        },
        {
            "id": "phone-1",
            "label": "phone",
            "worldTransform16": tf(1.7, 1.15, 0.05),
            "center_xyz": [1.7, 1.15, 0.05],
            "extent_xyz": [0.16, 0.03, 0.08],
            "base_anchor_xyz": [1.7, 1.135, 0.05],
            "support_relation": {
                "type": "supported_by",
                "support_object_id": desk_id,
                "support_label": "desk",
                "support_height_y": 1.15,
            },
        },
    ]
    room.scene_graph = {
        "nodes": [
            {
                "id": desk_id,
                "nodeType": "surface",
                "label": "desk",
                "worldTransform16": tf(2.0, 0.75, 0.0),
                "extentXyz": [1.2, 0.8, 0.8],
                "attributesJson": "{\"footprintXyz\": [[1.4, 0.35, -0.4], [2.6, 0.35, -0.4], [2.6, 0.35, 0.4], [1.4, 0.35, 0.4]]}",
            }
        ],
        "edges": [],
    }

    result = plan_route(
        room=room,
        start_world_transform16=tf(0.0, 0.0, 0.0),
        target_label="phone",
        grid_resolution_m=0.25,
        obstacle_inflation_radius_m=0.10,
    )

    assert result["reachable"] is True
    assert result["reason"] == "support_edge"
    assert result["waypoints"]

    goal = result["snappedGoalWorldTransform16"]
    assert goal is not None
    assert goal[12] < 1.4
    assert abs(goal[14]) <= 0.75
