class_name CompanionDrives
## The DECIDE step of the companion's agent loop. Each drive looks at the same
## perception and scores how strongly it wants to act right now; the highest score
## wins and produces the frame's intent. Splitting behavior into competing drives —
## rather than one if/elif chain — is what lets the companion act on its own wants:
## a drive can win without the player doing anything.
##
## Each drive is a tiny stateful object:
##   tick(delta)                                advance always-running timers
##   evaluate(perception, self, cfg, rng) -> float  how much it wants to act now
##       (0 = not); may latch internal state when it decides to start
##   act(perception, self, cfg, rng, delta)     only the winner is asked; returns
##       -> { behavior, move_target, desired_speed, look_at, reactions }
##
## The drives, strongest first:
##   Investigate — the player did something nearby. The sacred "it noticed me" beat;
##                 fixed high score, briefly interrupts anything.
##   Follow      — stay with the player. Eagerness RISES with the bond, plus a
##                 distance leash so even an independent companion is reeled in
##                 before you get off-screen.
##   Wander      — its own life. A fresh companion potters about on its own —
##                 investigating props, moseying to little spots, pausing to look
##                 around — and this OUTSCORES following at low bond, so it would
##                 rather explore than trail you. As the bond deepens it wanders
##                 less and following wins. This is the independent-creature phase.
##   Idle        — the baseline pause beat: stand, breathe, glance back at you.
##
## The bond arc lives in FollowDrive.evaluate (eagerness up with bond) and
## WanderDrive (roam score down with bond, pauses lengthen with bond), both read
## from CompanionSelf.bond and tuned in companion.json.


static func make_all(cfg: Dictionary, rng: RandomNumberGenerator) -> Array:
	# Order matters only for ties: earlier drives win an exact score tie, which is
	# why Follow sits ahead of Wander (the leash backstop should never lose a tie).
	return [InvestigateDrive.new(), FollowDrive.new(), WanderDrive.new(cfg, rng), IdleDrive.new(cfg, rng)]


