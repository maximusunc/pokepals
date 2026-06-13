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
	s.mood = 0.5
	s.short_term["last_poi"] = [12.0, 34.0]
	var restored := CompanionSelf.from_dict(s.to_dict(), cfg)
	var fails := 0
	fails += _ok(is_equal_approx(restored.trait_value("curiosity"), 0.42), "trait survives round-trip")
	fails += _ok(is_equal_approx(float(restored.observations["interactions"]), 7.0), "observation survives round-trip")
	fails += _ok(is_equal_approx(restored.mood, 0.5), "mood survives round-trip")
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
