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
	# Directed layer (F-1)
	fails += _test_instruct_switches_immediately()
	fails += _test_instruct_nondrawable_is_noop()
	fails += _test_hold_scales_with_bond()
	fails += _test_release_returns_to_drift()
	fails += _test_drift_biases_toward_preferred()
	fails += _test_preferred_species_derivation()
	fails += _test_rng_untouched_without_profiles()
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


# --- Directed layer (F-1) --------------------------------------------------------------------

# Drift interval fixed at 1s (so a >1s tick reliably shifts), a bond-scaled hold from 2s..20s, a full
# 0..1 drift bias toward the signature, and temperament profiles for the three forms in _forms().
# fox reads as the most curious/energetic, cat the most clingy/calm.
static func _cfg_directed() -> Dictionary:
	return {
		"enabled": true,
		"morph_interval": [1.0, 1.0],
		"hold_low": 2.0,
		"hold_high": 20.0,
		"preferred_bias_low": 0.0,
		"preferred_bias_high": 1.0,
		"species_profiles": {
			"cat": { "curiosity": 0.50, "energy": 0.35, "clinginess": 0.70 },
			"fox": { "curiosity": 0.90, "energy": 0.70, "clinginess": 0.40 },
			"rabbit": { "curiosity": 0.50, "energy": 0.60, "clinginess": 0.50 },
		},
	}


static func _test_instruct_switches_immediately() -> int:
	var f := CompanionForm.new(_forms(), _cfg_directed(), _rng(1))
	var fails := 0
	fails += _ok(f.instruct("fox", 0.5), "instruct a drawable form succeeds")
	fails += _ok(f.species() == "fox", "instruct switches to the form on the same call")
	fails += _ok(f.is_holding(), "and enters a held state")
	fails += _ok(f.directed_species() == "fox", "the held form is reported")
	return fails


static func _test_instruct_nondrawable_is_noop() -> int:
	# wolf is not among _forms() (cat/fox/rabbit) -> instruct must decline without changing anything.
	var f := CompanionForm.new(_forms(), _cfg_directed(), _rng(1))
	var before := f.species()
	var fails := 0
	fails += _ok(not f.instruct("wolf", 1.0), "instruct an un-drawable form is a no-op")
	fails += _ok(f.species() == before, "and leaves the worn form unchanged")
	fails += _ok(not f.is_holding(), "and enters no held state")
	return fails


static func _test_hold_scales_with_bond() -> int:
	# hold = lerp(2, 20, bond). A 2.5s tick releases the low-bond hold but not the high-bond one.
	var lo := CompanionForm.new(_forms(), _cfg_directed(), _rng(2))
	lo.instruct("fox", 0.0)
	var hi := CompanionForm.new(_forms(), _cfg_directed(), _rng(2))
	hi.instruct("fox", 1.0)
	var fails := 0
	lo.update(2.5, 0.0, {})
	hi.update(2.5, 1.0, {})
	fails += _ok(not lo.is_holding(), "a low-bond hold (~2s) lapses after 2.5s")
	fails += _ok(hi.is_holding(), "a high-bond hold (~20s) is still held after 2.5s")
	return fails


static func _test_release_returns_to_drift() -> int:
	var identity := { "curiosity": 0.9, "energy": 0.7, "clinginess": 0.4 }  # nearest fox
	var f := CompanionForm.new(_forms(), _cfg_directed(), _rng(4))
	f.instruct("fox", 0.0)                 # hold ~2s
	var fails := 0
	fails += _ok(not f.update(2.5, 0.0, identity), "the hold lapse itself reports no worn-form change")
	fails += _ok(not f.is_holding(), "no longer holding after the hold lapses")
	fails += _ok(f.directed_species() == "", "the directed form is cleared on release")
	# Drift is armed again (1s interval) -> a >1s tick now morphs autonomously.
	fails += _ok(f.update(2.0, 0.0, identity), "autonomous drift resumes after release")
	return fails


static func _test_drift_biases_toward_preferred() -> int:
	# Identity nearest fox. At high bond the drift favors fox; at low bond it's ~uniform. Count how
	# often fox is worn across many autonomous morphs, high vs low. Deterministic under the seed.
	var identity := { "curiosity": 0.9, "energy": 0.7, "clinginess": 0.4 }
	var n := 240
	var hi := CompanionForm.new(_forms(), _cfg_directed(), _rng(11))
	var lo := CompanionForm.new(_forms(), _cfg_directed(), _rng(11))
	var count_hi := 0
	var count_lo := 0
	for i in n:
		hi.update(2.0, 1.0, identity)
		lo.update(2.0, 0.0, identity)
		if hi.species() == "fox":
			count_hi += 1
		if lo.species() == "fox":
			count_lo += 1
	var fails := 0
	fails += _ok(count_hi > count_lo, "high bond wears the signature (fox) more than low bond (%d vs %d)" % [count_hi, count_lo])
	fails += _ok(count_hi > n / 3, "high bond wears the signature more than a uniform share (%d/%d)" % [count_hi, n])
	return fails


static func _test_preferred_species_derivation() -> int:
	var f := CompanionForm.new(_forms(), _cfg_directed(), _rng(1))
	var fails := 0
	fails += _ok(f.preferred_species({ "curiosity": 0.95, "energy": 0.8, "clinginess": 0.35 }) == "fox", "a curious, energetic identity -> fox")
	fails += _ok(f.preferred_species({ "curiosity": 0.45, "energy": 0.3, "clinginess": 0.75 }) == "cat", "a calm, clingy identity -> cat")
	fails += _ok(f.preferred_species({ "curiosity": 0.5, "energy": 0.6, "clinginess": 0.5 }) == "rabbit", "a middling identity -> rabbit")
	# No profiles configured -> no signature at all.
	var g := CompanionForm.new(_forms(), _cfg(), _rng(1))
	fails += _ok(g.preferred_species({ "curiosity": 0.9, "energy": 0.7, "clinginess": 0.4 }) == "", "no profiles -> no signature")
	return fails


static func _test_rng_untouched_without_profiles() -> int:
	# With no species_profiles, the bond/identity args must not perturb the drift RNG stream: the
	# old update(delta) and the new update(delta, bond, identity) must produce identical sequences.
	var identity := { "curiosity": 0.9, "energy": 0.7, "clinginess": 0.4 }
	var a := CompanionForm.new(_forms(), _cfg(), _rng(21))
	var b := CompanionForm.new(_forms(), _cfg(), _rng(21))
	var fails := 0
	for i in 20:
		a.update(2.0)
		b.update(2.0, 0.5, identity)
		fails += _ok(a.species() == b.species() and a.variant() == b.variant(), "shift %d identical with/without bond args (%s vs %s)" % [i, a.species(), b.species()])
	return fails
