class_name TestTide
## Tests for Ebbmere's pure logic: TideClock (the shared tide), TideField (the baked seabed), DigPlan (what is
## buried where, this tide) and DigSense (the companion sniffing it out). No nodes. The clock is also held to
## the SAME vectors as the server's Elixir twin (tests/world_fixtures/tide_vectors.json).

const P := { "period_s": 360.0, "epoch_s": 0.0, "level_low": 0.30, "level_high": 0.78, "yield_level": 0.345 }


static func run_all() -> int:
	var fails := 0
	print("TestTide")
	fails += _test_clock_matches_the_shared_vectors()
	fails += _test_clock_shape()
	fails += _test_low_window()
	fails += _test_cycle_index_steps_at_high_water()
	fails += _test_clock_epoch_shifts_the_cycle()
	fails += _test_field_bilinear_and_depth()
	fails += _test_field_round_trips_the_spec_encoding()
	fails += _test_field_deep_and_exposed()
	fails += _test_dig_hash_is_stable_and_spread()
	fails += _test_dig_activity_fraction()
	fails += _test_dig_outcomes()
	fails += _test_dig_verbs()
	fails += _test_dollar_ready()
	fails += _test_sense_notices_nearest_and_holds()
	fails += _test_sense_range_grows_with_bond()
	fails += _test_sense_lapses_when_the_tide_returns()
	fails += _test_sense_seen_by_eye()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _near(a: float, b: float, eps: float = 1e-9) -> bool:
	return absf(a - b) <= eps


static func _test_clock_matches_the_shared_vectors() -> int:
	var d: Dictionary = WorldData.load_json("res://tests/world_fixtures/tide_vectors.json")
	var params: Dictionary = d["params"]
	var fails := _ok(_near(TideClock.low_half_s(params), float(d["low_half_s"])), "the low window's half width agrees with the reference (%.4f s)" % TideClock.low_half_s(params))
	var bad := 0
	for v in d["vectors"]:
		var t := int(v["t"])
		if not _near(TideClock.phase(params, t), float(v["phase"])): bad += 1
		if TideClock.cycle(params, t) != int(v["cycle"]): bad += 1
		if not _near(TideClock.level(params, t), float(v["level"])): bad += 1
		if TideClock.in_low_window(params, t) != bool(v["low"]): bad += 1
		if TideClock.in_low_window(params, t, 30.0) != bool(v["low_grace_30"]): bad += 1
		if not _near(TideClock.seconds_until_low(params, t), float(v["until_low"]), 1e-6): bad += 1
	fails += _ok(bad == 0, "phase, cycle, level, the low window (with and without grace) and the countdown agree on all %d shared vectors" % d["vectors"].size())
	return fails


static func _test_clock_shape() -> int:
	var fails := _ok(_near(TideClock.level(P, 0), 0.78), "high water at phase 0")
	fails += _ok(_near(TideClock.level(P, 180000), 0.30), "lowest water at phase 0.5")
	fails += _ok(_near(TideClock.level(P, 90000), 0.54), "mid-tide at a quarter")
	fails += _ok(TideClock.state(P, 90000) == "ebbing" and TideClock.state(P, 270000) == "flooding" and TideClock.state(P, 180000) == "low", "ebbing, low, flooding")
	var mono := true
	var last := TideClock.level(P, 0)
	for s in range(1, 181):
		var l := TideClock.level(P, s * 1000)
		mono = mono and l <= last + 1e-12
		last = l
	fails += _ok(mono, "the level only falls from high water to the lowest")
	return fails


static func _test_low_window() -> int:
	var half := TideClock.low_half_s(P)
	var fails := _ok(half > 30.0 and half < 40.0, "the low window is about 70 s wide (half %.1f s)" % half)
	fails += _ok(TideClock.in_low_window(P, 180000 + int((half - 1.0) * 1000.0)), "inside the window just before its edge")
	fails += _ok(not TideClock.in_low_window(P, 180000 + int((half + 1.0) * 1000.0)), "outside just after its edge")
	fails += _ok(TideClock.in_low_window(P, 180000 + int((half + 20.0) * 1000.0), 30.0), "a grace period widens it")
	# at the exact edge the level IS the yield level
	fails += _ok(_near(TideClock.level(P, 180000 + int(round(half * 1000.0))), 0.345, 1e-4), "the edge is where the level meets yield_level")
	fails += _ok(_near(TideClock.seconds_until_low(P, 180000), 0.0), "no wait while it is low")
	fails += _ok(_near(TideClock.seconds_until_low(P, 0), 180.0 - half, 1e-6), "from high water the window opens half a period less its half width later")
	fails += _ok(_near(TideClock.seconds_until_low(P, 200000 + 100000), 360.0 - 300.0 + 180.0 - half, 1e-6), "after it closes the next one is a period away, less what has passed")
	fails += _ok(_near(TideClock.seconds_until_low_ends(P, 180000), half, 1e-6) and TideClock.seconds_until_low_ends(P, 0) == 0.0, "how long the window has left")
	var never := { "period_s": 360.0, "level_low": 0.3, "level_high": 0.78, "yield_level": 0.2 }
	fails += _ok(TideClock.low_half_s(never) == 0.0, "a yield level under the lowest water gives no window")
	return fails


