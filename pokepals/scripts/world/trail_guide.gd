class_name TrailGuide
extends RefCounted
## A companion LEADING YOU along an authored trail, as pure logic (state in, state out): Drifthallow's
## snow-hare tracks, which only a fox can read. The world authors a scent spot (`start`) and a list of
## waypoints (`trail`, the last one is the den); this decides, every frame, what the companion should be
## doing about it. It draws nothing and knows no nodes: the TracksDirector feeds it positions and the
## worn form, and turns the answer into a "guide" command, paw-prints and a hint.
##
## The cycle:
##   IDLE     nothing happening. If the companion wears the trail's `species`, it stands within
##            `scent_radius` of where the trail resumes, and you are within `player_radius` of it, the
##            nose goes down: SNIFF.
##   SNIFF    a beat of reading the snow (`sniff_seconds`), then it sets off. Cancelled if the shape or
##            the company is lost.
##   LEAD     walks the waypoints in order, leaving a print every `print_spacing` px it travels. Reaching
##            one (`waypoint_reach`) moves on to the next; the last is the DEN, and reaching it ends the
##            trail (`done`).
##   WAIT     you've fallen further than `wait_distance` behind: it stops and waits, facing you, until
##            you're back within `resume_distance`. Never a fail state: it waits as long as it takes.
##
## It is kind about being interrupted. If the shape is lost (the companion shifts into a cat, say) the
## lead lapses back to IDLE but PROGRESS IS KEPT: wear the fox again by where the trail stopped and it
## picks up from there. If you wander more than `give_up_distance` away it lets go too (so the companion
## goes back to following you rather than standing out in the snow forever). A waypoint it can't make
## headway toward for `waypoint_patience` seconds (a wall it can't route round) is simply skipped.
##
## All numbers come from the secret's `reveal` block in the world spec (Drifthallow's data), with the
## defaults below as a safety net only.

enum Phase { IDLE, SNIFF, LEAD, WAIT, DONE }

const DEFAULTS := {
	"species": "fox",
	"scent_radius": 150.0,      # how near the trail's resume point the companion must be to catch the scent
	"player_radius": 260.0,     # ...and how near you must be, so it never sets off with nobody about
	"sniff_seconds": 1.4,
	"waypoint_reach": 26.0,
	"wait_distance": 190.0,     # you're this far behind: it waits
	"resume_distance": 110.0,   # ...until you're this close
	"give_up_distance": 720.0,  # you're this far away: the lead lapses
	"print_spacing": 20.0,      # a paw-print every this many px it travels
	"waypoint_patience": 14.0,  # seconds without headway toward a waypoint before skipping it
	"progress_eps": 3.0,
}

var phase := Phase.IDLE
## Index of the waypoint it is heading for (0..trail.size()); == trail.size() once done.
var next_index := 0

var _start := Vector2.ZERO
var _trail: Array = []          # Array[Vector2]
var _cfg: Dictionary = {}
var _sniff_left := 0.0
var _last_print := Vector2.ZERO
var _has_print := false
var _best := INF                # closest we've come to the current waypoint
var _stalled := 0.0             # seconds without improving on it


## start: the scent spot. trail: the waypoints from there to the den (Vector2s, or [x, y] pairs). cfg:
## the secret's reveal block (see DEFAULTS for the keys).
func _init(start: Vector2, trail: Array, cfg: Dictionary = {}) -> void:
	_start = start
	for p in trail:
		_trail.append(p if p is Vector2 else Vector2(float(p[0]), float(p[1])))
	_cfg = DEFAULTS.duplicate()
	for k in cfg:
		if DEFAULTS.has(k):
			_cfg[k] = cfg[k]


func species() -> String:
	return String(_cfg["species"])


func is_done() -> bool:
	return phase == Phase.DONE


## The den: where the trail ends (the last waypoint), or the scent spot if the trail is empty.
func den() -> Vector2:
	return _trail[-1] if not _trail.is_empty() else _start


## 0..1, how far along the trail the companion has led you (a reached waypoint counts).
func fraction() -> float:
	if _trail.is_empty():
		return 1.0 if phase == Phase.DONE else 0.0
	return float(next_index) / float(_trail.size())


