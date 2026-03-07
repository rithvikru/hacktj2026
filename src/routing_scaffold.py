from __future__ import annotations

from dataclasses import dataclass, field
from heapq import heappop, heappush
from math import ceil, sqrt


@dataclass
class Vec2:
    x: float
    y: float


@dataclass
class Vec3:
    x: float
    y: float
    z: float


@dataclass
class Polygon2D:
    vertices: list[Vec2]


@dataclass
class RoomGeometry:
    room_boundary: Polygon2D
    obstacle_footprints: list[Polygon2D] = field(default_factory=list)
    named_regions: dict[str, Polygon2D] = field(default_factory=dict)


@dataclass
class OccupancyGrid:
    origin_x: float
    origin_y: float
    resolution: float
    width: int
    height: int
    blocked: list[list[bool]]


@dataclass
class RouteRequest:
    start_world: Vec2
    target_world: Vec2
    room_geometry: RoomGeometry
    grid_resolution_m: float = 0.10
    obstacle_inflation_radius_m: float = 0.25


@dataclass
class RouteResult:
    reachable: bool
    reason: str
    snapped_start: Vec2 | None = None
    snapped_goal: Vec2 | None = None
    world_waypoints: list[Vec2] = field(default_factory=list)


def project_room_to_floor(room_mesh_or_boxes):
    return room_mesh_or_boxes


def compute_room_bounds(room_geometry):
    xs = [pt.x for pt in room_geometry.room_boundary.vertices]
    ys = [pt.y for pt in room_geometry.room_boundary.vertices]
    for poly in room_geometry.obstacle_footprints:
        for pt in poly.vertices:
            xs.append(pt.x)
            ys.append(pt.y)
    return min(xs), min(ys), max(xs), max(ys)


def build_empty_occupancy_grid(room_geometry, resolution_m):
    min_x, min_y, max_x, max_y = compute_room_bounds(room_geometry)
    width = max(1, ceil((max_x - min_x) / resolution_m))
    height = max(1, ceil((max_y - min_y) / resolution_m))
    blocked = [[False for _ in range(width)] for _ in range(height)]
    return OccupancyGrid(min_x, min_y, resolution_m, width, height, blocked)


def point_in_polygon(point, poly):
    x = point.x
    y = point.y
    inside = False
    n = len(poly.vertices)
    if n < 3:
        return False
    j = n - 1
    for i in range(n):
        xi = poly.vertices[i].x
        yi = poly.vertices[i].y
        xj = poly.vertices[j].x
        yj = poly.vertices[j].y
        cross = ((yi > y) != (yj > y))
        if cross:
            denom = yj - yi
            if denom == 0:
                denom = 1e-9
            x_hit = (xj - xi) * (y - yi) / denom + xi
            if x < x_hit:
                inside = not inside
        j = i
    return inside


def rasterize_obstacles_into_grid(grid, obstacle_footprints):
    for row in range(grid.height):
        for col in range(grid.width):
            world_pt = grid_to_world(grid, row, col)
            for poly in obstacle_footprints:
                if point_in_polygon(world_pt, poly):
                    grid.blocked[row][col] = True
                    break


def inflate_blocked_cells(grid, inflation_radius_m):
    radius_cells = max(0, ceil(inflation_radius_m / grid.resolution))
    if radius_cells == 0:
        return
    original = [row[:] for row in grid.blocked]
    for row in range(grid.height):
        for col in range(grid.width):
            if not original[row][col]:
                continue
            for d_row in range(-radius_cells, radius_cells + 1):
                for d_col in range(-radius_cells, radius_cells + 1):
                    next_row = row + d_row
                    next_col = col + d_col
                    if not is_cell_in_bounds(grid, next_row, next_col):
                        continue
                    if sqrt(d_row * d_row + d_col * d_col) <= radius_cells:
                        grid.blocked[next_row][next_col] = True


def world_to_grid(grid, point):
    col = int((point.x - grid.origin_x) / grid.resolution)
    row = int((point.y - grid.origin_y) / grid.resolution)
    if col < 0:
        col = 0
    if row < 0:
        row = 0
    if col >= grid.width:
        col = grid.width - 1
    if row >= grid.height:
        row = grid.height - 1
    return row, col


def grid_to_world(grid, row, col):
    x = grid.origin_x + (col + 0.5) * grid.resolution
    y = grid.origin_y + (row + 0.5) * grid.resolution
    return Vec2(x, y)


def is_cell_in_bounds(grid, row, col):
    return 0 <= row < grid.height and 0 <= col < grid.width


def is_cell_walkable(grid, row, col):
    return is_cell_in_bounds(grid, row, col) and not grid.blocked[row][col]


def find_nearest_walkable_cell(grid, start_row, start_col):
    if is_cell_walkable(grid, start_row, start_col):
        return start_row, start_col
    seen = {(start_row, start_col)}
    queue = [(start_row, start_col)]
    head = 0
    while head < len(queue):
        row, col = queue[head]
        head += 1
        for next_row, next_col in get_neighbors_8_all(grid, row, col):
            if (next_row, next_col) in seen:
                continue
            if is_cell_walkable(grid, next_row, next_col):
                return next_row, next_col
            seen.add((next_row, next_col))
            queue.append((next_row, next_col))
    return None


