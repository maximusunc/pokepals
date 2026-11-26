class_name DoorwayGate
extends RefCounted
## A DOOR THAT ONLY OPENS FOR YOUR COMPANION, as pure logic (state in, state out): Lingerlong's Late Arch. One
## arch out in the pool shows an evening sky in its doorway. Walk through it yourself and you come out the other
## side, like any arch. Send your companion (a tap on the arch, or "Go look" when you are near) and it trots to
## the threshold, sniffs, and steps INTO the picture: then, for as long as it waits in there, the doorway is
## really open, and walking into it from the front takes you both to the evening terrace. A second arch on the
## terrace (showing the afternoon) always takes you back. This draws nothing and knows no nodes: the
## DoorwayDirector feeds it positions, the bond and the player's pending order, and turns the answer into a
## "guide" command, a placed or hidden body, the small figure drawn in the doorway, and a hint.
##
##   IDLE      nothing happening. `ask` starts a trip (from anywhere: the companion goes to the arch).
##   GO        it trots to the threshold, just in front of the arch. A Pet is enjoyed and the trip carries on;
##             a Call ends it ("called_off"); if it cannot get there in time it gives up ("lost_way").
##   SNIFF     it stands at the threshold looking into the picture, a moment (shorter as the bond deepens).
##   STEP_IN   it walks under the arch (the body, first) and on into the picture (the figure, after): the body is
##             hidden from the `vanish` point of the step on, and its mind is paused until it is back.
##   INSIDE    it waits on the painted terrace, turned to look back at you, for `hold` seconds (longer as the
##             bond deepens). The door is OPEN: walking into the doorway from the front is the crossing
##             ("through"). A Call brings it out early ("called_out").
##   STEP_OUT  it walks back out of the picture and under the arch to the threshold, and is yours again
##             ("came_out" if it gave up waiting, or after a Call).
## No failure anywhere: whatever happens, ask again.
##
## THE CROSSINGS (`crosses`): a player "steps into" a doorway when, between two frames, their feet cross a line
## just inside it (`line` px north of the arch's foot) while within `door_half_width` of its middle. The Late Arch
## counts only from the front (south to north) and only while the door is open; the terrace's arch counts from
## either side, always, so the way back can never be closed (a player who reconnects on the terrace walks
## straight back). A jump between frames longer than `step_max` is a teleport, never a step.
##
## BOND shapes it (low..high pairs in the data, blended by bond 0..1): how long the door is held (`hold`), how
## long it sniffs (`sniff`), and the NOTICE (`notice_range`, `notice_cooldown`): as you come near the Late Arch
## the companion stops and points at it for `notice_hold` seconds, then not again for a while.
##
## All numbers come from the spec's `doorway` block; DEFAULTS are a safety net only.

enum Phase { IDLE, GO, SNIFF, STEP_IN, INSIDE, STEP_OUT }

const DEFAULTS := {
	"ask_range": 380.0,          # "Go look" is offered while you are this near the Late Arch
	"tap_radius": 48.0,          # a tap this near the middle of its doorway is an order
	"threshold": 18.0,           # where the companion stops: this far in front (south) of the arch's foot
	"reach": 10.0,               # arrived at the threshold
	"go_speed": 92.0,
	"run_speed": 128.0,          # further than `run_distance` from the threshold it runs
	"run_distance": 240.0,
	"go_patience": 8.0,          # seconds of slack, on top of the time the way takes, before it gives up
	"pet_pause": 2.5,            # a Pet is enjoyed: leave it alone this long, then carry on
	"sniff_low": 1.8,            # seconds at the threshold, fresh...
	"sniff_high": 1.0,           # ...and bonded
	"step_seconds": 1.6,         # under the arch and into the picture
	"vanish": 0.3,               # the fraction of the step at which the body is gone and the figure takes over
	"hold_low": 7.0,             # seconds the door is held open, fresh...
	"hold_high": 16.0,           # ...and bonded
	"out_seconds": 1.4,          # out of the picture and back to the threshold
	"cooldown": 1.2,             # after it is back (or you went through), before the next ask
	"door_half_width": 20.0,     # how far off the doorway's middle a step still counts
	"line": 4.0,                 # the crossing line, this far north of the arch's foot
	"step_max": 48.0,            # a move longer than this between two frames is a teleport, not a step
	"notice_range_low": 260.0,
	"notice_range_high": 560.0,
	"notice_cooldown_low": 16.0,
	"notice_cooldown_high": 7.0,
	"notice_hold": 2.4,
}

