class_name TestFacetLight
## Tests for Glintwold's turning light (FacetLight): a pure function of the shared clock. No nodes.


static func run_all() -> int:
	var fails := 0
	print("TestFacetLight")
	fails += _test_starts_from_the_upper_left()
	fails += _test_turns_once_a_period()
	fails += _test_turns_slowly_and_smoothly()
	fails += _test_config()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _test_starts_from_the_upper_left() -> int:
	var a := FacetLight.angle(0)
	var d := FacetLight.direction(a)
	return _ok(d.x < -0.6 and d.y < -0.6, "at the start of a turn the light is up and to the left")


static func _test_turns_once_a_period() -> int:
	var fails := 0
	var ms := 1_764_000_000_000   # a real-looking unix time, so precision is tested too
	var a0 := FacetLight.angle(ms, 600.0)
	var a1 := FacetLight.angle(ms + 600_000, 600.0)
	fails += _ok(absf(angle_difference(a0, a1)) < 1e-6, "one period later the light is back where it was")
	var half := FacetLight.angle(ms + 300_000, 600.0)
	fails += _ok(absf(absf(angle_difference(a0, half)) - PI) < 1e-6, "half a period later it stands opposite")
	return fails


static func _test_turns_slowly_and_smoothly() -> int:
	var ms := 1_764_000_000_000
	var biggest := 0.0
	for i in 200:
		var a := FacetLight.angle(ms + i * 1000, 600.0)
		var b := FacetLight.angle(ms + i * 1000 + 16, 600.0)
		biggest = maxf(biggest, absf(angle_difference(a, b)))
	return _ok(biggest < 0.001, "a frame moves the light by a hair, never a jump (%f rad)" % biggest)


static func _test_config() -> int:
	var a := FacetLight.from_config({ "light_period": 600, "light_start": 0 }, 0)
	var b := FacetLight.from_config({ "light_period": 600, "light_start": 90 }, 0)
	return _ok(absf(a) < 1e-6 and absf(b - PI * 0.5) < 1e-6, "the ground's config sets where the turn starts (in degrees)")
