class_name TestNavAgent
## Pure tests for the route-keeper — no nodes, no scene. Documents the steering
## contract: pass the goal straight through while the line is clear, route around
## walls when it isn't, throttle replanning, and never leave a body wedged in a
## pocket it could walk out of (the U-pocket sim reproduces the old stuck-forever
## follow bug and proves it fixed).

const CELL := 24.0
const BODY := 6.0
const MARGIN := 2.0


static func run_all() -> int:
	var fails := 0
	print("TestNavAgent")
	fails += _test_clear_los_passes_through()
	fails += _test_blocked_returns_reachable_waypoint()
	fails += _test_repath_is_throttled()
	fails += _test_grid_swap_drops_the_path()
	fails += _test_escapes_a_u_pocket()
	return fails


static func _check(name: String, ok: bool) -> int:
	print("  %s  %s" % [("PASS" if ok else "FAIL"), name])
	return 0 if ok else 1


static func _bounds() -> Rect2:
	return Rect2(Vector2(-500, -500), Vector2(1000, 1000))


static func _grid(solids: Array) -> NavGrid:
	return NavGrid.build(solids, _bounds(), BODY, MARGIN, CELL)


static func _agent(grid: NavGrid) -> NavAgent:
	var a := NavAgent.new({})
	a.set_grid(grid)
	return a


## A U of hedges around `inside`, open toward +y — the wedge shape that used to trap
## the follower forever when its person stood on the far side of the closed end.
static func _u_pocket() -> Array:
	return [
		{ "a": Vector2(-100, -60), "b": Vector2(100, -60), "radius": 14.0 },
		{ "a": Vector2(-100, -60), "b": Vector2(-100, 100), "radius": 14.0 },
		{ "a": Vector2(100, -60), "b": Vector2(100, 100), "radius": 14.0 },
	]


static func _test_clear_los_passes_through() -> int:
	var agent := _agent(_grid([{ "center": Vector2(300, 300), "radius": 20.0 }]))
	var out := agent.steer_target(Vector2.ZERO, Vector2(0, 200), 1.0 / 60.0)
	return _check("clear line of sight: goal passes through untouched",
		out.is_equal_approx(Vector2(0, 200)) and agent.active_path().is_empty())


static func _test_blocked_returns_reachable_waypoint() -> int:
	var g := _grid([{ "a": Vector2(-150, 100), "b": Vector2(150, 100), "radius": 14.0 }])
	var agent := _agent(g)
	var pos := Vector2(0, 0)
	var goal := Vector2(0, 220)  # straight line runs through the hedge
	var out := agent.steer_target(pos, goal, 1.0 / 60.0)
	return _check("blocked: steers at a visible waypoint, not the goal",
		not out.is_equal_approx(goal) and g.line_clear(pos, out))


static func _test_repath_is_throttled() -> int:
	var g := _grid([{ "a": Vector2(-150, 100), "b": Vector2(150, 100), "radius": 14.0 }])
	var agent := _agent(g)
	var goal := Vector2(0, 220)
	agent.steer_target(Vector2.ZERO, goal, 1.0 / 60.0)
	var after_first: int = agent.plan_count
	# A dozen more frames with the goal drifting a little (well under repath_target_drift)
	# must ride the cached path, not replan.
	for i in 12:
		agent.steer_target(Vector2.ZERO, goal + Vector2(i, 0), 1.0 / 60.0)
	return _check("small goal drift inside the throttle window does not replan",
		after_first == 1 and agent.plan_count == 1)


static func _test_grid_swap_drops_the_path() -> int:
	var g := _grid([{ "a": Vector2(-150, 100), "b": Vector2(150, 100), "radius": 14.0 }])
	var agent := _agent(g)
	agent.steer_target(Vector2.ZERO, Vector2(0, 220), 1.0 / 60.0)
	var had_path: bool = not agent.active_path().is_empty()
	agent.set_grid(_grid([]))  # the world's solids changed (a slab dropped)
	return _check("swapping the grid invalidates the cached path",
		had_path and agent.active_path().is_empty())


static func _test_escapes_a_u_pocket() -> int:
	# The acid sim: companion wedged in a U, player behind the closed end. Step a fake
	# body exactly the way CompanionView does — steer, walk, Solids.resolve — and it
	# must round the pocket and reach its person within a few simulated seconds.
	var solids := _u_pocket()
	var agent := _agent(_grid(solids))
	var pos := Vector2(0, 0)      # inside the U
	var player := Vector2(0, -200)  # beyond the closed end
	var speed := 64.0
	var dt := 1.0 / 60.0
	var reached := false
	for _frame in int(30.0 / dt):
		var steer := agent.steer_target(pos, player, dt)
		var to_target := steer - pos
		if to_target.length() > 2.0:
			pos += to_target.normalized() * speed * dt
		pos = Solids.resolve(pos, BODY, solids, _bounds(), MARGIN)
		if pos.distance_to(player) < 20.0:
			reached = true
			break
	return _check("escapes a U pocket and reaches the player (old bug, now dead)", reached)
