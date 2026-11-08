class_name FollowGuide
extends RefCounted
## A companion LEADING YOU through the dark to something it can sense, as pure logic (state in, state
## out): Underroot's root-heart. The player DELEGATES ("Go look") and the companion leads along a route
## the director planned (waypoints through the tunnels). This decides, every frame, what the companion
## should be doing about it. It draws nothing and knows no nodes: the FollowDirector feeds it positions and
## the bond, and turns the answer into a "guide" command, a light and a hint.
##
## The one rule of the secret is "follow, don't steer": the companion LEADS and you FOLLOW.
##
##   IDLE     nothing happening (never asked, a lead that lapsed, or a leg that ended). Asking again
##            (`begin`) starts a fresh lead from wherever it now stands.
##   LEAD     walks the waypoints in order, at a pace that grows with bond.
##   WAIT     you've fallen further than `wait_distance` behind: it stops and waits, facing you, until you
##            are back within `resume_distance`. Never a fail state: it waits as long as it takes.
##   HOLD     you are PUSHING AHEAD: you have walked past it, further than `ahead_margin` px along its route
##            and standing in that tunnel. It holds back (stands, facing you) rather than lead from behind.
##            Fall in behind it again and it carries on; keep pushing on for `ahead_patience` seconds and it
##            gently lets the lead go (back to following you as an ordinary companion). You can ask again.
##   DONE     you and it have both arrived at the heart.
##
## Arriving does not need a lead: if you find your own way there and your companion has tagged along (both
## within their radii), that is arrival too. The player-facing condition is what matters.
##
## BOND shapes it (every value is a low..high pair in the data, blended by bond 0..1):
##   * `reach`: how far along the route it can lead in ONE ask. A fresh companion senses only so far, loses
##     the scent at the end of a stretch, and waits for you to ask again; a bonded one leads the whole way.
##   * `pace`: how fast it walks (always slower than you).
##   * `wait_distance`: how far behind you can fall before it stops for you.
##   * `ahead_patience` / `ahead_margin`: how long, and how far, it forgives you for running on ahead.
##   * `notice_*`: from how far off it senses the heart and points toward it, and how often.
##
## NOTICING (`notice`, separate from the cycle): while IDLE and you come within range of the heart (as the
## crow flies; it can sense through walls, which is exactly why pointing is not a map), the companion, in
## any state of mind, stops and points toward it for a moment, then cools down.
##
## All numbers come from the secret's `reveal` block in the world spec; DEFAULTS are a safety net only.

enum Phase { IDLE, LEAD, WAIT, HOLD, DONE }

const DEFAULTS := {
	"reach_low": 2600.0,           # px of route one ask can lead, at zero bond...
	"reach_high": 99999.0,         # ...and at full bond (effectively unlimited)
	"pace_low": 74.0,
	"pace_high": 100.0,
	"wait_low": 150.0,             # you're this far behind: it waits (zero bond)...
	"wait_high": 190.0,            # ...(full bond)
	"resume_distance": 90.0,       # ...until you're this close
	"give_up_distance": 900.0,     # you're this far away: the lead lapses and it comes back to you
	"waypoint_reach": 26.0,
	"waypoint_patience": 14.0,     # seconds without headway toward a waypoint before skipping it
	"progress_eps": 3.0,
	"ahead_margin_low": 70.0,      # you're this far ahead of it along its route: you are pushing ahead
	"ahead_margin_high": 110.0,
	"ahead_lateral": 75.0,         # ...and within this of the route (so across a wall is not "ahead")
	"ahead_look": 700.0,           # how much of the route ahead of it counts
	"ahead_patience_low": 7.0,     # seconds of pushing on before it lets the lead go (zero bond)...
	"ahead_patience_high": 14.0,   # ...(full bond)
	"arrive_player": 130.0,        # arrival: you within this of the heart...
	"arrive_companion": 170.0,     # ...and it within this
	"notice_range_low": 300.0,
	"notice_range_high": 620.0,
	"notice_cooldown_low": 18.0,
	"notice_cooldown_high": 8.0,
	"notice_hold": 2.5,
}

