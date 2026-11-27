class_name TestSkyRealm
## Tests for SkyRealm, the pure geometry of a sky-island world: islands fenced by segment solids, bridges that
## cut a gap in the fence and grow rails, hidden bridges that stay shut until revealed, and the ground test.

# two 200 x 200 islands, 300 px apart, joined by one bridge along y = 100 (mouths on their facing edges)
const SKY := {
	"islands": [
		{ "id": "west", "poly": [[0, 0], [200, 0], [200, 200], [0, 200]] },
		{ "id": "east", "poly": [[500, 0], [700, 0], [700, 200], [500, 200]] },
	],
	"bridges": [{ "id": "span", "a": [200, 100], "b": [500, 100], "width": 80.0 }],
}
const HIDDEN := {
	"islands": [
		{ "id": "west", "poly": [[0, 0], [200, 0], [200, 200], [0, 200]] },
		{ "id": "east", "poly": [[500, 0], [700, 0], [700, 200], [500, 200]] },
	],
	"bridges": [{ "id": "secret", "a": [200, 100], "b": [500, 100], "width": 80.0, "hidden": true }],
}


static func run_all() -> int:
	var fails := 0
	print("TestSkyRealm")
	fails += _test_island_edges_fence_the_island()
	fails += _test_a_bridge_cuts_a_gap_and_grows_rails()
	fails += _test_the_gap_lets_a_body_cross_and_the_rails_keep_it_on()
	fails += _test_a_hidden_bridge_is_shut_until_revealed()
	fails += _test_ground_test()
	fails += _test_no_sky_means_no_solids_and_no_test()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _bounds() -> Rect2:
	return Rect2(-300, -300, 1400, 800)


## Walk a body from `a` toward `b` in small steps through the real resolver; where it ends up.
static func _walk(sky: Dictionary, a: Vector2, b: Vector2) -> Vector2:
	var solids := SkyRealm.solids(sky)
	var p := a
	var dir := (b - a).normalized()
	for _i in int(a.distance_to(b) / 2.0) + 40:
		p += dir * 2.0
		p = Solids.resolve(p, 6.0, solids, _bounds(), 2.0)
	return p


static func _test_island_edges_fence_the_island() -> int:
	var f := 0
	var lone := { "islands": [SKY["islands"][0]] }
	var s := SkyRealm.solids(lone)
	f += _ok(s.size() == 4, "a square island is fenced by four edge segments (%d)" % s.size())
	var end := _walk(lone, Vector2(100, 100), Vector2(400, 100))
	f += _ok(end.x < 200.0, "a body walked at the edge is stopped by it (x = %.1f)" % end.x)
	end = _walk(lone, Vector2(100, 100), Vector2(100, -300))
	f += _ok(end.y > 0.0, "...north as well (y = %.1f)" % end.y)
	return f


static func _test_a_bridge_cuts_a_gap_and_grows_rails() -> int:
	var f := 0
	var s := SkyRealm.solids(SKY)
	var rails := 0
	for e in s:
		if float(e["radius"]) == SkyRealm.DEFAULT_RAIL_R:
			rails += 1
	f += _ok(rails == 2, "an open bridge has a rail down each side (%d)" % rails)
	# the two facing edges are each cut in two (above and below the gap)
	f += _ok(s.size() == 3 + 2 + 3 + 2 + 2, "the facing edges are cut in two (%d solids)" % s.size())
	var blocked := false
	for e in s:
		if float(e["radius"]) == SkyRealm.DEFAULT_EDGE_R:
			var p := Solids.nearest_point(e, Vector2(200, 100))
			if p.distance_to(Vector2(200, 100)) < 20.0:
				blocked = true
	f += _ok(not blocked, "nothing fences the middle of the mouth")
	return f


static func _test_the_gap_lets_a_body_cross_and_the_rails_keep_it_on() -> int:
	var f := 0
	var end := _walk(SKY, Vector2(100, 100), Vector2(600, 100))
	f += _ok(end.x > 560.0, "a body walks straight across the bridge to the far island (x = %.1f)" % end.x)
	end = _walk(SKY, Vector2(100, 100), Vector2(400, 20))
	f += _ok(end.y > 40.0 and end.x < 500.0, "a body cannot step off the bridge into the sky (%s)" % str(end))
	return f


static func _test_a_hidden_bridge_is_shut_until_revealed() -> int:
	var f := 0
	var shut := _walk(HIDDEN, Vector2(100, 100), Vector2(600, 100))
	f += _ok(shut.x < 200.0, "a hidden bridge leaves the island closed (x = %.1f)" % shut.x)
	var open_sky := HIDDEN.duplicate(true)
	open_sky["revealed"] = ["secret"]
	var through := _walk(open_sky, Vector2(100, 100), Vector2(600, 100))
	f += _ok(through.x > 560.0, "once revealed it can be walked (x = %.1f)" % through.x)
	f += _ok(SkyRealm.solids(HIDDEN).size() == 8, "shut, only the two islands' edges are solid (%d)" % SkyRealm.solids(HIDDEN).size())
	return f


static func _test_ground_test() -> int:
	var f := 0
	var g := SkyRealm.ground_test(SKY)
	f += _ok(g.call(Vector2(100, 100)) and g.call(Vector2(600, 100)), "islands are ground")
	f += _ok(g.call(Vector2(350, 100)), "a bridge is ground")
	f += _ok(not g.call(Vector2(350, 20)) and not g.call(Vector2(350, 300)), "the sky beside a bridge is not")
	var h := SkyRealm.ground_test(HIDDEN)
	f += _ok(not h.call(Vector2(350, 100)), "a hidden bridge is not ground until revealed")
	var open_sky := HIDDEN.duplicate(true)
	open_sky["revealed"] = ["secret"]
	f += _ok(SkyRealm.ground_test(open_sky).call(Vector2(350, 100)), "...and is once it is")
	return f


static func _test_no_sky_means_no_solids_and_no_test() -> int:
	var f := 0
	f += _ok(SkyRealm.solids({}).is_empty(), "no sky, no solids")
	f += _ok(not SkyRealm.ground_test({}).is_valid(), "no sky, no ground test")
	return f
