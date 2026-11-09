class_name SkyView
extends RefCounted
## Loftreach's secret, as pure logic: borrowing your companion's EYES. Shifted into a bird and sent up, the
## companion climbs into the sky and you see what it sees: the camera rises with it, and from high up the clouds
## and the shapes of the islands make a picture that points at an islet you cannot reach on foot. Once the bird
## has really LOOKED at it (high enough, with the islet and the head of the hidden bridge both in view, for a
## moment), `seen` is raised and the bridge may appear. No nodes, no input, no drawing: the director feeds it
## time, where the companion stands, the bond and the size of the view, and draws what it says.
##
## The flight:
##   ASCEND   the bird lifts off and flies to the VANTAGE (a point above the middle of the picture) while the
##            view zooms out; it takes `rise_secs`, or the flight time if that is longer;
##   STAY     it hangs there for `stay` seconds (bond makes it longer), looking; holding (`hold`) adds a few
##            more, up to `stay_cap`;
##   DESCEND  it glides home to wherever the companion stands now, the view coming back down with it.
## Ending early (a tap, a step) turns an ASCEND or STAY straight into a DESCEND from wherever it has got to;
## nothing is ever lost and there is no fail state: ask again.
##
## Bond shapes it three ways: how LONG it can stay up (`stay_low` .. `stay_high`), how HIGH it climbs and so how
## much of the sky the view takes in (`zoom_low` .. `zoom_high`, smaller is higher), and how far away it notices
## the unreachable islet and looks toward it (`notice_range_*`).

enum Phase { GROUNDED, ASCEND, STAY, DESCEND }

const DEFAULTS := {
	"rise_secs": 1.5, "fly_speed": 1100.0, "travel_min": 0.8, "travel_max": 3.0,
	"stay_low": 4.5, "stay_high": 9.0, "hold_add": 3.0, "stay_cap": 18.0,
	"descend_secs": 1.4, "min_flight": 0.6,
	"zoom_low": 0.42, "zoom_high": 0.31,
	"see_alt": 0.72, "see_secs": 1.3, "view_margin": 30.0,
	"picture_from": 0.35, "picture_to": 0.8,
	"reveal_secs": 2.6, "after_reveal_stay": 2.0,
	"notice_range_low": 760.0, "notice_range_high": 1200.0, "notice_cooldown_low": 18.0, "notice_cooldown_high": 8.0,
	"notice_hold": 2.5,
}

var phase: Phase = Phase.GROUNDED
var alt := 0.0                 # 0 on the ground .. 1 at the top
var pos := Vector2.ZERO        # where the bird is over the ground (world px)

var _cfg: Dictionary
var _vantage: Vector2
var _targets: Array            # Vector2s that must be in view for the bird to have seen the way
var _target := Vector2.ZERO    # the islet itself (the first target), for noticing
var _home := Vector2.ZERO
var _from_pos := Vector2.ZERO
var _from_alt := 0.0
var _t := 0.0                  # seconds into the current phase
var _flight_t := 0.0
var _travel := 1.0
var _stay_left := 0.0
var _stay_total := 0.0
var _seen := false
var _seen_t := 0.0
var _picture_said := false
var _zoom_end := 0.4
var _notice_cd := 0.0
var _notice_left := 0.0


func _init(vantage: Vector2, targets: Array, cfg: Dictionary = {}) -> void:
	_vantage = vantage
	_targets = targets
	_target = targets[0] if not targets.is_empty() else vantage
	_cfg = DEFAULTS.duplicate()
	for k in cfg:
		_cfg[k] = cfg[k]


func config() -> Dictionary:
	return _cfg


func is_flying() -> bool:
	return phase != Phase.GROUNDED


func is_seen() -> bool:
	return _seen


## The way is already known (found on an earlier visit): never ask the bird to look again for the bridge.
func mark_seen() -> void:
	_seen = true


func vantage() -> Vector2:
	return _vantage


func target() -> Vector2:
	return _target


## Seconds the bird can hang up there at this bond (0..1).
func stay_for(bond: float) -> float:
	return lerpf(float(_cfg["stay_low"]), float(_cfg["stay_high"]), clampf(bond, 0.0, 1.0))


## The view's zoom at the top for this bond (a Camera2D zoom: smaller is higher and shows more).
func zoom_top(bond: float) -> float:
	return lerpf(float(_cfg["zoom_low"]), float(_cfg["zoom_high"]), clampf(bond, 0.0, 1.0))


## The camera zoom at altitude `a` (0..1) for this bond: 1 on the ground, easing to zoom_top at the top.
func zoom_at(a: float, bond: float) -> float:
	return lerpf(1.0, zoom_top(bond), smoothstep(0.0, 1.0, clampf(a, 0.0, 1.0)))


## How much of the sky picture shows at altitude `a` (0..1): none near the ground, all of it up high.
func picture_at(a: float) -> float:
	return smoothstep(float(_cfg["picture_from"]), float(_cfg["picture_to"]), a)


