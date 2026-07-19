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
var _stuck_time := 0.6
var _stuck_min_move := 4.0
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
	_max_expansions = int(cfg.get("max_expansions", _max_expansions))
	_goal_snap_radius = int(cfg.get("goal_snap_radius", _goal_snap_radius))


## Swap in the world's walkability (on world load, and again whenever solids change —
## the Ruin's rising slabs). Any cached path belongs to the old geometry, so it's dropped.
func set_grid(grid: NavGrid) -> void:
	_grid = grid
	reset()


func reset() -> void:
	_path.clear()
	_has_los = false
	_los_t = 0.0
	_repath_t = 0.0
	_stuck_t = 0.0
	_stuck_from = Vector2.INF


## The current route, for the debug overlay only.
func active_path() -> Array:
	return _path


## Given where the body is and where it wants to end up, return the point to steer
## toward THIS frame. Returns `goal` itself whenever a straight walk works (the common
## case); otherwise the next corner of a planned route around the obstacles.
func steer_target(pos: Vector2, goal: Vector2, delta: float) -> Vector2:
	if _grid == null:
		return goal
	# Close enough that arrival easing should take over — never route micro-distances.
	if pos.distance_to(goal) <= _direct_distance:
		_path.clear()
		_stuck_t = 0.0
		_stuck_from = Vector2.INF
		return goal

	_los_t -= delta
	_repath_t -= delta
	var los_tick := _los_t <= 0.0
	if los_tick:
		_los_t = _los_interval
		_has_los = _grid.line_clear(pos, goal)

	if _has_los:
		_path.clear()
		_stuck_t = 0.0
		_stuck_from = Vector2.INF
		return goal

	# Blocked. A body that means to move but barely does (pressed into a corner the
	# grid path didn't anticipate) forces a fresh plan past the throttle.
	var force := _update_stuck(pos, delta)

	var drifted := (not _path.is_empty()) and _path_goal.distance_to(goal) > _repath_target_drift
	if (_path.is_empty() or drifted or force) and (_repath_t <= 0.0 or force):
		_repath_t = _repath_interval
		plan_count += 1
		_path = _grid.find_path(pos, goal, _max_expansions, _goal_snap_radius)
		_path_goal = goal
	if _path.is_empty():
		# Nowhere to route from here (start couldn't be placed) — press on directly and
		# let the collision slide; the next plan attempt comes after the throttle.
		return goal

	# Advance past waypoints we've reached; on LOS ticks also skip every waypoint we can
	# already see straight to — continuous string-pulling that rounds the corners.
	while _path.size() > 1 and pos.distance_to(_path[0]) <= _waypoint_reach:
		_path.remove_at(0)
	if los_tick and _path.size() > 1:
		var far := -1
		for j in range(_path.size() - 1, 0, -1):
			if _grid.line_clear(pos, _path[j]):
				far = j
				break
		if far > 0:
			for _i in far:
				_path.remove_at(0)
	if _path.size() == 1 and pos.distance_to(_path[0]) <= _waypoint_reach:
		# Route exhausted at a partial-path terminus short of the goal (sealed pocket or
		# expansion cap): steer at the goal until the throttle lets us plan again.
		_path.clear()
		return goal
	return _path[0]


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
