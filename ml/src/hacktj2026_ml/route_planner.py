from __future__ import annotations

import json
from dataclasses import dataclass
from heapq import heappop, heappush
from math import ceil, sqrt

@dataclass
class Rect:
    x1: float
    z1: float
    x2: float
    z2: float


@dataclass
class Grid:
    min_x: float
    min_z: float
    res: float
    width: int
    height: int
    blocked: list[list[bool]]


@dataclass
class TargetContext:
    object_id: str | None
    label: str | None
    world_transform16: list[float] | None
    center_xyz: tuple[float, float, float] | None
    extent_xyz: tuple[float, float, float] | None
    base_anchor_xyz: tuple[float, float, float] | None
    footprint_xz: list[tuple[float, float]]
    support_relation: dict | None


def tf_to_xyz(tf):
    if tf is None or len(tf) < 16:
        return None
    return tf[12], tf[13], tf[14]


def xyz_to_tf(x, y, z):
    return [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        x, y, z, 1.0,
    ]


def clamp(v, lo, hi):
    return max(lo, min(v, hi))


def scene_graph_to_obstacles(scene_graph):
    obs = []
    if not scene_graph:
        return obs
    for node in scene_graph.get("nodes", []):
        node_type = (node.get("nodeType") or node.get("node_type") or "").lower()
        if node_type not in {"surface", "container", "furniture"}:
            continue
        tf = node.get("worldTransform16") or node.get("world_transform16")
        pos = tf_to_xyz(tf)
        if pos is None:
            continue
        attrs = _parse_attributes(node.get("attributesJson") or node.get("attributes_json"))
        footprint_xz = _normalize_footprint(attrs)
        if footprint_xz:
            xs = [point[0] for point in footprint_xz]
            zs = [point[1] for point in footprint_xz]
            obs.append(Rect(min(xs), min(zs), max(xs), max(zs)))
            continue
        ext = node.get("extentXyz") or node.get("extent_xyz") or [0.8, 0.8, 0.8]
        if len(ext) < 3:
            ext = [0.8, 0.8, 0.8]
        half_x = max(float(ext[0]) / 2.0, 0.20)
        half_z = max(float(ext[2]) / 2.0, 0.20)
        x, _, z = pos
        obs.append(Rect(x - half_x, z - half_z, x + half_x, z + half_z))
    return obs


def compute_bounds(start_xyz, target_xyz, obstacles, margin=1.0):
    xs = [start_xyz[0], target_xyz[0]]
    zs = [start_xyz[2], target_xyz[2]]
    for r in obstacles:
        xs.extend([r.x1, r.x2])
        zs.extend([r.z1, r.z2])
    return min(xs) - margin, min(zs) - margin, max(xs) + margin, max(zs) + margin


def build_grid(min_x, min_z, max_x, max_z, res):
    width = max(1, ceil((max_x - min_x) / res))
    height = max(1, ceil((max_z - min_z) / res))
    blocked = [[False for _ in range(width)] for _ in range(height)]
    return Grid(min_x, min_z, res, width, height, blocked)


def world_to_grid(grid, x, z):
    col = int((x - grid.min_x) / grid.res)
    row = int((z - grid.min_z) / grid.res)
    col = clamp(col, 0, grid.width - 1)
    row = clamp(row, 0, grid.height - 1)
    return row, col


def grid_to_world(grid, row, col):
    x = grid.min_x + (col + 0.5) * grid.res
    z = grid.min_z + (row + 0.5) * grid.res
    return x, z


def in_bounds(grid, row, col):
    return 0 <= row < grid.height and 0 <= col < grid.width


def walkable(grid, row, col):
    return in_bounds(grid, row, col) and not grid.blocked[row][col]


def rasterize_rects(grid, rects):
    for rect in rects:
        min_row, min_col = world_to_grid(grid, rect.x1, rect.z1)
        max_row, max_col = world_to_grid(grid, rect.x2, rect.z2)
        r1 = min(min_row, max_row)
        r2 = max(min_row, max_row)
        c1 = min(min_col, max_col)
        c2 = max(min_col, max_col)
        for row in range(r1, r2 + 1):
            for col in range(c1, c2 + 1):
                if in_bounds(grid, row, col):
                    grid.blocked[row][col] = True


def inflate(grid, radius_m):
    radius_cells = max(0, ceil(radius_m / grid.res))
    original = [row[:] for row in grid.blocked]
    for row in range(grid.height):
        for col in range(grid.width):
            if not original[row][col]:
                continue
            for dr in range(-radius_cells, radius_cells + 1):
                for dc in range(-radius_cells, radius_cells + 1):
                    rr = row + dr
                    cc = col + dc
                    if not in_bounds(grid, rr, cc):
                        continue
                    if sqrt(dr * dr + dc * dc) <= radius_cells:
                        grid.blocked[rr][cc] = True


