class_name CompanionDrives
## The DECIDE step of the companion's agent loop. Each drive looks at the same
## perception and scores how strongly it wants to act right now; the highest score
## wins and produces the frame's intent. Splitting behavior into competing drives —
## rather than one if/elif chain — is what later lets the companion act on its own
## wants: a drive can win without the player doing anything.
##
## Each drive is a tiny stateful object:
##   tick(delta)                                advance always-running timers
##   evaluate(perception, self, cfg, rng) -> float  how much it wants to act now
##       (0 = not); may latch internal state when it decides to start
##   act(perception, self, cfg, rng, delta)     only the winner is asked; returns
##       -> { behavior, move_target, desired_speed, look_at, reactions }
##
## Priority is mostly encoded in the base scores (noticing the player > follow >
## idle). The one place the ORDERING itself shifts is the bond: a fresh companion
## is its own creature, so a self-directed wander outscores following — it would
## rather potter about than trail you. As the bond deepens, following grows more
## eager and wandering less, until staying with you wins. That arc lives in
## FollowDrive.evaluate and InvestigateDrive's self-wander score, both read from
## CompanionSelf.bond and tuned in companion.json.


static func make_all(cfg: Dictionary, rng: RandomNumberGenerator) -> Array:
	return [InvestigateDrive.new(), FollowDrive.new(), IdleDrive.new(cfg, rng)]


## Interface + safe defaults so a drive only overrides what it needs.
class Drive extends RefCounted:
	func tick(_delta: float) -> void:
		pass

	func evaluate(_perception: Dictionary, _s: CompanionSelf, _cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		return 0.0

	func act(_perception: Dictionary, _s: CompanionSelf, _cfg: Dictionary, _rng: RandomNumberGenerator, _delta: float) -> Dictionary:
		return {}


## Curiosity — two flavors:
##   "player": something the player did nearby caught its attention. The core
##             "it noticed what I did" beat; strongest pull, can interrupt a wander.
##   "self":   when settled near the player, it sometimes wanders off on its own to
##             a nearby point of interest. The seed of acting like its own player —
##             and it scores below following, so it abandons the detour if the
##             player walks away.
## Either way it waddles over, lingers, then loses interest, on a per-source
## cooldown. A player-triggered look always trumps everything (the sacred "it
## noticed me" beat); a self-directed wander, by contrast, is bond-scaled: strong
## when the companion barely knows you and fading as it comes to prefer your side.
class InvestigateDrive extends Drive:
	const PLAYER_SCORE := 20.0
	var _active := false
	var _source := "player"  # "player" | "self"
	var _target := Vector2.ZERO
	var _linger := 0.0
	var _player_cooldown := 0.0
	var _wander_cooldown := 0.0
	var _just_triggered := false

	func tick(delta: float) -> void:
		_player_cooldown = maxf(0.0, _player_cooldown - delta)
		_wander_cooldown = maxf(0.0, _wander_cooldown - delta)

	func evaluate(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator) -> float:
		# Player did something nearby: strongest pull; can take over a self-wander.
		if perception["has_interaction"] and _player_cooldown <= 0.0 and (not _active or _source == "self"):
			_start("player", perception["interaction_point"], float(cfg["curiosity_linger"]))
			_player_cooldown = float(cfg["curiosity_cooldown"])
		# Otherwise, when settled near the player, it may wander off on its own.
		elif not _active and _wander_cooldown <= 0.0 and perception["has_poi"] and perception["dist_to_player"] <= float(cfg["follow_near"]):
			var curiosity := s.trait_value("curiosity", _personality(cfg, "curiosity"))
			# A weaker bond means a more independent companion that strikes out on
			# its own more readily; as it bonds it initiates fewer detours.
			var bond_damp := 1.0 - s.bond * float(cfg.get("wander_chance_bond_damp", 0.0))
			var chance := float(cfg.get("wander_chance_per_sec", 0.0)) * curiosity * bond_damp * float(perception["delta"])
			if rng.randf() < chance:
				_start("self", perception["nearest_poi"], float(cfg.get("wander_linger", cfg["curiosity_linger"])))
				_wander_cooldown = float(cfg.get("wander_cooldown", cfg["curiosity_cooldown"]))

		if not _active:
			return 0.0
		return PLAYER_SCORE if _source == "player" else _self_score(s, cfg)

	# How strongly a self-directed wander competes: high at low bond (its own
	# agenda wins), fading toward the player's side as the bond deepens.
	func _self_score(s: CompanionSelf, cfg: Dictionary) -> float:
		var low := float(cfg.get("wander_score_low", 3.0))
		var high := float(cfg.get("wander_score_high", 3.0))
		return lerpf(low, high, s.bond)

	func _start(source: String, target: Vector2, linger: float) -> void:
		_active = true
		_source = source
		_target = target
		_linger = linger
		_just_triggered = true

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

	func _personality(cfg: Dictionary, key: String) -> float:
		return float(cfg["personality"].get(key, 0.5)) if cfg.has("personality") else 0.5


## Stay with the player: trail behind them, strolling when just behind, hustling
## when far.
##
## How much it WANTS to follow has two parts. Eagerness rises with the bond — a
## new companion barely cares to trail you, a deeply bonded one wants to be at your
## side. A distance "leash" adds urgency the farther you get, so that even an
## independent companion won't let you wander clean off the screen: get far enough
## and following wins regardless of how new the bond is.
class FollowDrive extends Drive:
	func evaluate(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		var dist: float = perception["dist_to_player"]
		var near := float(cfg["follow_near"])
		if dist <= near:
			return 0.0
		var eager := lerpf(float(cfg.get("follow_eager_low", 5.0)), float(cfg.get("follow_eager_high", 5.0)), s.bond)
		var far := float(cfg["follow_far"])
		var over := clampf((dist - near) / maxf(far - near, 1.0), 0.0, 1.0)
		var leash := over * float(cfg.get("follow_leash", 0.0))
		return eager + leash

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

	func evaluate(_perception: Dictionary, _s: CompanionSelf, _cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
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