var phase := Phase.IDLE
## Index of the waypoint it is heading for (0..path.size()).
var next_index := 0

var _heart := Vector2.ZERO
var _path: Array = []            # Array[Vector2], the planned route to the heart
var _cfg: Dictionary = {}
var _bond := 0.0
var _led := 0.0                  # route px led since the last ask
var _last_pos := Vector2.ZERO
var _has_last := false
var _best := INF                 # closest we've come to the current waypoint
var _stalled := 0.0
var _ahead_time := 0.0           # seconds spent pushing ahead (in HOLD)
var _notice_cd := 0.0
var _notice_left := 0.0
var _at_end := false             # it has led you to the heart and is standing there for you


## heart: where the root-heart is. cfg: the secret's reveal block (see DEFAULTS for the keys).
func _init(heart: Vector2, cfg: Dictionary = {}) -> void:
	_heart = heart
	_cfg = DEFAULTS.duplicate()
	for k in cfg:
		if DEFAULTS.has(k):
			_cfg[k] = cfg[k]


func heart() -> Vector2:
	return _heart


func is_done() -> bool:
	return phase == Phase.DONE


func is_leading() -> bool:
	return phase == Phase.LEAD or phase == Phase.WAIT or phase == Phase.HOLD


func path() -> Array:
	return _path


## Blend a low..high pair of the config by bond.
func at_bond(key: String, bond: float) -> float:
	return lerpf(float(_cfg[key + "_low"]), float(_cfg[key + "_high"]), clampf(bond, 0.0, 1.0))


## How fast a companion of this bond walks while leading (px/s).
func pace(bond: float) -> float:
	return at_bond("pace", bond)


## The ask: lead along `route` (waypoints from where the companion stands to the heart). Returns false,
## and does nothing, when there is no route to follow. Asking while already leading just takes the new route.
func begin(route: Array, bond: float) -> bool:
	if phase == Phase.DONE or route.is_empty():
		return false
	_path = []
	for p in route:
		_path.append(p if p is Vector2 else Vector2(float(p[0]), float(p[1])))
	_bond = clampf(bond, 0.0, 1.0)
	next_index = 0
	_led = 0.0
	_has_last = false
	_ahead_time = 0.0
	_notice_left = 0.0
	_at_end = false
	_reset_headway()
	phase = Phase.LEAD
	return true


## Let the lead go (the companion goes back to following you).
func stop() -> void:
	if phase != Phase.DONE:
		phase = Phase.IDLE
		_ahead_time = 0.0


