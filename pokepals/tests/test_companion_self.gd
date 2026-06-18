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