var phase := Phase.IDLE

var _cfg: Dictionary = {}
var _at := Vector2.ZERO          # the Late Arch's foot (the middle of its doorway, on the floor)
var _back_at := Vector2.ZERO     # the terrace arch's foot
var _t := 0.0
var _go_time := 0.0
var _go_budget := -1.0
var _pet_left := 0.0
var _hold := 0.0
var _cooldown := 0.0
var _bond := 0.0
var _notice_cd := 0.0
var _notice_left := 0.0
var _out_reason := ""


## at / back_at: the two arches' feet. cfg: the spec's doorway block (unknown keys are ignored).
func _init(at: Vector2, back_at: Vector2, cfg: Dictionary = {}) -> void:
	_at = at
	_back_at = back_at
	_cfg = DEFAULTS.duplicate(true)
	for k in cfg:
		if DEFAULTS.has(k):
			_cfg[k] = cfg[k]


func cfg(key: String) -> Variant:
	return _cfg[key]


func arch_foot() -> Vector2:
	return _at


func back_foot() -> Vector2:
	return _back_at


## Where the companion waits before it goes in: just in front of the arch.
func threshold() -> Vector2:
	return _at + Vector2(0.0, float(_cfg["threshold"]))


## The middle of the Late Arch's doorway (what the companion looks at, and what a tap aims for).
func door_middle() -> Vector2:
	return _at + Vector2(0.0, -42.0)


## Blend a low..high pair of the data by bond.
func at_bond(key: String, bond: float) -> float:
	return lerpf(float(_cfg[key + "_low"]), float(_cfg[key + "_high"]), clampf(bond, 0.0, 1.0))


func is_busy() -> bool:
	return phase != Phase.IDLE


## Whether the door is open right now (the companion is waiting in the picture).
func is_open() -> bool:
	return phase == Phase.INSIDE


## Whether the body is under the director's direct control (placed, its mind paused).
func is_controlled() -> bool:
	return phase == Phase.STEP_IN or phase == Phase.INSIDE or phase == Phase.STEP_OUT


## Whether the director should draw the small figure in the doorway (and keep the arch redrawing).
func shows_figure() -> bool:
	return is_controlled()


## Whether a "Go look" can start a trip now (idle, past the cooldown).
func can_ask() -> bool:
	return phase == Phase.IDLE and _cooldown <= 0.0


## Whether `p` is near enough the Late Arch for "Go look" to be on offer.
func in_ask_range(p: Vector2) -> bool:
	return p.distance_to(_at) <= float(_cfg["ask_range"])


## Whether a tap at world point `w` is on the Late Arch (its doorway, or the arch round it).
func is_tap_on_arch(w: Vector2) -> bool:
	return w.distance_to(door_middle()) <= float(_cfg["tap_radius"])


## Seconds the door stays open, at this bond.
func hold_for(bond: float) -> float:
	return at_bond("hold", bond)


## Seconds left before it gives up waiting (0 unless the door is open).
func open_left() -> float:
	return maxf(0.0, _hold - _t) if phase == Phase.INSIDE else 0.0


## Start a trip. False when busy or cooling down.
func ask(bond: float) -> bool:
	if not can_ask():
		return false
	_bond = bond
	phase = Phase.GO
	_t = 0.0
	_go_time = 0.0
	_go_budget = -1.0
	_pet_left = 0.0
	return true


