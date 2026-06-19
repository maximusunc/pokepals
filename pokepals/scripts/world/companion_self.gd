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

# The personality is THREE layers of the same 0..1 dimensions (curiosity, energy,
# clinginess, ...), distinguished by job, not just timescale:
#   birth:       the fixed birth inclination, set once at creation, never changes. The
#                companion is always pulled slightly back toward it, so two identically-
#                played companions stay faintly distinct and none gets stuck by bad luck.
#   identity:    the slow ANCHOR. Learns toward the player's long-run play style, paced by
#                bond and CRYSTALLIZING (drift tapers) as bond -> 1, so a deeply bonded
#                companion's core stabilizes. Pulled gently back toward birth (residual).
#   traits:      the live DISPOSITION — the value behavior actually reads. Orbits identity,
#                regresses toward it, bounded to identity +/- a band. The home for lingering
#                states like "upset" (a reversible push away from identity) — none built in
#                the cozy slice yet, so for now it simply tracks identity. Kept SEPARATE
#                from bond, which is what later allows "wounded but loyal" (deeply bonded yet
#                currently wary). Mood overlays this to make the effective trait.
# Full chain: birth -> identity -> disposition (traits) -> (+ mood overlay) -> effective.
var birth: Dictionary = {}
var identity: Dictionary = {}
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
var _last_discovery_appeal: float = 1.0
var _last_shared_novelty: float = 0.0
var _seconds_since_novelty: float = 999.0
# Set for the single frame the bond crosses a configured milestone (to "milestone"),
# so the presentation can play a one-off "we grew closer" beat. NOT persisted — but the
# milestones already reached ARE (in short_term), so a milestone never re-fires across
# sessions. Cleared at the top of _grow_bond every frame.
var bond_event: String = ""


## A fresh self seeded from the companion config. Traits come from an explicit
## "traits" block if present, otherwise from the legacy "personality" block so
## existing data files keep working unchanged.
static func make_default(cfg: Dictionary) -> CompanionSelf:
	var s := CompanionSelf.new()
	s.traits = _default_traits(cfg)
	# Birth and identity start equal to the disposition: a fresh companion is exactly its
	# (default) self, with nothing learned and nothing pushing disposition off its anchor.
	s.birth = s.traits.duplicate()
	s.identity = s.traits.duplicate()
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
## becoming pronounced archetypes. The jitter is the BIRTH inclination — identity and the
## live disposition start equal to it. The deterministic make_default path is left alone so
## tests and first-run feel stay exact.
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
			var jittered := clampf(init + rng.randf_range(-spread, spread), float(spec.get("min", 0.0)), float(spec.get("max", 1.0)))
			s.birth[key] = jittered
			s.identity[key] = jittered
			s.traits[key] = jittered
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
## time. Four sources:
##   1. A NOVELTY-weighted bump on each shared examine: the first real encounter with a
##      prop pays full, every repeat pays less (decaying to ~0), so poking one thing over
##      and over stops growing bond. The discount is permanent (familiarity never fades).
##   2. A SHARED-ATTENTION bump when the companion is right beside whatever the player is
##      attending to (from social referencing) — novelty-weighted the same way.
##   3. A NEW-AREA bump the first time it reaches a region of the world (novelty-weighted in
##      the same map, so re-entering a known place pays nothing). Area ids are world-
##      namespaced, so this also rewards venturing into a whole new world.
##   4. A slow proximity TRICKLE while you stay close — the gentle long-tail finisher,
##      deliberately weak so parking next to the companion is never the optimal play.
## Raw presence (growing just from the game running) is gone — it was farmable. Kept
## bounded so the wanderer->companion shift is felt across a session, not flipped in
## seconds. A no-op without "bond" config.
func _grow_bond(perception: Dictionary, cfg: Dictionary, delta: float, near: bool) -> void:
	bond_event = ""  # transient; set below only on the frame a milestone is crossed
	if not cfg.has("bond"):
		return
	var bond_cfg: Dictionary = cfg["bond"]
	var amount := 0.0
	if near:
		amount += float(bond_cfg.get("grow_per_sec_near", 0.0)) * delta
	# Reset each frame; set below if a prop was examined, so the mood update can read how
	# novel it was (a habituated prop barely stirs the mood) and how much it likes it (a
	# loved thing delights it more). Appeal defaults to 1.0 so non-examine discoveries (a new
	# area) aren't dampened.
	_last_discovery_novelty = 0.0
	_last_discovery_appeal = 1.0
	if perception["has_interaction"]:
		var key := _familiarity_key(perception)
		var seen := float(familiarity.get(key, 0.0))
		var novelty := _novelty_factor(seen, bond_cfg)
		_last_discovery_novelty = novelty
		_last_discovery_appeal = float(perception.get("interaction_appeal", 1.0))
		short_term["last_appeal"] = _last_discovery_appeal  # for the debug overlay
		amount += float(bond_cfg.get("grow_per_interaction", 0.0)) * novelty
		familiarity[key] = seen + 1.0
	# Shared-attention moment (from social referencing): you and it focused on the SAME
	# thing — the companion is right beside whatever you're attending to. A real bond beat,
	# novelty-gated in the same familiarity map (sharing the same spot twice stops paying).
	# Suppressed on a frame you actually examined something, so that moment counts once.
	_last_shared_novelty = 0.0
	if not perception["has_interaction"]:
		_last_shared_novelty = _shared_attention_novelty(perception, cfg)
		if _last_shared_novelty > 0.0:
			amount += float(bond_cfg.get("grow_per_shared_attention", 0.0)) * _last_shared_novelty
	# New-area discovery: only on the frame we cross INTO a different area, and only if it's
	# unfamiliar. The first area we're ever in (spawn) is "home", marked known without a bump.
	amount += _discover_area(perception, bond_cfg)
	# time_scale lets the real ~10-hour bond curve be experienced quickly while tuning
	# feel: the base rates are the real game, this multiplies them (set to 1.0 to ship).
	amount *= float(bond_cfg.get("time_scale", 1.0))
	bond = clampf(bond + amount, 0.0, float(bond_cfg.get("max", 1.0)))
	_check_bond_milestone(bond_cfg)