def choose_reachable_goal_cell(grid, target_world):
    row, col = world_to_grid(grid, target_world)
    if is_cell_walkable(grid, row, col):
        return row, col
    return find_nearest_walkable_cell(grid, row, col)


def get_neighbors_8(grid, row, col):
    out = []
    for d_row in (-1, 0, 1):
        for d_col in (-1, 0, 1):
            if d_row == 0 and d_col == 0:
                continue
            next_row = row + d_row
            next_col = col + d_col
            if is_cell_walkable(grid, next_row, next_col):
                out.append((next_row, next_col))
    return out


def get_neighbors_8_all(grid, row, col):
    out = []
    for d_row in (-1, 0, 1):
        for d_col in (-1, 0, 1):
            if d_row == 0 and d_col == 0:
                continue
            next_row = row + d_row
            next_col = col + d_col
            if is_cell_in_bounds(grid, next_row, next_col):
                out.append((next_row, next_col))
    return out


def euclidean_heuristic(a, b):
    return sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2)


def move_cost(a, b):
    if a[0] != b[0] and a[1] != b[1]:
        return 1.41421356237
    return 1.0


def reconstruct_path(came_from, end_cell):
    path = [end_cell]
    cur = end_cell
    while cur in came_from:
        cur = came_from[cur]
        path.append(cur)
    path.reverse()
    return path


def astar_search(grid, start_cell, goal_cell):
    open_heap = []
    heappush(open_heap, (0.0, start_cell))
    came_from = {}
    g_score = {start_cell: 0.0}
    closed = set()

    while open_heap:
        _, cur = heappop(open_heap)
        if cur in closed:
            continue
        if cur == goal_cell:
            return reconstruct_path(came_from, cur)
        closed.add(cur)

        for nbr in get_neighbors_8(grid, cur[0], cur[1]):
            if nbr in closed:
                continue
            cand = g_score[cur] + move_cost(cur, nbr)
            if nbr not in g_score or cand < g_score[nbr]:
                g_score[nbr] = cand
                came_from[nbr] = cur
                f_score = cand + euclidean_heuristic(nbr, goal_cell)
                heappush(open_heap, (f_score, nbr))
    return []


def simplify_path(grid_path):
    if len(grid_path) <= 2:
        return grid_path[:]
    out = [grid_path[0]]
    prev_dir = None
    for i in range(1, len(grid_path)):
        dr = grid_path[i][0] - grid_path[i - 1][0]
        dc = grid_path[i][1] - grid_path[i - 1][1]
        cur_dir = (0 if dr == 0 else dr // abs(dr), 0 if dc == 0 else dc // abs(dc))
        if prev_dir is None:
            prev_dir = cur_dir
            continue
        if cur_dir != prev_dir:
            out.append(grid_path[i - 1])
            prev_dir = cur_dir
    out.append(grid_path[-1])
    return out


def convert_grid_path_to_world_waypoints(grid, grid_path):
    return [grid_to_world(grid, row, col) for row, col in grid_path]


def plan_route(request):
    room_geometry = project_room_to_floor(request.room_geometry)
    grid = build_empty_occupancy_grid(room_geometry, request.grid_resolution_m)
    rasterize_obstacles_into_grid(grid, room_geometry.obstacle_footprints)
    inflate_blocked_cells(grid, request.obstacle_inflation_radius_m)

    start_row, start_col = world_to_grid(grid, request.start_world)
    start_cell = find_nearest_walkable_cell(grid, start_row, start_col)
    if start_cell is None:
        return RouteResult(False, "no reachable start")

    goal_cell = choose_reachable_goal_cell(grid, request.target_world)
    if goal_cell is None:
        return RouteResult(False, "no reachable goal")

    raw_path = astar_search(grid, start_cell, goal_cell)
    if not raw_path:
        return RouteResult(False, "no path found")

    simple_path = simplify_path(raw_path)
    return RouteResult(
        True,
        "ok",
        snapped_start=grid_to_world(grid, start_cell[0], start_cell[1]),
        snapped_goal=grid_to_world(grid, goal_cell[0], goal_cell[1]),
        world_waypoints=convert_grid_path_to_world_waypoints(grid, simple_path),
    )


def make_rect(x1, y1, x2, y2):
    return Polygon2D([
        Vec2(x1, y1),
        Vec2(x2, y1),
        Vec2(x2, y2),
        Vec2(x1, y2),
    ])


def main():
    room = RoomGeometry(
        room_boundary=make_rect(0.0, 0.0, 5.0, 4.0),
        obstacle_footprints=[make_rect(2.0, 1.0, 3.0, 2.8)],
    )
    req = RouteRequest(
        start_world=Vec2(0.5, 0.5),
        target_world=Vec2(4.5, 3.2),
        room_geometry=room,
        grid_resolution_m=0.25,
        obstacle_inflation_radius_m=0.20,
    )
    result = plan_route(req)
    print(result.reachable, result.reason)
    print(result.snapped_start)
    print(result.snapped_goal)
    print(result.world_waypoints)


if __name__ == "__main__":
    main()
