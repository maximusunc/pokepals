class_name TestStillnessGate
## Tests for W-2's stillness (StillnessGate): it fills only while you're still AND in the place, a
## fidget pauses it and drifts it back a little instead of wiping it, wandering off drifts it back the
## same gentle way, and it completes exactly once.


static func run_all() -> int:
	var fails := 0
	print("TestStillnessGate")
	fails += _test_it_fills_while_still_in_the_place()
	fails += _test_moving_only_drifts_back_a_little()
	fails += _test_away_from_the_place_it_does_not_fill()
	fails += _test_it_completes_once()
	return fails


static func _ok(cond: bool, label: String) -> int:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	return 0 if cond else 1


static func _test_it_fills_while_still_in_the_place() -> int:
	var g := StillnessGate.new(20.0)
	for i in 100:
		g.update(0.1, true, true)
	return _ok(is_equal_approx(g.fraction(), 0.5) and not g.is_done(), "ten seconds still is halfway there")


static func _test_moving_only_drifts_back_a_little() -> int:
	var g := StillnessGate.new(20.0, 0.5)
	for i in 100:
		g.update(0.1, true, true)
	for i in 10:
		g.update(0.1, true, false)  # a second of fidgeting
	return _ok(is_equal_approx(g.fraction(), 9.5 / 20.0), "a second of moving costs half a second, not everything")


static func _test_away_from_the_place_it_does_not_fill() -> int:
	var g := StillnessGate.new(20.0)
	for i in 300:
		g.update(0.1, false, true)
	return _ok(g.fraction() == 0.0, "standing still somewhere else doesn't count")


static func _test_it_completes_once() -> int:
	var g := StillnessGate.new(2.0)
	var completions := 0
	for i in 60:
		if g.update(0.1, true, true):
			completions += 1
	return _ok(completions == 1 and g.is_done() and g.fraction() == 1.0, "it completes exactly once")
