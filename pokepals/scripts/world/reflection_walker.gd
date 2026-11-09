class_name ReflectionWalker
extends RefCounted
## Stillglass's secret, as pure logic (state in, state out): your companion's REFLECTION, which is not
## quite your companion. Stand your companion at the lake's edge and, after it settles, its reflection
## turns into a different animal and WALKS OFF along the shore, a little way ahead of you, and you follow
## it step for step to the place where the real stone surfaces. It draws nothing and knows no nodes: the
## ReflectionDirector feeds it where you and your companion are and turns the answer into a walking
## image on the water, a gaze, a gentle order for the companion, and a hint.
##
## The cycle:
##   MIRROR  nothing special: the lake just mirrors your companion. If you linger near where the walk
##           resumes (`player_radius`, moving under `linger_speed` for `linger_seconds`) and your companion
##           is not yet at the edge (`edge_radius`), it is asked to go there by itself ("approach"). Once it
##           is at the edge, you are near and it stands settled (under `settle_speed`) for `settle_seconds`,
##           it begins to TURN. `gather` (0..1) rises while it settles, so the water can stir first.
##   TURN    `turn_seconds`: the image of the companion lets go and a different animal forms in its place.
##           The companion stands and watches. If you both wander off it quietly goes back to MIRROR.
##   WALK    the reflection walks the authored shore path at `pace`, a little ahead of you, one waypoint
##           after the next. The last waypoint is where the stone surfaces (DONE).
##   WAIT    you have fallen further than `wait_distance` behind it: it stands still until you are back
##           within `resume_distance`. Never a fail state; it waits as long as it takes ("step for step").
##   DONE    it stopped over the last waypoint. `done_time` counts up from there.
##
## It is kind about being interrupted. If your companion leaves the shore (`companion_radius` from the
## reflection) or you wander far off (`give_up_distance`), the reflection goes back to mirroring, but the
## PROGRESS IS KEPT: it stays where it had got to, and standing your companion at the edge THERE picks the
## walk up again from that point (the same kindness as Drifthallow's trail).
##
## NOTICING (`notice`, separate from the cycle): while the walk is not under way and you come within range
## of where it resumes, the companion, in any shape, stops and points toward the water there for a moment,
## then cools down; range and frequency scale with bond, like the Riverbank's salamander points.
##
## All numbers come from the secret's `reveal` block in the world spec, with the defaults below as a safety
## net only.

enum Phase { MIRROR, TURN, WALK, WAIT, DONE }

const DEFAULTS := {
	"edge_radius": 190.0,        # your companion this near the resume point counts as "at the edge" (generous)
	"player_radius": 280.0,      # ...and you this near, so it never sets off with nobody about
	"linger_seconds": 1.2,       # you have lingered near the edge this long: the companion goes to it
	"linger_speed": 34.0,        # ...moving slower than this
	"approach_offset": [0.0, -26.0],  # where, relative to the resume point, the companion goes to stand
	"settle_seconds": 1.0,       # your companion stands still at the edge this long, and the water turns
	"settle_speed": 14.0,        # ...slower than this counts as still
	"turn_seconds": 1.6,
	"pace": 68.0,                # px/s the reflection walks (you walk at 118)
	"wait_distance": 200.0,      # you are this far behind it: it waits
	"resume_distance": 120.0,    # ...until you are this close
	"companion_radius": 340.0,   # your companion further than this from the reflection: it lets go
	"give_up_distance": 760.0,   # you further than this: it lets go
	"waypoint_reach": 8.0,
	"done_hold": 5.0,            # how long it lingers over the stone before the lake lets it go
	"notice_range_low": 280.0,
	"notice_range_high": 620.0,
	"notice_cooldown_low": 16.0,
	"notice_cooldown_high": 6.0,
	"notice_hold": 2.5,
}

var phase := Phase.MIRROR
## Index of the waypoint it is heading for (0..trail.size()); == trail.size() once done.
var next_index := 0
## Where the reflection's feet are on the waterline right now (where the walk resumes from).
var pos := Vector2.ZERO
## The way it is facing (a unit vector, along the shore).
var face := Vector2.RIGHT
## Seconds since it stopped over the stone (0 until DONE).
var done_time := 0.0

