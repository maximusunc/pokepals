class_name TestCompanionSelf
## Tests for the companion's persistent identity. Pure data in, pure data out —
## no nodes, no filesystem — so this also documents the save schema's behavior.

static func run_all() -> int:
	var fails := 0
	var cfg: Dictionary = WorldData.load_json("res://data/companion.json")
	print("TestCompanionSelf")
	fails += _test_seeds_traits_from_personality(cfg)
	fails += _test_round_trips(cfg)
	fails += _test_from_dict_fills_missing(cfg)
	fails += _test_clamps_traits(cfg)
	fails += _test_drift_reflects_an_exploring_player(cfg)
	fails += _test_drift_reflects_a_homebody_player(cfg)
	fails += _test_drift_respects_bounds(cfg)
	fails += _test_no_drift_before_warmup(cfg)
	fails += _test_make_default_unchanged(cfg)
	fails += _test_make_random_stays_near_init(cfg)
	fails += _test_make_random_varies(cfg)
	fails += _test_bond_does_not_grow_from_idle_presence(cfg)
	fails += _test_bond_habituates_on_repeat(cfg)
	fails += _test_bond_full_novelty_for_a_new_prop(cfg)
	fails += _test_familiarity_round_trips(cfg)
	fails += _test_mood_rests_higher_arousal_for_energetic(cfg)
	fails += _test_mood_spikes_on_novel_discovery(cfg)
	fails += _test_mood_spike_dampens_with_habituation(cfg)
	fails += _test_mood_overlays_effective_traits(cfg)
	fails += _test_shared_attention_grows_bond(cfg)
	fails += _test_shared_attention_lifts_valence(cfg)
	fails += _test_being_noticed_lifts_valence(cfg)
	fails += _test_identity_crystallizes_with_bond(cfg)
	fails += _test_identity_keeps_birth_individuality(cfg)
	fails += _test_disposition_relaxes_toward_identity(cfg)
	fails += _test_identity_and_birth_round_trip(cfg)
	fails += _test_old_save_seeds_identity_from_traits(cfg)
	fails += _test_new_area_grows_bond_once(cfg)
	fails += _test_new_world_is_all_new(cfg)
	fails += _test_appeal_scales_discovery_delight(cfg)
	fails += _test_bond_milestone_fires_once(cfg)
	fails += _test_bond_milestone_persists_across_save(cfg)
	fails += _test_pet_grows_bond_then_habituates(cfg)
	fails += _test_pet_spam_pays_once(cfg)
	fails += _test_pet_lifts_mood(cfg)
	fails += _test_pet_rebuff_no_bond_and_stays_above_floor(cfg)
	fails += _test_pet_familiarity_round_trips(cfg)
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _test_seeds_traits_from_personality(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var fails := 0
	# Legacy personality keys should appear as traits with matching values.
	fails += _ok(s.traits.has("curiosity"), "seeds curiosity trait from personality")
	fails += _ok(is_equal_approx(s.trait_value("clinginess"), float(cfg["personality"]["clinginess"])), "trait value matches personality value")
	fails += _ok(s.observations.has("play_seconds"), "starts with observation accumulators")
	return fails


static func _test_round_trips(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.traits["curiosity"] = 0.42
	s.observations["interactions"] = 7.0
	s.mood_valence = 0.5
	s.mood_arousal = -0.3
	s.short_term["last_poi"] = [12.0, 34.0]
	var restored := CompanionSelf.from_dict(s.to_dict(), cfg)
	var fails := 0
	fails += _ok(is_equal_approx(restored.trait_value("curiosity"), 0.42), "trait survives round-trip")
	fails += _ok(is_equal_approx(float(restored.observations["interactions"]), 7.0), "observation survives round-trip")
	fails += _ok(is_equal_approx(restored.mood_valence, 0.5), "mood valence survives round-trip")
	fails += _ok(is_equal_approx(restored.mood_arousal, -0.3), "mood arousal survives round-trip")
	fails += _ok(restored.short_term.get("last_poi") == [12.0, 34.0], "short-term memory survives round-trip")
	return fails


static func _test_from_dict_fills_missing(cfg: Dictionary) -> int:
	# An old/partial save (only one trait) should still load, with the rest
	# filled from defaults.
	var partial := { "version": 1, "traits": { "curiosity": 0.9 } }
	var restored := CompanionSelf.from_dict(partial, cfg)
	var fails := 0
	fails += _ok(is_equal_approx(restored.trait_value("curiosity"), 0.9), "loads the saved trait")
	fails += _ok(restored.observations.has("play_seconds"), "fills missing observations from defaults")
	fails += _ok(restored.traits.has("energy"), "fills missing traits from defaults")
	return fails


static func _test_clamps_traits(cfg: Dictionary) -> int:
	var restored := CompanionSelf.from_dict({ "traits": { "curiosity": 5.0 } }, cfg)
	return _ok(restored.trait_value("curiosity") <= 1.0, "clamps out-of-range trait values to 0..1")


# A player who roams far and examines lots of things should grow a more curious,
# energetic, and less clingy companion.
static func _test_drift_reflects_an_exploring_player(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.observations["play_seconds"] = 600.0
	s.observations["explored_distance"] = 600.0 * 120.0  # ~120 px/s average pace
	s.observations["time_far"] = 590.0
	s.observations["time_near"] = 10.0
	s.observations["interactions"] = 100.0
	var cling_before := s.trait_value("clinginess")
	for i in 600:
		s.apply_drift(cfg, 0.1)  # ~60s of drift
	var fails := 0
	fails += _ok(s.trait_value("energy") > 0.7, "energy drifts up for a roaming player")
	fails += _ok(s.trait_value("clinginess") < cling_before, "clinginess drifts down when the player ranges far")
	return fails


# A player who stays close and rarely wanders should grow a clingier, calmer one.
static func _test_drift_reflects_a_homebody_player(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.observations["play_seconds"] = 600.0
	s.observations["explored_distance"] = 600.0 * 5.0  # barely moves
	s.observations["time_near"] = 595.0
	s.observations["time_far"] = 5.0
	s.observations["interactions"] = 1.0
	var energy_before := s.trait_value("energy")
	var cling_before := s.trait_value("clinginess")
	for i in 600:
		s.apply_drift(cfg, 0.1)
	var fails := 0
	fails += _ok(s.trait_value("energy") < energy_before, "energy drifts down for a stay-still player")
	fails += _ok(s.trait_value("clinginess") > cling_before, "clinginess drifts up when the player stays close")
	return fails


static func _test_drift_respects_bounds(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	# Extreme "never moves, never engages" profile pushes curiosity toward 0...
	s.observations["play_seconds"] = 10000.0
	s.observations["explored_distance"] = 0.0
	s.observations["time_near"] = 10000.0
	s.observations["interactions"] = 0.0
	for i in 5000:
		s.apply_drift(cfg, 0.5)
	var min_floor: float = float(cfg["traits"]["curiosity"]["min"])
	return _ok(s.trait_value("curiosity") >= min_floor - 0.0001, "a trait never drifts below its configured min")


static func _test_no_drift_before_warmup(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.observations["play_seconds"] = 5.0  # below warmup_seconds
	s.observations["explored_distance"] = 5.0 * 200.0
	var before := s.trait_value("energy")
	s.apply_drift(cfg, 0.1)
	return _ok(is_equal_approx(s.trait_value("energy"), before), "no drift before the warmup period")


# make_default must stay exactly the configured init values — the deterministic path
# the rest of the suite (and the brain tests) relies on.
static func _test_make_default_unchanged(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var fails := 0
	for key in ["curiosity", "energy", "clinginess"]:
		var init := float(cfg["traits"][key]["init"])
		fails += _ok(is_equal_approx(s.trait_value(key), init), "make_default keeps %s at its init" % key)
	return fails


# A randomized companion's traits sit within the configured spread of their init
# (gentle variation, not archetypes) and never escape the trait's min/max.
static func _test_make_random_stays_near_init(cfg: Dictionary) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var default_spread := float(cfg.get("trait_spread", 0.12))
	var fails := 0
	# Sample several so we exercise the random range, not a single lucky draw.
	for _i in 50:
		var s := CompanionSelf.make_random(cfg, rng)
		for key in ["curiosity", "energy", "clinginess"]:
			var spec: Dictionary = cfg["traits"][key]
			var init := float(spec["init"])
			var spread := float(spec.get("spread", default_spread))
			var lo := maxf(init - spread, float(spec["min"]))
			var hi := minf(init + spread, float(spec["max"]))
			var v := s.trait_value(key)
			if v < lo - 0.0001 or v > hi + 0.0001:
				fails += _ok(false, "make_random keeps %s within its spread (got %f)" % [key, v])
				return fails
	return _ok(true, "make_random keeps every trait within its configured spread of init")


# Different seeds produce genuinely different companions (variability exists).
static func _test_make_random_varies(cfg: Dictionary) -> int:
	var a := CompanionSelf.make_random(cfg, _seeded(1))
	var b := CompanionSelf.make_random(cfg, _seeded(2))
	var differs := (
		not is_equal_approx(a.trait_value("curiosity"), b.trait_value("curiosity"))
		or not is_equal_approx(a.trait_value("energy"), b.trait_value("energy"))
		or not is_equal_approx(a.trait_value("clinginess"), b.trait_value("clinginess"))
	)
	return _ok(differs, "different seeds yield differently-tempered companions")


static func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# A minimal perception dict for exercising observe()/_grow_bond without the brain.
static func _perception(near: bool, interaction_id: String = "") -> Dictionary:
	return {
		"player_velocity": Vector2.ZERO,
		"dist_to_player": 10.0 if near else 5000.0,
		"follow_near": 100.0,
		"has_interaction": interaction_id != "",
		"interaction_id": interaction_id,
		"interaction_point": Vector2.ZERO,
	}


# Bond must NOT grow from idle presence (the old farmable raw-presence source is gone).
# Standing far away with no interaction leaves it flat.
static func _test_bond_does_not_grow_from_idle_presence(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	for _i in 600:
		s.observe(_perception(false), cfg, 0.1)
	return _ok(is_equal_approx(s.bond, 0.0), "bond stays flat from idle, far-away presence")


# Examining the SAME prop pays less each time (habituation): the second poke grows bond
# strictly less than the first, and a long run of repeats drives the gain toward ~0.
static func _test_bond_habituates_on_repeat(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var before1 := s.bond
	s.observe(_perception(false, "chime_stone"), cfg, 0.0)  # delta 0 isolates the interaction
	var first_gain := s.bond - before1

	var before2 := s.bond
	s.observe(_perception(false, "chime_stone"), cfg, 0.0)
	var second_gain := s.bond - before2

	var fails := 0
	fails += _ok(first_gain > 0.0, "first examine of a prop grows bond")
	fails += _ok(second_gain < first_gain, "repeating the same prop grows bond less (habituation)")

	for _i in 30:
		s.observe(_perception(false, "chime_stone"), cfg, 0.0)
	var before_late := s.bond
	s.observe(_perception(false, "chime_stone"), cfg, 0.0)
	fails += _ok((s.bond - before_late) < first_gain * 0.05, "a thoroughly-familiar prop adds ~nothing")
	return fails


# A different prop is fresh again: its first examine pays full novelty, same as the first
# prop's did — novelty is per-prop, not global.
static func _test_bond_full_novelty_for_a_new_prop(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var b0 := s.bond
	s.observe(_perception(false, "chime_stone"), cfg, 0.0)
	var gain_a := s.bond - b0
	# Habituate the first prop hard, then meet a brand-new one.
	for _i in 20:
		s.observe(_perception(false, "chime_stone"), cfg, 0.0)
	var b1 := s.bond
	s.observe(_perception(false, "crystal"), cfg, 0.0)
	var gain_b := s.bond - b1
	return _ok(is_equal_approx(gain_a, gain_b), "a new prop pays full novelty even after another is exhausted")


static func _test_familiarity_round_trips(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.observe(_perception(false, "lantern"), cfg, 0.0)
	s.observe(_perception(false, "lantern"), cfg, 0.0)
	var restored := CompanionSelf.from_dict(s.to_dict(), cfg)
	return _ok(is_equal_approx(float(restored.familiarity.get("lantern", 0.0)), 2.0), "familiarity tallies survive a round-trip")


# A copy of cfg with the mood random walk silenced, so the deterministic mood dynamics
# (rest, spikes, decay) can be asserted without the noise of the random walk.
static func _mood_cfg_no_walk(cfg: Dictionary) -> Dictionary:
	var c := cfg.duplicate(true)
	c["mood"]["walk_amp"] = 0.0
	return c


static func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	return r


# Settle a self's mood by ticking idle, near, with no events, until it relaxes to rest.
static func _settle_mood(s: CompanionSelf, cfg: Dictionary) -> void:
	var rng := _rng()
	for _i in 400:
		s.update_mood(_perception(true), cfg, 0.1, rng)


# The resting point is trait-derived: an energetic companion settles at a higher arousal
# than a low-energy one, so different companions have different emotional weather.
static func _test_mood_rests_higher_arousal_for_energetic(cfg: Dictionary) -> int:
	var c := _mood_cfg_no_walk(cfg)
	var lively := CompanionSelf.make_default(c)
	lively.traits["energy"] = 1.0
	var sleepy := CompanionSelf.make_default(c)
	sleepy.traits["energy"] = 0.0
	_settle_mood(lively, c)
	_settle_mood(sleepy, c)
	return _ok(lively.mood_arousal > sleepy.mood_arousal + 0.05, "an energetic companion rests at a higher arousal")


# A novel shared discovery lifts the mood (both axes) above its resting point.
static func _test_mood_spikes_on_novel_discovery(cfg: Dictionary) -> int:
	var c := _mood_cfg_no_walk(cfg)
	var s := CompanionSelf.make_default(c)
	_settle_mood(s, c)
	var rest_arousal := s.mood_arousal
	var rest_valence := s.mood_valence
	# A frame in which a never-seen prop is examined (observe records the novelty).
	var p := _perception(true, "crystal")
	s.observe(p, c, 0.1)
	s.update_mood(p, c, 0.1, _rng())
	var fails := 0
	fails += _ok(s.mood_arousal > rest_arousal + 0.1, "a novel discovery spikes arousal")
	fails += _ok(s.mood_valence > rest_valence + 0.05, "a novel discovery lifts valence")
	return fails


# That spike is novelty-weighted: a thoroughly-familiar prop barely moves the mood, so a
# small world of repeated props doesn't keep the companion permanently thrilled.
static func _test_mood_spike_dampens_with_habituation(cfg: Dictionary) -> int:
	var c := _mood_cfg_no_walk(cfg)
	var rng := _rng()

	var fresh := CompanionSelf.make_default(c)
	_settle_mood(fresh, c)
	var a0 := fresh.mood_arousal
	var p := _perception(true, "lantern")
	fresh.observe(p, c, 0.1)
	fresh.update_mood(p, c, 0.1, rng)
	var novel_jump := fresh.mood_arousal - a0

	var jaded := CompanionSelf.make_default(c)
	for _i in 25:  # wear the prop's novelty down to ~0
		jaded.observe(_perception(true, "lantern"), c, 0.0)
	_settle_mood(jaded, c)
	var b0 := jaded.mood_arousal
	jaded.observe(p, c, 0.1)
	jaded.update_mood(p, c, 0.1, rng)
	var jaded_jump := jaded.mood_arousal - b0

	return _ok(jaded_jump < novel_jump * 0.2, "a habituated prop barely stirs the mood")


# The payoff: mood overlays the effective traits a happy/excited companion reads as more
# energetic and affectionate than its resting self, via CompanionTraits.value.
static func _test_mood_overlays_effective_traits(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var base_energy := s.trait_value("energy")
	s.mood_arousal = 0.8  # strongly aroused
	var eff_energy := CompanionTraits.value(s, cfg, "energy")
	var fails := 0
	fails += _ok(eff_energy > base_energy, "high arousal raises effective energy above the raw trait")
	# Curiosity has no mood axis, so it should read its raw value regardless of mood.
	s.mood_valence = 0.9
	fails += _ok(is_equal_approx(CompanionTraits.value(s, cfg, "curiosity"), s.trait_value("curiosity")), "curiosity is unaffected by mood")
	return fails


# A perception of a shared-attention moment: the companion right beside something the
# player is clearly attending to, with no explicit examine this frame.
static func _perception_shared(companion_pos: Vector2, attended: Vector2, strength: float) -> Dictionary:
	return {
		"player_velocity": Vector2.ZERO,
		"dist_to_player": 10.0,
		"follow_near": 100.0,
		"has_interaction": false,
		"interaction_id": "",
		"interaction_point": Vector2.ZERO,
		"has_attended": true,
		"attention_strength": strength,
		"attended_object": attended,
		"companion_pos": companion_pos,
		"noticed_strength": 0.0,
	}


# Focusing on the same thing together grows the bond — and, like other sources, it's
# novelty-gated, so co-attending the same spot pays less each time.
static func _test_shared_attention_grows_bond(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var b0 := s.bond
	s.observe(_perception_shared(Vector2.ZERO, Vector2(40, 0), 0.8), cfg, 0.0)
	var first := s.bond - b0
	var b1 := s.bond
	s.observe(_perception_shared(Vector2.ZERO, Vector2(40, 0), 0.8), cfg, 0.0)
	var second := s.bond - b1
	var fails := 0
	fails += _ok(first > 0.0, "a shared-attention moment grows bond")
	fails += _ok(second < first, "repeating the same shared spot grows bond less (novelty)")
	# A weak/far signal isn't a shared moment at all.
	var t := CompanionSelf.make_default(cfg)
	var t0 := t.bond
	t.observe(_perception_shared(Vector2.ZERO, Vector2(400, 0), 0.8), cfg, 0.0)  # too far
	fails += _ok(is_equal_approx(t.bond, t0), "a prop the companion isn't beside is not a shared moment")
	return fails


static func _test_shared_attention_lifts_valence(cfg: Dictionary) -> int:
	var c := _mood_cfg_no_walk(cfg)
	var s := CompanionSelf.make_default(c)
	_settle_mood(s, c)
	var rest_v := s.mood_valence
	var p := _perception_shared(Vector2.ZERO, Vector2(40, 0), 0.8)
	s.observe(p, c, 0.1)
	s.update_mood(p, c, 0.1, _rng())
	return _ok(s.mood_valence > rest_v + 0.05, "a shared-attention moment lifts valence")


static func _test_being_noticed_lifts_valence(cfg: Dictionary) -> int:
	var c := _mood_cfg_no_walk(cfg)
	var s := CompanionSelf.make_default(c)
	_settle_mood(s, c)
	var rest_v := s.mood_valence
	var p := _perception(true)
	p["has_attended"] = false
	p["noticed_strength"] = 0.8  # the player is turning toward and coming over
	for _i in 20:
		s.update_mood(p, c, 0.1, _rng())
	return _ok(s.mood_valence > rest_v + 0.05, "being noticed by the player lifts valence")


# Give a self the observation profile of a roaming, rarely-close player, so identity learns
# toward higher energy / lower clinginess.
static func _seed_exploring(s: CompanionSelf) -> void:
	s.observations["play_seconds"] = 600.0
	s.observations["explored_distance"] = 600.0 * 120.0
	s.observations["time_far"] = 590.0
	s.observations["time_near"] = 10.0
	s.observations["interactions"] = 100.0


# Identity is malleable when fresh and LOCKS as the bond deepens: given identical play, a
# fresh companion's identity moves far more than a deeply bonded one's.
static func _test_identity_crystallizes_with_bond(cfg: Dictionary) -> int:
	var fresh := CompanionSelf.make_default(cfg)
	fresh.bond = 0.0
	_seed_exploring(fresh)
	var bonded := CompanionSelf.make_default(cfg)
	bonded.bond = 1.0
	_seed_exploring(bonded)
	var start: float = float(fresh.identity["energy"])  # both start equal (make_default)
	for _i in 600:
		fresh.apply_drift(cfg, 0.1)
		bonded.apply_drift(cfg, 0.1)
	var fresh_moved: float = absf(float(fresh.identity["energy"]) - start)
	var bonded_moved: float = absf(float(bonded.identity["energy"]) - start)
	var fails := 0
	fails += _ok(fresh_moved > 0.1, "a fresh companion's identity learns toward how you play")
	fails += _ok(bonded_moved < fresh_moved * 0.2, "a deeply bonded companion's identity has crystallized (barely moves)")
	return fails


# Two companions played identically still end up faintly distinct, because identity is
# always pulled slightly back toward each one's own birth inclination.
static func _test_identity_keeps_birth_individuality(cfg: Dictionary) -> int:
	var timid := CompanionSelf.make_default(cfg)
	timid.birth["energy"] = 0.3
	timid.identity["energy"] = 0.3
	var lively := CompanionSelf.make_default(cfg)
	lively.birth["energy"] = 0.9
	lively.identity["energy"] = 0.9
	_seed_exploring(timid)
	_seed_exploring(lively)
	for _i in 2000:  # let both converge toward the (shared) exploring play style
		timid.apply_drift(cfg, 0.1)
		lively.apply_drift(cfg, 0.1)
	var fails := 0
	# Both learned toward high energy...
	fails += _ok(float(timid.identity["energy"]) > 0.6, "the timid-born companion still grows toward an exploring player")
	# ...but they never fully converge — the born-lively one settles a touch higher.
	fails += _ok(float(lively.identity["energy"]) > float(timid.identity["energy"]) + 0.02, "identical play still yields faintly distinct companions (birth residual)")
	return fails


# The live disposition relaxes back toward its identity anchor on its own — the machinery
# that will let a future "upset" push fade with time. Here we push it off and watch it return.
static func _test_disposition_relaxes_toward_identity(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var anchor := float(s.identity["clinginess"])
	s.traits["clinginess"] = anchor - 0.2  # a lingering push away from identity
	for _i in 600:  # no play change (under warmup), so identity holds; disposition relaxes
		s.apply_drift(cfg, 0.1)
	return _ok(absf(float(s.traits["clinginess"]) - anchor) < 0.05, "disposition relaxes back toward its identity anchor")


static func _test_identity_and_birth_round_trip(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.identity["energy"] = 0.42
	s.birth["energy"] = 0.88
	var r := CompanionSelf.from_dict(s.to_dict(), cfg)
	var fails := 0
	fails += _ok(is_equal_approx(float(r.identity["energy"]), 0.42), "identity survives a round-trip")
	fails += _ok(is_equal_approx(float(r.birth["energy"]), 0.88), "birth inclination survives a round-trip")
	return fails


# A pre-split save (disposition only) loads with identity seeded FROM that disposition, so
# the loaded companion is its own anchor and doesn't snap back toward defaults.
static func _test_old_save_seeds_identity_from_traits(cfg: Dictionary) -> int:
	var r := CompanionSelf.from_dict({ "version": 1, "traits": { "energy": 0.33 } }, cfg)
	return _ok(is_equal_approx(float(r.identity["energy"]), float(r.traits["energy"])), "an old save seeds identity from its saved disposition")


# A far-away, non-interacting perception that just reports which area we're in.
static func _perception_area(area: String) -> Dictionary:
	var p := _perception(false)
	p["current_area"] = area
	return p


# Reaching a new area grows bond exactly once: spawn is home (no bump), a new region pays,
# and returning to any known area (home or already-discovered) pays nothing.
static func _test_new_area_grows_bond_once(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.observe(_perception_area("vale:clearing"), cfg, 0.0)  # spawn -> home
	var fails := 0
	fails += _ok(is_equal_approx(s.bond, 0.0), "the spawn area is home, not a discovery (no bond)")
	s.observe(_perception_area("vale:grove"), cfg, 0.0)  # cross into a new region
	var after_grove := s.bond
	fails += _ok(after_grove > 0.0, "reaching a new area grows bond")
	s.observe(_perception_area("vale:clearing"), cfg, 0.0)  # back home
	fails += _ok(is_equal_approx(s.bond, after_grove), "returning home earns no fresh bond")
	s.observe(_perception_area("vale:grove"), cfg, 0.0)  # back to the discovered region
	fails += _ok(is_equal_approx(s.bond, after_grove), "returning to a discovered area earns no fresh bond")
	return fails


# The world-of-worlds case: because area ids are world-namespaced and familiarity persists,
# the first area of a DIFFERENT world is a fresh discovery, not mistaken for home.
static func _test_new_world_is_all_new(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.observe(_perception_area("vale:clearing"), cfg, 0.0)  # home in the first world
	var before := s.bond
	s.observe(_perception_area("thornfen:gate"), cfg, 0.0)  # step into a new world
	return _ok(s.bond > before, "the first area of a new world is a discovery (world-namespaced)")


# Examining a thing it LIKES delights it more than one it's indifferent to: the mood
# discovery spike is scaled by the appraised appeal carried in perception.
static func _test_appeal_scales_discovery_delight(cfg: Dictionary) -> int:
	var c := _mood_cfg_no_walk(cfg)

	var loved := CompanionSelf.make_default(c)
	_settle_mood(loved, c)
	var lv0 := loved.mood_valence
	var p_loved := _perception(false, "crystal")
	p_loved["interaction_appeal"] = 0.9
	loved.observe(p_loved, c, 0.1)
	loved.update_mood(p_loved, c, 0.1, _rng())
	var loved_jump := loved.mood_valence - lv0

	var plain := CompanionSelf.make_default(c)
	_settle_mood(plain, c)
	var pv0 := plain.mood_valence
	var p_plain := _perception(false, "signpost")
	p_plain["interaction_appeal"] = 0.3
	plain.observe(p_plain, c, 0.1)
	plain.update_mood(p_plain, c, 0.1, _rng())
	var plain_jump := plain.mood_valence - pv0

	return _ok(loved_jump > plain_jump, "a loved find delights more than an indifferent one")


# Crossing a bond milestone flags bond_event exactly once: it fires the frame the threshold
# is passed, stays clear while bond holds, and never re-fires for an already-reached level.
static func _test_bond_milestone_fires_once(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var fails := 0
	# A fresh companion at bond 0 hasn't crossed anything yet.
	s.observe(_perception(true), cfg, 0.1)
	fails += _ok(s.bond_event == "", "no milestone fires before any threshold is crossed")
	# Jump bond just past the first milestone (0.25) and observe a frame.
	s.bond = 0.26
	s.observe(_perception(true), cfg, 0.0)
	fails += _ok(s.bond_event == "milestone", "crossing the first milestone fires a milestone event")
	# The very next frame, still above 0.25, must not re-fire.
	s.observe(_perception(true), cfg, 0.0)
	fails += _ok(s.bond_event == "", "an already-reached milestone does not fire again")
	# A second, higher milestone (0.5) fires its own event.
	s.bond = 0.51
	s.observe(_perception(true), cfg, 0.0)
	fails += _ok(s.bond_event == "milestone", "crossing the next milestone fires again")
	return fails


# The milestone memory lives in short_term, which is persisted — so a companion loaded from
# a save past a milestone does NOT re-fire it on its first frame back.
static func _test_bond_milestone_persists_across_save(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.30
	s.observe(_perception(true), cfg, 0.0)  # crosses 0.25, records it in short_term
	var restored := CompanionSelf.from_dict(s.to_dict(), cfg)
	var fails := 0
	fails += _ok(is_equal_approx(float(restored.short_term.get("bond_milestone", -1.0)), 0.25), "the reached milestone survives a save")
	restored.observe(_perception(true), cfg, 0.0)
	fails += _ok(restored.bond_event == "", "a reloaded companion does not re-fire a milestone it already reached")
	return fails


# A welcomed pet grows bond, and like every bond source it HABITUATES: the second pet (well
# after the cooldown, so the cooldown gate isn't what's limiting it) grows bond less.
static func _test_pet_grows_bond_then_habituates(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.observations["play_seconds"] = 100.0
	var b0 := s.bond
	s.pet(cfg)
	var first := s.bond - b0
	s.observations["play_seconds"] += float(cfg["pet"]["bond_cooldown"]) + 1.0
	var b1 := s.bond
	s.pet(cfg)
	var second := s.bond - b1
	var fails := 0
	fails += _ok(first > 0.0, "the first pet grows bond")
	fails += _ok(second > 0.0, "a later pet still grows some bond")
	fails += _ok(second < first, "repeated pets habituate (each grows bond less)")
	return fails


# The anti-farm backstop: tapping Pet many times within the same instant of play (play_seconds
# not advancing) pays AT MOST once — the cooldown gate stops the spam the novelty curve alone
# wouldn't (since familiarity would still tick on each call).
static func _test_pet_spam_pays_once(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.observations["play_seconds"] = 100.0
	var b0 := s.bond
	for _i in 20:
		s.pet(cfg)  # same play_seconds throughout -> only the first should pay
	var spammed_gain := s.bond - b0
	# Compare to a single pet on an identical fresh self.
	var t := CompanionSelf.make_default(cfg)
	t.observations["play_seconds"] = 100.0
	var tb := t.bond
	t.pet(cfg)
	var single_gain := t.bond - tb
	return _ok(is_equal_approx(spammed_gain, single_gain), "spamming pet in one instant pays at most once (anti-farm)")


static func _test_pet_lifts_mood(cfg: Dictionary) -> int:
	var c := _mood_cfg_no_walk(cfg)
	var s := CompanionSelf.make_default(c)
	_settle_mood(s, c)
	var v0 := s.mood_valence
	s.pet(c)
	return _ok(s.mood_valence > v0, "a welcomed pet lifts the mood")


# A rebuff (shy-away) costs no bond and never drops the mood below the cozy floor.
static func _test_pet_rebuff_no_bond_and_stays_above_floor(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var floor_v := float(cfg["mood"]["neg_floor"])
	s.mood_valence = floor_v  # already at the floor
	var b0 := s.bond
	s.pet_rebuff(cfg)
	var fails := 0
	fails += _ok(s.mood_valence >= floor_v - 0.0001, "a rebuff never drops the mood below the negative floor")
	fails += _ok(is_equal_approx(s.bond, b0), "a rebuff grows no bond")
	return fails


static func _test_pet_familiarity_round_trips(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.observations["play_seconds"] = 100.0
	s.pet(cfg)
	var restored := CompanionSelf.from_dict(s.to_dict(), cfg)
	return _ok(is_equal_approx(float(restored.familiarity.get("pet", 0.0)), 1.0), "pet familiarity survives a save/load")