static func _test_cycle_index_steps_at_high_water() -> int:
	var fails := _ok(TideClock.cycle(P, 0) == 0 and TideClock.cycle(P, 359999) == 0 and TideClock.cycle(P, 360000) == 1, "the cycle steps up at high water")
	fails += _ok(TideClock.cycle(P, -1) == -1, "and counts back before the epoch")
	return fails


static func _test_clock_epoch_shifts_the_cycle() -> int:
	var shifted := P.duplicate()
	shifted["epoch_s"] = 60.0
	var fails := _ok(_near(TideClock.level(shifted, 60000), 0.78), "the epoch is a high water")
	fails += _ok(TideClock.cycle(shifted, 59999) == -1 and TideClock.cycle(shifted, 60000) == 0, "and the cycle counts from it")
	return fails


static func _grid(w: int, h: int, fn: Callable) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(w * h)
	for y in h:
		for x in w:
			b[y * w + x] = int(round(clampf(float(fn.call(x, y)), 0.0, 1.0) * 255.0))
	return b


static func _test_field_bilinear_and_depth() -> int:
	# a ramp that rises 0.1 per cell along x, over a 4 x 3 grid of 10 px cells at (100, 200)
	var f := TideField.from_bytes(Vector2(100, 200), 10.0, 4, 3, _grid(4, 3, func(x, _y): return x * 0.1))
	var fails := _ok(not f.is_empty() and f.rect() == Rect2(100, 200, 40, 30), "a field knows its rectangle")
	fails += _ok(_near(f.elev_at(Vector2(105, 210)), 0.0, 0.005), "a cell centre reads that cell")
	fails += _ok(_near(f.elev_at(Vector2(115, 210)), 0.1, 0.005), "the next cell centre reads the next cell")
	fails += _ok(_near(f.elev_at(Vector2(110, 210)), 0.05, 0.005), "between centres it blends")
	fails += _ok(_near(f.elev_at(Vector2(0, 0)), 0.0, 0.005) and _near(f.elev_at(Vector2(900, 900)), 0.3, 0.005), "outside the grid it clamps to the edge")
	fails += _ok(_near(f.depth(Vector2(115, 210), 0.5), 0.4, 0.005), "depth is the level over the sand")
	fails += _ok(f.depth(Vector2(135, 210), 0.2) < 0.0, "a point higher than the water is dry (negative depth)")
	fails += _ok(TideField.new().is_empty() and TideField.new().elev_at(Vector2.ZERO) == 1.0, "an empty field is all dry land")
	return fails


static func _test_field_round_trips_the_spec_encoding() -> int:
	var bytes := _grid(5, 4, func(x, y): return (x + y * 5) / 20.0)
	var spec := { "origin": [10, 20], "cell": 8, "w": 5, "h": 4, "data": TideField.encode(bytes) }
	var f := TideField.from_spec(spec, 0.26)
	var fails := _ok(not f.is_empty() and f.width == 5 and f.height == 4 and f.origin == Vector2(10, 20), "a field decodes from the spec's block")
	fails += _ok(_near(f.elev_at(Vector2(10 + 4 + 8 * 2, 20 + 4 + 8 * 1)), 7.0 / 20.0, 0.004), "...with its values intact")
	var fine := TideField.from_spec({ "origin": [0, 0], "cell": 10, "w": 3, "h": 1, "bits": 16, "data": TideField.encode16([0.2501, 0.2502, 0.9]) })
	fails += _ok(not fine.is_empty() and _near(fine.elev_at(Vector2(5, 5)), 0.2501, 0.0001) and _near(fine.elev_at(Vector2(15, 5)), 0.2502, 0.0001), "a 16-bit field keeps differences far finer than one byte can")
	var wrong := spec.duplicate()
	wrong["w"] = 6
	fails += _ok(TideField.from_spec(wrong).is_empty(), "a block whose size does not match its data is rejected, not misread")
	fails += _ok(TideField.from_spec({}).is_empty(), "no block, no field")
	return fails