def nbrs_all(grid, row, col):
    out = []
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            if dr == 0 and dc == 0:
                continue
            rr = row + dr
            cc = col + dc
            if in_bounds(grid, rr, cc):
                out.append((rr, cc))
    return out


def nbrs_walk(grid, row, col):
    out = []
    for rr, cc in nbrs_all(grid, row, col):
        if walkable(grid, rr, cc):
            out.append((rr, cc))
    return out


def nearest_walkable(grid, row, col):
    if walkable(grid, row, col):
        return row, col
    seen = {(row, col)}
    q = [(row, col)]
    idx = 0
    while idx < len(q):
        cur = q[idx]
        idx += 1
        for nxt in nbrs_all(grid, cur[0], cur[1]):
            if nxt in seen:
                continue
            if walkable(grid, nxt[0], nxt[1]):
                return nxt
            seen.add(nxt)
            q.append(nxt)
    return None


def h(a, b):
    return sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2)


def move_cost(a, b):
    if a[0] != b[0] and a[1] != b[1]:
        return 1.41421356237
    return 1.0


def rebuild(came_from, end):
    out = [end]
    cur = end
    while cur in came_from:
        cur = came_from[cur]
        out.append(cur)
    out.reverse()
    return out


def astar(grid, start, goal):
    heap = []
    heappush(heap, (0.0, start))
    came_from = {}
    g = {start: 0.0}
    closed = set()
    while heap:
        _, cur = heappop(heap)
        if cur in closed:
            continue
        if cur == goal:
            return rebuild(came_from, cur)
        closed.add(cur)
        for nxt in nbrs_walk(grid, cur[0], cur[1]):
            if nxt in closed:
                continue
            cand = g[cur] + move_cost(cur, nxt)
            if nxt not in g or cand < g[nxt]:
                g[nxt] = cand
                came_from[nxt] = cur
                heappush(heap, (cand + h(nxt, goal), nxt))
    return []