## Drop whatever is happening, at once (the world is torn down, or the player went back to the plaza).
func cancel() -> void:
	phase = Phase.IDLE
	_t = 0.0


## Whether a move from `prev` to `cur` steps into the doorway of an arch whose foot is `foot`: across the line
## `line` px north of the foot, within `half_w` of the middle, northward (or either way when `both_ways`). A move
## longer than `step_max` is a teleport and never counts.
static func crosses(prev: Vector2, cur: Vector2, foot: Vector2, half_w: float, line: float, both_ways: bool, step_max: float) -> bool:
	if not prev.is_finite() or prev.distance_to(cur) > step_max:
		return false
	var ly := foot.y - line
	var north := prev.y > ly and cur.y <= ly
	var south := both_ways and prev.y < ly and cur.y >= ly
	if not (north or south):
		return false
	# where the step crossed the line, so a quick diagonal step is judged where it went through
	var u := clampf((ly - prev.y) / (cur.y - prev.y), 0.0, 1.0) if not is_equal_approx(cur.y, prev.y) else 1.0
	return absf(lerpf(prev.x, cur.x, u) - foot.x) <= half_w


## One frame. `ctx`: companion_pos, player_pos, player_prev (Vector2: last frame's, INF at first), bond (0..1),
## pending (the player's order the brain has not taken yet: "come", "pet" or ""). Returns:
##   command:  "guide" (issue the guide order to `target` at `speed`; `hold` = stand still) or ""
##   target, speed, hold
##   look:     a point the companion gazes at (its ears up), or Vector2.INF
##   control:  the director places the body this frame (`body`: { pos, hidden })
##   figure:   { k: 0 (at the arch's foot) .. 1 (on the painted terrace), facing: "up" | "down", walking: bool }
##             while the small figure is drawn in the doorway, else {}
##   open:     the door is open (glow it)
##   through:  the player stepped into the open doorway this frame: take them both to the terrace
##   back:     the player stepped into the terrace arch's doorway this frame: take them both back
##   events:   strings for the director's cues and lines
func update(delta: float, ctx: Dictionary) -> Dictionary:
	var out := {
		"command": "", "target": Vector2.ZERO, "speed": 0.0, "hold": false, "look": Vector2.INF,
		"control": false, "body": {}, "figure": {}, "open": false, "through": false, "back": false, "events": [],
	}
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	var player: Vector2 = ctx["player_pos"]
	var prev: Vector2 = ctx.get("player_prev", Vector2.INF)
	var half := float(_cfg["door_half_width"])
	var line := float(_cfg["line"])
	var step_max := float(_cfg["step_max"])
	# The way back is always open, whatever else is happening.
	if crosses(prev, player, _back_at, half, line, true, step_max):
		out["back"] = true
		out["events"].append("back")
		if phase != Phase.IDLE:
			cancel()
		_cooldown = float(_cfg["cooldown"])
		return out
	var through_arch := crosses(prev, player, _at, half, line, false, step_max)
	if phase == Phase.IDLE:
		if through_arch:
			out["events"].append("plain_through")   # the door is shut: you come out the other side
		return out
	_t += delta
	var companion: Vector2 = ctx["companion_pos"]
	var pending := String(ctx.get("pending", ""))
	_bond = float(ctx.get("bond", _bond))
	var thr := threshold()
	match phase:
		Phase.GO:
			if pending == "come":
				out["events"].append("called_off")
				cancel()
				return out
			if pending == "pet":
				_pet_left = float(_cfg["pet_pause"])
			var far := companion.distance_to(thr)
			if _go_budget < 0.0:
				_go_budget = float(_cfg["go_patience"]) + far / float(_cfg["go_speed"]) * 1.6
			if _pet_left > 0.0:
				_pet_left -= delta   # enjoying it: no orders, and the patience clock waits
			else:
				_go_time += delta
				out["command"] = "guide"
				out["target"] = thr
				out["speed"] = float(_cfg["run_speed"]) if far > float(_cfg["run_distance"]) else float(_cfg["go_speed"])
				if _go_time >= _go_budget:
					out["command"] = ""
					out["events"].append("lost_way")
					cancel()
					return out
			if through_arch:
				out["events"].append("plain_through")
			if far <= float(_cfg["reach"]):
				phase = Phase.SNIFF
				_t = 0.0
				out["events"].append("sniff")
		Phase.SNIFF:
			if pending == "come":
				out["events"].append("called_off")
				cancel()
				return out
			out["command"] = "guide"
			out["target"] = thr
			out["hold"] = true
			out["look"] = door_middle()
			if through_arch:
				out["events"].append("plain_through")
			if _t >= at_bond("sniff", _bond):
				phase = Phase.STEP_IN
				_t = 0.0
		Phase.STEP_IN:
			var dur := maxf(0.05, float(_cfg["step_seconds"]))
			var u := clampf(_t / dur, 0.0, 1.0)
			var vanish := clampf(float(_cfg["vanish"]), 0.05, 0.95)
			out["control"] = true
			if u < vanish:
				out["body"] = { "pos": thr.lerp(_at, u / vanish), "hidden": false }
			else:
				out["body"] = { "pos": _at, "hidden": true }
				out["figure"] = { "k": (u - vanish) / (1.0 - vanish), "facing": "up", "walking": true }
			if through_arch:
				out["events"].append("plain_through")   # not open yet: a moment early
			if u >= 1.0:
				phase = Phase.INSIDE
				_t = 0.0
				_hold = hold_for(_bond)
				out["events"].append("inside")
		Phase.INSIDE:
			out["control"] = true
			out["open"] = true
			out["body"] = { "pos": _at, "hidden": true }
			out["figure"] = { "k": 1.0, "facing": "down", "walking": false }
			if through_arch:
				out["through"] = true
				out["events"].append("through")
				phase = Phase.IDLE
				_t = 0.0
				_cooldown = float(_cfg["cooldown"])
				return out
			if pending == "come":
				_out_reason = "called_out"
				phase = Phase.STEP_OUT
				_t = 0.0
			elif _t >= _hold:
				_out_reason = "came_out"
				phase = Phase.STEP_OUT
				_t = 0.0
		Phase.STEP_OUT:
			var dur2 := maxf(0.05, float(_cfg["out_seconds"]))
			var u2 := clampf(_t / dur2, 0.0, 1.0)
			var appear := 1.0 - clampf(float(_cfg["vanish"]), 0.05, 0.95)
			out["control"] = true
			if u2 < appear:
				out["body"] = { "pos": _at, "hidden": true }
				out["figure"] = { "k": 1.0 - u2 / appear, "facing": "down", "walking": true }
			else:
				out["body"] = { "pos": _at.lerp(thr, (u2 - appear) / (1.0 - appear)), "hidden": false }
			if through_arch:
				out["events"].append("plain_through")   # it is on its way out: the door has closed
			if u2 >= 1.0:
				out["events"].append(_out_reason if _out_reason != "" else "came_out")
				phase = Phase.IDLE
				_t = 0.0
				_cooldown = float(_cfg["cooldown"])
	return out


## The companion NOTICING the Late Arch as you come near: a held point toward its doorway, then a cooldown (the
## Riverbank's pointing, by bond). Only while idle. Returns { point, target, started }.
func notice(delta: float, player_pos: Vector2, bond: float) -> Dictionary:
	var out := { "point": false, "target": door_middle(), "started": false }
	if phase != Phase.IDLE:
		_notice_left = 0.0
		return out
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left > 0.0:
			out["point"] = true
		else:
			_notice_cd = at_bond("notice_cooldown", bond)
		return out
	if _notice_cd > 0.0:
		_notice_cd = maxf(0.0, _notice_cd - delta)
		return out
	if player_pos.distance_to(_at) <= at_bond("notice_range", bond):
		_notice_left = float(_cfg["notice_hold"])
		out["point"] = true
		out["started"] = true
	return out
