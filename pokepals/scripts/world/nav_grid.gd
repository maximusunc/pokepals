class_name NavGrid
extends RefCounted
## The world's WALKABILITY as pure logic: a coarse grid over the map, rasterized once
## from the same solid list the collision resolver uses (Solids.build), plus an A* path
## search and an exact line-of-sight test over it. No nodes, no physics, no navigation
## server — geometry in, waypoints out — so it's unit-testable, runs headless, and could
## later run the same routing on the server (like the Solids port for ambient pals).
##
## The companion's *brain* never sees this. Deciding "be at the follow point" stays pure
## logic; getting the legs there through hedge walls is a body problem, and this module
## is how the body solves it (see NavAgent for the steering that consumes these paths).

var _cell_size := 24.0
var _origin := Vector2.ZERO       # world position of cell (0,0)'s top-left corner
var _cols := 0
var _rows := 0
var _walk := PackedByteArray()    # 1 = a body can stand at this cell's center
var _solids: Array = []           # kept for the exact line_clear test
var _solid_boxes: Array = []      # per-solid AABB pre-grown by its clearance — line_clear broad-phase
var _inflate := 8.0               # body_radius + margin — clearance around every solid


## Rasterize the solid list into a walkability grid covering `bounds`. A cell is walkable
## iff a body of `body_radius` (+ `margin` slack, mirroring Solids.resolve) standing at the
## cell's CENTER touches no solid and no map edge. Each solid only visits the cells in its
## own inflated bounding box, so the whole build is a few milliseconds even for the maze's
## ~230 hedge segments — cheap enough to redo whenever solids change (the Ruin's slabs).
static func build(solids: Array, bounds: Rect2, body_radius: float, margin: float, cell_size: float) -> NavGrid:
	var g := NavGrid.new()
	g._cell_size = maxf(cell_size, 1.0)
	g._origin = bounds.position
	g._cols = maxi(1, int(ceilf(bounds.size.x / g._cell_size)))
	g._rows = maxi(1, int(ceilf(bounds.size.y / g._cell_size)))
	g._solids = solids
	g._inflate = body_radius + margin
	g._walk.resize(g._cols * g._rows)
	g._walk.fill(1)

	# The map edge blocks like a wall: centers the body couldn't stand at (clamped by
	# Solids._clamp_bounds) are unwalkable, so paths never hug an edge they'd be pushed off.
	# Only cells in the outermost band can fail this (inflate < cell size), so visit just those.
	var interior := bounds.grow(-g._inflate)
	var band := maxi(1, int(ceilf(g._inflate / g._cell_size)))
	for col in g._cols:
		for row in g._rows:
			if col >= band and col < g._cols - band and row >= band and row < g._rows - band:
				continue
			if not interior.has_point(g.center_of(Vector2i(col, row))):
				g._walk[row * g._cols + col] = 0

	# A solid smaller than the half-cell diagonal could slip between cell CENTERS and go
	# unseen by the grid (a lone tree near a cell corner), letting A* plan a leg through
	# its clearance band. Rasterize with at least that radius so every solid blocks the
	# cell(s) it sits in; the exact line_clear test still uses the true radii.
	var min_raster_r := g._cell_size * 0.7072  # half diagonal, a hair over sqrt(2)/2
	for s in solids:
		var r := maxf(float(s["radius"]) + g._inflate, min_raster_r)
		var lo: Vector2
		var hi: Vector2
		if s.has("a"):
			var a: Vector2 = s["a"]
			var b: Vector2 = s["b"]
			lo = Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(r, r)
			hi = Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(r, r)
		else:
			var c: Vector2 = s["center"]
			lo = c - Vector2(r, r)
			hi = c + Vector2(r, r)
		g._solid_boxes.append(Rect2(lo, hi - lo))
		var c0 := maxi(0, int(floorf((lo.x - g._origin.x) / g._cell_size)))
		var c1 := mini(g._cols - 1, int(floorf((hi.x - g._origin.x) / g._cell_size)))
		var r0 := maxi(0, int(floorf((lo.y - g._origin.y) / g._cell_size)))
		var r1 := mini(g._rows - 1, int(floorf((hi.y - g._origin.y) / g._cell_size)))
		for row in range(r0, r1 + 1):
			for col in range(c0, c1 + 1):
				var idx := row * g._cols + col
				if g._walk[idx] == 0:
					continue
				var center := g.center_of(Vector2i(col, row))
				if center.distance_to(Solids.nearest_point(s, center)) < r:
					g._walk[idx] = 0
	return g


