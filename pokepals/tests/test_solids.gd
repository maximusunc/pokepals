class_name TestSolids
## Pure tests for the barrier resolver and the solid-list builder — no nodes, no scene.
## Documents the collision contract: keep a body inside the map and out of every solid,
## sliding along surfaces rather than passing through them.

static func run_all() -> int:
	var fails := 0
	print("TestSolids")
	fails += _test_pushes_out_of_circle()
	fails += _test_clamps_to_bounds()
	fails += _test_slides_along_obstacle()
	fails += _test_leaves_a_clear_point_untouched()
	fails += _test_build_includes_the_right_categories()
	fails += _test_buildings_block_their_whole_footprint()
	return fails


static func _test_buildings_block_their_whole_footprint() -> int:
	var world := { "buildings": [{ "rect": [100, 100, 120, 90] }], "plates": [{ "rect": [0, 0, 60, 60], "solid": true }, { "rect": [500, 500, 60, 60] }] }
	var solids := Solids.build(world, [], {})
	var fails := 0
	# a body dropped just inside the building's edges and corners, ends up outside it
	for inside in [Vector2(160, 104), Vector2(104, 150), Vector2(104, 104), Vector2(216, 186)]:
		var p := Solids.resolve(inside, 6.0, solids, _big_bounds(), 2.0)
		var out := not Rect2(100, 100, 120, 90).has_point(p)
		fails += _check("a body at %s is pushed out of the building (ended at %s)" % [inside, p], out)
	# a clear spot beside it is left alone, and the plain (non-solid) plate adds nothing
	var free := Solids.resolve(Vector2(300, 145), 6.0, solids, _big_bounds(), 2.0)
	fails += _check("open ground beside a building is untouched", free.is_equal_approx(Vector2(300, 145)))
	var on_plate := Solids.resolve(Vector2(530, 530), 6.0, solids, _big_bounds(), 2.0)
	fails += _check("a non-solid plate does not block", on_plate.is_equal_approx(Vector2(530, 530)))
	var water := Solids.resolve(Vector2(30, 30), 6.0, solids, _big_bounds(), 2.0)
	fails += _check("a solid plate (water) blocks", not Rect2(0, 0, 60, 60).has_point(water))
	return fails


static func _check(name: String, ok: bool) -> int:
	print("  %s  %s" % [("PASS" if ok else "FAIL"), name])
	return 0 if ok else 1


static func _big_bounds() -> Rect2:
	return Rect2(Vector2(-1000, -1000), Vector2(2000, 2000))


static func _test_pushes_out_of_circle() -> int:
	var solids := [{ "center": Vector2.ZERO, "radius": 10.0 }]
	var p := Solids.resolve(Vector2(2, 0), 6.0, solids, _big_bounds(), 0.0)
	# pushed to the rim: body(6) + solid(10) + margin(0) = 16
	return _check("pushes a penetrating point out to the solid's rim", p.length() >= 15.99)


static func _test_clamps_to_bounds() -> int:
	var bounds := Rect2(Vector2.ZERO, Vector2(100, 100))
	var p := Solids.resolve(Vector2(-50, 50), 6.0, [], bounds, 2.0)
	# r = body(6) + margin(2) = 8, so x clamps to 8
	return _check("clamps an out-of-bounds point to the map edge", is_equal_approx(p.x, 8.0))


static func _test_slides_along_obstacle() -> int:
	var solids := [{ "center": Vector2.ZERO, "radius": 10.0 }]
	var p := Solids.resolve(Vector2(-3, 5), 6.0, solids, _big_bounds(), 0.0)
	# pushed out radially; the tangential (y) component survives -> it slides, not passes
	return _check("preserves tangential motion (slides around)", p.y > 0.0 and p.length() >= 15.99)


static func _test_leaves_a_clear_point_untouched() -> int:
	var solids := [{ "center": Vector2(500, 500), "radius": 10.0 }]
	var p := Solids.resolve(Vector2.ZERO, 6.0, solids, _big_bounds(), 2.0)
	return _check("leaves a clear point exactly where it is", p.is_equal_approx(Vector2.ZERO))


static func _test_build_includes_the_right_categories() -> int:
	var world := {
		"trees": [[10, 10], [20, 20]],
		"landmarks": [{ "type": "great_tree", "position": [100, 100] }],
		"props": [
			{ "type": "bench", "position": [0, 0] },        # solid by type
			{ "type": "wildflowers", "position": [5, 5] },  # flat -> excluded
		],
		"pond": { "center": [200, 200], "radius": 50 },
	}
	var border := [Vector2(-300, -300)]
	var solids := Solids.build(world, border, { "pond_blocks": true })
	# 2 trees + 1 border + 1 great_tree + 1 bench + 1 pond = 6 (wildflowers skipped)
	return _check("builds trees/border/landmark/solid-prop/pond, skips flat props", solids.size() == 6)