## Interface + safe defaults so a drive only overrides what it needs.
class Drive extends RefCounted:
	func tick(_delta: float) -> void:
		pass

	func evaluate(_perception: Dictionary, _s: CompanionSelf, _cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		return 0.0

	func act(_perception: Dictionary, _s: CompanionSelf, _cfg: Dictionary, _rng: RandomNumberGenerator, _delta: float) -> Dictionary:
		return {}

	func _personality(cfg: Dictionary, key: String) -> float:
		return float(cfg["personality"].get(key, 0.5)) if cfg.has("personality") else 0.5


## Player-triggered curiosity: something the player did nearby caught its attention.
## The core "it noticed what I did" beat — the strongest pull, able to interrupt a
## wander. It waddles over, lingers, then loses interest, on a cooldown so a flurry
## of pokes doesn't spam it.
class InvestigateDrive extends Drive:
	const SCORE := 20.0
	var _active := false
	var _target := Vector2.ZERO
	var _linger := 0.0
	var _cooldown := 0.0
	var _just_triggered := false

	func tick(delta: float) -> void:
		_cooldown = maxf(0.0, _cooldown - delta)

	func evaluate(perception: Dictionary, _s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		if perception["has_interaction"] and _cooldown <= 0.0 and not _active:
			_active = true
			_target = perception["interaction_point"]
			_linger = float(cfg["curiosity_linger"])
			_just_triggered = true
			_cooldown = float(cfg["curiosity_cooldown"])
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


## Its own life — the engine of the independent, pre-bond phase. Left to itself the
## companion potters: it moseys to a little spot (a nearby prop if there is one,
## otherwise just an interesting patch of nearby ground), pauses there to look
## around, then after a beat picks somewhere new. The roam/pause rhythm — not a
## single perpetual drift — is what reads as a small creature busy with its own day.
##
## A two-state machine: PAUSE (standing about; bids nothing, so IdleDrive owns the
## beat) and ROAM (moving to a chosen spot, then lingering; bids the bond-scaled
## wander score). The bond shapes both ends of the arc: roaming scores high at low
## bond (its own agenda wins over following) and fades as you bond, while the pauses
## between roams stretch longer the more bonded it is — so a new companion is busy
## and independent, and a bonded one settles at your side. Energetic/curious
## companions roam more often. It only sets off when the player is within
## follow_far; past that the leash has already handed control to FollowDrive, so it
## won't strand itself chasing a prop while you walk away.
class WanderDrive extends Drive:
	enum { PAUSE, ROAM }
	var _state := PAUSE
	var _pause_timer := 0.0
	var _target := Vector2.ZERO
	var _linger := 0.0
	var _just_set_off := false

	func _init(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
		# Start on a pause so the very first frame is calm, not a lurch into motion.
		_pause_timer = _roll_pause(cfg, rng, 0.0, 0.5)

	func tick(delta: float) -> void:
		# Count down toward the next roam only while paused; the roam's own linger is
		# advanced in act(), so it never elapses unseen while FollowDrive holds control.
		if _state == PAUSE:
			_pause_timer = maxf(0.0, _pause_timer - delta)

	func evaluate(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator) -> float:
		if _state == ROAM:
			# If the player has walked off and dragged our destination out of reach,
			# give up on it: pause, and FollowDrive (now scoring higher) takes over.
			# We'll pick a fresh, in-reach spot next time we set off.
			if _target.distance_to(perception["player_pos"]) > float(cfg["follow_far"]):
				_state = PAUSE
				_pause_timer = _roll_pause(cfg, rng, s.bond, _trait(s, cfg, "energy"))
				return 0.0
			return _roam_score(s, cfg)
		# Paused: ready to set off once the timer elapses and the player is close
		# enough that wandering, not following, is the thing to be doing.
		if _pause_timer <= 0.0 and perception["dist_to_player"] <= float(cfg["follow_far"]):
			_target = _pick_target(perception, s, rng, cfg)
			_state = ROAM
			_linger = 0.0
			_just_set_off = true
			return _roam_score(s, cfg)
		return 0.0

	func act(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator, delta: float) -> Dictionary:
		var reactions: Array = []
		if _just_set_off:
			reactions.append("look")
			# A spring in its step now and then, more often when it's a lively one.
			if rng.randf() < _trait(s, cfg, "energy") * 0.4:
				reactions.append("hop")
			_just_set_off = false

		var companion_pos: Vector2 = perception["companion_pos"]
		var move_target := companion_pos
		var speed := 0.0
		if companion_pos.distance_to(_target) > float(cfg["curiosity_stop_distance"]):
			# Still on its way: amble over.
			move_target = _target
			speed = float(cfg["walk_speed"])
		else:
			# Arrived: linger a moment, then settle back into a pause and line up the
			# next outing — pauses grow with the bond so it ranges less as it bonds.
			_linger += delta
			if _linger >= float(cfg.get("wander_linger", 2.5)):
				_state = PAUSE
				_pause_timer = _roll_pause(cfg, rng, s.bond, _trait(s, cfg, "energy"))

		return {
			"behavior": "wander",
			"move_target": move_target,
			"desired_speed": speed,
			"look_at": _target,
			"reactions": reactions,
		}

	# How strongly a self-directed roam competes: high at low bond (its own agenda
	# wins over following), fading toward your side as the bond deepens.
	func _roam_score(s: CompanionSelf, cfg: Dictionary) -> float:
		return lerpf(float(cfg.get("wander_score_low", 7.0)), float(cfg.get("wander_score_high", 2.0)), s.bond)

	# Where to potter off to, picked within the companion's "territory": a disk
	# around the PLAYER. Keeping targets inside this disk matters because the follow
	# leash reels the companion in once following outscores wandering — so a target
	# beyond that crossover would start a tug-of-war the companion never wins,
	# jittering instead of arriving. The territory is exactly that crossover radius
	# (with a hair of margin), which means it shrinks on its own as the bond grows:
	# an independent young companion ranges wide, a bonded one barely leaves your
	# side. (Anchored on the player, so its little range of life moves with you.) A
	# standing prop inside the territory is chosen as a deliberate thing to
	# investigate; otherwise it ambles to an interesting patch of nearby ground.
	func _pick_target(perception: Dictionary, s: CompanionSelf, rng: RandomNumberGenerator, cfg: Dictionary) -> Vector2:
		var player_pos: Vector2 = perception["player_pos"]
		var radius := _territory_radius(s, cfg)
		if perception["has_poi"] and perception["nearest_poi"].distance_to(player_pos) <= radius:
			return perception["nearest_poi"]
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(radius * 0.35, radius)
		return player_pos + Vector2(cos(angle), sin(angle)) * dist

	# How far the companion can roam from the player before following would win and
	# reel it back — the distance where FollowDrive's score crosses this roam's. We
	# stay just inside it (and never beyond roam_radius) so every outing completes.
	func _territory_radius(s: CompanionSelf, cfg: Dictionary) -> float:
		var near := float(cfg["follow_near"])
		var far := float(cfg["follow_far"])
		var leash := float(cfg.get("follow_leash", 0.0))
		var cap := float(cfg.get("roam_radius", 90.0))
		if leash <= 0.0:
			return minf(cap, far)
		var eager := lerpf(float(cfg.get("follow_eager_low", 5.0)), float(cfg.get("follow_eager_high", 5.0)), s.bond)
		var over := clampf((_roam_score(s, cfg) - eager) / leash, 0.0, 1.0)
		return minf(cap, (near + over * (far - near)) * 0.92)

	# Seconds to stand about before the next roam: a base window, stretched as the
	# bond grows (bonded -> ranges less) and shortened for an energetic companion.
	func _roll_pause(cfg: Dictionary, rng: RandomNumberGenerator, bond: float, energy: float) -> float:
		var window: Array = cfg.get("roam_pause", [1.5, 4.0])
		var base := rng.randf_range(float(window[0]), float(window[1]))
		var bond_stretch := lerpf(1.0, float(cfg.get("roam_pause_bond_scale", 2.0)), clampf(bond, 0.0, 1.0))
		var energy_scale := lerpf(1.4, 0.6, clampf(energy, 0.0, 1.0))
		return base * bond_stretch * energy_scale

	# Prefer the (drifting) self trait; fall back to the static personality config.
	func _trait(s: CompanionSelf, cfg: Dictionary, key: String) -> float:
		return s.trait_value(key, _personality(cfg, key))


## The baseline pause beat: stand near where it is and just be present — glance back
## at the player (clinginess), look around now and then, and hop when feeling
## energetic. This is what fills the quiet moments between roams and when settled at
## a bonded player's side.
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
		return s.trait_value(key, _personality(cfg, key))