## Where the trail resumes from: the scent spot until a waypoint has been reached, then the last one
## reached. This is the place the companion must stand at (in the right shape) to pick the scent up.
func resume_point() -> Vector2:
	return _start if next_index <= 0 else _trail[mini(next_index, _trail.size()) - 1]


## Advance by `delta`. Returns what the director should do this frame:
##   command: "" (nothing: let it live), "guide" (issue a guide order to `target`; `hold` says wait)
##   target:  the point to head for / stand at
##   hold:    true while waiting for you to catch up (or sniffing)
##   prints:  [Vector2] the companion's feet where a paw-print should be left this frame
##   events:  [String] one-shot moments: "sniff" (nose goes down), "set_off", "reached" (a waypoint),
##            "wait" (began waiting), "resume", "lost" (the shape or company was lost), "done"
func update(delta: float, companion_pos: Vector2, player_pos: Vector2, form_species: String) -> Dictionary:
	var out := { "command": "", "target": companion_pos, "hold": false, "prints": [], "events": [] }
	if phase == Phase.DONE or _trail.is_empty():
		return out
	var right_shape := form_species == species()
	var player_gap := companion_pos.distance_to(player_pos)

	match phase:
		Phase.IDLE:
			var anchor := resume_point()
			if right_shape \
					and companion_pos.distance_to(anchor) <= float(_cfg["scent_radius"]) \
					and player_pos.distance_to(anchor) <= float(_cfg["player_radius"]):
				phase = Phase.SNIFF
				_sniff_left = float(_cfg["sniff_seconds"])
				out["events"].append("sniff")
		Phase.SNIFF:
			if not right_shape or player_pos.distance_to(resume_point()) > float(_cfg["player_radius"]) * 1.5:
				phase = Phase.IDLE
				out["events"].append("lost")
			else:
				_sniff_left -= delta
				out["command"] = "guide"
				out["hold"] = true
				out["target"] = companion_pos
				if _sniff_left <= 0.0:
					phase = Phase.LEAD
					_has_print = false
					_reset_headway()
					out["events"].append("set_off")
		Phase.LEAD, Phase.WAIT:
			if not right_shape or player_gap > float(_cfg["give_up_distance"]):
				phase = Phase.IDLE
				out["events"].append("lost")
				return out
			var target: Vector2 = _trail[next_index]
			if phase == Phase.LEAD and player_gap > float(_cfg["wait_distance"]):
				phase = Phase.WAIT
				out["events"].append("wait")
			elif phase == Phase.WAIT and player_gap <= float(_cfg["resume_distance"]):
				phase = Phase.LEAD
				out["events"].append("resume")
			if phase == Phase.WAIT:
				out["command"] = "guide"
				out["hold"] = true
				out["target"] = companion_pos
				return out
			# LEAD
			out["command"] = "guide"
			out["target"] = target
			_maybe_print(companion_pos, out)
			if companion_pos.distance_to(target) <= float(_cfg["waypoint_reach"]):
				_advance(out)
			else:
				_watch_headway(delta, companion_pos.distance_to(target), out)
	return out


func _advance(out: Dictionary) -> void:
	next_index += 1
	_reset_headway()
	if next_index >= _trail.size():
		phase = Phase.DONE
		out["events"].append("reached")
		out["events"].append("done")
		out["command"] = ""
	else:
		out["events"].append("reached")


func _reset_headway() -> void:
	_best = INF
	_stalled = 0.0


## Give up on a waypoint we can't get nearer to (a wall the routing can't round): skip to the next.
func _watch_headway(delta: float, dist: float, out: Dictionary) -> void:
	if dist < _best - float(_cfg["progress_eps"]):
		_best = dist
		_stalled = 0.0
		return
	_stalled += delta
	if _stalled >= float(_cfg["waypoint_patience"]):
		_advance(out)


func _maybe_print(pos: Vector2, out: Dictionary) -> void:
	if not _has_print:
		_has_print = true
		_last_print = pos
		return
	if pos.distance_to(_last_print) >= float(_cfg["print_spacing"]):
		_last_print = pos
		out["prints"].append(pos)
