class_name TestCompanionForm
## Tests for the companion's DAEMON FORM decision logic (CompanionForm) — the pure state machine
## that holds which animal the companion currently wears and decides WHEN to shift into a different
## one. No nodes, no sprites, no filesystem: it takes a plain list of drawable forms and an injected
## RNG, so the whole shift schedule is deterministic and unit-testable. These assertions document its
## guarantees: it starts wearing something, it holds until the interval elapses, a shift genuinely
## changes the species, a lone form never shifts, and disabling it freezes the form entirely.

const EPS := 0.0001


static func run_all() -> int:
	var fails := 0
	print("TestCompanionForm")
	fails += _test_picks_an_initial_form()
	fails += _test_no_forms_is_inert()
	fails += _test_holds_until_interval_elapses()
	fails += _test_shift_changes_species()
	fails += _test_single_form_never_shifts()
	fails += _test_disabled_never_shifts()
	fails += _test_variant_stays_in_range()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


static func _forms() -> Array:
	return [
		{ "species": "cat", "variants": 4 },
		{ "species": "fox", "variants": 3 },
		{ "species": "rabbit", "variants": 4 },
	]


# A tiny interval so a single small delta reliably crosses it.
static func _cfg() -> Dictionary:
	return { "enabled": true, "morph_interval": [1.0, 1.0] }


static func _test_picks_an_initial_form() -> int:
	var f := CompanionForm.new(_forms(), _cfg(), _rng(1))
	return _ok(f.species() != "", "a fresh form is already wearing an animal")


static func _test_no_forms_is_inert() -> int:
	var f := CompanionForm.new([], _cfg(), _rng(1))
	var fails := 0
	fails += _ok(f.species() == "", "no drawable forms -> wears nothing")
	fails += _ok(not f.update(100.0), "no drawable forms -> never shifts")
	return fails


static func _test_holds_until_interval_elapses() -> int:
	# Interval fixed at 2.0s; small ticks below it must not shift.
	var f := CompanionForm.new(_forms(), { "enabled": true, "morph_interval": [2.0, 2.0] }, _rng(3))
	var fails := 0
	fails += _ok(not f.update(0.5), "holds its form partway through the interval")
	fails += _ok(not f.update(1.0), "still holds before the interval elapses")
	fails += _ok(f.update(1.0), "shifts once the interval elapses")
	return fails


static func _test_shift_changes_species() -> int:
	# Across several shifts the species must actually change each time (never repeat back-to-back).
	var f := CompanionForm.new(_forms(), _cfg(), _rng(7))
	var prev := f.species()
	var fails := 0
	for i in 12:
		var shifted := f.update(2.0)  # comfortably past the 1.0s interval
		fails += _ok(shifted, "shift %d fired" % i)
		fails += _ok(f.species() != prev, "shift %d changed the species (%s -> %s)" % [i, prev, f.species()])
		prev = f.species()
	return fails


static func _test_single_form_never_shifts() -> int:
	var f := CompanionForm.new([{ "species": "wolf", "variants": 4 }], _cfg(), _rng(2))
	var fails := 0
	fails += _ok(f.species() == "wolf", "a lone form is worn")
	fails += _ok(not f.update(100.0), "a lone form never shifts (nothing to change into)")
	fails += _ok(f.species() == "wolf", "and stays itself")
	return fails


static func _test_disabled_never_shifts() -> int:
	var f := CompanionForm.new(_forms(), { "enabled": false, "morph_interval": [1.0, 1.0] }, _rng(5))
	var fails := 0
	fails += _ok(f.species() != "", "a disabled form still wears an initial animal")
	var start := f.species()
	fails += _ok(not f.update(100.0), "disabled -> never shifts")
	fails += _ok(f.species() == start, "disabled -> form is frozen")
	return fails


static func _test_variant_stays_in_range() -> int:
	# fox has 3 variants -> variant is always 0..2, across the initial pick and many shifts.
	var only_fox := [{ "species": "fox", "variants": 3 }, { "species": "cat", "variants": 4 }]
	var f := CompanionForm.new(only_fox, _cfg(), _rng(9))
	var fails := 0
	for i in 20:
		f.update(2.0)
		if f.species() == "fox":
			fails += _ok(f.variant() >= 0 and f.variant() <= 2, "fox coat in range at shift %d (%d)" % [i, f.variant()])
	return fails
