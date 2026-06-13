class_name CompanionDrives
## The DECIDE step of the companion's agent loop. Each drive looks at the same
## perception and scores how strongly it wants to act right now; the highest score
## wins and produces the frame's intent. Splitting behavior into competing drives —
## rather than one if/elif chain — is what later lets the companion act on its own
## wants: a drive can win without the player doing anything.
##
## Each drive is a tiny stateful object:
##   tick(delta)                              advance always-running timers
##   evaluate(perception, self, cfg) -> float how much it wants to act (0 = not)
##   act(perception, self, cfg, rng, delta)   only the winner is asked; returns
##       -> { behavior, move_target, desired_speed, look_at, reactions }
##
## Priority is encoded in the base scores (investigate > follow > idle), which
## reproduces the original behavior. Traits modulate behavior within a drive, not
## the ordering — for now.


static func make_all(cfg: Dictionary, rng: RandomNumberGenerator) -> Array:
	return [InvestigateDrive.new(), FollowDrive.new(), IdleDrive.new(cfg, rng)]


## Interface + safe defaults so a drive only overrides what it needs.
class Drive extends RefCounted:
	func tick(_delta: float) -> void:
		pass

	func evaluate(_perception: Dictionary, _s: CompanionSelf, _cfg: Dictionary) -> float:
		return 0.0

	func act(_perception: Dictionary, _s: CompanionSelf, _cfg: Dictionary, _rng: RandomNumberGenerator, _delta: float) -> Dictionary:
		return {}


## Something nearby caught its attention — the core "it noticed what I did" beat.
## It waddles over, lingers, then loses interest (with a cooldown before it can be
## drawn again).
class InvestigateDrive extends Drive:
	const SCORE := 10.0
	var _active := false
	var _target := Vector2.ZERO
	var _linger := 0.0
	var _cooldown := 0.0
	var _just_triggered := false

	func tick(delta: float) -> void:
		_cooldown = maxf(0.0, _cooldown - delta)

	func evaluate(perception: Dictionary, _s: CompanionSelf, cfg: Dictionary) -> float:
		if not _active and _cooldown <= 0.0 and perception["has_interaction"]:
			_active = true
			_target = perception["interaction_point"]
			_linger = float(cfg["curiosity_linger"])
			_cooldown = float(cfg["curiosity_cooldown"])
			_just_triggered = true
		return SCORE if _active else 0.0

	func act(perception: Dictionary, _s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator, delta: float) -> Dictionary:
		var reactions: Array = []
		if _just_triggered:
			reactions.append("perk")
			_just_triggered = false
		_linger -= delta
		var companion_pos: Vector2 = perception["companion_pos"]
		var move_target := companion_pos
		var speed := 0.0
		if companion_pos.distance_to(_target) > float(cfg["curiosity_stop_distance"]):
			move_target = _target
			speed = float(cfg["walk_speed"])
		if _linger <= 0.0:
			_active = false
		return {
			"behavior": "curious",
			"move_target": move_target,
			"desired_speed": speed,
			"look_at": _target,
			"reactions": reactions,
		}


## Stay with the player: trail behind them, strolling when just behind, hustling
## when far.
class FollowDrive extends Drive:
	const SCORE := 5.0

	func evaluate(perception: Dictionary, _s: CompanionSelf, cfg: Dictionary) -> float:
		return SCORE if perception["dist_to_player"] > float(cfg["follow_near"]) else 0.0

	func act(perception: Dictionary, _s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator, _delta: float) -> Dictionary:
		var dist: float = perception["dist_to_player"]
		var speed := float(cfg["run_speed"]) if dist > float(cfg["follow_far"]) else float(cfg["walk_speed"])
		return {
			"behavior": "follow",
			"move_target": perception["follow_point"],
			"desired_speed": speed,
			"look_at": perception["player_pos"],
			"reactions": [],
		}


## The baseline: stand near the player and just be present — glance back at them
## (clinginess), look around now and then, and hop when feeling energetic.
class IdleDrive extends Drive:
	const SCORE := 1.0
	var _look_timer := 0.0
	var _look_at := Vector2.ZERO
	var _has_look := false

	func _init(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
		_look_timer = _roll_interval(cfg, rng)

	func _roll_interval(cfg: Dictionary, rng: RandomNumberGenerator) -> float:
		var interval: Array = cfg["idle_look_interval"]
		return rng.randf_range(float(interval[0]), float(interval[1]))

	func evaluate(_perception: Dictionary, _s: CompanionSelf, _cfg: Dictionary) -> float:
		return SCORE

	func act(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator, delta: float) -> Dictionary:
		var companion_pos: Vector2 = perception["companion_pos"]
		var player_pos: Vector2 = perception["player_pos"]
		var reactions: Array = []

		_look_timer -= delta
		if _look_timer <= 0.0:
			_look_timer = _roll_interval(cfg, rng)
			# Mostly glance back at the player (clinginess); sometimes look around.
			if rng.randf() < _trait(s, cfg, "clinginess"):
				_look_at = player_pos
			else:
				_look_at = companion_pos + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 48.0
			_has_look = true
			reactions.append("look")
			# Energetic companions hop more often when idling.
			if rng.randf() < _trait(s, cfg, "energy") * 0.5:
				reactions.append("hop")

		return {
			"behavior": "idle",
			"move_target": companion_pos,
			"desired_speed": 0.0,
			"look_at": _look_at if _has_look else player_pos,
			"reactions": reactions,
		}

	# Prefer the (drifting) self trait; fall back to the static personality config.
	func _trait(s: CompanionSelf, cfg: Dictionary, key: String) -> float:
		var fallback := float(cfg["personality"].get(key, 0.5)) if cfg.has("personality") else 0.5
		return s.trait_value(key, fallback)
