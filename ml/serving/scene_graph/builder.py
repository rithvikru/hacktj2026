from __future__ import annotations

import json
import math
from uuid import uuid4

from serving.storage.room_store import RoomState

# Label categories for node_type classification
_SURFACE_LABELS = {"table", "desk", "counter", "countertop", "shelf", "nightstand", "dresser", "bench"}
_CONTAINER_LABELS = {"drawer", "cabinet", "closet", "box", "basket", "bin", "bag", "backpack", "suitcase"}


def _classify_node_type(label: str) -> str:
    lower = label.lower()
    if lower in _SURFACE_LABELS:
        return "surface"
    if lower in _CONTAINER_LABELS:
        return "container"
    return "furniture"


def _extract_position(transform: list[float] | None) -> tuple[float, float, float] | None:
    if transform is None or len(transform) < 16:
        return None
    return (transform[12], transform[13], transform[14])


def _distance_3d(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def build_scene_graph(room: RoomState) -> dict:
    nodes = []
    edges = []

    # Room node
    room_node_id = f"room-{room.room_id}"
    nodes.append({
        "id": room_node_id,
        "nodeType": "room",
        "label": room.name,
        "worldTransform16": None,
        "extentXyz": None,
        "parentId": None,
        "attributesJson": "{}",
    })

    # Build nodes from observations + frames
    observation_nodes = []
    for obs in room.observations:
        node_id = obs.get("id", str(uuid4()))
        label = obs.get("label", "unknown")
        transform = obs.get("worldTransform16") or obs.get("world_transform16")
        attributes = {
            "source": obs.get("source"),
            "confidence": obs.get("confidence"),
            "meshAssetURL": obs.get("meshAssetURL") or obs.get("mesh_asset_url"),
            "semanticSceneRef": obs.get("semanticSceneRef") or obs.get("semantic_scene_ref"),
            "centerXyz": obs.get("centerXyz") or obs.get("center_xyz"),
            "baseAnchorXyz": obs.get("baseAnchorXyz") or obs.get("base_anchor_xyz"),
            "footprintXyz": obs.get("footprintXyz") or obs.get("footprint_xyz"),
            "supportRelation": obs.get("supportRelation") or obs.get("support_relation"),
        }
        node = {
            "id": node_id,
            "nodeType": _classify_node_type(label),
            "label": label,
            "worldTransform16": transform,
            "extentXyz": obs.get("extentXyz") or obs.get("extent_xyz"),
            "parentId": room_node_id,
            "attributesJson": json.dumps({k: v for k, v in attributes.items() if v is not None}),
        }
        nodes.append(node)
        pos = _extract_position(transform)
        observation_nodes.append((node, pos))

    # Also extract observations embedded in frames
    for frame in room.frames:
        for obs in frame.get("observations", []):
            node_id = obs.get("id", str(uuid4()))
            label = obs.get("label", "unknown")
            transform = obs.get("worldTransform16") or obs.get("world_transform16")
            attributes = {
                "source": obs.get("source"),
                "confidence": obs.get("confidence"),
                "meshAssetURL": obs.get("meshAssetURL") or obs.get("mesh_asset_url"),
                "semanticSceneRef": obs.get("semanticSceneRef") or obs.get("semantic_scene_ref"),
                "centerXyz": obs.get("centerXyz") or obs.get("center_xyz"),
                "baseAnchorXyz": obs.get("baseAnchorXyz") or obs.get("base_anchor_xyz"),
                "footprintXyz": obs.get("footprintXyz") or obs.get("footprint_xyz"),
                "supportRelation": obs.get("supportRelation") or obs.get("support_relation"),
            }
            node = {
                "id": node_id,
                "nodeType": _classify_node_type(label),
                "label": label,
                "worldTransform16": transform,
                "extentXyz": obs.get("extentXyz") or obs.get("extent_xyz"),
                "parentId": room_node_id,
                "attributesJson": json.dumps({k: v for k, v in attributes.items() if v is not None}),
            }
            nodes.append(node)
            pos = _extract_position(transform)
            observation_nodes.append((node, pos))

    # Compute edges
    edge_id_counter = 0
    for i, (node_a, pos_a) in enumerate(observation_nodes):
        if pos_a is None:
            continue
        for j, (node_b, pos_b) in enumerate(observation_nodes):
            if j <= i or pos_b is None:
                continue

            dist = _distance_3d(pos_a, pos_b)

            # Near edge: within 2m
            if dist < 2.0:
                edge_id_counter += 1
                edges.append({
                    "id": f"edge-{edge_id_counter}",
                    "sourceNodeId": node_a["id"],
                    "targetNodeId": node_b["id"],
                    "edgeType": "near",
                    "weight": max(0.0, 1.0 - dist / 2.0),
                })

            # Supports edge: surface below another object
            # Check if node_b is a surface and node_a is above it (or vice versa)
            horizontal_dist = math.sqrt((pos_a[0] - pos_b[0]) ** 2 + (pos_a[2] - pos_b[2]) ** 2)
            vertical_diff = pos_a[1] - pos_b[1]

            if horizontal_dist < 0.3:
                if 0.0 < vertical_diff < 0.5 and node_b["nodeType"] == "surface":
                    edge_id_counter += 1
                    edges.append({
                        "id": f"edge-{edge_id_counter}",
                        "sourceNodeId": node_b["id"],
                        "targetNodeId": node_a["id"],
                        "edgeType": "supports",
                        "weight": 1.0,
                    })
                elif -0.5 < vertical_diff < 0.0 and node_a["nodeType"] == "surface":
                    edge_id_counter += 1
                    edges.append({
                        "id": f"edge-{edge_id_counter}",
                        "sourceNodeId": node_a["id"],
                        "targetNodeId": node_b["id"],
                        "edgeType": "supports",
                        "weight": 1.0,
                    })

    return {
        "roomId": room.room_id,
        "sceneGraphVersion": 1,
        "nodes": nodes,
        "edges": edges,
    }
