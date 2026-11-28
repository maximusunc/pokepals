class_name ViewRig
extends RefCounted
## How a perspective world's camera moves, as pure logic (state in, state out; no nodes): it swings round behind
## the way you walk, and settles lower while you stand still ("lingering"). Fed your velocity each frame;
## read `yaw` (the heading to look along) and `linger` (0 walking .. 1 fully settled) back out. The projection
## itself is ViewProjection; this only decides where it points and how low it sits.
##
## Swing: the heading eases toward your direction of travel. Walking straight ahead or diagonally it catches up
## quickly; walking across the screen only a `sideways` share of that (holding a side shouldn't spin you
## round); walking back toward the camera (more than `max_deg` off its heading) not at all, so you can step
## back without the world flipping.

var yaw := 0.0
var linger := 0.0
var still := 0.0

var swing_rate := 2.0
var swing_sideways := 0.25
var swing_max_deg := 115.0
var min_speed := 20.0     # slower than this counts as standing
var full_speed := 90.0    # the swing is at full rate from this speed
var linger_after := 2.5   # seconds standing before it settles
var linger_down := 0.45   # per second, settling
var linger_up := 2.5      # per second, rising again
## While something wants the view held steady (Farmeadow's picture lining up), standing still doesn't settle it.
var hold_linger := false


func configure(cfg: Dictionary) -> ViewRig:
	var swing: Dictionary = cfg.get("swing", {})
	swing_rate = float(swing.get("rate", swing_rate))
	swing_sideways = float(swing.get("sideways", swing_sideways))
	swing_max_deg = float(swing.get("max_deg", swing_max_deg))
	var lg: Dictionary = cfg.get("linger", {})
	linger_after = float(lg.get("after", linger_after))
	linger_down = float(lg.get("down_rate", linger_down))
	linger_up = float(lg.get("up_rate", linger_up))
	return self


func step(velocity: Vector2, delta: float) -> void:
	var speed := velocity.length()
	if speed > min_speed:
		var target := atan2(velocity.x, -velocity.y)
		var diff := angle_difference(yaw, target)
		if absf(diff) < deg_to_rad(swing_max_deg):
			var pace := clampf(speed / full_speed, 0.0, 1.0)
			var w := swing_sideways + (1.0 - swing_sideways) * maxf(0.0, cos(diff))
			yaw = wrapf(yaw + diff * (1.0 - exp(-swing_rate * pace * w * delta)), -PI, PI)
		still = 0.0
	else:
		still += delta
	var want := 1.0 if still > linger_after and not hold_linger else 0.0
	linger = move_toward(linger, want, (linger_down if want > linger else linger_up) * delta)
