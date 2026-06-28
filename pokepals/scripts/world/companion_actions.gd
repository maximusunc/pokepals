class_name CompanionActions
## The library of things the companion can DO, and the interface they share. This
## replaces the old companion_drives.gd. The decisive change is that an action now only
## ever reasons about ITSELF: it scores its own desire from perception + its own state +
## its own config, and never reaches into another action's math. (The old WanderDrive
## recomputed FollowDrive's entire eager+leash formula to find a score "crossover" — the
## exact coupling that made the brain hard to grow. That is gone: Wander now keeps to its
## OWN range and yields to Follow purely through the arbiter's bands + commitment.)
##
## All cross-action concerns — priority, tie-breaks, anti-jitter, interruption — live in
## CompanionArbiter, not here. So adding an action (cook, farm, run an errand) is: write
## one self-contained CompanionAction, give it a band, declare its considerations in
## companion.json. Nothing existing needs to change.
##
## An action is a small stateful object:
##   tick(delta)                       advance always-running timers
##   score(perception, self, cfg, rng) its OWN desire to act now (0 = don't bid); may
##                                     latch internal state when it decides to start
##   act(perception, self, cfg, rng, delta) only the winner is asked; returns the intent
##                                     { behavior, move_target, desired_speed, look_at, reactions }
##   commitment(cfg)                   how hard it resists being abandoned right now, in
##                                     desire units (default = a small anti-jitter nudge; a
##                                     committed beat returns a large value so it finishes)
##
## SEAM — player COMMANDS (not built): a future order ("go run an errand") slots in as one
## CompanionAction on the reserved `command` band (above interrupt), whose score() bids
## only while a command is queued and whose commitment() is large until it's done. Because
## the arbiter compares band first, it would preempt even Investigate with no arbiter change.
## The intended entry point is CompanionBrain.issue_command(...).
##
## SEAM — multi-step / long-running TASKS (not built): the interface already suffices — an
## action owns its own tick()+state, so a RunErrandAction would hold its own sub-step
## machine exactly as WanderAction holds PAUSE/ROAM today. The convention is: take the
## reserved `task` band, and return a large commitment() during a critical step and the base
## nudge at safe checkpoints, so a command or Investigate can still break in but idle chatter
## can't. (Commitment is also where a future graded danger-era salience would generalize.)


static func make_all(cfg: Dictionary, rng: RandomNumberGenerator) -> Array:
	# Array order breaks exact ties in the arbiter (earlier wins), which is why Follow is
	# listed before Wander: the leash backstop should never lose a coin-flip to a roam.
	var bands: Dictionary = cfg.get("arbiter", {}).get("bands", {})
	var b_auto := int(bands.get("autonomous", 1))
	var b_social := int(bands.get("social", 2))
	var b_interrupt := int(bands.get("interrupt", 4))
	var b_command := int(bands.get("command", 5))
	return [
		ComeAction.new(b_command),
		PetAction.new(b_command),
		SeekAction.new(b_command),
		InvestigateAction.new(b_interrupt),
		CheckInAction.new(cfg, rng, b_social),
		LeadAction.new(cfg, b_social),
		FollowAction.new(b_auto),
		WanderAction.new(cfg, rng, b_auto),
		IdleAction.new(cfg, rng, b_auto),
	]