def simplify(path):
    if len(path) <= 2:
        return path[:]
    out = [path[0]]
    prev_dir = None
    for i in range(1, len(path)):
        dr = path[i][0] - path[i - 1][0]
        dc = path[i][1] - path[i - 1][1]
        cur_dir = (0 if dr == 0 else dr // abs(dr), 0 if dc == 0 else dc // abs(dc))
        if prev_dir is None:
            prev_dir = cur_dir
            continue
        if cur_dir != prev_dir:
            out.append(path[i - 1])
            prev_dir = cur_dir
    out.append(path[-1])
    return out


def _parse_attributes(raw):
    if not raw:
        return {}
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return {}
    return {}


def _normalize_xyz(value):
    if not isinstance(value, (list, tuple)) or len(value) < 3:
        return None
    return float(value[0]), float(value[1]), float(value[2])


def _normalize_extent(value):
    xyz = _normalize_xyz(value)
    if xyz is None:
        return None
    return max(xyz[0], 0.02), max(xyz[1], 0.02), max(xyz[2], 0.02)


def _normalize_footprint(payload):
    raw = (
        payload.get("footprintXyz")
        or payload.get("footprint_xyz")
        or payload.get("footprintXZ")
        or payload.get("footprint_xz")
    )
    if not isinstance(raw, list):
        return []
    footprint = []
    for point in raw:
        xyz = _normalize_xyz(point)
        if xyz is not None:
            footprint.append((xyz[0], xyz[2]))
    return footprint


def _normalize_support_relation(payload):
    relation = payload.get("supportRelation") or payload.get("support_relation")
    return relation if isinstance(relation, dict) else None


def _context_from_observation(observation):
    world_transform16 = observation.get("worldTransform16") or observation.get("world_transform16")
    center_xyz = _normalize_xyz(observation.get("centerXyz") or observation.get("center_xyz"))
    extent_xyz = _normalize_extent(observation.get("extentXyz") or observation.get("extent_xyz"))
    base_anchor_xyz = _normalize_xyz(
        observation.get("baseAnchorXyz") or observation.get("base_anchor_xyz")
    )
    return TargetContext(
        object_id=observation.get("id"),
        label=observation.get("label"),
        world_transform16=world_transform16,
        center_xyz=center_xyz or tf_to_xyz(world_transform16),
        extent_xyz=extent_xyz,
        base_anchor_xyz=base_anchor_xyz,
        footprint_xz=_normalize_footprint(observation),
        support_relation=_normalize_support_relation(observation),
    )


def _context_from_node(node):
    attrs = _parse_attributes(node.get("attributesJson") or node.get("attributes_json"))
    world_transform16 = node.get("worldTransform16") or node.get("world_transform16")
    return TargetContext(
        object_id=node.get("id"),
        label=node.get("label"),
        world_transform16=world_transform16,
        center_xyz=_normalize_xyz(attrs.get("centerXyz") or attrs.get("center_xyz")) or tf_to_xyz(world_transform16),
        extent_xyz=_normalize_extent(node.get("extentXyz") or node.get("extent_xyz")),
        base_anchor_xyz=_normalize_xyz(attrs.get("baseAnchorXyz") or attrs.get("base_anchor_xyz")),
        footprint_xz=_normalize_footprint(attrs),
        support_relation=_normalize_support_relation(attrs),
    )


def _fallback_target_context(target_world_transform16, target_label):
    center_xyz = tf_to_xyz(target_world_transform16)
    return TargetContext(
        object_id=None,
        label=target_label,
        world_transform16=target_world_transform16,
        center_xyz=center_xyz,
        extent_xyz=None,
        base_anchor_xyz=center_xyz,
        footprint_xz=[],
        support_relation=None,
    )


def _label_match_score(query_label, candidate_label):
    if not query_label or not candidate_label:
        return -1
    query = query_label.lower()
    candidate = candidate_label.lower()
    if candidate == query:
        return 3
    if query in candidate:
        return 2
    query_tokens = set(query.split())
    candidate_tokens = set(candidate.split())
    if query_tokens and query_tokens <= candidate_tokens:
        return 1
    return -1


def _distance_xz(a, b):
    return sqrt((a[0] - b[0]) ** 2 + (a[2] - b[2]) ** 2)


def _resolve_target_context(room, target_label=None, target_world_transform16=None):
    requested_xyz = tf_to_xyz(target_world_transform16)
    candidates = []
    for observation in room.observations:
        context = _context_from_observation(observation)
        score = _label_match_score(target_label, context.label) if target_label else 0
        if target_label and score < 0:
            continue
        distance = _distance_xz(requested_xyz, context.center_xyz) if requested_xyz and context.center_xyz else 0.0
        candidates.append((score, -distance, context))

    if candidates:
        candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)
        return candidates[0][2]

    if target_label and room.scene_graph:
        node_candidates = []
        for node in room.scene_graph.get("nodes", []):
            context = _context_from_node(node)
            score = _label_match_score(target_label, context.label)
            if score < 0:
                continue
            distance = _distance_xz(requested_xyz, context.center_xyz) if requested_xyz and context.center_xyz else 0.0
            node_candidates.append((score, -distance, context))
        if node_candidates:
            node_candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)
            return node_candidates[0][2]

    if target_world_transform16:
        return _fallback_target_context(target_world_transform16, target_label)
    return None


def _find_context_by_id(room, object_id):
    if not object_id:
        return None
    for observation in room.observations:
        if observation.get("id") == object_id:
            return _context_from_observation(observation)
    if room.scene_graph:
        for node in room.scene_graph.get("nodes", []):
            if node.get("id") == object_id:
                return _context_from_node(node)
    return None


def _resolve_support_context(room, target_context):
    if target_context is None or not target_context.support_relation:
        return None
    relation = target_context.support_relation
    support_object_id = relation.get("support_object_id")
    if support_object_id:
        return _find_context_by_id(room, support_object_id)
    return None


def _footprint_from_extent(center_xyz, extent_xyz):
    if center_xyz is None or extent_xyz is None:
        return []
    half_x = extent_xyz[0] * 0.5
    half_z = extent_xyz[2] * 0.5
    x, _, z = center_xyz
    return [
        (x - half_x, z - half_z),
        (x + half_x, z - half_z),
        (x + half_x, z + half_z),
        (x - half_x, z + half_z),
    ]


def _project_to_segment(point, start, end):
    sx, sz = start
    ex, ez = end
    dx = ex - sx
    dz = ez - sz
    denom = dx * dx + dz * dz
    if denom <= 1e-6:
        return start
    t = ((point[0] - sx) * dx + (point[1] - sz) * dz) / denom
    t = clamp(t, 0.0, 1.0)
    return sx + dx * t, sz + dz * t


def _normalize_2d(vector):
    length = sqrt(vector[0] ** 2 + vector[1] ** 2)
    if length <= 1e-6:
        return None
    return vector[0] / length, vector[1] / length


