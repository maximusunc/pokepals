class_name AlignGate
extends RefCounted
## Farmeadow's secret, as pure logic (no nodes): a picture painted across boards scattered through a field, which
## only lines up from one spot, looking one way (south: back the way you came). Fed each frame where you are, how
## fast you're going and where the view is looking; says how strongly the view should be drawn onto the exact spot
## and heading (the "magnet"), whether the picture is lined up, how long it's been held, and when it's done.
##
##   * CAPTURE: standing still (slower than `still_speed`) within `capture_radius` of the spot, YOU facing within
##     `capture_deg` of the facing (the way you last walked, not the camera's heading: walking back toward the
##     camera never turns it, so you'd never get it to face south by walking there), the view is drawn exactly onto
##     the spot and heading (PerspectiveView.set_magnet), swinging round to look the way you face. Walking past
##     doesn't capture: you have to stop there.
##   * ALIGNED: the view has settled within `center_tol` of the spot and `yaw_tol_deg` of the facing.
##   * HELD: aligned for `hold_seconds` in a row (a couple of seconds, so someone just walking by never sets it
##     off) and it's DONE, once. Moving off, or turning away, lets the hold go back to zero.
##   * NOTICE: inside `notice_range` of the spot (further the deeper the bond) your companion points at it now and
##     then; nearer than `visit_range` it goes and sits on the very spot, once per approach, so you can see where
##     to stand.

const DEFAULTS := {
	"capture_radius": 26.0,
	"capture_deg": 35.0,
	"still_speed": 14.0,
	"center_tol": 1.5,
	"yaw_tol_deg": 1.0,
	"hold_seconds": 2.0,
	"notice_range_low": 320.0,
	"notice_range_high": 720.0,
	"notice_cooldown_low": 16.0,
	"notice_cooldown_high": 6.0,
	"notice_hold": 2.0,
	"visit_range": 260.0,
	"visit_reset": 520.0,
}

var spot := Vector2.ZERO
var facing := PI
var held := 0.0
var done := false
var _cfg: Dictionary
var _notice_cd := 0.0
var _notice_left := 0.0
var _visited := false


func _init(reveal: Dictionary) -> void:
	_cfg = DEFAULTS.duplicate()
	for k in DEFAULTS:
		if reveal.has(k):
			_cfg[k] = float(reveal[k])
	spot = WorldData.to_vec2(reveal.get("spot", [0, 0]))
	facing = deg_to_rad(float(reveal.get("facing_deg", 180.0)))


func cfg(key: String) -> float:
	return float(_cfg[key])


## One frame. Returns { capture: bool, aligned: bool, progress: 0..1, completed: bool (true once, the frame it's
## done), point: bool (the companion should point at the spot now), visit: bool (it should go and sit on it) }.
## `player_heading` is the bearing the player faces (radians, 0 north, clockwise), `view_yaw` the camera's.
func update(delta: float, player_pos: Vector2, player_speed: float, player_heading: float, view_center: Vector2, view_yaw: float, bond: float) -> Dictionary:
	var out := { "capture": false, "aligned": false, "progress": 0.0, "completed": false, "point": false, "visit": false }
	var d := player_pos.distance_to(spot)
	var capture := not done and d <= cfg("capture_radius") and player_speed < cfg("still_speed") \
			and absf(angle_difference(player_heading, facing)) <= deg_to_rad(cfg("capture_deg"))
	var aligned := capture and view_center.distance_to(spot) <= cfg("center_tol") \
			and absf(angle_difference(view_yaw, facing)) <= deg_to_rad(cfg("yaw_tol_deg"))
	if aligned:
		held += delta
	else:
		held = 0.0
	if aligned and held >= cfg("hold_seconds") and not done:
		done = true
		out["completed"] = true
	out["capture"] = capture
	out["aligned"] = aligned
	out["progress"] = clampf(held / cfg("hold_seconds"), 0.0, 1.0)
	if done:
		return out
	# The companion's part: a point now and then from afar, and once near, it goes and sits on the spot.
	var b := clampf(bond, 0.0, 1.0)
	if d > cfg("visit_reset"):
		_visited = false
	if not _visited and d <= cfg("visit_range") and not capture:
		_visited = true
		out["visit"] = true
	if _notice_left > 0.0:
		_notice_left -= delta
		out["point"] = _notice_left > 0.0
		if _notice_left <= 0.0:
			_notice_cd = lerpf(cfg("notice_cooldown_low"), cfg("notice_cooldown_high"), b)
	elif _notice_cd > 0.0:
		_notice_cd = maxf(0.0, _notice_cd - delta)
	elif d <= lerpf(cfg("notice_range_low"), cfg("notice_range_high"), b) and d > cfg("visit_range"):
		_notice_left = cfg("notice_hold")
		out["point"] = true
	return out
