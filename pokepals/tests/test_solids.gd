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
		"interactables": [
			{ "type": "bench", "position": [0, 0] },        # solid by type
			{ "type": "wildflowers", "position": [5, 5] },  # flat -> excluded
		],
		"pond": { "center": [200, 200], "radius": 50 },
	}
	var border := [Vector2(-300, -300)]
	var solids := Solids.build(world, border, { "pond_blocks": true })
	# 2 trees + 1 border + 1 great_tree + 1 bench + 1 pond = 6 (wildflowers skipped)
	return _check("builds trees/border/landmark/solid-prop/pond, skips flat props", solids.size() == 6)
