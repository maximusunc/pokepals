class_name AlignGate
extends RefCounted
## Farmeadow's secret, as pure logic (no nodes): a picture painted across boards scattered through a field, which
## only lines up from one spot, looking one way (south: back the way you came). Fed each frame where you are, how
## fast you're going and where the view is looking; says how strongly the view should be drawn onto the exact spot
## and heading (the "magnet"), whether the picture is lined up, how long it's been held, and when it's done.
##
##   * THE EYE: the picture lines up from one point, the camera's eye when it stands on the spot: `eye_back` behind
##     it along the facing. Moving a camera along its own line of sight only zooms what it sees, so the picture
##     lines up from ANY focus along that line, as long as the eye stays put. That's what makes the place you can
##     stand a long strip rather than a dot.
##   * CAPTURE: standing still (slower than `still_speed`) within `capture_radius` of the strip that runs from
##     `capture_back` behind the spot to `capture_ahead` in front of it, YOU facing within `capture_deg` of the
##     facing (the way you last walked, not the camera's heading: walking back toward the camera never turns it, so
##     you'd never get it to face south by walking there). Then the view is drawn onto the line (magnet_view: its
##     focus level with you on the line, its eye on the eye point), swinging round to look the way you face.
##     Walking past doesn't capture: you have to stop there.
##   * ALIGNED: the view's eye has settled within `center_tol` of the eye point and its heading within
##     `yaw_tol_deg` of the facing.
##   * HELD: aligned for `hold_seconds` in a row (a couple of seconds, so someone just walking by never sets it
##     off) and it's DONE, once. Moving off, or turning away, lets the hold go back to zero.
##   * NOTICE: inside `notice_range` of the spot (further the deeper the bond) your companion points at it now and
##     then; nearer than `visit_range` it goes and sits on the very spot, once per approach, so you can see where
##     to stand.

const DEFAULTS := {
	"capture_radius": 26.0,
	"capture_back": 0.0,     # how far the strip you can stand on runs back from the spot (away from the picture)
	"capture_ahead": 0.0,    # ...and on toward it
	"eye_back": 220.0,       # the camera's eye, this far behind the spot (data/view.json camera.back)
	"min_back": 60.0,        # nearest the eye the focus may come
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


## The way the view faces (a unit vector).
func forward() -> Vector2:
	return Vector2(0, -1).rotated(facing)


## The point the picture lines up from: the camera's eye when it stands on the spot.
func eye_point() -> Vector2:
	return spot - forward() * cfg("eye_back")


## Where the view should be to show the picture to someone standing at `player_pos`: its focus on the line, level
## with them, and how far behind the focus its camera stands (so the eye stays on the eye point). [center, back]
func magnet_view(player_pos: Vector2) -> Array:
	var eye := eye_point()
	var a := clampf((player_pos - eye).dot(forward()), cfg("min_back"), cfg("eye_back") + cfg("capture_ahead") + cfg("capture_radius"))
	return [eye + forward() * a, a]


## How far `p` is from the strip you can stand on.
func _off_strip(p: Vector2) -> float:
	var a := spot - forward() * cfg("capture_back")
	var b := spot + forward() * cfg("capture_ahead")
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 1e-6 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## One frame. Returns { capture: bool, aligned: bool, progress: 0..1, completed: bool (true once, the frame it's
## done), point: bool (the companion should point at the spot now), visit: bool (it should go and sit on it) }.
## `player_heading` is the bearing the player faces (radians, 0 north, clockwise); `view_eye` and `view_yaw` where
## the camera's eye is and the way it looks.
func update(delta: float, player_pos: Vector2, player_speed: float, player_heading: float, view_eye: Vector2, view_yaw: float, bond: float) -> Dictionary:
	var out := { "capture": false, "aligned": false, "progress": 0.0, "completed": false, "point": false, "visit": false }
	var d := player_pos.distance_to(spot)
	var capture := not done and _off_strip(player_pos) <= cfg("capture_radius") and player_speed < cfg("still_speed") \
			and absf(angle_difference(player_heading, facing)) <= deg_to_rad(cfg("capture_deg"))
	var aligned := capture and view_eye.distance_to(eye_point()) <= cfg("center_tol") \
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