## Begin a flight from `home` (where the companion stands). False when one is already under way.
func launch(home: Vector2, bond: float) -> bool:
	if phase != Phase.GROUNDED:
		return false
	_home = home
	_from_pos = home
	pos = home
	_from_alt = 0.0
	alt = 0.0
	phase = Phase.ASCEND
	_t = 0.0
	_flight_t = 0.0
	_seen_t = 0.0
	_picture_said = false
	var dist := home.distance_to(_vantage)
	_travel = clampf(dist / maxf(1.0, float(_cfg["fly_speed"])), float(_cfg["travel_min"]), float(_cfg["travel_max"]))
	_stay_total = stay_for(bond)
	_stay_left = _stay_total
	return true


## Ask it to come down (a tap, a step). Ignored for the first instant so the tap that launched it cannot also
## end it. True when it actually turned for home.
func request_end() -> bool:
	if phase != Phase.ASCEND and phase != Phase.STAY:
		return false
	if _flight_t < float(_cfg["min_flight"]):
		return false
	_begin_descend()
	return true


## Ask it to stay a little longer (the player pressed Go up again while it is up). True when it did.
func hold() -> bool:
	if phase != Phase.STAY and phase != Phase.ASCEND:
		return false
	var cap := float(_cfg["stay_cap"])
	var room := cap - _stay_left
	if room <= 0.0:
		return false
	_stay_left += minf(float(_cfg["hold_add"]), room)
	return true


func _begin_descend() -> void:
	phase = Phase.DESCEND
	_t = 0.0
	_from_pos = pos
	_from_alt = alt


## Step the flight. `home` is where the companion stands now (the bird's way back), `view` the size of the
## visible area at zoom 1 (the viewport size, world px), `bond` 0..1. Returns { phase, alt, pos, zoom, lift,
## picture, flying, events } where events may hold "picture", "seen", "landed".
func update(delta: float, home: Vector2, view: Vector2, bond: float) -> Dictionary:
	var events: Array = []
	if phase == Phase.GROUNDED:
		return _state(events, bond)
	_home = home
	_t += delta
	_flight_t += delta
	match phase:
		Phase.ASCEND:
			var rise := maxf(0.01, float(_cfg["rise_secs"]))
			alt = smoothstep(0.0, 1.0, clampf(_t / rise, 0.0, 1.0))
			pos = _from_pos.lerp(_vantage, smoothstep(0.0, 1.0, clampf(_t / _travel, 0.0, 1.0)))
			if _t >= maxf(rise, _travel):
				phase = Phase.STAY
				_t = 0.0
				alt = 1.0
				pos = _vantage
		Phase.STAY:
			alt = 1.0
			pos = _vantage
			_stay_left -= delta
			if _stay_left <= 0.0:
				_begin_descend()
		Phase.DESCEND:
			var d := maxf(0.01, float(_cfg["descend_secs"]))
			var k := smoothstep(0.0, 1.0, clampf(_t / d, 0.0, 1.0))
			alt = lerpf(_from_alt, 0.0, k)
			pos = _from_pos.lerp(_home, k)
			if _t >= d:
				phase = Phase.GROUNDED
				alt = 0.0
				pos = _home
				events.append("landed")
	if phase != Phase.GROUNDED and phase != Phase.DESCEND:
		_look(delta, view, bond, events)
	if phase != Phase.GROUNDED and not _picture_said and picture_at(alt) >= 0.5:
		_picture_said = true
		events.append("picture")
	return _state(events, bond)


## The bird looking: high enough, with every target in the view, for `see_secs`, and the way is seen.
func _look(delta: float, view: Vector2, bond: float, events: Array) -> void:
	if _seen:
		return
	if alt < float(_cfg["see_alt"]):
		_seen_t = maxf(0.0, _seen_t - delta)
		return
	var z := zoom_at(alt, bond)
	var size := view / maxf(0.01, z)
	var rect := Rect2(pos - size * 0.5, size).grow(-float(_cfg["view_margin"]))
	var all_in := true
	for t in _targets:
		if not rect.has_point(t):
			all_in = false
			break
	if all_in:
		_seen_t += delta
		if _seen_t >= float(_cfg["see_secs"]):
			_seen = true
			events.append("seen")
			# let the player watch the bridge come in before it comes down
			_stay_left = maxf(_stay_left, float(_cfg["reveal_secs"]) + float(_cfg["after_reveal_stay"]))
	else:
		_seen_t = maxf(0.0, _seen_t - delta)


func _state(events: Array, bond: float) -> Dictionary:
	return {
		"phase": phase, "alt": alt, "pos": pos, "zoom": zoom_at(alt, bond),
		"lift": alt, "picture": picture_at(alt), "flying": phase != Phase.GROUNDED, "events": events,
	}


## The companion NOTICING the islet it cannot reach: while no flight is under way and the way is still unseen,
## coming within range of the islet makes it stop and look toward it, then cool down. Returns { point, target,
## started }. Call every frame with the player's position and the bond.
func notice(delta: float, player_pos: Vector2, bond: float) -> Dictionary:
	var out := { "point": false, "target": _target, "started": false }
	if phase != Phase.GROUNDED or _seen:
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
	if player_pos.distance_to(_target) <= reach:
		_notice_left = float(_cfg["notice_hold"])
		out["point"] = true
		out["started"] = true
	return out