var _start := Vector2.ZERO
var _trail: Array = []          # Array[Vector2]
var _cfg: Dictionary = {}
var _settle := 0.0
var _linger := 0.0
var _turn_t := 0.0
var _gather_said := false
var _notice_cd := 0.0
var _notice_left := 0.0


## start: where the walk first resumes (a point on the waterline). trail: the waypoints from there to the
## stone (Vector2s, or [x, y] pairs; the last is where it surfaces). cfg: the secret's reveal block.
func _init(start: Vector2, trail: Array, cfg: Dictionary = {}) -> void:
	_start = start
	pos = start
	for p in trail:
		_trail.append(p if p is Vector2 else Vector2(float(p[0]), float(p[1])))
	_cfg = DEFAULTS.duplicate()
	for k in cfg:
		if DEFAULTS.has(k):
			_cfg[k] = cfg[k]
	if not _trail.is_empty():
		face = ((_trail[0] as Vector2) - pos).normalized() if (_trail[0] as Vector2).distance_to(pos) > 0.5 else Vector2.RIGHT


func is_done() -> bool:
	return phase == Phase.DONE


## True while the reflection is its own creature on the water (turning into it, walking, waiting, or
## standing over the stone), as opposed to simply mirroring your companion.
func is_independent() -> bool:
	return phase != Phase.MIRROR


## Where the walk resumes from: the start until it has moved, then wherever it had got to.
func resume_point() -> Vector2:
	return pos


## The stone's place: the last waypoint (or the start for an empty trail).
func end_point() -> Vector2:
	return _trail[-1] if not _trail.is_empty() else _start


## 0..1, how far along the shore it has walked.
func fraction() -> float:
	if _trail.is_empty():
		return 1.0 if phase == Phase.DONE else 0.0
	return float(next_index) / float(_trail.size())


## How far the turn has come (0..1); 1 once it is walking.
func turn_fraction() -> float:
	if phase == Phase.TURN:
		return clampf(_turn_t, 0.0, 1.0)
	return 0.0 if phase == Phase.MIRROR else 1.0


## How far the water has stirred toward turning (0..1), while your companion settles at the edge.
func gather_fraction() -> float:
	return clampf(_settle / maxf(0.01, float(_cfg["settle_seconds"])), 0.0, 1.0) if phase == Phase.MIRROR else 0.0


## Start the whole walk afresh (a found secret keeps the toy: another walk, no stone).
func reset() -> void:
	phase = Phase.MIRROR
	next_index = 0
	pos = _start
	done_time = 0.0
	_settle = 0.0
	_linger = 0.0
	_turn_t = 0.0
	_gather_said = false


func _offset() -> Vector2:
	var o: Array = _cfg["approach_offset"]
	return Vector2(float(o[0]), float(o[1]))


## Advance by `delta`. Returns what the director should do this frame:
##   command: "" (nothing: let it live) | "approach" (send the companion to `target`, the edge) |
##            "hold" (the companion stands still where it is) | "follow" (the companion walks beside the
##            reflection: `target` is the point, `speed` the pace)
##   target / speed: for those orders
##   moving: the reflection is walking this frame (its feet animate)
##   events: one-shot moments: "gather" (the water stirs), "turn", "set_off", "wait", "resume", "reached",
##           "lost" (it let go; progress kept), "done"
func update(delta: float, companion_pos: Vector2, companion_speed: float, player_pos: Vector2, player_speed: float) -> Dictionary:
	var out := { "command": "", "target": companion_pos, "speed": float(_cfg["pace"]), "moving": false, "events": [] }
	if _trail.is_empty():
		return out
	match phase:
		Phase.MIRROR:
			_update_mirror(delta, companion_pos, companion_speed, player_pos, player_speed, out)
		Phase.TURN:
			_update_turn(delta, companion_pos, player_pos, out)
		Phase.WALK, Phase.WAIT:
			_update_walk(delta, companion_pos, player_pos, out)
		Phase.DONE:
			done_time += delta
	return out


