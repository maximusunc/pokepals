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
