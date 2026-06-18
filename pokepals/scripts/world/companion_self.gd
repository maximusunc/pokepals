class_name CompanionSelf
extends RefCounted
## The companion's persistent IDENTITY — the part of its mind that carries across
## sessions and slowly comes to reflect the player. This is pure data plus
## serialization: no file IO and no scene-tree references, so it stays portable
## (it could be saved on a server later) and is trivially testable.
##
##   traits:       0..1 personality dimensions that DRIFT over time (curiosity,
##                 energy, clinginess, ...). They bias how the companion behaves.
##   bond:         0..1 the RELATIONSHIP itself, separate from personality. It
##                 starts near 0 — a fresh companion is its own creature, happier
##                 to wander and investigate than to follow — and grows, mostly
##                 monotonically, the more time you spend together. As it grows the
##                 companion chooses to follow you more and stray less. This is the
##                 "bond deepens over time" arc, kept apart from the trait drift so
##                 the two effects stay legible.
##   observations: running tallies of how the player actually plays. The raw
##                 material that drift reads to nudge traits.
##   mood:         a light, fast-moving FEELING, modelled in 2D — valence (withdrawn
##                 ↔ warm) and arousal (calm ↔ energized). It relaxes toward a resting
##                 point derived from the companion's traits (so each one has its own
##                 emotional "weather"), spikes on events, drifts with a small random
##                 walk, and leans cozy-positive. It's a transient OVERLAY on the
##                 traits, not character — see CompanionTraits.
##   short_term:   small working memory (e.g. the last point of interest).
##   familiarity:  per-prop encounter tallies (keyed by a stable prop id). Bond
##                 gain from examining a thing is NOVELTY-weighted against this, so
##                 the first real encounter pays and repeats fade to ~0 — you can't
##                 farm bond by poking one prop. Permanent (a familiar prop stays
##                 quiet); this is also the seed of the companion's memory.
##
## from_dict() always starts from make_default() and layers saved values on top,
## so older save files keep loading as the schema grows.

const SCHEMA_VERSION := 1

var traits: Dictionary = {}
var bond: float = 0.0
var observations: Dictionary = {}
var mood_valence: float = 0.0
var mood_arousal: float = 0.0
var short_term: Dictionary = {}
var familiarity: Dictionary = {}

# Transient scratch — NOT persisted (recomputed each frame / harmless to reset on load).
# The novelty of the prop examined this frame (0 if none), handed from _grow_bond to the
# mood update so a habituated prop barely moves the mood. And how long it's been since
# anything novel happened, for the boredom drift.
var _last_discovery_novelty: float = 0.0
var _seconds_since_novelty: float = 999.0


## A fresh self seeded from the companion config. Traits come from an explicit
## "traits" block if present, otherwise from the legacy "personality" block so
## existing data files keep working unchanged.
static func make_default(cfg: Dictionary) -> CompanionSelf:
	var s := CompanionSelf.new()
	s.traits = _default_traits(cfg)
	s.bond = clampf(float(cfg.get("bond", {}).get("init", 0.0)), 0.0, 1.0)
	s.observations = _default_observations()
	s.mood_valence = 0.0
	s.mood_arousal = 0.0
	s.short_term = {}
	s.familiarity = {}
	return s


## A fresh self with GENTLY randomized traits, for a newly created or reset
## companion. Identical to make_default except each trait is jittered within a small
## spread around its init, so playthroughs differ a little (one a touch more
## wander-inclined, another more drawn to props, another more of a follower) without
## becoming pronounced archetypes. The deterministic make_default path is left alone
## so tests and first-run feel stay exact.
static func make_random(cfg: Dictionary, rng: RandomNumberGenerator) -> CompanionSelf:
	var s := make_default(cfg)
	if cfg.has("traits"):
		var default_spread := float(cfg.get("trait_spread", 0.12))
		for key in cfg["traits"]:
			# Skip doc-only entries like "_comment"; real traits are objects.
			if not (cfg["traits"][key] is Dictionary):
				continue
			var spec: Dictionary = cfg["traits"][key]
			var init := float(spec.get("init", 0.5))
			var spread := float(spec.get("spread", default_spread))
			var jittered := init + rng.randf_range(-spread, spread)
			s.traits[key] = clampf(jittered, float(spec.get("min", 0.0)), float(spec.get("max", 1.0)))
	return s


static func _default_traits(cfg: Dictionary) -> Dictionary:
	var out := {}
	if cfg.has("traits"):
		for key in cfg["traits"]:
			# Skip doc-only entries like "_comment"; real traits are objects.
			if not (cfg["traits"][key] is Dictionary):
				continue
			var spec: Dictionary = cfg["traits"][key]
			out[key] = clampf(float(spec.get("init", 0.5)), 0.0, 1.0)
	elif cfg.has("personality"):
		for key in cfg["personality"]:
			out[key] = clampf(float(cfg["personality"][key]), 0.0, 1.0)
	return out