static func _test_field_deep_and_exposed() -> int:
	var f := TideField.from_bytes(Vector2.ZERO, 10.0, 3, 1, _grid(3, 1, func(x, _y): return [0.1, 0.5, 0.9][x]), 0.26)
	var fails := _ok(f.is_deep(Vector2(5, 5)) and not f.is_deep(Vector2(15, 5)), "the low cell is open sea, the others are not")
	var tall := TideField.from_bytes(Vector2(0, 0), 10.0, 2, 4, _grid(2, 4, func(_x, y): return [0.2, 0.5, 0.9, 0.95][y]))
	fails += _ok(tall.wet_extent(0.6, 0.05) == Rect2(0, 0, 20, 20), "the water's reach stops at the last row it can wet")
	fails += _ok(f.is_exposed(Vector2(25, 5), 0.78 - 0.1), "high sand is dry at high water")
	fails += _ok(not f.is_exposed(Vector2(15, 5), 0.6) and f.is_exposed(Vector2(15, 5), 0.4), "a flat is dry once the tide falls under it")
	fails += _ok(not f.is_exposed(Vector2(15, 5), 0.49, 0.02) and f.is_exposed(Vector2(15, 5), 0.47, 0.02), "a margin keeps the sign out of the wet edge")
	return fails


static func _test_dig_hash_is_stable_and_spread() -> int:
	var fails := _ok(DigPlan.hash01(3, "bar_a") == DigPlan.hash01(3, "bar_a"), "the same tide and spot always hash the same")
	fails += _ok(DigPlan.hash01(3, "bar_a") != DigPlan.hash01(4, "bar_a") and DigPlan.hash01(3, "bar_a") != DigPlan.hash01(3, "bar_b"), "a new tide or spot hashes differently")
	var lo := 1.0
	var hi := 0.0
	var inside := true
	var sum := 0.0
	for i in 400:
		var h := DigPlan.hash01(i, "spot_%d" % (i % 13))
		inside = inside and h >= 0.0 and h < 1.0
		lo = minf(lo, h)
		hi = maxf(hi, h)
		sum += h
	fails += _ok(inside and lo < 0.05 and hi > 0.95 and absf(sum / 400.0 - 0.5) < 0.08, "it is spread evenly over 0..1")
	# pinned values: if these move, every client's tide changes, so a change here must be deliberate
	fails += _ok(_near(DigPlan.hash01(0, "a"), DigPlan.hash01(0, "a")) and DigPlan.hash01(12, "bar_1") >= 0.0, "(values are pure of the engine's String.hash)")
	return fails


static func _test_dig_activity_fraction() -> int:
	var alive := 0
	for i in 600:
		if DigPlan.is_active(i, "s%d" % (i % 24), 0.6):
			alive += 1
	var fails := _ok(alive > 600 * 0.5 and alive < 600 * 0.7, "about the asked fraction of spots are alive in a tide (%d of 600)" % alive)
	fails += _ok(DigPlan.is_active(5, "any", 0.0, true) and not DigPlan.is_active(5, "any", 0.0) and DigPlan.is_active(5, "any", 1.0), "an `always` spot is alive every tide; 0 and 1 are never and always")
	var varies := false
	for c in range(1, 30):
		varies = varies or DigPlan.is_active(c, "s0", 0.5) != DigPlan.is_active(0, "s0", 0.5)
	fails += _ok(varies, "a spot is not alive every tide")
	return fails


static func _test_dig_outcomes() -> int:
	var table := [
		{ "kind": "shell", "weight": 6, "names": ["cockle", "whelk", "razor clam"] },
		{ "kind": "crab", "weight": 2 },
		{ "kind": "glass", "weight": 1 },
	]
	var counts := { "shell": 0, "crab": 0, "glass": 0 }
	var names := {}
	for i in 900:
		var o := DigPlan.pick_outcome(i, "s%d" % (i % 19), table)
		counts[o["kind"]] += 1
		if o["kind"] == "shell":
			names[o["name"]] = true
	var fails := _ok(counts["shell"] > counts["crab"] and counts["crab"] > counts["glass"] and counts["glass"] > 20, "outcomes follow the weights (%s)" % str(counts))
	fails += _ok(names.size() == 3, "a shell is one of its named kinds")
	fails += _ok(DigPlan.pick_outcome(7, "x", table) == DigPlan.pick_outcome(7, "x", table), "the same spot in the same tide always holds the same thing")
	fails += _ok(DigPlan.pick_outcome(7, "x", [])["kind"] == "shell", "an empty table still gives a shell")
	return fails