## Advance by `delta`. Returns what the director should do this frame:
##   command: "" (nothing: let it live) or "guide" (issue a guide order to `target`; `hold` says stand)
##   target:  the point to head for / stand at
##   hold:    true while waiting for you or holding back
##   speed:   the pace to walk at (px/s)
##   light:   0..1, how brightly the companion's own light should shine: full while it leads, steady while
##            it waits, off while holding back or resting
##   events:  [String] one-shot moments: "set_off", "reached" (a waypoint), "wait", "resume", "balk"
##            (you are pushing ahead), "let_go" (it stopped leading because you kept pushing on), "lost"
##            (you are too far away), "scent_lost" (this stretch is as far as it can sense; ask again),
##            "arrived"
func update(delta: float, companion_pos: Vector2, player_pos: Vector2, bond: float) -> Dictionary:
	var out := { "command": "", "target": companion_pos, "hold": false, "speed": pace(bond), "light": 0.0, "events": [] }
	if phase == Phase.DONE:
		return out
	_bond = clampf(bond, 0.0, 1.0)

	# Arrival counts however you got here.
	if player_pos.distance_to(_heart) <= float(_cfg["arrive_player"]) and companion_pos.distance_to(_heart) <= float(_cfg["arrive_companion"]):
		phase = Phase.DONE
		out["events"].append("arrived")
		return out

	if not is_leading():
		return out

	var player_gap := companion_pos.distance_to(player_pos)
	if player_gap > float(_cfg["give_up_distance"]):
		phase = Phase.IDLE
		out["events"].append("lost")
		return out

	# Count the route it has led, so a fresh companion's reach can run out.
	if _has_last and phase == Phase.LEAD:
		_led += companion_pos.distance_to(_last_pos)
	_last_pos = companion_pos
	_has_last = true
	if phase == Phase.LEAD and _led >= at_bond("reach", _bond):
		phase = Phase.IDLE
		out["events"].append("scent_lost")
		return out

	# Where is the player along its route? Pushing ahead is being on its route, past it.
	var ahead := _player_ahead(companion_pos, player_pos)

	match phase:
		Phase.LEAD:
			if ahead:
				phase = Phase.HOLD
				_ahead_time = 0.0
				out["events"].append("balk")
			elif player_gap > at_bond("wait", _bond):
				phase = Phase.WAIT
				out["events"].append("wait")
		Phase.WAIT:
			if ahead:
				phase = Phase.HOLD
				_ahead_time = 0.0
				out["events"].append("balk")
			elif player_gap <= float(_cfg["resume_distance"]):
				phase = Phase.LEAD
				out["events"].append("resume")
		Phase.HOLD:
			if ahead:
				_ahead_time += delta
				if _ahead_time >= at_bond("ahead_patience", _bond):
					phase = Phase.IDLE
					_ahead_time = 0.0
					out["events"].append("let_go")
					return out
			else:
				_ahead_time = 0.0
				phase = Phase.LEAD
				out["events"].append("resume")

	match phase:
		Phase.WAIT:
			out["command"] = "guide"
			out["hold"] = true
			out["light"] = 0.7
		Phase.HOLD:
			out["command"] = "guide"
			out["hold"] = true
			out["light"] = 0.0
		Phase.LEAD:
			var target: Vector2 = _path[next_index]
			out["command"] = "guide"
			out["target"] = target
			out["light"] = 1.0
			if _at_end:
				# It has brought you to the heart: it stands there, light up, for you to come the last steps.
				out["hold"] = true
				out["target"] = _heart
				out["light"] = 0.7
			elif companion_pos.distance_to(target) <= float(_cfg["waypoint_reach"]):
				_advance(out)
			else:
				_watch_headway(delta, companion_pos.distance_to(target), out)
	return out


## The companion NOTICING the heart (see the class doc). Call every frame with the bond (0..1).
## Returns { "point": bool (hold a point this frame), "target": the heart, "started": true on the frame a
## new point begins }. Only while IDLE; any other phase cancels a point in progress.
func notice(delta: float, player_pos: Vector2, bond: float) -> Dictionary:
	var out := { "point": false, "target": _heart, "started": false }
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
	if player_pos.distance_to(_heart) <= at_bond("notice_range", bond):
		_notice_left = float(_cfg["notice_hold"])
		out["point"] = true
		out["started"] = true
	return out


## Whether the player is pushing ahead of the companion: on its route (within `ahead_lateral` of it), and
## further along it than `ahead_margin`. Only the stretch `ahead_look` px ahead of it counts, measured along
## the route from the companion's own position through the waypoints it has yet to reach.
func _player_ahead(companion_pos: Vector2, player_pos: Vector2) -> bool:
	if _path.is_empty():
		return false
	var margin := at_bond("ahead_margin", _bond)
	var lateral := float(_cfg["ahead_lateral"])
	var look := float(_cfg["ahead_look"])
	var a := companion_pos
	var along := 0.0
	var i := next_index
	while i < _path.size() and along < look:
		var b: Vector2 = _path[i]
		var seg := b - a
		var len2 := seg.length_squared()
		if len2 > 0.0001:
			var t := clampf((player_pos - a).dot(seg) / len2, 0.0, 1.0)
			var closest := a + seg * t
			if player_pos.distance_to(closest) <= lateral and along + seg.length() * t >= margin:
				return true
		along += seg.length()
		a = b
		i += 1
	return false


func _advance(out: Dictionary) -> void:
	next_index += 1
	_reset_headway()
	out["events"].append("reached")
	if next_index >= _path.size():
		# The route ends at the heart: stand there and wait for you (arrival needs you both).
		next_index = _path.size() - 1
		_at_end = true
		out["events"].append("at_heart")
		out["command"] = "guide"
		out["hold"] = true
		out["target"] = _heart
		out["light"] = 0.7


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