## A relationship deepening past a configured threshold (e.g. 0.25/0.5/0.75/1.0) is a
## beat worth feeling. We remember the highest milestone reached in short_term (which IS
## persisted), so each one fires exactly once ever — never on a repeat, never on reload.
## When a fresh one is crossed this frame, flag bond_event for the presentation to read.
func _check_bond_milestone(bond_cfg: Dictionary) -> void:
	var milestones: Array = bond_cfg.get("milestones", [])
	if milestones.is_empty():
		return
	var highest := float(short_term.get("bond_milestone", -1.0))
	var crossed := highest
	for m in milestones:
		var threshold := float(m)
		if bond >= threshold and threshold > crossed:
			crossed = threshold
	if crossed > highest:
		short_term["bond_milestone"] = crossed
		bond_event = "milestone"


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


## Detects a shared-attention moment and returns its novelty (0 if none), bumping the
## familiarity tally for the shared spot as a side effect so repeats fade — mirroring the
## discovery path. A shared moment = the player is clearly attending to something the
## companion is right beside. Keyed by quantized position, since POIs reach perception as
## bare points (no id); kept in its own "share:" namespace.
func _shared_attention_novelty(perception: Dictionary, cfg: Dictionary) -> float:
	if not bool(perception.get("has_attended", false)):
		return 0.0
	var ac: Dictionary = cfg.get("attention", {})
	if float(perception.get("attention_strength", 0.0)) < float(ac.get("share_min_strength", 0.25)):
		return 0.0
	var attended: Vector2 = perception.get("attended_object", Vector2.ZERO)
	var companion_pos: Vector2 = perception.get("companion_pos", Vector2.ZERO)
	if companion_pos.distance_to(attended) > float(ac.get("share_distance", 90.0)):
		return 0.0
	var key := "share:%d,%d" % [roundi(attended.x / 24.0), roundi(attended.y / 24.0)]
	var seen := float(familiarity.get(key, 0.0))
	familiarity[key] = seen + 1.0
	return _novelty_factor(seen, cfg.get("bond", {}))