func cell_size() -> float:
	return _cell_size


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(floorf((pos.x - _origin.x) / _cell_size)), 0, _cols - 1),
		clampi(int(floorf((pos.y - _origin.y) / _cell_size)), 0, _rows - 1))


func center_of(cell: Vector2i) -> Vector2:
	return _origin + Vector2((cell.x + 0.5) * _cell_size, (cell.y + 0.5) * _cell_size)


func is_walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= _cols or cell.y < 0 or cell.y >= _rows:
		return false
	return _walk[cell.y * _cols + cell.x] == 1


## Spiral outward from `near` (rings of growing Chebyshev radius) to a walkable cell,
## preferring the candidate whose center is closest to `near` itself — NOT the first hit
## in scan order, which would bias toward one side and could snap a point that's inside
## a hedge band to the wrong side of the hedge. Returns the input cell if it's already
## walkable, or (-1,-1) if nothing within max_rings ("can't path from/to here").
func nearest_walkable(near: Vector2, max_rings: int) -> Vector2i:
	var cell := cell_of(near)
	if is_walkable(cell):
		return cell
	for ring in range(1, max_rings + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var c := cell + Vector2i(dx, dy)
				if is_walkable(c):
					var d := center_of(c).distance_squared_to(near)
					if d < best_d:
						best_d = d
						best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Exact clearance test: can a body slide straight from `a` to `b` without touching any
## solid (with the same inflation the grid uses)? This is geometry against the REAL solids,
## not the grid — so it's what gates "just steer directly" and what string-pulls paths,
## and its answer never suffers from grid resolution. A pre-grown AABB per solid rejects
## almost every solid before the exact segment math (line_clear runs hot during smoothing).
func line_clear(a: Vector2, b: Vector2) -> bool:
	var seg_box := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2.ZERO)
	seg_box.end = Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	for i in _solids.size():
		if not (_solid_boxes[i] as Rect2).intersects(seg_box):
			continue
		var s: Dictionary = _solids[i]
		var min_dist := float(s["radius"]) + _inflate
		if s.has("a"):
			var pts := Geometry2D.get_closest_points_between_segments(a, b, s["a"], s["b"])
			if pts[0].distance_to(pts[1]) < min_dist:
				return false
		else:
			var near := Geometry2D.get_closest_point_to_segment(s["center"], a, b)
			if near.distance_to(s["center"]) < min_dist:
				return false
	return true


