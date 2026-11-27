class_name TestPlazaRealm
## Tests for PlazaRealm, the pure geometry of a floating plaza: rectangles of floor laid edge to edge, fenced
## only where the far side is sky, an island that touches nothing, and the ground test that keeps routes off
## the sky.

# A court with a narrower porch to its south, a wing to its east that starts lower than the court's top, a
# pool along the court's north edge, and a terrace floating apart.
const PLAZA := {
	"floors": [
		{ "id": "court", "rect": [0, 0, 400, 300] },
		{ "id": "porch", "rect": [150, 300, 250, 380] },
		{ "id": "wing", "rect": [400, 100, 600, 300] },
		{ "id": "terrace", "rect": [100, -500, 300, -400] },
	],
	"pool": { "rect": [0, -200, 400, 0] },
}


static func run_all() -> int:
	var fails := 0
	print("TestPlazaRealm")
	fails += _test_ground_test()
	fails += _test_fences_stand_only_against_sky()
	fails += _test_a_body_crosses_between_floors_but_not_into_sky()
	fails += _test_the_terrace_is_an_island()
	fails += _test_floor_lookup()
	fails += _test_no_plaza_means_no_solids_and_no_test()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _bounds() -> Rect2:
	return Rect2(-300, -800, 1200, 1400)


## Walk a body from `a` toward `b` in small steps through the real resolver; where it ends up.
static func _walk(a: Vector2, b: Vector2) -> Vector2:
	var solids := PlazaRealm.solids(PLAZA)
	var p := a
	var dir := (b - a).normalized()
	for _i in int(a.distance_to(b) / 2.0) + 40:
		p += dir * 2.0
		p = Solids.resolve(p, 6.0, solids, _bounds(), 2.0)
	return p


static func _test_ground_test() -> int:
	var f := 0
	var g := PlazaRealm.ground_test(PLAZA)
	f += _ok(g.is_valid(), "a plaza has a ground test")
	f += _ok(g.call(Vector2(200, 150)) and g.call(Vector2(200, 350)) and g.call(Vector2(500, 200)), "every floor is ground")
	f += _ok(g.call(Vector2(200, -100)), "the pool is ground (you wade in it)")
	f += _ok(g.call(Vector2(400, 200)) and g.call(Vector2(0, 0)), "edges and corners count as ground")
	f += _ok(not g.call(Vector2(500, 50)) and not g.call(Vector2(100, 350)) and not g.call(Vector2(200, -300)), "the sky between them is not")
	return f


static func _test_fences_stand_only_against_sky() -> int:
	var f := 0
	var s := PlazaRealm.solids(PLAZA)
	var g := PlazaRealm.ground_test(PLAZA)
	var bad := 0
	for e in s:
		var a: Vector2 = e["a"]
		var b: Vector2 = e["b"]
		var mid := (a + b) * 0.5
		var n := (b - a).normalized().orthogonal()
		# a fence has ground on exactly one side of it
		if bool(g.call(mid + n * 2.0)) == bool(g.call(mid - n * 2.0)):
			bad += 1
	f += _ok(bad == 0 and not s.is_empty(), "every fence has ground on one side and sky on the other (%d fences, %d wrong)" % [s.size(), bad])
	var shared := false
	for e in s:
		var p := Solids.nearest_point(e, Vector2(400, 200))
		if p.distance_to(Vector2(400, 200)) < 1.0:
			shared = true
	f += _ok(not shared, "no fence where the court meets its wing")
	# the court's south edge is fenced either side of the porch, but not across its mouth
	var mouth := false
	for e in s:
		if Solids.nearest_point(e, Vector2(200, 300)).distance_to(Vector2(200, 300)) < 1.0:
			mouth = true
	f += _ok(not mouth, "no fence across the porch's mouth")
	# collinear pieces are joined: the pool's north edge and the court's west edge (pool + court) are one each
	var west := 0
	for e in s:
		var a: Vector2 = e["a"]
		var b: Vector2 = e["b"]
		if is_equal_approx(a.x, 0.0) and is_equal_approx(b.x, 0.0):
			west += 1
	f += _ok(west <= 2, "a straight edge is a few solids, not many (%d on the west)" % west)
	return f


static func _test_a_body_crosses_between_floors_but_not_into_sky() -> int:
	var f := 0
	var end := _walk(Vector2(200, 150), Vector2(550, 200))
	f += _ok(end.x > 540.0, "a body walks from the court onto its wing (x = %.1f)" % end.x)
	end = _walk(Vector2(200, 150), Vector2(200, 370))
	f += _ok(end.y > 360.0, "...and down onto the porch (y = %.1f)" % end.y)
	end = _walk(Vector2(200, 150), Vector2(200, -150))
	f += _ok(end.y < -140.0, "...and into the pool (y = %.1f)" % end.y)
	end = _walk(Vector2(200, -100), Vector2(200, -400))
	f += _ok(end.y > -200.0, "the pool's far edge is the edge of the world (y = %.1f)" % end.y)
	end = _walk(Vector2(500, 200), Vector2(500, 0))
	f += _ok(end.y > 100.0, "the wing's north edge stops a body (y = %.1f)" % end.y)
	end = _walk(Vector2(200, 350), Vector2(50, 350))
	f += _ok(end.x > 150.0, "the porch's sides stop a body (x = %.1f)" % end.x)
	return f


static func _test_the_terrace_is_an_island() -> int:
	var f := 0
	var solids := PlazaRealm.solids(PLAZA)
	var grid := NavGrid.build(solids, _bounds(), 6.0, 2.0, 16.0, PlazaRealm.ground_test(PLAZA))
	# (an unreachable goal gets the best partial route, so what matters is that it never leaves the terrace)
	var to_court := grid.find_path(Vector2(200, -450), Vector2(200, 150), 20000, 0)
	var stays := true
	for p: Vector2 in to_court:
		if p.y > -400.0:
			stays = false
	f += _ok(stays, "no route leads from the terrace to the court (%d waypoints, all on the terrace)" % to_court.size())
	var across := grid.find_path(Vector2(200, 150), Vector2(500, 250), 20000)
	f += _ok(not across.is_empty(), "but one does lead from the court to its wing")
	var end := _walk(Vector2(200, -450), Vector2(200, -150))
	f += _ok(end.y < -400.0, "a body on the terrace stays on it (y = %.1f)" % end.y)
	return f


static func _test_floor_lookup() -> int:
	var f := 0
	f += _ok(String(PlazaRealm.floor_at(PLAZA, Vector2(500, 200)).get("id", "")) == "wing", "the floor underfoot is found")
	f += _ok(PlazaRealm.floor_at(PLAZA, Vector2(200, -100)).is_empty() and PlazaRealm.in_pool(PLAZA, Vector2(200, -100)), "the pool is no floor, but it is the pool")
	return f


static func _test_no_plaza_means_no_solids_and_no_test() -> int:
	var f := 0
	f += _ok(PlazaRealm.solids({}).is_empty(), "no plaza, no solids")
	f += _ok(not PlazaRealm.ground_test({}).is_valid(), "no plaza, no ground test")
	return f
