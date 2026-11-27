class_name NavAgent
extends RefCounted
## The companion's ROUTE-KEEPER: turns "I want to be at that point" into "step toward
## here right now", going around walls when a straight walk can't get there. Pure logic
## (no nodes), but deliberately stateful — it caches the current path and throttles its
## replanning — which is why it lives here and not in the stateless perception.
##
## The feel contract: DIRECT steering is the default. While the straight line to the
## goal is clear (checked on a small timer, not every frame) this returns the goal
## untouched, so in open ground the companion behaves exactly as it always has. Only
## when the line is blocked does it consult the NavGrid for a smoothed path, and even
## then it keeps re-checking ahead and skips every waypoint it can already see — so it
## rounds corners like a creature cutting across grass, not a unit tracing grid lines.

var plan_count := 0  # how many A* plans have run (read by tests; cheap telemetry)

var _grid: NavGrid = null
var _path: Array = []            # world-space waypoints still ahead of us
var _path_goal := Vector2.ZERO   # the goal the current path was planned for
var _has_los := false
var _los_t := 0.0                # countdown to the next line-of-sight check
var _repath_t := 0.0             # countdown until another plan is allowed
var _stuck_t := 0.0              # how long we've been barely moving while wanting to move
var _stuck_from := Vector2.INF   # where the stuck window started

var _direct_distance := 24.0
var _waypoint_reach := 12.0
var _los_interval := 0.15
var _repath_interval := 0.35
var _repath_target_drift := 60.0
var _stuck_time := 0.4
var _stuck_min_move := 4.0
var _fruitless_backoff := 1.0
var _max_expansions := 6000
var _goal_snap_radius := 4


func _init(cfg: Dictionary = {}) -> void:
	_direct_distance = float(cfg.get("direct_distance", _direct_distance))
	_waypoint_reach = float(cfg.get("waypoint_reach", _waypoint_reach))
	_los_interval = float(cfg.get("los_interval", _los_interval))
	_repath_interval = float(cfg.get("repath_interval", _repath_interval))
	_repath_target_drift = float(cfg.get("repath_target_drift", _repath_target_drift))
	_stuck_time = float(cfg.get("stuck_time", _stuck_time))
	_stuck_min_move = float(cfg.get("stuck_min_move", _stuck_min_move))
	_fruitless_backoff = float(cfg.get("fruitless_backoff", _fruitless_backoff))
	_max_expansions = int(cfg.get("max_expansions", _max_expansions))
	_goal_snap_radius = int(cfg.get("goal_snap_radius", _goal_snap_radius))


## Swap in the world's walkability (on world load, and again whenever solids change —
## the Ruin's rising slabs). Any cached path belongs to the old geometry, so it's dropped.
func set_grid(grid: NavGrid) -> void:
	_grid = grid
	reset()


func reset() -> void:
	_drop_route()
	_has_los = false
	_los_t = 0.0
	_repath_t = 0.0


## The current route, for the debug overlay only.
func active_path() -> Array:
	return _path


## Forget the current route and stuck window (the goal is direct, gone, or replaced).
## `_update_stuck` re-seeds `_stuck_t` from the INF sentinel, so this is the full reset.
func _drop_route() -> void:
	_path.clear()
	_stuck_from = Vector2.INF


