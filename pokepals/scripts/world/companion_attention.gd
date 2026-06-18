class_name CompanionAttention
extends RefCounted
## SOCIAL REFERENCING (perception side): reads what the PLAYER seems to be paying
## attention to, so the companion can take your focus as a cue. This is the one piece of
## the companion's perception that needs MEMORY across frames (a per-candidate dwell
## timer), which is why it lives here as a small stateful object the brain owns, rather
## than in the pure, stateless CompanionPerception.
##
## "You're attending to X" is inferred from a little kinematic vocabulary about the
## player relative to a candidate point of interest X — no new input channels, just the
## player position/velocity and the POIs the companion already knows about:
##   • proximity — are you near X?            (necessary, not sufficient)
##   • slowness  — moving slowly / stopped?   (we key on being slow, not dead-stopped)
##   • approach  — moving toward X?           (sign of velocity · (X − player))
##   • dwell     — how long you've lingered slow-and-near X (the bit that needs memory)
## ≈ near + slow + (approaching OR dwelling). The dwell term is what gives the companion
## its believable BEAT OF LATENCY: it catches on a moment after you settle on something.
##
## Output (merged into perception by the brain):
##   { has_attended: bool, attended_object: Vector2, attention_strength: 0..1 }
## Pure of RNG and the scene tree; deterministic given the same inputs and prior state.

var _dwell: Dictionary = {}   # candidate index -> seconds lingered slow-and-near it
var _locked := -1             # the candidate we're currently reporting (for hysteresis)
var _hold := 0.0              # seconds left holding the lock before we'll freely switch


func _none() -> Dictionary:
	return { "has_attended": false, "attended_object": Vector2.ZERO, "attention_strength": 0.0 }


## Advance one frame and report what the player seems focused on. A no-op (returns none)
## without "attention" config, on a zero/negative delta, or when there are no POIs.
func update(context: Dictionary, cfg: Dictionary, delta: float) -> Dictionary:
	var ac: Dictionary = cfg.get("attention", {})
	if ac.is_empty() or delta <= 0.0:
		return _none()
	var pois: Array = context.get("points_of_interest", [])
	if pois.is_empty():
		_dwell.clear()
		_locked = -1
		_hold = 0.0
		return _none()

	var player_pos: Vector2 = context["player_pos"]
	var player_vel: Vector2 = context.get("player_velocity", Vector2.ZERO)
	var speed := player_vel.length()

	var radius := float(ac.get("radius", 170.0))
	var slow_speed := float(ac.get("slow_speed", 60.0))
	var slow_gate := float(ac.get("slow_gate", 0.25))
	var dwell_full := maxf(float(ac.get("dwell_full", 1.1)), 0.001)
	var dwell_decay := float(ac.get("dwell_decay", 1.8))
	var approach_floor := float(ac.get("approach_floor", 0.0))

	var slowness := clampf(1.0 - speed / maxf(slow_speed, 0.001), 0.0, 1.0)

	# Score every candidate, advancing/draining its dwell, and remember the strongest.
	var strengths: Dictionary = {}
	var best := -1
	var best_strength := 0.0
	for i in pois.size():
		var p: Vector2 = pois[i]
		var to := p - player_pos
		var d := to.length()
		var cur := float(_dwell.get(i, 0.0))
		if d > radius:
			# Out of range: not a candidate this frame; let any dwell drain away.
			cur = maxf(0.0, cur - dwell_decay * delta)
			_dwell[i] = cur
			continue
		var proximity := 1.0 - d / radius
		var attending_now := slowness >= slow_gate
		if attending_now:
			cur = minf(dwell_full, cur + delta)
		else:
			cur = maxf(0.0, cur - dwell_decay * delta)
		_dwell[i] = cur
		var dwell_norm := cur / dwell_full
		var approaching := speed > 1.0 and to.dot(player_vel) > 0.0
		# near + slow + (approaching OR dwelling): approach engages at once, dwell ramps in.
		var engagement := maxf(dwell_norm, 1.0 if approaching else approach_floor)
		var strength := clampf(proximity * slowness * engagement, 0.0, 1.0)
		strengths[i] = strength
		if strength > best_strength:
			best_strength = strength
			best = i

	var min_strength := float(ac.get("min_strength", 0.06))
	if best == -1 or best_strength < min_strength:
		_locked = -1
		_hold = 0.0
		return _none()

	# Hysteresis: once locked onto something, hold it briefly and require a clear margin to
	# switch, so the gaze doesn't flicker between two nearby props frame to frame.
	var chosen := best
	if _locked != -1 and _hold > 0.0 and strengths.has(_locked):
		var locked_strength := float(strengths[_locked])
		if locked_strength >= min_strength and best_strength <= locked_strength + float(ac.get("switch_margin", 0.15)):
			chosen = _locked
	if chosen != _locked:
		_hold = float(ac.get("hold", 0.6))
	else:
		_hold = maxf(0.0, _hold - delta)
	_locked = chosen

	return {
		"has_attended": true,
		"attended_object": pois[chosen] as Vector2,
		"attention_strength": float(strengths[chosen]),
	}