## New-area discovery. Returns the (pre-time_scale) bond earned by crossing into a NEW area
## this frame, 0 otherwise. Unlike props, an area is BINARY — you've been somewhere or you
## haven't — so a discovered area pays nothing on return (not even a faded amount). The first
## area we ever occupy (spawn, or a fresh load with no recorded area) is "home": marked known
## without a bump. A genuine discovery also feeds the mood's discovery spike (a new place is
## exciting). Area ids are world-namespaced, so this rewards new worlds as well as new regions.
func _discover_area(perception: Dictionary, bond_cfg: Dictionary) -> float:
	var area := String(perception.get("current_area", ""))
	if area == "" or String(short_term.get("last_area", "")) == area:
		return 0.0  # no areas configured, or still in the same area — no crossing
	var first_ever := not short_term.has("last_area")
	short_term["last_area"] = area
	var key := "area:" + area
	var seen := float(familiarity.get(key, 0.0))
	if first_ever and seen == 0.0:
		familiarity[key] = 1.0  # where we begin is home, not a discovery
		return 0.0
	familiarity[key] = seen + 1.0
	if seen > 0.0:
		return 0.0  # already been here — a known place earns no fresh bond
	_last_discovery_novelty = maxf(_last_discovery_novelty, 1.0)
	return float(bond_cfg.get("grow_per_area", 0.0))


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

	# Event spike: a novel discovery is exciting and warming — scaled by how much the
	# companion likes the thing (appraisal), so it lights up for a loved find and barely
	# stirs for one it's indifferent to. (Appeal is 1.0 for non-appraised discoveries.)
	if _last_discovery_novelty > 0.0:
		var spike := _last_discovery_novelty * _last_discovery_appeal
		mood_valence += float(m.get("discovery_valence", 0.0)) * spike
		mood_arousal += float(m.get("discovery_arousal", 0.0)) * spike
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

	# Shared attention (from social referencing): focusing on the same thing together is
	# warming — a valence lift, novelty-weighted so co-attending the same spot fades.
	if _last_shared_novelty > 0.0:
		mood_valence += float(m.get("shared_attention_valence", 0.0)) * _last_shared_novelty
	# Being noticed — the player turning toward and easing up to us — feels good (a gentle
	# continuous lift while it's happening).
	mood_valence += float(m.get("noticed_valence_gain", 0.0)) * float(perception.get("noticed_strength", 0.0)) * delta

	# Random walk — the main variety source (Brownian, so it's frame-rate independent).
	var walk := float(m.get("walk_amp", 0.0)) * sqrt(delta)
	mood_valence += rng.randf_range(-1.0, 1.0) * walk
	mood_arousal += rng.randf_range(-1.0, 1.0) * walk

	# Cozy asymmetry: a mild negative floor (no real lows yet), full positive headroom.
	var floor_v := float(m.get("neg_floor", -1.0))
	mood_valence = clampf(mood_valence, floor_v, 1.0)
	mood_arousal = clampf(mood_arousal, floor_v, 1.0)


## The companion has just heard the player's CALL and is acknowledging it — a small, warm
## mood lift (being noticed by you feels good), whether or not it then decides to come. No
## bond: a whistle isn't earned discovery, so only the relationship — not repetition — makes
## the call land. Clamped to the same cozy negative floor as the rest of the mood. A no-op
## without "come"/"mood" config.
func apply_command_ack(cfg: Dictionary) -> void:
	var c: Dictionary = cfg.get("come", {})
	var floor_v := float(cfg.get("mood", {}).get("neg_floor", -1.0))
	mood_valence = clampf(mood_valence + float(c.get("ack_valence", 0.0)), floor_v, 1.0)
	mood_arousal = clampf(mood_arousal + float(c.get("ack_arousal", 0.0)), floor_v, 1.0)


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


## REMEMBER (slow part): advance the two slow personality layers. The point is subtlety —
## over a session the companion gently becomes a reflection of how you play, never snapping,
## and once deeply bonded its core settles. Requires "traits" + "drift" config; a no-op
## otherwise.
##   1. IDENTITY learns toward the player's play style, but: the target is pulled slightly
##      back toward birth (so it never exactly matches and keeps individuality), and the
##      learning rate CRYSTALLIZES — it tapers with bond, so a fresh companion is malleable
##      and a deeply bonded one is locked. Held still until we've watched long enough.
##   2. DISPOSITION (the live read value) regresses toward identity, bounded to identity +/-
##      a band. With no events pushing it (cozy slice), it simply tracks identity; the
##      machinery is here so a later "upset" push relaxes back on its own.
func apply_drift(cfg: Dictionary, delta: float) -> void:
	if not (cfg.has("traits") and cfg.has("drift")):
		return
	var drift_cfg: Dictionary = cfg["drift"]
	_learn_identity(cfg, drift_cfg, delta)
	_relax_disposition(cfg, delta)