## Given where the body is and where it wants to end up, return the point to steer
## toward THIS frame. Returns `goal` itself whenever a straight walk works (the common
## case); otherwise the next corner of a planned route around the obstacles.
##
## `detour_ratio` > 0 caps how far around the route may go, as a multiple of the
## straight-line distance (plus a couple of cells of slack, so rounding a nearby bench
## is never unfairly capped). A route past the cap is DECLINED — the caller steers
## straight, slides at the wall, and its own give-up (the wander stuck-guard) takes it
## from there. This is for idle, self-directed goals (wandering): ambling somewhere is
## not worth a trek around the maze, while follow/come keep routing unlimited.
func steer_target(pos: Vector2, goal: Vector2, delta: float, detour_ratio: float = 0.0) -> Vector2:
	if _grid == null:
		return goal
	# Close enough that arrival easing should take over — never route micro-distances.
	if pos.distance_to(goal) <= _direct_distance:
		_drop_route()
		return goal

	_los_t -= delta
	_repath_t -= delta
	var los_tick := _los_t <= 0.0
	if los_tick:
		_los_t = _los_interval
		_has_los = _grid.line_clear(pos, goal)

	if _has_los:
		_drop_route()
		return goal

	# Blocked. A body that means to move but barely does (pressed into a corner the
	# grid path didn't anticipate) forces a fresh plan ahead of the normal throttle —
	# but never ahead of the fruitless backoff: when planning itself keeps failing to
	# reach the goal (a sealed pocket), re-searching harder won't unwedge us, so those
	# retries are spaced out instead of burning a worst-case A* every stuck window.
	var force := _update_stuck(pos, delta)

	var drifted := (not _path.is_empty()) and _path_goal.distance_to(goal) > _repath_target_drift
	var want_plan := _path.is_empty() or drifted or force
	var may_plan := _repath_t <= 0.0 or (force and _repath_t <= _repath_interval)
	if want_plan and may_plan:
		plan_count += 1
		_path = _grid.find_path(pos, goal, _max_expansions, _goal_snap_radius)
		_path_goal = goal
		var reached := (not _path.is_empty()) \
			and (_path.back() as Vector2).distance_to(goal) <= _grid.cell_size() * 2.0
		_repath_t = _repath_interval if reached else _fruitless_backoff
		if detour_ratio > 0.0 and not _path.is_empty():
			var allowance := pos.distance_to(goal) * detour_ratio + _grid.cell_size() * 2.0
			if _route_length(pos) > allowance:
				_drop_route()
				_repath_t = _fruitless_backoff
				return goal
	if _path.is_empty():
		# Nowhere better to route from here — press on directly and let the collision
		# slide; the next plan attempt comes after the backoff.
		return goal

	# Consume the route from the front: drop every waypoint already reached, and on LOS
	# ticks every waypoint we can see straight past — continuous string-pulling, so the
	# body rounds corners instead of touching each one. A single slice keeps the
	# invariant visible: _path always starts at the next corner to steer at.
	var keep := 0
	while keep < _path.size() - 1 and pos.distance_to(_path[keep]) <= _waypoint_reach:
		keep += 1
	if los_tick:
		for j in range(_path.size() - 1, keep, -1):
			if _grid.line_clear(pos, _path[j]):
				keep = j
				break
	if keep > 0:
		_path = _path.slice(keep)
	if _path.size() == 1 and pos.distance_to(_path[0]) <= _waypoint_reach:
		# Route exhausted at a partial-path terminus short of the goal (sealed pocket or
		# expansion cap): steer at the goal until the backoff lets us plan again.
		_drop_route()
		return goal
	return _path[0]


## Total walking distance of the current route, from `pos` through every waypoint.
func _route_length(pos: Vector2) -> float:
	var length := 0.0
	var prev := pos
	for p in _path:
		length += prev.distance_to(p)
		prev = p
	return length


## While route-following, watch for a body that wants to move but isn't. Returns true
## once per stuck episode: when `stuck_time` has passed with less than `stuck_min_move`
## of actual travel — the signal to replan immediately from wherever we're wedged.
func _update_stuck(pos: Vector2, delta: float) -> bool:
	if _stuck_from == Vector2.INF:
		_stuck_from = pos
		_stuck_t = 0.0
		return false
	if pos.distance_to(_stuck_from) >= _stuck_min_move:
		_stuck_from = pos
		_stuck_t = 0.0
		return false
	_stuck_t += delta
	if _stuck_t >= _stuck_time:
		_stuck_from = pos
		_stuck_t = 0.0
		return true
	return false