static func _default_observations() -> Dictionary:
	return {
		"explored_distance": 0.0,  # total distance the player has roamed
		"time_near": 0.0,          # seconds the player spent close to us
		"time_far": 0.0,           # seconds the player spent away from us
		"interactions": 0.0,       # things the player examined nearby
		"play_seconds": 0.0,       # total observed time
	}


## Read a trait, tolerating ones that don't exist yet.
func trait_value(key: String, fallback: float = 0.5) -> float:
	return float(traits.get(key, fallback))


## REMEMBER (fast part): fold this frame's perception into the running tallies of
## how the player plays. Cheap and side-effect-light — just accumulators.
func observe(perception: Dictionary, cfg: Dictionary, delta: float) -> void:
	observations["play_seconds"] += delta
	var velocity: Vector2 = perception["player_velocity"]
	observations["explored_distance"] += velocity.length() * delta
	# "Near" uses the bond-scaled comfort distance from perception: wide when fresh, so
	# simply sharing the screen counts as togetherness and bonding starts easily, then
	# tightening as the bond deepens so the last of it asks for genuine closeness.
	var near: bool = perception["dist_to_player"] <= float(perception["follow_near"])
	if near:
		observations["time_near"] += delta
	else:
		observations["time_far"] += delta
	if perception["has_interaction"]:
		observations["interactions"] += 1.0
	_grow_bond(perception, cfg, delta, near)


## The bond DEEPENS through genuine play — discovery and shared moments — not idle
## time. Two sources remain:
##   1. A NOVELTY-weighted bump on each shared examine: the first real encounter with a
##      prop pays full, every repeat pays less (decaying to ~0), so poking one thing over
##      and over stops growing bond. The discount is permanent (familiarity never fades).
##   2. A slow proximity TRICKLE while you stay close — the gentle long-tail finisher,
##      deliberately weak so parking next to the companion is never the optimal play.
## Raw presence (growing just from the game running) is gone — it was farmable. Kept
## bounded so the wanderer->companion shift is felt across a session, not flipped in
## seconds. A no-op without "bond" config.
func _grow_bond(perception: Dictionary, cfg: Dictionary, delta: float, near: bool) -> void:
	if not cfg.has("bond"):
		return
	var bond_cfg: Dictionary = cfg["bond"]
	var amount := 0.0
	if near:
		amount += float(bond_cfg.get("grow_per_sec_near", 0.0)) * delta
	# Reset each frame; set below if a prop was examined, so the mood update can read how
	# novel it was (a habituated prop barely stirs the mood).
	_last_discovery_novelty = 0.0
	if perception["has_interaction"]:
		var key := _familiarity_key(perception)
		var seen := float(familiarity.get(key, 0.0))
		var novelty := _novelty_factor(seen, bond_cfg)
		_last_discovery_novelty = novelty
		amount += float(bond_cfg.get("grow_per_interaction", 0.0)) * novelty
		familiarity[key] = seen + 1.0
	# time_scale lets the real ~10-hour bond curve be experienced quickly while tuning
	# feel: the base rates are the real game, this multiplies them (set to 1.0 to ship).
	amount *= float(bond_cfg.get("time_scale", 1.0))
	bond = clampf(bond + amount, 0.0, float(bond_cfg.get("max", 1.0)))


## How fresh the Nth encounter with a prop is, 1.0 (first, seen == 0) decaying geometrically
## toward 0. novelty_decay in (0,1) sets the falloff: lower = goes quiet faster. This is the
## un-grindable mechanism — and what later makes the companion stop reacting to stale stimuli.
static func _novelty_factor(seen: float, bond_cfg: Dictionary) -> float:
	return pow(clampf(float(bond_cfg.get("novelty_decay", 0.4)), 0.0, 0.999), maxf(seen, 0.0))


## A stable key for habituation. Prefer the explicit prop id the world hands us; if none,
## fall back to a quantized position so distinct spots still read as distinct things while
## repeatedly poking one spot still habituates.
static func _familiarity_key(perception: Dictionary) -> String:
	var id := String(perception.get("interaction_id", ""))
	if id != "":
		return id
	var p: Vector2 = perception.get("interaction_point", Vector2.ZERO)
	return "pos:%d,%d" % [roundi(p.x / 24.0), roundi(p.y / 24.0)]


