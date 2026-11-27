class_name DigSense
extends RefCounted
## The companion SNIFFING OUT buried things as you cross the flats (Ebbmere). Pure and stateful: each frame
## it is told where you are, how bonded the companion is and which dig spots the water has uncovered but
## nobody has noticed yet, and it answers whether the companion should be stopped, nose down, pointing at
## one. A spot is NOTICED when a point on it finishes (it then shows its sign: a bubbling hole), or when
## you or the companion simply walk within `see_radius` of it (you would see the little bubbles yourself).
## Range and frequency grow with the bond, like every other notice in the game (Drifthallow, Stillglass).
##
## cfg: sniff_range_low / _high (px from YOU), sniff_cooldown_low / _high (s), sniff_hold (s), see_radius (px).

const DEFAULTS := {
	"sniff_range_low": 240.0, "sniff_range_high": 560.0,
	"sniff_cooldown_low": 9.0, "sniff_cooldown_high": 3.5, "sniff_hold": 2.4, "see_radius": 64.0,
}

var _cfg := DEFAULTS.duplicate()
var _left := 0.0
var _cd := 1.5            # the first sniff comes a moment after the water uncovers something
var _target_id := ""
var _target := Vector2.ZERO


func _init(cfg: Dictionary = {}) -> void:
	for k in DEFAULTS:
		if cfg.has(k):
			_cfg[k] = float(cfg[k])


func reset() -> void:
	_left = 0.0
	_cd = 1.5
	_target_id = ""


## The spots seen by eye: any candidate within see_radius of you or your companion.
func seen_by_eye(candidates: Array, player_pos: Vector2, companion_pos: Vector2) -> Array:
	var out: Array = []
	var r := float(_cfg["see_radius"])
	for c in candidates:
		var pos: Vector2 = c["pos"]
		if pos.distance_to(player_pos) <= r or pos.distance_to(companion_pos) <= r:
			out.append(String(c["id"]))
	return out


## Call every frame. `candidates` are [{ id, pos }] of exposed, alive, un-noticed spots.
## Returns { point: bool (hold a point this frame), target: Vector2, started: bool (a new point began),
## noticed: String (a spot id whose point just finished: show its sign) }.
func update(delta: float, player_pos: Vector2, bond: float, candidates: Array) -> Dictionary:
	var out := { "point": false, "target": _target, "started": false, "noticed": "" }
	if _left > 0.0:
		# the spot has to still be uncovered and un-noticed, or the point lapses (the tide came back in)
		var alive := false
		for c in candidates:
			if String(c["id"]) == _target_id:
				alive = true
				_target = c["pos"]
		if not alive:
			_left = 0.0
			_target_id = ""
			return out
		_left -= delta
		if _left > 0.0:
			out["point"] = true
			out["target"] = _target
			return out
		out["noticed"] = _target_id
		_target_id = ""
		_cd = lerpf(float(_cfg["sniff_cooldown_low"]), float(_cfg["sniff_cooldown_high"]), clampf(bond, 0.0, 1.0))
		return out
	if _cd > 0.0:
		_cd = maxf(0.0, _cd - delta)
		return out
	var reach := lerpf(float(_cfg["sniff_range_low"]), float(_cfg["sniff_range_high"]), clampf(bond, 0.0, 1.0))
	var best := ""
	var best_d := INF
	var best_pos := Vector2.ZERO
	for c in candidates:
		var pos: Vector2 = c["pos"]
		var d := pos.distance_to(player_pos)
		if d <= reach and d < best_d:
			best = String(c["id"])
			best_d = d
			best_pos = pos
	if best == "":
		return out
	_target_id = best
	_target = best_pos
	_left = float(_cfg["sniff_hold"])
	out["point"] = true
	out["started"] = true
	out["target"] = _target
	return out