func _update_mirror(delta: float, companion_pos: Vector2, companion_speed: float, player_pos: Vector2, player_speed: float, out: Dictionary) -> void:
	var anchor := pos
	var player_near := player_pos.distance_to(anchor) <= float(_cfg["player_radius"])
	var at_edge := companion_pos.distance_to(anchor) <= float(_cfg["edge_radius"])
	if player_near and player_speed < float(_cfg["linger_speed"]):
		_linger += delta
	else:
		_linger = maxf(0.0, _linger - delta * 2.0)
	if _linger >= float(_cfg["linger_seconds"]) and not at_edge:
		# You have stopped by the water: your companion does its part and goes to stand at the edge.
		out["command"] = "approach"
		out["target"] = anchor + _offset()
	var settled := player_near and at_edge and companion_speed < float(_cfg["settle_speed"])
	if settled:
		_settle += delta
		if not _gather_said and _settle >= 0.3:
			_gather_said = true
			out["events"].append("gather")
	else:
		_settle = maxf(0.0, _settle - delta * 1.5)
		if _settle <= 0.0:
			_gather_said = false
	if _settle >= float(_cfg["settle_seconds"]):
		phase = Phase.TURN
		_turn_t = 0.0
		_settle = 0.0
		_linger = 0.0
		out["events"].append("turn")
		out["command"] = "hold"


func _update_turn(delta: float, companion_pos: Vector2, player_pos: Vector2, out: Dictionary) -> void:
	if companion_pos.distance_to(pos) > float(_cfg["edge_radius"]) * 1.6 or player_pos.distance_to(pos) > float(_cfg["player_radius"]) * 1.6:
		phase = Phase.MIRROR
		out["events"].append("lost")
		return
	out["command"] = "hold"
	_turn_t += delta / maxf(0.05, float(_cfg["turn_seconds"]))
	if _turn_t >= 1.0:
		phase = Phase.WALK
		out["events"].append("set_off")


func _update_walk(delta: float, companion_pos: Vector2, player_pos: Vector2, out: Dictionary) -> void:
	if companion_pos.distance_to(pos) > float(_cfg["companion_radius"]) or player_pos.distance_to(pos) > float(_cfg["give_up_distance"]):
		phase = Phase.MIRROR
		_settle = 0.0
		_linger = 0.0
		out["events"].append("lost")
		return
	var gap := player_pos.distance_to(pos)
	if phase == Phase.WALK and gap > float(_cfg["wait_distance"]):
		phase = Phase.WAIT
		out["events"].append("wait")
	elif phase == Phase.WAIT and gap <= float(_cfg["resume_distance"]):
		phase = Phase.WALK
		out["events"].append("resume")
	out["target"] = pos
	if phase == Phase.WAIT:
		out["command"] = "follow"
		out["speed"] = 0.0
		return
	out["command"] = "follow"
	var target: Vector2 = _trail[next_index]
	var to := target - pos
	var step := float(_cfg["pace"]) * delta
	if to.length() > 0.001:
		face = to.normalized()
	if to.length() <= maxf(step, float(_cfg["waypoint_reach"])):
		pos = target
		next_index += 1
		out["events"].append("reached")
		if next_index >= _trail.size():
			phase = Phase.DONE
			done_time = 0.0
			out["events"].append("done")
			out["command"] = ""
			return
	else:
		pos += face * step
	out["moving"] = true


## The companion NOTICING the water where the walk resumes (see the class doc). Call every frame with the
## bond (0..1). Returns { point: bool (hold a point this frame), target: the spot, started: true on the
## frame a new point begins }. Only while the walk is not under way.
func notice(delta: float, player_pos: Vector2, bond: float) -> Dictionary:
	var out := { "point": false, "target": pos, "started": false }
	if phase != Phase.MIRROR or _trail.is_empty():
		_notice_left = 0.0
		return out
	var b := clampf(bond, 0.0, 1.0)
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left > 0.0:
			out["point"] = true
		else:
			_notice_cd = lerpf(float(_cfg["notice_cooldown_low"]), float(_cfg["notice_cooldown_high"]), b)
		return out
	if _notice_cd > 0.0:
		_notice_cd = maxf(0.0, _notice_cd - delta)
		return out
	var reach := lerpf(float(_cfg["notice_range_low"]), float(_cfg["notice_range_high"]), b)
	if player_pos.distance_to(pos) <= reach:
		_notice_left = float(_cfg["notice_hold"])
		out["point"] = true
		out["started"] = true
	return out
