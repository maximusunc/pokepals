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
	fails += _test_a_pond_blocks_along_its_drawn_bank()
	fails += _test_a_soft_worlds_pond_is_round()
	return fails


# The pond at (300, 200), radius 100: its bank bulges out to ~119 px at angle ~2.076 and dips in to
# ~85 px at angle ~5.379 (PondShape; the same vectors pin the server's twin in ambient_pals_test.exs).
const POND_C := Vector2(300, 200)
const BULGE_A := 2.0758
const DENT_A := 5.3789

static func _pond_world(extra := {}) -> Dictionary:
	var w := { "ponds": [{ "center": [300, 200], "radius": 100 }] }
	w.merge(extra)
	return w


static func _test_a_pond_blocks_along_its_drawn_bank() -> int:
	var fails := 0
	fails += _check("the bank formula matches its pinned vectors",
		absf(PondShape.radius_at(1.0, 100.0, PondShape.seed_for(POND_C)) - 93.3920) < 0.01
		and absf(PondShape.radius_at(2.0, 100.0, PondShape.seed_for(POND_C)) - 117.9170) < 0.01
		and absf(WorldArt.organic_radius(3.0, 100.0, PondShape.seed_for(POND_C)) - 85.8548) < 0.01)
	var solids := Solids.build(_pond_world(), [], {})
	var bank_bulge := PondShape.radius_at(BULGE_A, 100.0, PondShape.seed_for(POND_C))
	# standing where the bank bulges out (outside the old circle, but in the drawn water): pushed out to the bank
	var wet := POND_C + Vector2.from_angle(BULGE_A) * 110.0
	var p := Solids.resolve(wet, 6.0, solids, _big_bounds(), 2.0)
	fails += _check("a body in the bulging water is pushed out to the drawn bank (%.1f >= %.1f)" % [p.distance_to(POND_C), bank_bulge + 8.0],
		p.distance_to(POND_C) >= bank_bulge + 7.9)
	# standing where the bank dips in (inside the old circle, but on dry ground): left alone
	var dry := POND_C + Vector2.from_angle(DENT_A) * 97.0
	fails += _check("a body on the dry ground of a dent in the bank is not pushed",
		Solids.resolve(dry, 6.0, solids, _big_bounds(), 2.0).is_equal_approx(dry))
	# the nav grid agrees: a line across the bulge is blocked, one skirting the dent is clear
	var grid := NavGrid.build(solids, _big_bounds(), 6.0, 2.0, 16.0)
	var t := Vector2.from_angle(BULGE_A).orthogonal() * 60.0
	var across_bulge := POND_C + Vector2.from_angle(BULGE_A) * 112.0
	fails += _check("routing sees the bulge", not grid.line_clear(across_bulge - t, across_bulge + t))
	var u := Vector2.from_angle(DENT_A).orthogonal() * 10.0
	fails += _check("routing walks the dent", grid.line_clear(dry - u, dry + u))
	return fails


static func _test_a_soft_worlds_pond_is_round() -> int:
	var soft := _pond_world({ "art": { "entities": { "ground": { "render": "soft" } } } })
	var solids := Solids.build(soft, [], {})
	var p := Solids.resolve(POND_C + Vector2.from_angle(DENT_A) * 97.0, 6.0, solids, _big_bounds(), 2.0)
	return _check("a soft world's round pond blocks as a plain circle", p.distance_to(POND_C) >= 107.9)


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
