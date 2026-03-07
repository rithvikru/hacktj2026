from __future__ import annotations

from dataclasses import dataclass
from heapq import heappop, heappush
from math import ceil, sqrt

# Just take from scaffold dont do it again
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
    # rithvik fix this part up its fried cause if scene graph extends it gets weird later
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


def find_target_tf(room, target_label=None, target_world_transform16=None):
    if target_world_transform16:
        return target_world_transform16
    if not target_label:
        return None
    label_lower = target_label.lower()
    if room.scene_graph:
        for node in room.scene_graph.get("nodes", []):
            label = (node.get("label") or "").lower()
            if label == label_lower or label_lower in label:
                tf = node.get("worldTransform16") or node.get("world_transform16")
                if tf:
                    return tf
    for obs in room.observations:
        label = (obs.get("label") or "").lower()
        if label == label_lower or label_lower in label:
            tf = obs.get("worldTransform16") or obs.get("world_transform16")
            if tf:
                return tf
    return None


def plan_route(room, start_world_transform16, target_world_transform16=None, target_label=None, grid_resolution_m=0.20, obstacle_inflation_radius_m=0.25):
    start_xyz = tf_to_xyz(start_world_transform16)
    target_tf = find_target_tf(room, target_label, target_world_transform16)
    target_xyz = tf_to_xyz(target_tf)
    if start_xyz is None:
        return {"reachable": False, "reason": "invalid start transform", "waypoints": []}
    if target_xyz is None:
        return {"reachable": False, "reason": "target not found", "waypoints": []}

    obstacles = scene_graph_to_obstacles(room.scene_graph)
    min_x, min_z, max_x, max_z = compute_bounds(start_xyz, target_xyz, obstacles)
    grid = build_grid(min_x, min_z, max_x, max_z, grid_resolution_m)
    rasterize_rects(grid, obstacles)
    inflate(grid, obstacle_inflation_radius_m)

    start_row, start_col = world_to_grid(grid, start_xyz[0], start_xyz[2])
    goal_row, goal_col = world_to_grid(grid, target_xyz[0], target_xyz[2])
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
        "reason": "ok",
        "targetLabel": target_label,
        "snappedGoalWorldTransform16": xyz_to_tf(gx, y, gz),
        "waypoints": waypoints,
    }