## A* over the grid, 8-connected (diagonals only when both flanking orthogonal cells are
## open, so a path never clips a wall corner). Returns smoothed world-space waypoints
## ENDING at `to` when reachable. When `to` isn't reachable (sealed pocket, expansion cap),
## returns the path to the closest point the search DID reach — a best partial path — so a
## follower presses toward its goal rather than freezing. [] when `from` can't be placed on
## the grid, or when no reachable cell is closer to the goal than where we already stand
## (nowhere better to go — the caller should ease off, not spin).
func find_path(from: Vector2, to: Vector2, max_expansions: int, snap_rings: int = 4) -> Array:
	var start := nearest_walkable(from, snap_rings)
	if start.x < 0:
		return []
	# A goal that can't snap to walkable ground (a point deep inside a pond) keeps its raw
	# cell: the search can never terminate ON it, so it flows toward it and returns the
	# best partial path — the companion trots to the shore nearest the point, not nowhere.
	var goal_reachable := true
	var goal := nearest_walkable(to, snap_rings)
	if goal.x < 0:
		goal = cell_of(to)
		goal_reachable = false

	var count := _cols * _rows
	var g_score := PackedFloat32Array()
	g_score.resize(count)
	g_score.fill(INF)
	var parent := PackedInt32Array()
	parent.resize(count)
	parent.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)

	var start_i := start.y * _cols + start.x
	var goal_i := goal.y * _cols + goal.x
	g_score[start_i] = 0.0
	# Binary heap of [f, index] pairs kept in two flat arrays. Plain Arrays on purpose:
	# packed arrays pass to helpers BY VALUE in GDScript, and the helpers must mutate these.
	var heap_f: Array[float] = [_octile(start, goal)]
	var heap_i: Array[int] = [start_i]
	var best_i := start_i
	var best_h := _octile(start, goal)
	var expansions := 0

	while heap_i.size() > 0 and expansions < max_expansions:
		var current := _heap_pop(heap_f, heap_i)
		if closed[current] == 1:
			continue
		closed[current] = 1
		expansions += 1
		if current == goal_i:
			best_i = goal_i
			break
		var cell := _cell_at(current)
		var h := _octile(cell, goal)
		if h < best_h:
			best_h = h
			best_i = current
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var n := cell + Vector2i(dx, dy)
				if not is_walkable(n):
					continue
				if dx != 0 and dy != 0:
					# No corner clipping: a diagonal step needs both orthogonal neighbours open.
					if not is_walkable(cell + Vector2i(dx, 0)) or not is_walkable(cell + Vector2i(0, dy)):
						continue
				var ni := n.y * _cols + n.x
				if closed[ni] == 1:
					continue
				var step := 1.41421356 if (dx != 0 and dy != 0) else 1.0
				var tentative := g_score[current] + step
				if tentative < g_score[ni]:
					g_score[ni] = tentative
					parent[ni] = current
					_heap_push(heap_f, heap_i, tentative + _octile(n, goal), ni)

	var points: Array = []
	var walk_i := best_i
	while walk_i != -1 and walk_i != start_i:
		points.push_front(center_of(_cell_at(walk_i)))
		walk_i = parent[walk_i]
	# End the route at the true goal point (not its cell center) when the search reached its
	# cell, that cell wasn't snapped elsewhere, AND the exact point is actually attainable
	# (the final leg is clear) — a goal 10px from a trunk keeps the cell center instead of
	# steering the body at a spot the collision resolver will never let it occupy.
	if goal_reachable and best_i == goal_i and cell_of(to) == goal:
		var leg_from: Vector2 = points[points.size() - 2] if points.size() > 1 else from
		if line_clear(leg_from, to):
			if points.is_empty():
				points.append(to)
			else:
				points[points.size() - 1] = to
	return smooth(from, points)


## Greedy string-pulling: from `from`, keep only the farthest waypoint still directly
## reachable (line_clear), then repeat from there. Turns staircase grid paths into the
## few straight legs a creature would actually take — corners get cut naturally. Walks
## FORWARD, extending each leg while it stays clear, so the whole pass is linear in the
## path length (a backward scan is quadratic on the maze's long winding paths). The one
## shortcut: if the last point is already visible, the answer is a single straight leg.
func smooth(from: Vector2, points: Array) -> Array:
	if points.size() <= 1:
		return points
	if line_clear(from, points.back()):
		return [points.back()]
	var out: Array = []
	var anchor := from
	var i := 0
	while i < points.size():
		var far := i
		while far + 1 < points.size() and line_clear(anchor, points[far + 1]):
			far += 1
		out.append(points[far])
		anchor = points[far]
		i = far + 1
	return out


func _cell_at(index: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(index % _cols, index / _cols)


func _octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(float(a.x - b.x))
	var dy := absf(float(a.y - b.y))
	return maxf(dx, dy) + 0.41421356 * minf(dx, dy)


static func _heap_push(heap_f: Array[float], heap_i: Array[int], f: float, idx: int) -> void:
	heap_f.append(f)
	heap_i.append(idx)
	var i := heap_f.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if heap_f[p] <= heap_f[i]:
			break
		var tf := heap_f[p]; heap_f[p] = heap_f[i]; heap_f[i] = tf
		var ti := heap_i[p]; heap_i[p] = heap_i[i]; heap_i[i] = ti
		i = p


static func _heap_pop(heap_f: Array[float], heap_i: Array[int]) -> int:
	var top := heap_i[0]
	var last := heap_f.size() - 1
	heap_f[0] = heap_f[last]
	heap_i[0] = heap_i[last]
	heap_f.remove_at(last)
	heap_i.remove_at(last)
	var i := 0
	var n := heap_f.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var small := i
		if l < n and heap_f[l] < heap_f[small]:
			small = l
		if r < n and heap_f[r] < heap_f[small]:
			small = r
		if small == i:
			break
		var tf := heap_f[small]; heap_f[small] = heap_f[i]; heap_f[i] = tf
		var ti := heap_i[small]; heap_i[small] = heap_i[i]; heap_i[i] = ti
		i = small
	return top