## The interface + safe defaults so an action only overrides what it needs.
class CompanionAction extends RefCounted:
	var id := ""
	var band := 0
	var behavior := ""

	func tick(_delta: float) -> void:
		pass

	func score(_perception: Dictionary, _s: CompanionSelf, _cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		return 0.0

	func act(_perception: Dictionary, _s: CompanionSelf, _cfg: Dictionary, _rng: RandomNumberGenerator, _delta: float) -> Dictionary:
		return {}

	# How strongly this action resists being abandoned RIGHT NOW, in desire units, while it's
	# the one running. The arbiter adds it to this action's own desire, so a SAME-band rival
	# must clear desire + commitment to take over — graded "commitment inertia" that replaces
	# the old fixed commit_bonus and the binary interruptible() flag both. The default is the
	# small universal anti-jitter nudge; a committed beat overrides this to return much more
	# (commit_bonus + committed_inertia) so it finishes rather than being yanked at a score
	# crossover. Higher BANDS still preempt regardless — commitment is within-band only.
	func commitment(cfg: Dictionary) -> float:
		return float(cfg.get("arbiter", {}).get("commit_bonus", 0.0))

	# This action's declared considerations from companion.json, or [] if none.
	func _considerations(cfg: Dictionary) -> Array:
		return cfg.get("actions", {}).get(id, {}).get("considerations", [])


## Player-triggered curiosity: something the player did nearby caught its attention — the
## sacred "it noticed what I did" beat. The NOTICE is instant (it perks and turns to look),
## but coming over is a CONSIDERED choice, not a reflex: it pauses for a beat to weigh it up,
## then sometimes ambles over and sometimes doesn't. The pause and the odds of going both
## scale with bond — a fresh companion hesitates longer and often stays put; a bonded one
## barely pauses and reliably comes — with appeal and current mood tipping the marginal calls
## (a loved find, or a bright/energized mood, makes it readier to go). Even fully bonded a
## slight delay remains, so coming over always reads as a live decision. On a cooldown so a
## flurry of pokes doesn't spam it. On the interrupt band, so it preempts any autonomous beat;
## carries a large commitment while it lasts (consider AND approach) so the beat reads as deliberate.
class InvestigateAction extends CompanionAction:
	var _active := false
	var _target := Vector2.ZERO
	var _linger := 0.0
	var _cooldown := 0.0
	var _just_triggered := false
	# The hesitation: while considering, it stands and looks but doesn't move; _will_approach is
	# the (bond/appeal/mood-weighted) decision rolled when it first notices.
	var _considering := false
	var _consider_timer := 0.0
	var _will_approach := false

	func _init(band_value: int) -> void:
		id = "investigate"
		band = band_value
		behavior = "curious"

	func tick(delta: float) -> void:
		_cooldown = maxf(0.0, _cooldown - delta)

	func score(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		if perception["has_interaction"] and _cooldown <= 0.0 and not _active:
			_active = true
			_target = perception["interaction_point"]
			# Notice now; decide whether/when to actually go during the pause that follows.
			_considering = true
			var cc: Dictionary = cfg.get("curiosity_consider", {})
			_consider_timer = lerpf(float(cc.get("delay_low", 1.3)), float(cc.get("delay_high", 0.4)), s.bond)
			_will_approach = float(perception.get("investigate_roll", 0.0)) < _approach_chance(perception, s, cfg, cc)
			# Set the admiring linger now, while the thing's appraised appeal is still in
			# perception — it lingers longer over a thing it likes. Only spent once it actually
			# goes (the engage branch counts it down), so the pause doesn't eat into it.
			var la: Array = cfg.get("appraisal", {}).get("linger_appeal", [1.0, 1.0])
			var appeal := float(perception.get("interaction_appeal", 1.0))
			_linger = float(cfg["curiosity_linger"]) * lerpf(float(la[0]), float(la[1]), appeal)
			_just_triggered = true
			_cooldown = float(cfg["curiosity_cooldown"])
		return 1.0 if _active else 0.0

	# The odds of coming over: bond is the primary axis; a tempting thing (appeal) and a
	# bright/energized mood nudge it up, a dull thing or a withdrawn mood down. Clamped to a
	# probability. Weights are small so bond stays dominant — appeal and mood only tip the
	# marginal calls (and mood's random walk gives the decision its day-to-day variability).
	func _approach_chance(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, cc: Dictionary) -> float:
		var base := lerpf(float(cc.get("approach_low", 0.35)), float(cc.get("approach_high", 1.0)), s.bond)
		var neutral := float(cfg.get("appraisal", {}).get("neutral", 0.5))
		var appeal := float(perception.get("interaction_appeal", neutral))
		var chance := base
		chance += (appeal - neutral) * float(cc.get("appeal_weight", 0.5))
		chance += s.mood_valence * float(cc.get("valence_weight", 0.15))
		chance += s.mood_arousal * float(cc.get("arousal_weight", 0.15))
		return clampf(chance, 0.0, 1.0)

	func commitment(cfg: Dictionary) -> float:
		# A look in progress is a committed beat, so it reads as deliberate, not a twitch.
		if _active:
			return super.commitment(cfg) + float(cfg.get("arbiter", {}).get("committed_inertia", 0.0))
		return super.commitment(cfg)

	func act(perception: Dictionary, _s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator, delta: float) -> Dictionary:
		var reactions: Array = []
		if _just_triggered:
			reactions.append("perk")
			_just_triggered = false
		var companion_pos: Vector2 = perception["companion_pos"]
		var move_target := companion_pos
		var speed := 0.0
		if _considering:
			# Pause and weigh it up — stand still, keep looking at the thing.
			_consider_timer -= delta
			if _consider_timer <= 0.0:
				_considering = false
				if not _will_approach:
					_active = false  # considered it, decided to stay put
		else:
			# Decided to go: amble over, then admire until the linger runs out.
			_linger -= delta
			if companion_pos.distance_to(_target) > float(cfg["curiosity_stop_distance"]):
				move_target = _target
				speed = float(cfg["walk_speed"])
			if _linger <= 0.0:
				_active = false
		return {
			"behavior": behavior,
			"move_target": move_target,
			"desired_speed": speed,
			"look_at": _target,
			"reactions": reactions,
		}


## Its own idea to come say hi — the heart of feeling attended-to during the independent,
## pre-bond phase. It sets off only when it ISN'T already close and the player is in reach;
## how eager it is fades with the bond (by then Follow keeps it at your side). On the
## social band, above the autonomous beats, so a visit it decides to make wins over
## following/wandering; carries a large commitment while the visit is underway so it commits to it.
class CheckInAction extends CompanionAction:
	var _cooldown := 0.0
	var _active := false
	var _target := Vector2.ZERO
	var _linger := 0.0
	var _just_triggered := false

	func _init(cfg: Dictionary, rng: RandomNumberGenerator, band_value: int) -> void:
		id = "checkin"
		band = band_value
		behavior = "checkin"
		# Stagger the first possible visit so it isn't an instant lurch on spawn.
		_cooldown = _roll_interval(cfg, rng)

	func tick(delta: float) -> void:
		_cooldown = maxf(0.0, _cooldown - delta)

	func commitment(cfg: Dictionary) -> float:
		# A visit underway is committed, so it follows through instead of half-turning back.
		if _active:
			return super.commitment(cfg) + float(cfg.get("arbiter", {}).get("committed_inertia", 0.0))
		return super.commitment(cfg)

	func score(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator) -> float:
		var far := float(cfg["follow_far"])
		if _active:
			# Player walked out of reach mid-visit: give up, let Follow's leash take over.
			if perception["dist_to_player"] > far:
				_active = false
				_cooldown = _roll_interval(cfg, rng)
				return 0.0
			return 1.0
		if _cooldown > 0.0:
			return 0.0
		# Window elapsed: queue the next one regardless, then maybe set off now.
		_cooldown = _roll_interval(cfg, rng)
		var dist: float = perception["dist_to_player"]
		var near: float = perception["follow_near"]
		# Only worth a visit when not already close, and only if the player is in reach.
		if dist <= near or dist > far:
			return 0.0
		# How likely it is to bother right now: eager when fresh, fading to ~0 once bonded;
		# keener the further away; coloured by how sociable this companion is. The SHAPE of
		# each axis is authored as considerations in companion.json (defaults to a plain
		# product, reproducing the old pull * distance * clinginess).
		var inputs := {
			"checkin_pull": lerpf(float(cfg.get("checkin_pull_low", 1.0)), float(cfg.get("checkin_pull_high", 0.0)), s.bond),
			"dist_factor": clampf((dist - near) / maxf(far - near, 1.0), 0.0, 1.0),
			"clinginess": CompanionTraits.value(s, cfg, "clinginess"),
		}
		var specs := _considerations(cfg)
		var chance: float
		if specs.is_empty():
			chance = inputs["checkin_pull"] * inputs["dist_factor"] * inputs["clinginess"]
		else:
			chance = CompanionConsiderations.product(CompanionConsiderations.appeals(specs, inputs))
		if rng.randf() >= chance:
			return 0.0
		_active = true
		_target = perception["player_pos"]
		_linger = float(cfg.get("checkin_linger", 2.5))
		_just_triggered = true
		return 1.0

	func act(perception: Dictionary, _s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator, delta: float) -> Dictionary:
		var reactions: Array = []
		if _just_triggered:
			reactions.append("perk")
			reactions.append("look")
			_just_triggered = false
		# Head toward where the player IS now, not where they were when it set off.
		_target = perception["player_pos"]
		var companion_pos: Vector2 = perception["companion_pos"]
		var move_target := companion_pos
		var speed := 0.0
		if companion_pos.distance_to(_target) > float(cfg.get("checkin_stop_distance", 80.0)):
			move_target = _target
			speed = float(cfg["walk_speed"])
		else:
			# Arrived: settle in to say hi for a moment, then the visit ends.
			_linger -= delta
			if _linger <= 0.0:
				_active = false
		return {
			"behavior": behavior,
			"move_target": move_target,
			"desired_speed": speed,
			"look_at": _target,
			"reactions": reactions,
		}

	func _roll_interval(cfg: Dictionary, rng: RandomNumberGenerator) -> float:
		var window: Array = cfg.get("checkin_interval", [14.0, 26.0])
		return rng.randf_range(float(window[0]), float(window[1]))


## Stay with the player: trail behind, strolling when just behind, hustling when far.
## Desire is eagerness (rises with the bond, coloured by clinginess) PLUS a distance leash
## past the bond-scaled comfort distance. A comfort-bubble deadzone keeps it from rigidly
## snapping to one trailing point. Stateless — the arbiter's commitment bonus gives it
## whatever hysteresis it needs, so it carries no anti-jitter logic of its own.
class FollowAction extends CompanionAction:
	func _init(band_value: int) -> void:
		id = "follow"
		band = band_value
		behavior = "follow"

	func score(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		var dist: float = perception["dist_to_player"]
		var near := float(perception["follow_near"])
		if dist <= near:
			return 0.0
		var eager_high := float(cfg.get("follow_eager_high", 5.0))
		# Inside the comfort bubble just past the comfort distance, pull only gently so the
		# autonomous beats can win and the companion mills about instead of snapping rigid.
		var deadzone := float(cfg.get("follow_deadzone", 0.0))
		if dist <= near + deadzone:
			return lerpf(0.0, eager_high * 0.25, s.bond)
		# Eagerness rises with the bond and is coloured by the clinginess trait.
		var eager := lerpf(float(cfg.get("follow_eager_low", 5.0)), eager_high, s.bond)
		eager = CompanionTraits.apply_mult(eager, { "trait": "clinginess", "lo": 0.8, "hi": 1.2 }, s, cfg)
		var far := float(cfg["follow_far"])
		var over := clampf((dist - near) / maxf(far - near, 1.0), 0.0, 1.0)
		var leash := over * float(cfg.get("follow_leash", 0.0))
		return eager + leash

	func act(perception: Dictionary, _s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator, _delta: float) -> Dictionary:
		var dist: float = perception["dist_to_player"]
		var run_at := float(cfg.get("run_distance", cfg.get("follow_far", 200.0)))
		var speed := float(cfg["run_speed"]) if dist > run_at else float(cfg["walk_speed"])
		return {
			"behavior": behavior,
			"move_target": perception["follow_point"],
			"desired_speed": speed,
			"look_at": perception["player_pos"],
			"reactions": [],
		}


## Its own life — the engine of the independent, pre-bond phase. It moseys to a little
## spot, pauses to look around, then picks somewhere new. A PAUSE/ROAM machine: PAUSE bids
## nothing (Idle owns the beat), ROAM bids the bond-scaled roam score (high when fresh,
## fading as you bond). Crucially it roams only within its OWN range (wide when fresh, snug
## when bonded) and abandons a target the player has dragged out of that range — it never
## consults Follow's scoring; it just yields its band to Follow when it stops bidding. A
## roam is a COMMITTED beat (see commitment()): once set off its large commitment keeps the
## same-band Follow from out-bidding it, only a higher band breaks in — so it finishes its
## excursion (or gives up because you left) rather than getting yanked at the score crossover.
class WanderAction extends CompanionAction:
	enum { PAUSE, ROAM }
	var _state := PAUSE
	var _pause_timer := 0.0
	var _target := Vector2.ZERO
	var _linger := 0.0
	var _just_set_off := false
	# Stuck-guard bookkeeping: the body's position last act() and how long it's been
	# trying-but-failing to make headway toward a roam target (see act()).
	var _prev_pos := Vector2.ZERO
	var _has_prev := false
	var _stuck := 0.0

	func _init(cfg: Dictionary, rng: RandomNumberGenerator, band_value: int) -> void:
		id = "wander"
		band = band_value
		behavior = "wander"
		# Start on a pause so the very first frame is calm, not a lurch into motion.
		_pause_timer = _roll_pause(cfg, rng, 0.0, 0.5)

	func tick(delta: float) -> void:
		# Count down toward the next roam only while paused; the roam's own linger is
		# advanced in act(), so it never elapses unseen while another action holds control.
		if _state == PAUSE:
			_pause_timer = maxf(0.0, _pause_timer - delta)

	# A roam is a COMMITTED BEAT: while ROAM it returns a large commitment, so the same-band
	# Follow can't out-bid it and yank it off mid-excursion. This is what kills the
	# wander<->follow limit cycle — without it, Follow unseats a roam at the score crossover,
	# the companion's own motion re-crosses the threshold, and it paces in a shell around the
	# player. The inertia must exceed any same-band rival's plausible desire, so the roam is
	# released only by its own state (the give-up check in score() drops to PAUSE / bids 0
	# when the player leaves the target behind), never by a desire crossover — that
	# state-based release is what stops the cycle from simply re-forming at a higher threshold.
	# A strictly higher band (a look, a visit, a future command) still preempts. While PAUSED
	# we're idle and carry only the base nudge.
	func commitment(cfg: Dictionary) -> float:
		if _state == ROAM:
			return super.commitment(cfg) + float(cfg.get("arbiter", {}).get("committed_inertia", 0.0))
		return super.commitment(cfg)

	func score(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator) -> float:
		if _state == ROAM:
			# Give up a target the player has dragged out of our OWN reachable range (range
			# + a slack margin, seeded from the comfort bubble so a small drift never trips
			# it). Then pause and bid nothing — the arbiter hands the band to Follow, which
			# is now the keener bid, with no need to know Follow's formula.
			var slack := float(cfg.get("roam_slack", cfg.get("follow_deadzone", 0.0)))
			if _target.distance_to(perception["player_pos"]) > _wander_range(s, cfg) + slack:
				_state = PAUSE
				_pause_timer = _roll_pause(cfg, rng, s.bond, CompanionTraits.value(s, cfg, "energy"))
				return 0.0
			return _roam_score(s, cfg)
		# Paused: ready to set off once the timer elapses and the player is close enough
		# that wandering, not following, is the thing to be doing.
		if _pause_timer <= 0.0 and perception["dist_to_player"] <= float(cfg["follow_far"]):
			_target = _pick_target(perception, s, rng, cfg)
			_state = ROAM
			_linger = 0.0
			_just_set_off = true
			_has_prev = false
			_stuck = 0.0
			return _roam_score(s, cfg)
		return 0.0

	func act(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator, delta: float) -> Dictionary:
		var reactions: Array = []
		if _just_set_off:
			reactions.append("look")
			if rng.randf() < CompanionTraits.value(s, cfg, "energy") * 0.4:
				reactions.append("hop")
			_just_set_off = false

		var companion_pos: Vector2 = perception["companion_pos"]
		var move_target := companion_pos
		var speed := 0.0
		if companion_pos.distance_to(_target) > float(cfg["curiosity_stop_distance"]):
			move_target = _target
			speed = float(cfg["walk_speed"])
			# Stuck-guard. A roam target can land beyond a barrier the companion can't get
			# past — the border treeline, a solid prop, the map edge — and it has no
			# path-finding: the body just slides along the obstacle while the edge clamps it.
			# Without this it grinds there forever, because it never reaches
			# curiosity_stop_distance to begin its linger, and the player-left give-up in
			# score() never trips while the player stands by. So watch our OWN body: if we
			# mean to walk yet barely move for a moment, the way is blocked — abandon the
			# roam and pause. (Pure self-observation, so the brain stays geometry-blind: it
			# reads its own position each frame, never the world's solids.)
			if _has_prev:
				var moved := companion_pos.distance_to(_prev_pos)
				var expected := float(cfg["walk_speed"]) * delta
				if moved < expected * float(cfg.get("wander_stuck_fraction", 0.3)):
					_stuck += delta
				else:
					_stuck = 0.0
			_prev_pos = companion_pos
			_has_prev = true
			if _stuck >= float(cfg.get("wander_stuck_time", 0.5)):
				_state = PAUSE
				_pause_timer = _roll_pause(cfg, rng, s.bond, CompanionTraits.value(s, cfg, "energy"))
				move_target = companion_pos
				speed = 0.0
		else:
			_linger += delta
			if _linger >= float(cfg.get("wander_linger", 2.5)):
				_state = PAUSE
				_pause_timer = _roll_pause(cfg, rng, s.bond, CompanionTraits.value(s, cfg, "energy"))

		return {
			"behavior": behavior,
			"move_target": move_target,
			"desired_speed": speed,
			"look_at": _target,
			"reactions": reactions,
		}

	# How strongly a self-directed roam competes: high at low bond, fading toward your side
	# as the bond deepens (kept above 0 so a bonded companion still potters).
	func _roam_score(s: CompanionSelf, cfg: Dictionary) -> float:
		return lerpf(float(cfg.get("wander_score_low", 7.0)), float(cfg.get("wander_score_high", 2.0)), s.bond)

	# The companion's OWN roaming range around the player: wide when fresh (roam_radius),
	# shrinking toward a floor (wander_min_radius) as the bond grows, with an energetic
	# companion using a touch more of it. No reference to Follow — anti-jitter is the
	# arbiter's job now, not a hand-computed crossover.
	func _wander_range(s: CompanionSelf, cfg: Dictionary) -> float:
		var wide := float(cfg.get("roam_radius", 90.0))
		var snug := float(cfg.get("wander_min_radius", wide))
		var r := lerpf(wide, snug, clampf(s.bond, 0.0, 1.0))
		r *= lerpf(0.8, 1.25, CompanionTraits.value(s, cfg, "energy"))
		return clampf(r, snug, wide)

	# Where to potter off to, within our own range: a standing prop if a curious companion
	# fancies it, otherwise an interesting patch of nearby ground.
	func _pick_target(perception: Dictionary, s: CompanionSelf, rng: RandomNumberGenerator, cfg: Dictionary) -> Vector2:
		var player_pos: Vector2 = perception["player_pos"]
		var radius := _wander_range(s, cfg)
		# Social referencing — the player-cue bias: when bonded, often go potter over to
		# whatever the player is attending to, so your focus gradually steers where it
		# explores (the cozy version of "leading it through content", no command needed).
		# Strictly BOND-GATED — a fresh companion ignores the cue — and scaled by signal
		# strength. Pre-rolled die, so no action-RNG draw. This stays layered ON TOP of the
		# independent target logic below, which never switches off (anti-mirroring).
		if bool(perception.get("has_attended", false)) and s.bond > 0.0:
			var cue_chance := s.bond * float(perception.get("attention_strength", 0.0)) * float(cfg.get("attention", {}).get("cue_weight", 0.8))
			if float(perception.get("cue_roll", 1.0)) < cue_chance:
				return perception["attended_object"]
		if perception["has_poi"] and perception["nearest_poi"].distance_to(player_pos) <= radius:
			if rng.randf() < CompanionTraits.value(s, cfg, "curiosity"):
				return perception["nearest_poi"]
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(radius * 0.1, radius)
		return player_pos + Vector2(cos(angle), sin(angle)) * dist

	# Seconds to stand about before the next roam: a base window, stretched as the bond
	# grows (bonded -> ranges less) and shortened for an energetic companion.
	func _roll_pause(cfg: Dictionary, rng: RandomNumberGenerator, bond: float, energy: float) -> float:
		var window: Array = cfg.get("roam_pause", [1.5, 4.0])
		var base := rng.randf_range(float(window[0]), float(window[1]))
		var bond_stretch := lerpf(1.0, float(cfg.get("roam_pause_bond_scale", 2.0)), clampf(bond, 0.0, 1.0))
		var energy_scale := lerpf(1.4, 0.6, clampf(energy, 0.0, 1.0))
		return base * bond_stretch * energy_scale


## The baseline pause beat: stand, breathe, glance back at the player (clinginess), look
## around now and then, hop when energetic. The lowest of the autonomous beats — it wins
## whenever nothing else is bidding, filling the quiet moments.
class IdleAction extends CompanionAction:
	var _look_timer := 0.0
	var _look_at := Vector2.ZERO
	var _has_look := false

	func _init(cfg: Dictionary, rng: RandomNumberGenerator, band_value: int) -> void:
		id = "idle"
		band = band_value
		behavior = "idle"
		_look_timer = _roll_interval(cfg, rng)

	func _roll_interval(cfg: Dictionary, rng: RandomNumberGenerator) -> float:
		var interval: Array = cfg["idle_look_interval"]
		return rng.randf_range(float(interval[0]), float(interval[1]))

	func score(_perception: Dictionary, _s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		return float(cfg.get("actions", {}).get("idle", {}).get("weight", 1.0))

	func act(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator, delta: float) -> Dictionary:
		var companion_pos: Vector2 = perception["companion_pos"]
		var player_pos: Vector2 = perception["player_pos"]
		var reactions: Array = []

		_look_timer -= delta
		if _look_timer <= 0.0:
			_look_timer = _roll_interval(cfg, rng)
			if rng.randf() < CompanionTraits.value(s, cfg, "clinginess"):
				_look_at = player_pos
			else:
				_look_at = companion_pos + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 48.0
			# Social referencing: the glance sometimes lands on whatever the PLAYER is
			# attending to instead. A low BOND FLOOR means even a fresh companion flicks its
			# eyes there now and then (curiosity-driven), looking more as you bond. Uses the
			# pre-rolled referencing die, so the action RNG stream above is untouched.
			if bool(perception.get("has_attended", false)):
				var ac: Dictionary = cfg.get("attention", {})
				var strength := float(perception.get("attention_strength", 0.0))
				var glance_chance := strength * lerpf(float(ac.get("glance_floor", 0.35)), 1.0, s.bond) * CompanionTraits.value(s, cfg, "curiosity") * float(ac.get("glance_gain", 1.0))
				if float(perception.get("glance_roll", 1.0)) < glance_chance:
					_look_at = perception["attended_object"]
			_has_look = true
			reactions.append("look")
			if rng.randf() < CompanionTraits.value(s, cfg, "energy") * 0.5:
				reactions.append("hop")

		return {
			"behavior": behavior,
			"move_target": companion_pos,
			"desired_speed": 0.0,
			"look_at": _look_at if _has_look else player_pos,
			"reactions": reactions,
		}


## The player's CALL / whistle — the implementation of the reserved `command` band. A whistle
## is a BID for attention, not a guaranteed summon, and it leans on the same two axes the whole
## game is built around: distance and bond. First DISTANCE gates it — beyond hear_radius the
## companion simply can't hear you, so the call no-ops (it never reaches across the whole map;
## if it has wandered off you may have to go to it). When it does hear, it ACKNOWLEDGES — stands,
## looks over and perks for a beat, with a small mood lift from being noticed — and only THEN,
## by BOND, decides whether to come: a fresh companion usually just acknowledges and carries on,
## a bonded one reliably comes running. So the call's power grows with the relationship, the same
## arc as the follow-distance tightening. On the command band, so the acknowledgment preempts any
## autonomous beat; calling never grows bond (a whistle isn't earned discovery). Once it arrives
## it doesn't park at the call spot and bolt — it ESCORTS you, sticking close and following while
## you move, drifting back to its own life only a beat after you settle (so you can whistle it
## along on the way somewhere).
class ComeAction extends CompanionAction:
	enum { ACK, COME, ESCORT }
	var _active := false
	var _phase := ACK
	var _ack_timer := 0.0
	var _will_come := false
	var _just_triggered := false
	var _escort_timer := 0.0

	func _init(band_value: int) -> void:
		id = "come"
		band = band_value
		behavior = "come"

	func commitment(cfg: Dictionary) -> float:
		# A call in progress (acknowledging, or on its way over) is a committed beat, so it
		# follows through rather than being yanked by an autonomous urge mid-acknowledgment.
		if _active:
			return super.commitment(cfg) + float(cfg.get("arbiter", {}).get("committed_inertia", 0.0))
		return super.commitment(cfg)

	func score(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		if String(perception.get("command", "")) == "come" and not _active:
			var come: Dictionary = cfg.get("come", {})
			# Out of earshot: it can't hear you, so the whistle does nothing at all.
			if float(perception["dist_to_player"]) > float(come.get("hear_radius", 900.0)):
				return 0.0
			# Heard: latch and acknowledge first; the mood lifts at being called whether or not
			# it then comes. Decide the come/stay outcome now (bond-gated, mood-nudged).
			_active = true
			_phase = ACK
			_ack_timer = float(come.get("ack_pause", 0.5))
			_just_triggered = true
			_will_come = float(perception.get("command_roll", 1.0)) < _come_chance(s, come)
			s.apply_command_ack(cfg)
		return 1.0 if _active else 0.0

	# Odds it actually comes once it has heard you: bond is the axis, with a small mood nudge so a
	# bright/energized companion is a touch readier. Clamped to a probability.
	func _come_chance(s: CompanionSelf, come: Dictionary) -> float:
		var chance := lerpf(float(come.get("chance_low", 0.1)), float(come.get("chance_high", 1.0)), s.bond)
		chance += s.mood_valence * float(come.get("valence_weight", 0.0))
		chance += s.mood_arousal * float(come.get("arousal_weight", 0.0))
		return clampf(chance, 0.0, 1.0)

	func act(perception: Dictionary, _s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator, delta: float) -> Dictionary:
		var come: Dictionary = cfg.get("come", {})
		var companion_pos: Vector2 = perception["companion_pos"]
		var player_pos: Vector2 = perception["player_pos"]
		var move_target := companion_pos
		var speed := 0.0
		var reactions: Array = []
		if _just_triggered:
			# The instant "I heard you" beat: perk and turn toward the player.
			reactions.append("perk")
			reactions.append("look")
			_just_triggered = false
		var stop_distance := float(come.get("stop_distance", 48.0))
		if _phase == ACK:
			# Hold a beat to acknowledge, standing and looking at the player.
			_ack_timer -= delta
			if _ack_timer <= 0.0:
				if _will_come:
					_phase = COME
				else:
					_active = false  # acknowledged, but chose to stay its own course
		elif _phase == COME:
			# Coming over: run to the player, then a happy arrival hop, and fall in beside you.
			if companion_pos.distance_to(player_pos) > stop_distance:
				move_target = player_pos
				speed = float(cfg["run_speed"])
			else:
				reactions.append("hop")
				reactions.append("look")
				_escort_timer = float(come.get("stay", 3.0))
				_phase = ESCORT
		else:
			# ESCORT: stick close and travel with you. Stay near (run if you've pulled ahead,
			# walk if just trailing), keep facing you. The window refreshes while you're moving,
			# so it accompanies you the whole way; once you settle it counts down and only then
			# drifts back to its own life — it doesn't bolt the instant it arrives.
			var dist := companion_pos.distance_to(player_pos)
			if dist > stop_distance:
				move_target = player_pos
				speed = float(cfg["run_speed"]) if dist > float(cfg.get("run_distance", 160.0)) else float(cfg["walk_speed"])
			if bool(perception.get("player_moving", false)):
				_escort_timer = float(come.get("stay", 3.0))
			else:
				_escort_timer -= delta
			if _escort_timer <= 0.0:
				_active = false
		return {
			"behavior": behavior,
			"move_target": move_target,
			"desired_speed": speed,
			"look_at": player_pos,
			"reactions": reactions,
		}


## A deliberate PET when you're right beside it — also on the command band, sharing the
## issue_command channel ("pet"), self-gated on distance. What it does is BOND-dependent: a
## bonded companion leans in (a step toward you, a heart, a warm mood lift and a small,
## un-grindable bond gain); a fresh, wary one often SHIES a little away instead (a startle step
## back, a tiny mood dip, no bond) — it doesn't trust you yet. So petting a stranger is a gamble
## and petting a friend is reliably sweet: the relationship is the mechanic. The accept/shy
## outcome rides the pre-rolled pet_roll on the dedicated command stream (no action-RNG draw).
class PetAction extends CompanionAction:
	var _active := false
	var _accept := false
	var _timer := 0.0
	var _just_triggered := false
	var _step_target := Vector2.ZERO

	func _init(band_value: int) -> void:
		id = "pet"
		band = band_value
		behavior = "pet"

	func commitment(cfg: Dictionary) -> float:
		if _active:
			return super.commitment(cfg) + float(cfg.get("arbiter", {}).get("committed_inertia", 0.0))
		return super.commitment(cfg)

	func score(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		if String(perception.get("command", "")) == "pet" and not _active:
			var pet: Dictionary = cfg.get("pet", {})
			# Only a pet you can actually reach lands; out of range the order silently no-ops.
			if float(perception["dist_to_player"]) > float(pet.get("range", 56.0)):
				return 0.0
			_active = true
			_timer = float(pet.get("duration", 1.0))
			_just_triggered = true
			# Welcome it, or shy away? Bond is the axis, via the pre-rolled die.
			var accept_chance := lerpf(float(pet.get("accept_low", 0.25)), float(pet.get("accept_high", 1.0)), s.bond)
			_accept = float(perception.get("pet_roll", 1.0)) < accept_chance
			# Where it ends up: a small step TOWARD you if welcomed, a startle step BACK if not.
			var companion_pos: Vector2 = perception["companion_pos"]
			var player_pos: Vector2 = perception["player_pos"]
			var toward := player_pos - companion_pos
			if toward.length() < 1.0:
				toward = Vector2.RIGHT
			toward = toward.normalized()
			var step := float(pet.get("step", 14.0))
			_step_target = companion_pos + (toward * step if _accept else -toward * step)
			if _accept:
				s.pet(cfg)
			else:
				s.pet_rebuff(cfg)
		return 1.0 if _active else 0.0

	func act(perception: Dictionary, _s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator, delta: float) -> Dictionary:
		var companion_pos: Vector2 = perception["companion_pos"]
		var player_pos: Vector2 = perception["player_pos"]
		var reactions: Array = []
		if _just_triggered:
			reactions.append("love" if _accept else "perk")
			_just_triggered = false
		var move_target := companion_pos
		var speed := 0.0
		# Ease the little lean-in / shy-away over the beat, then settle and release.
		if companion_pos.distance_to(_step_target) > 2.0:
			move_target = _step_target
			speed = float(cfg["walk_speed"])
		_timer -= delta
		if _timer <= 0.0:
			_active = false
		return {
			"behavior": behavior,
			"move_target": move_target,
			"desired_speed": speed,
			"look_at": player_pos,
			"reactions": reactions,
		}


## Companion-LED discovery — the companion's OWN initiative to take YOU somewhere. The deepest
## partnership beat: it stops reacting to you and instead picks an appealing, still-novel prop,
## beckons, and leads you to it, glancing back to check you're following, then presents the find
## with a delight and a shared-discovery bond/mood bump. Reserved for a FULLY bonded companion
## (leading you to share something is what a partner who completely trusts you does). On the
## social band with a CheckIn-like spacing — but DETERMINISTIC throughout (deterministic interval,
## nearest qualifying prop, no dice), so it draws no action RNG and leaves the seeded suite
## byte-identical. Gives up gracefully if you don't follow. A large commitment while underway so
## the trek reads as deliberate; a player look or command (higher band) still breaks in.
class LeadAction extends CompanionAction:
	enum { BECKON, TRAVEL, ARRIVE }
	var _cooldown := 0.0
	var _active := false
	var _phase := BECKON
	var _target := Vector2.ZERO
	var _target_id := ""
	var _target_appeal := 0.5
	var _just_triggered := false
	var _beckon_timer := 0.0
	var _glance_timer := 0.0
	var _glancing := false
	var _glance_left := 0.0
	var _patience := 0.0
	var _linger := 0.0
	var _presented := false

	func _init(cfg: Dictionary, band_value: int) -> void:
		id = "lead"
		band = band_value
		behavior = "lead"
		# An initial delay so it never leads on spawn. Deterministic (no rng) by design.
		_cooldown = float(cfg.get("lead", {}).get("interval", 40.0))

	func tick(delta: float) -> void:
		if not _active:
			_cooldown = maxf(0.0, _cooldown - delta)

	func commitment(cfg: Dictionary) -> float:
		if _active:
			return super.commitment(cfg) + float(cfg.get("arbiter", {}).get("committed_inertia", 0.0))
		return super.commitment(cfg)

	func score(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		if _active:
			return 1.0
		if _cooldown > 0.0:
			return 0.0
		var lead: Dictionary = cfg.get("lead", {})
		# Window elapsed: re-arm the spacing regardless (deterministic), then maybe set off.
		_cooldown = float(lead.get("interval", 40.0))
		# Only a FULLY bonded companion leads; only to a prop it likes and that's still novel.
		if s.bond < float(lead.get("min_bond", 1.0)):
			return 0.0
		if not bool(perception.get("has_poi", false)):
			return 0.0
		if float(perception.get("nearest_poi_appeal", 0.0)) < float(lead.get("min_appeal", 0.6)):
			return 0.0
		if float(perception.get("nearest_poi_novelty", 0.0)) < float(lead.get("min_novelty", 0.5)):
			return 0.0
		# Set off: beckon first.
		_active = true
		_phase = BECKON
		_target = perception["nearest_poi"]
		_target_id = String(perception.get("nearest_poi_id", ""))
		_target_appeal = float(perception.get("nearest_poi_appeal", 0.5))
		_beckon_timer = float(lead.get("beckon_time", 0.8))
		_glance_timer = 0.0
		_glancing = false
		_patience = 0.0
		_presented = false
		_just_triggered = true
		return 1.0

	func act(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, _rng: RandomNumberGenerator, delta: float) -> Dictionary:
		var lead: Dictionary = cfg.get("lead", {})
		var companion_pos: Vector2 = perception["companion_pos"]
		var player_pos: Vector2 = perception["player_pos"]
		var move_target := companion_pos
		var speed := 0.0
		var look_at := _target
		var reactions: Array = []
		if _just_triggered:
			reactions.append("perk")
			reactions.append("look")
			_just_triggered = false
		match _phase:
			BECKON:
				# Stand and call you over before setting off.
				look_at = player_pos
				_beckon_timer -= delta
				if _beckon_timer <= 0.0:
					_phase = TRAVEL
			TRAVEL:
				# Give up gracefully if you don't keep up for a while.
				if player_pos.distance_to(companion_pos) > float(lead.get("follow_check_distance", 320.0)):
					_patience += delta
				else:
					_patience = 0.0
				if _patience >= float(lead.get("patience", 4.0)):
					_active = false
				elif _glancing:
					# Paused to look back and check you're coming.
					look_at = player_pos
					_glance_left -= delta
					if _glance_left <= 0.0:
						_glancing = false
						_glance_timer = 0.0
				elif companion_pos.distance_to(_target) <= float(lead.get("stop_distance", 40.0)):
					_phase = ARRIVE
					_linger = float(lead.get("present_linger", 2.0))
				else:
					# Walk toward the find; periodically stop to glance back.
					move_target = _target
					speed = float(cfg["walk_speed"])
					_glance_timer += delta
					if _glance_timer >= float(lead.get("glance_interval", 1.5)):
						_glancing = true
						_glance_left = float(lead.get("glance_pause", 0.5))
			ARRIVE:
				look_at = _target
				if not _presented:
					reactions.append("delight")
					s.record_led_discovery(_target_id, _target_appeal, cfg)
					_presented = true
				_linger -= delta
				if _linger <= 0.0:
					_active = false
		return {
			"behavior": behavior,
			"move_target": move_target,
			"desired_speed": speed,
			"look_at": look_at,
			"reactions": reactions,
		}


## The player's "GO LOOK" — sending the companion off to SEARCH on its own. The spine of the Ruin:
## you don't steer it to a spot, you DELEGATE, and it ranges out under its own agency, truth-blind
## (it never learns where the hidden plate is — the world tells it nothing). The controller is the
## referee that watches the sweep and, when it brings the companion near a buried plate, uncovers
## the plate and re-commands "settle" with the now-revealed point. So Seek has two faces caught off
## the same command channel: "seek" starts the sweep; "settle" (carrying a command_point) turns the
## sweep into a walk-over-and-stand. On the command band so it preempts autonomous living; a large
## commitment while underway so a stray urge can't yank it off the search. The sweep is bond-
## flavoured — a bonded companion ranges wider and with intent, a fresh one mills in tight, fidgety
## hops — so how well the search goes IS the relationship, the same arc as the salamander tell. It
## searches OUTWARD FROM THE PLAYER, so where you stand softly biases where it looks (accompaniment,
## never a leash). Releasing after the settle-hold lets Follow resume; a latched slab stays open.
class SeekAction extends CompanionAction:
	enum { SEARCH, GO, HOLD }
	var _active := false
	var _phase := SEARCH
	var _target := Vector2.ZERO   # current sweep waypoint (SEARCH) or the settle point (GO/HOLD)
	var _dwell := 0.0             # sniff pause at a reached sweep waypoint
	var _hold_left := 0.0
	var _just_triggered := false
	var _arrived := false

	func _init(band_value: int) -> void:
		id = "seek"
		band = band_value
		behavior = "seek"

	func commitment(cfg: Dictionary) -> float:
		if _active:
			return super.commitment(cfg) + float(cfg.get("arbiter", {}).get("committed_inertia", 0.0))
		return super.commitment(cfg)

	func score(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator) -> float:
		var command := String(perception.get("command", ""))
		if command == "seek":
			# Start (or restart) the sweep — head off to nose around.
			_active = true
			_phase = SEARCH
			_dwell = 0.0
			_arrived = false
			_just_triggered = true
			_target = _pick_sweep(perception, s, cfg, rng)
		elif command == "settle":
			# Go to (and stand on) a specific point: the controller pointing us at a revealed plate after
			# a search, OR a directed step in the Cistern carry (fetch the light, then bring it to the
			# brazier). Latches on its own — no prior "seek" needed — so the carry can drive it standalone.
			var pt: Variant = perception.get("command_point")
			if pt is Vector2:
				_active = true
				_phase = GO
				_target = pt
				_arrived = false
		return 1.0 if _active else 0.0

	func act(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator, delta: float) -> Dictionary:
		var seek: Dictionary = cfg.get("seek", {})
		var companion_pos: Vector2 = perception["companion_pos"]
		var move_target := companion_pos
		var speed := 0.0
		var reactions: Array = []
		if _just_triggered:
			reactions.append("perk")
			reactions.append("look")
			_just_triggered = false
		var stop := float(cfg.get("curiosity_stop_distance", 30.0))
		match _phase:
			SEARCH:
				# Sweep: walk to a waypoint, pause to sniff, pick the next. The controller will
				# interrupt with "settle" the moment the sweep noses near the hidden plate.
				if companion_pos.distance_to(_target) > stop:
					move_target = _target
					speed = float(cfg["walk_speed"])
				else:
					_dwell += delta
					if _dwell >= float(seek.get("sniff_pause", 0.7)):
						_dwell = 0.0
						_target = _pick_sweep(perception, s, cfg, rng)
						reactions.append("look")
			GO:
				# Amble the last bit onto the revealed plate.
				if companion_pos.distance_to(_target) > stop:
					move_target = _target
					speed = float(cfg["walk_speed"])
				else:
					_phase = HOLD
					_hold_left = float(seek.get("hold_seconds", 3.0))
					if not _arrived:
						reactions.append("love")  # found it!
						_arrived = true
			HOLD:
				# Settle ON the plate so the referee registers the weight; just stand and breathe,
				# then release back to its own life (the latched slab stays raised).
				move_target = _target
				_hold_left -= delta
				if _hold_left <= 0.0:
					_active = false
		return {
			"behavior": behavior,
			"move_target": move_target,
			"desired_speed": speed,
			"look_at": _target,
			"reactions": reactions,
		}

	# A fresh sweep waypoint: a point out around the PLAYER (so where you stand biases the search),
	# at a reach that grows with bond — a bonded companion searches wider and with purpose, a fresh
	# one keeps it tight and fidgety. Pure geometry; it never consults where the plate actually is.
	func _pick_sweep(perception: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator) -> Vector2:
		var seek: Dictionary = cfg.get("seek", {})
		var player_pos: Vector2 = perception["player_pos"]
		var near := float(seek.get("reach_near", 90.0))
		var far := lerpf(float(seek.get("reach_low", 180.0)), float(seek.get("reach_high", 300.0)), s.bond)
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(near, maxf(near + 1.0, far))
		return player_pos + Vector2(cos(angle), sin(angle)) * dist
