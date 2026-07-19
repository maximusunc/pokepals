class_name TestNavGrid
## Pure tests for the walkability grid + A* router — no nodes, no scene. Documents the
## routing contract: rasterization respects clearance, paths go AROUND solids and never
## cut through them, unreachable goals yield a best-effort partial path (never a freeze),
## and the real maze fixture is fully solvable from spawn to heart.

const CELL := 24.0
const BODY := 6.0
const MARGIN := 2.0


static func run_all() -> int:
	var fails := 0
	print("TestNavGrid")
	fails += _test_circle_rasterization()
	fails += _test_capsule_rasterization()
	fails += _test_line_clear()
	fails += _test_path_around_wall()
	fails += _test_partial_path_when_sealed()
	fails += _test_unsnappable_goal_reaches_the_shore()
	fails += _test_goal_inside_solid_snaps()
	fails += _test_smooth_collapses_visible_waypoints()
	fails += _test_maze_fixture_is_solvable()
	return fails


static func _check(name: String, ok: bool) -> int:
	print("  %s  %s" % [("PASS" if ok else "FAIL"), name])
	return 0 if ok else 1


static func _big_bounds() -> Rect2:
	return Rect2(Vector2(-500, -500), Vector2(1000, 1000))


static func _grid(solids: Array) -> NavGrid:
	return NavGrid.build(solids, _big_bounds(), BODY, MARGIN, CELL)


## The path-validity contract: every leg of a returned route, including the approach from
## `from`, must itself be a clear straight walk. Empty paths vacuously hold.
static func _legs_clear(g: NavGrid, from: Vector2, path: Array) -> bool:
	if path.is_empty():
		return true
	if not g.line_clear(from, path[0]):
		return false
	for i in range(path.size() - 1):
		if not g.line_clear(path[i], path[i + 1]):
			return false
	return true


static func _test_circle_rasterization() -> int:
	var g := _grid([{ "center": Vector2.ZERO, "radius": 30.0 }])
	# Cell centers within radius(30) + body(6) + margin(2) = 38 of the origin are blocked.
	var blocked := not g.is_walkable(g.cell_of(Vector2.ZERO))
	var open := g.is_walkable(g.cell_of(Vector2(200, 0)))
	# A center just beyond the inflated rim must stay walkable (grid is not over-inflated).
	var rim_cell := g.cell_of(Vector2(60, 60))
	var rim_open := g.is_walkable(rim_cell) and g.center_of(rim_cell).length() > 38.0
	return _check("circle blocks its inflated disc, leaves the rest open", blocked and open and rim_open)


static func _test_capsule_rasterization() -> int:
	# A horizontal hedge through the origin, maze-style: thickness 28 -> radius 14.
	var g := _grid([{ "a": Vector2(-200, 0), "b": Vector2(200, 0), "radius": 14.0 }])
	var on_wall := not g.is_walkable(g.cell_of(Vector2(0, 0)))
	var mid_wall := not g.is_walkable(g.cell_of(Vector2(150, 0)))
	var above := g.is_walkable(g.cell_of(Vector2(0, -80)))
	var below := g.is_walkable(g.cell_of(Vector2(0, 80)))
	var past_end := g.is_walkable(g.cell_of(Vector2(300, 0)))
	return _check("capsule blocks its band, corridor beside it stays open",
		on_wall and mid_wall and above and below and past_end)


static func _test_line_clear() -> int:
	var g := _grid([
		{ "center": Vector2(100, 0), "radius": 20.0 },
		{ "a": Vector2(-100, -100), "b": Vector2(-100, 100), "radius": 14.0 },
	])
	var open := g.line_clear(Vector2(0, 200), Vector2(200, 200))
	var through_circle := g.line_clear(Vector2(0, 0), Vector2(200, 0))
	var through_capsule := g.line_clear(Vector2(-200, 0), Vector2(0, 0))
	# Grazing inside the clearance band (within body+margin of the surface) also blocks.
	var grazing := g.line_clear(Vector2(0, 25), Vector2(200, 25))
	return _check("line_clear: open yes; through circle/capsule/graze no",
		open and not through_circle and not through_capsule and not grazing)