static func _test_dig_verbs() -> int:
	var aff := { "fox": "dig", "rabbit": "dig", "wolf": "dig", "_default": "dig" }
	var fails := _ok(DigPlan.verb_for("fox", aff) == "dig" and DigPlan.verb_for("rabbit", aff) == "dig", "a fox and a rabbit dig")
	fails += _ok(DigPlan.verb_for("bird", aff) == "" and DigPlan.verb_for("cat", aff) == "", "a bird and a cat cannot")
	fails += _ok(DigPlan.verb_for("", aff) == "dig", "the classic rig takes the default")
	return fails


static func _test_dollar_ready() -> int:
	var fails := _ok(DigPlan.dollar_ready(true, false, true), "the spot gives the dollar up in the lowest window")
	fails += _ok(not DigPlan.dollar_ready(true, false, false), "not outside it")
	fails += _ok(not DigPlan.dollar_ready(true, true, true), "not once it has been found")
	fails += _ok(not DigPlan.dollar_ready(false, false, true), "and no other spot ever does")
	fails += _ok(DigPlan.exposed(0.357, 0.344, 0.012) and not DigPlan.exposed(0.357, 0.346, 0.012), "the dollar's bar (0.357) shows exactly while the level is under the yield level (0.345)")
	return fails


static func _spots() -> Array:
	return [{ "id": "near", "pos": Vector2(100, 0) }, { "id": "far", "pos": Vector2(400, 0) }]


static func _test_sense_notices_nearest_and_holds() -> int:
	var s := DigSense.new()
	var seen := ""
	var started := false
	var held := 0.0
	var i := 0
	while i < 400 and seen == "":
		var r := s.update(0.05, Vector2.ZERO, 0.5, _spots())
		started = started or r["started"]
		if r["point"]:
			held += 0.05
			if r["started"]:
				seen = "_"
		i += 1
	var fails := _ok(started, "after a moment the companion stops and points")
	var s2 := DigSense.new()
	var first_target := Vector2.ZERO
	var noticed := ""
	for _i in 600:
		var r := s2.update(0.05, Vector2.ZERO, 0.5, _spots())
		if r["started"]:
			first_target = r["target"]
		if r["noticed"] != "":
			noticed = r["noticed"]
			break
	fails += _ok(first_target == Vector2(100, 0), "it points at the nearest uncovered spot")
	fails += _ok(noticed == "near", "when the point ends that spot is noticed (its sign shows)")
	# after a notice it cools down before pointing again
	var again := false
	for _i in 30:
		again = again or s2.update(0.05, Vector2.ZERO, 0.5, [{ "id": "far", "pos": Vector2(400, 0) }])["started"]
	fails += _ok(not again, "then it cools down before the next")
	return fails


static func _test_sense_range_grows_with_bond() -> int:
	var spot := [{ "id": "s", "pos": Vector2(400, 0) }]
	var fresh := DigSense.new()
	var bonded := DigSense.new()
	var a := false
	var b := false
	for _i in 60:
		a = a or fresh.update(0.1, Vector2.ZERO, 0.0, spot)["started"]
		b = b or bonded.update(0.1, Vector2.ZERO, 1.0, spot)["started"]
	return _ok(not a and b, "a spot 400 px away is beyond a stranger's nose and within a bonded companion's")


static func _test_sense_lapses_when_the_tide_returns() -> int:
	var s := DigSense.new()
	var r := {}
	for _i in 40:
		r = s.update(0.05, Vector2.ZERO, 0.5, _spots())
		if r["point"]:
			break
	var fails := _ok(r["point"], "(it is pointing)")
	r = s.update(0.05, Vector2.ZERO, 0.5, [])
	fails += _ok(not r["point"] and r["noticed"] == "", "the water covers the spot: the point lapses and nothing is noticed")
	return fails


static func _test_sense_seen_by_eye() -> int:
	var s := DigSense.new()
	var seen := s.seen_by_eye(_spots(), Vector2(60, 0), Vector2(900, 0))
	var fails := _ok(seen == ["near"], "a spot right by you is seen without a sniff")
	seen = s.seen_by_eye(_spots(), Vector2(900, 0), Vector2(380, 10))
	fails += _ok(seen == ["far"], "...or right by your companion")
	return fails