## Each companion's resting mood — the center its feeling relaxes back to — is derived
## from its traits, so two companions have different emotional "weather": an energetic one
## rests at a higher arousal, a warm/clingy one at a higher valence. Returns { valence,
## arousal } in roughly -1..1, leaning cozy-positive. A neutral 0,0 without "mood" config.
func _resting_mood(cfg: Dictionary) -> Dictionary:
	var m: Dictionary = cfg.get("mood", {})
	var rv: Dictionary = m.get("rest_valence", {})
	var ra: Dictionary = m.get("rest_arousal", {})
	var valence := lerpf(float(rv.get("lo", 0.0)), float(rv.get("hi", 0.0)), trait_value(String(rv.get("trait", "clinginess"))))
	var arousal := lerpf(float(ra.get("lo", 0.0)), float(ra.get("hi", 0.0)), trait_value(String(ra.get("trait", "energy"))))
	return { "valence": valence, "arousal": arousal }


## Advance the fast MOOD one frame. Pure-ish (mutates only this self) and reuses signals
## the companion already perceives — no new input channels. The pieces, all data-tuned in
## cfg["mood"]:
##   • relax toward the trait-derived resting point (the emotional center of gravity);
##   • a novel discovery spikes valence + arousal (habituated props barely move it);
##   • separation (player far) eases valence down, BOND-scaled — a fresh companion likes
##     its independence, a bonded one misses you;
##   • arousal contagion — a briskly-moving player pulls arousal up a little;
##   • boredom — a stretch with nothing novel drifts arousal gently down (so the next
##     novel thing pops harder);
##   • a small random walk — the PRIMARY source of day-to-day variety;
##   • cozy asymmetry — clamped to a mild negative floor; real lows arrive with danger.
## A no-op without "mood" config.
func update_mood(perception: Dictionary, cfg: Dictionary, delta: float, rng: RandomNumberGenerator) -> void:
	if not cfg.has("mood") or delta <= 0.0:
		return
	var m: Dictionary = cfg["mood"]
	var rest := _resting_mood(cfg)

	# Relax toward the resting point (exponential ease, frame-rate independent).
	var relax := 1.0 - exp(-float(m.get("relax_rate", 0.3)) * delta)
	mood_valence += (float(rest["valence"]) - mood_valence) * relax
	mood_arousal += (float(rest["arousal"]) - mood_arousal) * relax

	# Event spike: a novel shared discovery is exciting and warming.
	if _last_discovery_novelty > 0.0:
		mood_valence += float(m.get("discovery_valence", 0.0)) * _last_discovery_novelty
		mood_arousal += float(m.get("discovery_arousal", 0.0)) * _last_discovery_novelty
		_seconds_since_novelty = 0.0
	else:
		_seconds_since_novelty += delta

	# Separation: missing the player when far, scaled by how bonded we are.
	var near := float(perception.get("dist_to_player", 0.0)) <= float(perception.get("follow_near", 0.0))
	if not near:
		mood_valence -= float(m.get("separation_valence_rate", 0.0)) * bond * delta

	# Arousal contagion: a moving player is energizing (lightly, slightly bond-scaled).
	var player_speed := float((perception.get("player_velocity", Vector2.ZERO) as Vector2).length())
	var player_energy := clampf(player_speed / maxf(float(m.get("contagion_ref_speed", 120.0)), 0.001), 0.0, 1.0)
	var contagion_scale := lerpf(1.0, float(m.get("contagion_bond_scale", 1.0)), bond)
	mood_arousal += float(m.get("contagion_arousal_gain", 0.0)) * player_energy * contagion_scale * delta

	# Boredom: a stretch without novelty quiets arousal a touch.
	if _seconds_since_novelty > float(m.get("boredom_onset", 12.0)):
		mood_arousal -= float(m.get("boredom_arousal_rate", 0.0)) * delta

	# Random walk — the main variety source (Brownian, so it's frame-rate independent).
	var walk := float(m.get("walk_amp", 0.0)) * sqrt(delta)
	mood_valence += rng.randf_range(-1.0, 1.0) * walk
	mood_arousal += rng.randf_range(-1.0, 1.0) * walk

	# Cozy asymmetry: a mild negative floor (no real lows yet), full positive headroom.
	var floor_v := float(m.get("neg_floor", -1.0))
	mood_valence = clampf(mood_valence, floor_v, 1.0)
	mood_arousal = clampf(mood_arousal, floor_v, 1.0)