# Identity learns toward play style (blended back toward birth), at a rate that tapers to ~0
# as bond -> 1. Held still before warmup so it doesn't learn from a few noisy opening seconds.
func _learn_identity(cfg: Dictionary, drift_cfg: Dictionary, delta: float) -> void:
	if float(observations["play_seconds"]) < float(drift_cfg.get("warmup_seconds", 0.0)):
		return
	var signals := play_signals(cfg)
	var targets: Dictionary = drift_cfg.get("targets", {})
	var residual := float(drift_cfg.get("birth_residual", 0.15))
	# Crystallization: malleable when fresh, locking as the bond deepens.
	var crystallize := pow(clampf(1.0 - bond, 0.0, 1.0), float(drift_cfg.get("crystallize_exp", 1.5)))
	for key in cfg["traits"]:
		if not (cfg["traits"][key] is Dictionary) or not targets.has(key):
			continue
		var spec: Dictionary = cfg["traits"][key]
		var playstyle := _blend_target(targets[key], signals)
		# Never fully abandon the birth inclination — keep a slight pull back toward it.
		var target := lerpf(playstyle, float(birth.get(key, playstyle)), residual)
		var rate := float(spec.get("drift_rate", 0.0)) * crystallize * delta
		var current := float(identity.get(key, spec.get("init", 0.5)))
		var moved := current + (target - current) * rate
		identity[key] = clampf(moved, float(spec.get("min", 0.0)), float(spec.get("max", 1.0)))


# Disposition relaxes toward its identity anchor, bounded to identity +/- a band (and the
# trait's own min/max). No-op when it already sits at identity, which is the cozy norm.
func _relax_disposition(cfg: Dictionary, delta: float) -> void:
	var disp_cfg: Dictionary = cfg.get("disposition", {})
	var band := float(disp_cfg.get("band", 0.25))
	var regress := float(disp_cfg.get("regress_rate", 0.05)) * delta
	for key in cfg["traits"]:
		if not (cfg["traits"][key] is Dictionary) or not identity.has(key):
			continue
		var spec: Dictionary = cfg["traits"][key]
		var anchor := float(identity[key])
		var moved := trait_value(key) + (anchor - trait_value(key)) * regress
		moved = clampf(moved, anchor - band, anchor + band)
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


# How many distinct areas the companion has been to (including home), from the memory map.
func _count_areas_found() -> int:
	var n := 0
	for key in familiarity:
		if String(key).begins_with("area:"):
			n += 1
	return n


## A read-only snapshot of the identity for diagnostics: the bond, the drifting
## traits, the derived play signals, and the headline observation tallies. Reuses
## play_signals() so the overlay shows exactly the numbers drift reads.
func debug_state(cfg: Dictionary) -> Dictionary:
	var rest := _resting_mood(cfg)
	return {
		"bond": bond,
		"traits": traits.duplicate(),
		"identity": identity.duplicate(),
		"signals": play_signals(cfg),
		"play_seconds": float(observations.get("play_seconds", 0.0)),
		"interactions": float(observations.get("interactions", 0.0)),
		"familiar_props": familiarity.size(),
		"areas_found": _count_areas_found(),
		"last_appeal": float(short_term.get("last_appeal", -1.0)),
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
		"identity": identity.duplicate(true),
		"birth": birth.duplicate(true),
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
	# Load the slow layers if present; for OLD saves (pre-split) seed them from the saved
	# disposition so the loaded companion is its own anchor — no snap back toward defaults.
	if data.get("identity") is Dictionary:
		for key in data["identity"]:
			s.identity[key] = clampf(float(data["identity"][key]), 0.0, 1.0)
	else:
		s.identity = s.traits.duplicate()
	if data.get("birth") is Dictionary:
		for key in data["birth"]:
			s.birth[key] = clampf(float(data["birth"][key]), 0.0, 1.0)
	else:
		s.birth = s.identity.duplicate()
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
