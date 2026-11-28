class_name TestMirrorGeometry
## Tests for the pure geometry of Stillglass's reflections: WaterMask (the lake's outline as a bitmap) and
## MirrorGeometry (where the waterline is below something, the image's place, how it fades, and which animal
## the lake shows instead of your companion). No nodes.


static func run_all() -> int:
	var fails := 0
	print("TestMirrorGeometry")
	fails += _test_mask_matches_the_outline()
	fails += _test_mask_unions_overlapping_outlines()
	fails += _test_mask_empty_without_water()
	fails += _test_waterline_below_a_bank()
	fails += _test_waterline_none_in_the_water_or_out_of_reach()
	fails += _test_reflect_point()
	fails += _test_strength_fades_with_distance()
	fails += _test_pick_species_is_never_the_one_worn()
	fails += _test_pick_species_is_deterministic_and_varied()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _circle(c: Vector2, r: float, n := 64) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func _test_mask_matches_the_outline() -> int:
	var m := WaterMask.build([_circle(Vector2(100, 100), 80.0)])
	var fails := _ok(not m.is_empty(), "a lake gives a bitmap")
	fails += _ok(m.is_water(Vector2(100, 100)) and m.is_water(Vector2(150, 100)), "inside the outline is water")
	fails += _ok(not m.is_water(Vector2(100, 10)) and not m.is_water(Vector2(200, 100)) and not m.is_water(Vector2(-500, 0)), "outside it is land (and far outside the box too)")
	# the edge is right to within a texel or two
	var edge := Vector2(100 + 80, 100)
	fails += _ok(m.is_water(edge - Vector2(3, 0)) and not m.is_water(edge + Vector2(3, 0)), "the edge is where the outline says")
	return fails


static func _test_mask_unions_overlapping_outlines() -> int:
	var m := WaterMask.build([_circle(Vector2(0, 0), 60.0), _circle(Vector2(90, 0), 60.0)])
	return _ok(m.is_water(Vector2(45, 0)) and m.is_water(Vector2(-50, 0)) and m.is_water(Vector2(140, 0)), "two overlapping ponds are one lake")


static func _test_mask_empty_without_water() -> int:
	var m := WaterMask.build([])
	return _ok(m.is_empty() and not m.is_water(Vector2.ZERO), "no water, no mask")


static func _test_waterline_below_a_bank() -> int:
	var m := WaterMask.build([_circle(Vector2(0, 200), 150.0)])   # its top edge is at y = 50
	var y := MirrorGeometry.waterline_below(Vector2(0, 20), m.is_water, 100.0)
	var fails := _ok(absf(y - 50.0) <= 2.5, "the waterline below a bank is the lake's edge (%.1f)" % y)
	var side := MirrorGeometry.waterline_below(Vector2(100, 60), m.is_water, 150.0)
	fails += _ok(absf(side - 88.2) <= 2.5, "...and follows the curve off to the side (%.1f)" % side)
	return fails


static func _test_waterline_none_in_the_water_or_out_of_reach() -> int:
	var m := WaterMask.build([_circle(Vector2(0, 200), 150.0)])
	var fails := _ok(is_nan(MirrorGeometry.waterline_below(Vector2(0, 200), m.is_water, 100.0)), "something standing in the water has no waterline below it")
	fails += _ok(is_nan(MirrorGeometry.waterline_below(Vector2(0, -200), m.is_water, 100.0)), "the water is too far away to reflect anything")
	fails += _ok(is_nan(MirrorGeometry.waterline_below(Vector2(400, 20), m.is_water, 300.0)), "no water below at all")
	return fails


static func _test_reflect_point() -> int:
	var r := MirrorGeometry.reflect_point(Vector2(30, 40), 50.0)
	return _ok(r.is_equal_approx(Vector2(30, 60)), "a point 10 above the waterline is imaged 10 below it")


static func _test_strength_fades_with_distance() -> int:
	var fails := _ok(MirrorGeometry.strength(0.0, 100.0) == 1.0, "at the edge the image is full")
	fails += _ok(MirrorGeometry.strength(100.0, 100.0) == 0.0 and MirrorGeometry.strength(400.0, 100.0) == 0.0, "at the reach it is gone")
	fails += _ok(MirrorGeometry.strength(30.0, 100.0) > MirrorGeometry.strength(60.0, 100.0), "it fades the further you stand")
	fails += _ok(MirrorGeometry.strength(10.0, 0.0) == 0.0, "no reach, no image")
	return fails


static func _test_pick_species_is_never_the_one_worn() -> int:
	var pool := ["cat", "fox", "rabbit", "bird", "wolf"]
	var ok := true
	for cur in pool:
		for seed in 12:
			ok = ok and MirrorGeometry.pick_species(cur, pool, seed) != cur and MirrorGeometry.pick_species(cur, pool, seed) != ""
	var fails := _ok(ok, "the lake never shows the animal your companion wears")
	fails += _ok(MirrorGeometry.pick_species("cat", ["cat"], 3) == "", "...and shows nothing if there is nothing else")
	return fails


static func _test_pick_species_is_deterministic_and_varied() -> int:
	var pool := ["cat", "fox", "rabbit", "bird", "wolf"]
	var a := MirrorGeometry.pick_species("fox", pool, MirrorGeometry.seed_of("mirror_stone"))
	var b := MirrorGeometry.pick_species("fox", pool, MirrorGeometry.seed_of("mirror_stone"))
	var seen := {}
	for s in 8:
		seen[MirrorGeometry.pick_species("fox", pool, s)] = true
	var fails := _ok(a == b, "the same seed and shape always meet the same other animal")
	fails += _ok(seen.size() == 4, "...and different seeds reach every other animal")
	return fails
