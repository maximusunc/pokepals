class_name TestFishing
## Tests for fishing's pure logic (usable items, docs/usable-items-design.md): the timing ring (FishingRing)
## lands a tap in its window and lets a fish go otherwise, and the water (FishingWater) finds where a cast
## lands, in ponds and rivers and in water a world adds (the tide), and nowhere dry.


static func run_all() -> int:
	var fails := 0
	print("TestFishing")
	fails += _test_a_tap_in_the_window_lands()
	fails += _test_a_tap_outside_the_window_misses()
	fails += _test_no_tap_times_out_after_the_passes()
	fails += _test_the_first_tap_decides()
	fails += _test_the_ring_meets_the_target_at_the_window()
	fails += _test_a_quicker_ring_is_quicker()
	fails += _test_ponds_and_rivers_are_water()
	fails += _test_a_cast_lands_in_the_water_ahead()
	fails += _test_a_cast_finds_water_beside_you()
	fails += _test_no_water_in_reach_means_no_cast()
	fails += _test_water_a_world_adds_counts()
	return fails


static func _ok(cond: bool, label: String) -> int:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	return 0 if cond else 1


# Run the ring to `share` of the way through its first pass.
static func _ring_at(ring: FishingRing, share: float) -> FishingRing:
	ring.update(ring.pass_seconds() * share)
	return ring


static func _test_a_tap_in_the_window_lands() -> int:
	var ring := _ring_at(FishingRing.new(0.2, 1.0), FishingRing.TARGET)
	return _ok(ring.in_window() and ring.tap() == "landed" and ring.result() == "landed", "a tap as the ring meets the target lands the fish")


static func _test_a_tap_outside_the_window_misses() -> int:
	var early := _ring_at(FishingRing.new(0.2, 1.0), 0.3)
	var late := _ring_at(FishingRing.new(0.2, 1.0), 0.95)
	return _ok(early.tap() == "missed" and late.tap() == "missed", "a tap too early or too late lets it go")


static func _test_no_tap_times_out_after_the_passes() -> int:
	var ring := FishingRing.new(0.2, 1.0)
	ring.update(ring.pass_seconds() * (FishingRing.PASSES - 0.05))
	var still_running := not ring.is_over()
	ring.update(ring.pass_seconds() * 0.1)
	return _ok(still_running and ring.result() == "timeout", "the ring comes round %d times, then the fish swims off" % FishingRing.PASSES)


static func _test_the_first_tap_decides() -> int:
	var ring := _ring_at(FishingRing.new(0.2, 1.0), 0.2)
	ring.tap()
	ring.update(ring.pass_seconds() * (FishingRing.TARGET - 0.2))
	return _ok(ring.tap() == "missed", "a second tap can't undo a miss")


static func _test_the_ring_meets_the_target_at_the_window() -> int:
	var ring := _ring_at(FishingRing.new(0.2, 1.0), FishingRing.TARGET)
	var meets := is_equal_approx(ring.ring_scale(), FishingRing.target_scale())
	var warm := ring.closeness() > 0.95
	var cold := _ring_at(FishingRing.new(0.2, 1.0), 0.05).closeness() < 0.05
	return _ok(meets and warm and cold, "the ring meets the target circle just as the window opens, warming as it nears")


static func _test_a_quicker_ring_is_quicker() -> int:
	var slow := FishingRing.new(0.2, 1.0)
	var quick := FishingRing.new(0.1, 1.4)
	return _ok(quick.pass_seconds() < slow.pass_seconds() and quick.window < slow.window, "a rarer fish's ring closes faster, with a narrower window")


static func _water() -> FishingWater:
	return FishingWater.from_world({
		"ponds": [{ "center": [0, 0], "radius": 50 }],
		"river": { "rect": [400, 0, 300, 100] },
	})


static func _test_ponds_and_rivers_are_water() -> int:
	var w := _water()
	var ok := w.is_water(Vector2(10, 10)) and w.is_water(Vector2(500, 50)) and not w.is_water(Vector2(48, 0)) \
		and not w.is_water(Vector2(200, 200)) and w.has_water() and not FishingWater.from_world({}).has_water()
	return _ok(ok, "ponds (a little inside their edge) and rivers are water; the bank and the meadow are not")


static func _test_a_cast_lands_in_the_water_ahead() -> int:
	var p: Variant = _water().cast_point(Vector2(0, -80), Vector2.DOWN)
	return _ok(p is Vector2 and _water().is_water(p) and (p as Vector2).y > -50.0 and absf((p as Vector2).x) < 1.0, "facing the pond, the bobber lands in it, straight ahead")


static func _test_a_cast_finds_water_beside_you() -> int:
	var p: Variant = _water().cast_point(Vector2(-80, 0), Vector2.UP)
	return _ok(p is Vector2 and _water().is_water(p), "facing away along the shore, the cast still finds the pond beside you")


static func _test_no_water_in_reach_means_no_cast() -> int:
	return _ok(_water().cast_point(Vector2(200, 300), Vector2.DOWN) == null, "with no water in reach, there's nowhere to cast")


static func _test_water_a_world_adds_counts() -> int:
	var w := FishingWater.from_world({})
	w.set_extra(func(p: Vector2) -> bool: return p.y > 100.0)
	var p: Variant = w.cast_point(Vector2(0, 60), Vector2.DOWN)
	return _ok(w.has_water() and p is Vector2 and (p as Vector2).y > 100.0, "water a world adds (the tide) can be fished too")