## Normalized 0..1 read-outs of how the player plays, derived from observations:
##   explore   — how much they roam (distance over time vs. a reference pace)
##   together  — how much they stay close to the companion
##   engage    — how often they examine things nearby
func play_signals(cfg: Dictionary) -> Dictionary:
	var drift_cfg: Dictionary = cfg.get("drift", {})
	var seconds: float = maxf(float(observations["play_seconds"]), 0.0001)
	var ref_speed := float(drift_cfg.get("reference_speed", 90.0))
	var ref_rate := float(drift_cfg.get("reference_interactions_per_min", 6.0))

	var explore := clampf((float(observations["explored_distance"]) / seconds) / ref_speed, 0.0, 1.0)
	var near := float(observations["time_near"])
	var far := float(observations["time_far"])
	var together := 0.5 if (near + far) <= 0.0 else clampf(near / (near + far), 0.0, 1.0)
	var per_min := float(observations["interactions"]) / (seconds / 60.0)
	var engage := clampf(per_min / ref_rate, 0.0, 1.0)
	return { "explore": explore, "together": together, "engage": engage }


## REMEMBER (slow part): nudge each trait toward what the player's signals imply,
## bounded by the trait's min/max and rate-limited by its drift_rate. The point is
## subtlety — over a session the companion gently becomes a reflection of how you
## play, never snapping. Requires "traits" + "drift" config; a no-op otherwise.
func apply_drift(cfg: Dictionary, delta: float) -> void:
	if not (cfg.has("traits") and cfg.has("drift")):
		return
	var drift_cfg: Dictionary = cfg["drift"]
	# Hold still until we've watched long enough for the signals to mean something.
	if float(observations["play_seconds"]) < float(drift_cfg.get("warmup_seconds", 0.0)):
		return
	var signals := play_signals(cfg)
	var targets: Dictionary = drift_cfg.get("targets", {})
	for key in cfg["traits"]:
		if not targets.has(key):
			continue
		var spec: Dictionary = cfg["traits"][key]
		var target := _blend_target(targets[key], signals)
		var rate := float(spec.get("drift_rate", 0.0)) * delta
		var current := trait_value(key)
		var moved := current + (target - current) * rate
		traits[key] = clampf(moved, float(spec.get("min", 0.0)), float(spec.get("max", 1.0)))


# Weighted blend of named signals into a single 0..1 target for a trait.
static func _blend_target(weights: Dictionary, signals: Dictionary) -> float:
	var total := 0.0
	var acc := 0.0
	for sig in weights:
		var w := float(weights[sig])
		total += w
		acc += w * float(signals.get(sig, 0.5))
	return 0.5 if total <= 0.0 else acc / total


## A read-only snapshot of the identity for diagnostics: the bond, the drifting
## traits, the derived play signals, and the headline observation tallies. Reuses
## play_signals() so the overlay shows exactly the numbers drift reads.
func debug_state(cfg: Dictionary) -> Dictionary:
	var rest := _resting_mood(cfg)
	return {
		"bond": bond,
		"traits": traits.duplicate(),
		"signals": play_signals(cfg),
		"play_seconds": float(observations.get("play_seconds", 0.0)),
		"interactions": float(observations.get("interactions", 0.0)),
		"familiar_props": familiarity.size(),
		"mood_valence": mood_valence,
		"mood_arousal": mood_arousal,
		"mood_rest_valence": float(rest["valence"]),
		"mood_rest_arousal": float(rest["arousal"]),
	}


## Plain, JSON-serializable snapshot. Dictionaries are deep-copied so callers
## can't mutate our state by holding the returned dict.
func to_dict() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"traits": traits.duplicate(true),
		"bond": bond,
		"observations": observations.duplicate(true),
		"mood_valence": mood_valence,
		"mood_arousal": mood_arousal,
		"short_term": short_term.duplicate(true),
		"familiarity": familiarity.duplicate(true),
	}


## Rebuild a self from a saved snapshot, filling any missing fields from defaults.
static func from_dict(data: Dictionary, cfg: Dictionary) -> CompanionSelf:
	var s := make_default(cfg)
	if data.get("traits") is Dictionary:
		for key in data["traits"]:
			s.traits[key] = clampf(float(data["traits"][key]), 0.0, 1.0)
	if data.has("bond"):
		s.bond = clampf(float(data["bond"]), 0.0, 1.0)
	if data.get("observations") is Dictionary:
		for key in data["observations"]:
			s.observations[key] = float(data["observations"][key])
	# Mood is fast and transient, so we don't fret about migrating the old scalar "mood"
	# field from very early saves — it just starts at its resting point. Newer saves carry
	# the 2D valence/arousal.
	if data.has("mood_valence"):
		s.mood_valence = clampf(float(data["mood_valence"]), -1.0, 1.0)
	if data.has("mood_arousal"):
		s.mood_arousal = clampf(float(data["mood_arousal"]), -1.0, 1.0)
	if data.get("short_term") is Dictionary:
		s.short_term = (data["short_term"] as Dictionary).duplicate(true)
	if data.get("familiarity") is Dictionary:
		for key in data["familiarity"]:
			s.familiarity[key] = maxf(float(data["familiarity"][key]), 0.0)
	return s
