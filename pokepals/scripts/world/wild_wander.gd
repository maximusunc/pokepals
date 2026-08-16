class_name WildWander
extends RefCounted
## Pure decision logic for a WILD creature's gentle life on its own — the milling-about of the
## first-meeting flock (see EncounterDirector / EncounterPal). A tiny state machine — stand about,
## amble to a spot, hurry away from someone — that each tick answers only "where am I headed, and
## how fast?". It knows nothing about nodes, sprites or collision: the presentation moves the body
## toward the returned target and resolves walls itself — the same logic/presentation split as
## CompanionBrain / CompanionView, so this stays unit-testable with an injected RNG.
##
## States:
##   pause — standing about; counts down, then picks a fresh amble target inside `radius` of the
##           `anchor` passed each tick. The anchor is a fixed home spot for most of the flock, and
##           THE PLAYER for the hidden true companion — which is how its wander range stays
##           centred on you (a shade bigger than the screen) while the others hold their patch.
##   amble — walking to the target at amble_speed. Arriving (or exhausting a travel-time budget,
##           so a target behind a wall this logic can't see never wedges it forever) drops back
##           to pause.
##   away  — the post-examine exit: hurrying to a point away from whoever just looked it over, at
##           away_speed. Same arrival rules; while active the creature reads as "leaving".
##   still — frozen (the bonding ceremony owns the body); holds until told otherwise.

const STATE_PAUSE := "pause"
const STATE_AMBLE := "amble"
const STATE_AWAY := "away"
const STATE_STILL := "still"

var _cfg: Dictionary
var _rng: RandomNumberGenerator
var _state := STATE_PAUSE
var _pause_left := 0.0
var _target := Vector2.ZERO
var _travel_left := 0.0  # seconds of walking allowed before giving up on an unreachable target


## cfg keys (all with defaults): amble_speed, away_speed, arrive_distance, pause [lo, hi],
## away_distance [lo, hi]. rng is injected so a seeded test replays exactly.
func _init(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	_cfg = cfg
	_rng = rng
	# Desync the flock's first step: each creature sits out a different slice of a full pause.
	_pause_left = _rng.randf_range(0.0, _pause_hi())


## Advance one tick. pos: where the body actually IS (post-collision, so arrival is judged against
## the truth). anchor + radius: the roam disc fresh targets are picked in. Returns
## { "state": String, "target": Vector2, "speed": float } — speed 0.0 means "stand still".
func update(delta: float, pos: Vector2, anchor: Vector2, radius: float) -> Dictionary:
	match _state:
		STATE_STILL:
			return { "state": _state, "target": pos, "speed": 0.0 }
		STATE_PAUSE:
			_pause_left -= delta
			if _pause_left <= 0.0:
				_begin_amble(pos, anchor, radius)
			return { "state": _state, "target": pos, "speed": 0.0 }
		_:
			var speed := _away_speed() if _state == STATE_AWAY else _amble_speed()
			_travel_left -= delta
			if pos.distance_to(_target) <= float(_cfg.get("arrive_distance", 10.0)) or _travel_left <= 0.0:
				_begin_pause()
				return { "state": _state, "target": pos, "speed": 0.0 }
			return { "state": _state, "target": _target, "speed": speed }


## Hurry off away from `from` (whoever just examined us): a point the configured distance out,
## biased directly opposite with a little random swing so a flock never scatters on perfect rays.
func walk_away(pos: Vector2, from: Vector2) -> void:
	var dir := pos - from
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
	dir = dir.rotated(_rng.randf_range(-0.5, 0.5))
	var span: Array = _cfg.get("away_distance", [150.0, 230.0])
	_state = STATE_AWAY
	_set_target(pos, pos + dir * _rng.randf_range(float(span[0]), float(span[1])), _away_speed())


## Freeze in place (the bonding ceremony owns the body now). Only a fresh walk_away releases it —
## in practice a frozen creature is mid-ceremony and never returns to the flock's life.
func freeze() -> void:
	_state = STATE_STILL


## Whether it's currently hurrying off after being examined (the director skips these from the
## examine scan, so a leaving creature can't be chain-poked).
func is_leaving() -> bool:
	return _state == STATE_AWAY


func state() -> String:
	return _state


func _begin_amble(pos: Vector2, anchor: Vector2, radius: float) -> void:
	# Never aim dead-centre (0.2 floor): a wander that keeps crossing its anchor reads as pacing.
	var dist := _rng.randf_range(0.2, 1.0) * maxf(radius, 1.0)
	var spot := anchor + Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU)) * dist
	_state = STATE_AMBLE
	_set_target(pos, spot, _amble_speed())


func _begin_pause() -> void:
	_state = STATE_PAUSE
	var span := _pause_span()
	_pause_left = _rng.randf_range(float(span[0]), float(span[1]))


func _set_target(pos: Vector2, target: Vector2, speed: float) -> void:
	_target = target
	# Walking-time budget: straight-line time plus generous slack. If walls (which the
	# presentation resolves, invisible to us) stall the walk, the budget lapses into a pause
	# instead of pinning the creature against a trunk forever.
	_travel_left = pos.distance_to(target) / maxf(speed, 1.0) * 2.5 + 1.0


func _amble_speed() -> float:
	return float(_cfg.get("amble_speed", 42.0))


func _away_speed() -> float:
	return float(_cfg.get("away_speed", 88.0))


func _pause_span() -> Array:
	return _cfg.get("pause", [1.2, 3.4])


func _pause_hi() -> float:
	return float(_pause_span()[1])