static func _test_path_around_wall() -> int:
	# A wall between start and goal, with room to go around either end.
	var wall := { "a": Vector2(0, -150), "b": Vector2(0, 150), "radius": 14.0 }
	var g := _grid([wall])
	var from := Vector2(-100, 0)
	var to := Vector2(100, 0)
	var path := g.find_path(from, to, 6000)
	if path.is_empty() or g.line_clear(from, to):
		return _check("routes around a blocking wall", false)
	var ends_at_goal: bool = (path.back() as Vector2).distance_to(to) < 1.0
	return _check("routes around a blocking wall, all legs clear, ends at goal",
		ends_at_goal and _legs_clear(g, from, path))


static func _test_partial_path_when_sealed() -> int:
	# Goal sealed inside a box of hedges bigger than goal-snap can escape: the search
	# can't reach it, but must still return progress toward it, never [].
	var box := [
		{ "a": Vector2(100, -100), "b": Vector2(300, -100), "radius": 14.0 },
		{ "a": Vector2(300, -100), "b": Vector2(300, 100), "radius": 14.0 },
		{ "a": Vector2(300, 100), "b": Vector2(100, 100), "radius": 14.0 },
		{ "a": Vector2(100, 100), "b": Vector2(100, -100), "radius": 14.0 },
	]
	var g := _grid(box)
	var from := Vector2(-400, 0)
	var to := Vector2(200, 0)  # inside the sealed box
	var path := g.find_path(from, to, 6000)
	if path.is_empty():
		return _check("sealed goal still yields a partial path", false)
	var closer: bool = (path.back() as Vector2).distance_to(to) < from.distance_to(to)
	return _check("sealed goal still yields a partial path that makes progress", closer)


static func _test_unsnappable_goal_reaches_the_shore() -> int:
	# A goal so deep inside a pond that goal-snapping can't rescue it must still produce
	# a partial path that walks to the shore near the point — never [] (which would leave
	# the follower grinding at the water's edge with no route at all).
	var pond := { "center": Vector2(200, 0), "radius": 150.0 }
	var g := _grid([pond])
	var from := Vector2(-300, 0)
	var path := g.find_path(from, pond["center"], 6000)
	if path.is_empty():
		return _check("goal deep in a pond yields a shore-approach partial path", false)
	var terminus := path.back() as Vector2
	var closer: bool = terminus.distance_to(pond["center"]) < from.distance_to(pond["center"])
	return _check("goal deep in a pond yields a shore-approach partial path",
		closer and _legs_clear(g, from, path))


static func _test_goal_inside_solid_snaps() -> int:
	# The follow point can land inside a hedge; the goal must snap out and still path.
	var g := _grid([{ "a": Vector2(-150, 100), "b": Vector2(150, 100), "radius": 14.0 }])
	var to := Vector2(0, 100)  # dead center of the hedge
	var path := g.find_path(Vector2(0, -100), to, 6000)
	if path.is_empty():
		return _check("goal inside a solid snaps to nearest walkable", false)
	var near_wall: bool = (path.back() as Vector2).distance_to(to) < CELL * 4.0
	return _check("goal inside a solid snaps to nearest walkable", near_wall)


static func _test_smooth_collapses_visible_waypoints() -> int:
	var g := _grid([])
	# An open-field staircase of waypoints should collapse to just the last point.
	var staircase: Array = [Vector2(24, 0), Vector2(48, 24), Vector2(72, 24), Vector2(96, 48)]
	var out := g.smooth(Vector2.ZERO, staircase)
	return _check("smoothing collapses mutually-visible waypoints",
		out.size() == 1 and (out[0] as Vector2).is_equal_approx(Vector2(96, 48)))


static func _test_maze_fixture_is_solvable() -> int:
	# The acid test: the REAL maze world. Build solids exactly as the client does, then
	# assert the router can take the companion from its spawn to the heart at (0,0).
	var data := WorldData.load_json("res://tests/world_fixtures/maze.json")
	var ccfg: Dictionary = data.get("collision", {})
	var solids := Solids.build(data, [], ccfg)
	var g := NavGrid.build(solids, WorldData.bounds_rect(data),
		float(ccfg.get("body_radius", 6.0)), float(ccfg.get("margin", 2.0)), CELL)
	var spawn := WorldData.to_vec2(data["companion_spawn"])
	var heart := Vector2.ZERO
	var path := g.find_path(spawn, heart, 20000)
	if path.is_empty():
		return _check("maze: spawn -> heart path exists", false)
	var reached: bool = (path.back() as Vector2).distance_to(heart) < CELL * 2.0
	return _check("maze: spawn -> heart path exists and every leg is clear",
		reached and _legs_clear(g, spawn, path))