def _build_approach_candidates(start_xyz, target_context, support_context, clearance_m):
    approach_context = support_context or target_context
    if approach_context is None:
        return []

    footprint = list(approach_context.footprint_xz)
    if not footprint:
        footprint = _footprint_from_extent(approach_context.center_xyz, approach_context.extent_xyz)
    if len(footprint) < 2:
        return []

    center_xyz = approach_context.center_xyz or target_context.center_xyz
    if center_xyz is None:
        return []
    center_xz = (center_xyz[0], center_xyz[2])

    anchor_xyz = target_context.base_anchor_xyz or target_context.center_xyz
    if anchor_xyz is None and support_context is not None:
        anchor_xyz = support_context.base_anchor_xyz or support_context.center_xyz
    if anchor_xyz is None:
        anchor_xyz = center_xyz
    anchor_xz = (anchor_xyz[0], anchor_xyz[2])

    candidates = []
    loop = footprint + [footprint[0]]
    for start, end in zip(loop, loop[1:]):
        edge_point = _project_to_segment(anchor_xz, start, end)
        outward = _normalize_2d((edge_point[0] - center_xz[0], edge_point[1] - center_xz[1]))
        if outward is None:
            midpoint = ((start[0] + end[0]) * 0.5, (start[1] + end[1]) * 0.5)
            outward = _normalize_2d((midpoint[0] - center_xz[0], midpoint[1] - center_xz[1]))
        if outward is None:
            continue
        approach = (
            edge_point[0] + outward[0] * clearance_m,
            edge_point[1] + outward[1] * clearance_m,
        )
        candidates.append(approach)

    if not candidates and center_xz:
        candidates.append(center_xz)

    candidates.sort(key=lambda point: sqrt((point[0] - start_xyz[0]) ** 2 + (point[1] - start_xyz[2]) ** 2))
    deduped = []
    for candidate in candidates:
        if any(sqrt((candidate[0] - existing[0]) ** 2 + (candidate[1] - existing[1]) ** 2) < 0.08 for existing in deduped):
            continue
        deduped.append(candidate)
    return deduped


def _goal_reason(target_context, support_context):
    if support_context is not None:
        return "support_edge"
    if target_context and target_context.footprint_xz:
        return "object_edge"
    return "target_center"


def plan_route(room, start_world_transform16, target_world_transform16=None, target_label=None, grid_resolution_m=0.20, obstacle_inflation_radius_m=0.25):
    start_xyz = tf_to_xyz(start_world_transform16)
    if start_xyz is None:
        return {"reachable": False, "reason": "invalid start transform", "waypoints": []}

    target_context = _resolve_target_context(room, target_label, target_world_transform16)
    if target_context is None:
        return {"reachable": False, "reason": "target not found", "waypoints": []}
    target_xyz = target_context.center_xyz or tf_to_xyz(target_context.world_transform16)
    if target_xyz is None:
        return {"reachable": False, "reason": "target not found", "waypoints": []}

    support_context = _resolve_support_context(room, target_context)
    approach_candidates = _build_approach_candidates(
        start_xyz,
        target_context,
        support_context,
        clearance_m=max(obstacle_inflation_radius_m + 0.30, 0.40),
    )
    goal_xyz = None
    if approach_candidates:
        goal_xyz = (approach_candidates[0][0], start_xyz[1], approach_candidates[0][1])
    else:
        goal_xyz = (target_xyz[0], start_xyz[1], target_xyz[2])

    obstacles = scene_graph_to_obstacles(room.scene_graph)
    min_x, min_z, max_x, max_z = compute_bounds(start_xyz, goal_xyz, obstacles)
    grid = build_grid(min_x, min_z, max_x, max_z, grid_resolution_m)
    rasterize_rects(grid, obstacles)
    inflate(grid, obstacle_inflation_radius_m)

    start_row, start_col = world_to_grid(grid, start_xyz[0], start_xyz[2])
    goal_row, goal_col = world_to_grid(grid, goal_xyz[0], goal_xyz[2])
    start_cell = nearest_walkable(grid, start_row, start_col)
    goal_cell = nearest_walkable(grid, goal_row, goal_col)

    if start_cell is None:
        return {"reachable": False, "reason": "no reachable start", "waypoints": []}
    if goal_cell is None:
        return {"reachable": False, "reason": "no reachable goal", "waypoints": []}

    raw_path = astar(grid, start_cell, goal_cell)
    if not raw_path:
        return {"reachable": False, "reason": "no path found", "waypoints": []}

    y = start_xyz[1]
    waypoints = []
    for row, col in simplify(raw_path):
        x, z = grid_to_world(grid, row, col)
        waypoints.append({
            "x": x,
            "y": y,
            "z": z,
            "worldTransform16": xyz_to_tf(x, y, z),
        })

    gx, gz = grid_to_world(grid, goal_cell[0], goal_cell[1])
    return {
        "reachable": True,
        "reason": _goal_reason(target_context, support_context),
        "targetLabel": target_context.label or target_label,
        "snappedGoalWorldTransform16": xyz_to_tf(gx, y, gz),
        "waypoints": waypoints,
    }
