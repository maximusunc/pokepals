class_name TestCompanionAppraisal
## Tests for the pure appraisal: neutral tags + tastes + curiosity -> 0..1 appeal.

static func run_all() -> int:
	var fails := 0
	var cfg: Dictionary = WorldData.load_json("res://data/companion.json")
	print("TestCompanionAppraisal")
	fails += _test_loved_beats_plain(cfg)
	fails += _test_empty_is_neutral(cfg)
	fails += _test_unknown_tag_is_neutral(cfg)
	fails += _test_curiosity_raises_appeal(cfg)
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _test_loved_beats_plain(cfg: Dictionary) -> int:
	var loved := CompanionAppraisal.appeal(["shiny", "light"], cfg, 0.85)
	var plain := CompanionAppraisal.appeal(["made"], cfg, 0.85)
	var fails := 0
	fails += _ok(loved > plain, "a thing with liked tags appeals more than a plain one")
	fails += _ok(loved > 0.5 and plain < 0.5, "liked reads above neutral, indifferent below")
	return fails


static func _test_empty_is_neutral(cfg: Dictionary) -> int:
	return _ok(is_equal_approx(CompanionAppraisal.appeal([], cfg, 0.5), float(cfg["appraisal"]["neutral"])), "no tags -> neutral appeal")


static func _test_unknown_tag_is_neutral(cfg: Dictionary) -> int:
	# Curiosity 0.5 is the midpoint, so the curiosity multiplier is 1.0 and an unknown tag
	# (defaulting to neutral) reads exactly neutral.
	return _ok(is_equal_approx(CompanionAppraisal.appeal(["zorblax"], cfg, 0.5), float(cfg["appraisal"]["neutral"])), "an unknown tag -> neutral appeal")


static func _test_curiosity_raises_appeal(cfg: Dictionary) -> int:
	var incurious := CompanionAppraisal.appeal(["flower"], cfg, 0.0)
	var curious := CompanionAppraisal.appeal(["flower"], cfg, 1.0)
	return _ok(curious > incurious, "a curious companion finds more appeal in the same thing")
