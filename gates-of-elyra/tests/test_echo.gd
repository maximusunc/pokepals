class_name TestEcho
## Tests for EchoField (the canyon's echoes as geometry) and EchoGuide (Hollowsong's howl: cooldown, hints,
## the companion noticing the cave, the cave revealing itself). No nodes: just points and numbers.

const CFG := {
	"speed": 700.0, "path_low": 1500.0, "path_high": 2200.0, "min_strength": 0.10, "falloff": 1.0,
	"hollow": 0.35, "wrong_range_low": 1000.0, "wrong_range_high": 1600.0, "wrong_noise_low": 0.4,
	"wrong_noise_high": 0.1, "wrong_noise_floor": 0.2, "wrong_strength_low": 0.7, "wrong_strength_high": 1.0,
	"cooldown_low": 4.0, "cooldown_high": 2.0, "reveal_radius": 200.0,
	"notice_range_low": 300.0, "notice_range_high": 600.0, "notice_cooldown_low": 10.0, "notice_cooldown_high": 4.0,
	"notice_hold": 2.0,
}
# a tall cliff face on the east (x = 300), facing west
const EAST := [300.0, -200.0, 300.0, 200.0]
const CAVE := Vector2(0, -700)


static func run_all() -> int:
	var fails := 0
	print("TestEcho")
	fails += _test_mirror()
	fails += _test_a_wall_ahead_answers_from_its_foot()
	fails += _test_arrival_is_distance_over_speed()
	fails += _test_no_echo_from_behind_a_wall()
	fails += _test_a_wall_off_to_the_side_misses()
	fails += _test_farther_is_fainter_and_too_far_is_silent()
	fails += _test_bond_carries_further()
	fails += _test_a_wall_in_the_way_blocks_the_echo()
	fails += _test_two_walls_two_echoes_in_order()
	fails += _test_separate_ears_bounce_at_the_midpoint()
	fails += _test_wrong_echo_range_and_timing()
	fails += _test_wrong_echo_is_late_and_repeatable()
	fails += _test_wrong_bearing_is_truer_when_bonded_and_near()
	fails += _test_two_bearings_find_the_cave()
	fails += _test_unit_is_in_range_and_repeatable()
	fails += _test_howl_cooldown_and_bond()
	fails += _test_a_friends_howl_costs_us_nothing()
	fails += _test_hints_fire_once()
	fails += _test_cave_reveals_on_walking_up_and_stays()
	fails += _test_companion_notices_the_cave_by_bond()
	fails += _test_noticing_never_reveals_or_resets()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _walls(list: Array) -> Array:
	return EchoField.walls_from(list)


static func _guide() -> EchoGuide:
	return EchoGuide.new([EAST], CAVE, Vector2(0, -600), CFG)


static func _test_mirror() -> int:
	var m := EchoField.mirror(Vector2(100, 40), Vector2(300, -200), Vector2(300, 200))
	return _ok(m.is_equal_approx(Vector2(500, 40)), "a point mirrors across a wall's line")


static func _test_a_wall_ahead_answers_from_its_foot() -> int:
	var e := EchoField.echoes(Vector2(0, 0), Vector2(0, 0), _walls([EAST]), CFG, 0.0)
	var ok := e.size() == 1 and (e[0]["point"] as Vector2).is_equal_approx(Vector2(300, 0))
	return _ok(ok, "a wall straight ahead answers from the point nearest the voice")


static func _test_arrival_is_distance_over_speed() -> int:
	var e := EchoField.echoes(Vector2(0, 0), Vector2(0, 0), _walls([EAST]), CFG, 0.0)
	var ok := not e.is_empty() and is_equal_approx(float(e[0]["arrive"]), 600.0 / 700.0) \
		and is_equal_approx(float(e[0]["t_hit"]), 300.0 / 700.0)
	return _ok(ok, "the echo is back after there-and-back over the speed, and reaches the wall halfway")


static func _test_no_echo_from_behind_a_wall() -> int:
	# the voice on one side, the ears on the other: no bounce
	var e := EchoField.echoes(Vector2(0, 0), Vector2(600, 0), _walls([EAST]), CFG, 0.0)
	return _ok(e.is_empty(), "no echo when the voice and the ears are on opposite sides of the wall")


static func _test_a_wall_off_to_the_side_misses() -> int:
	# a short wall far up the canyon: the straight line from its mirror image never crosses it
	var e := EchoField.echoes(Vector2(0, 0), Vector2(0, 0), _walls([[300.0, 300.0, 300.0, 400.0]]), CFG, 0.0)
	return _ok(e.is_empty(), "a wall the voice cannot reach head-on does not answer")


static func _test_farther_is_fainter_and_too_far_is_silent() -> int:
	var near := EchoField.echoes(Vector2.ZERO, Vector2.ZERO, _walls([EAST]), CFG, 0.0)
	var far_wall := [600.0, -400.0, 600.0, 400.0]
	var far := EchoField.echoes(Vector2.ZERO, Vector2.ZERO, _walls([far_wall]), CFG, 0.0)
	var too_far := EchoField.echoes(Vector2.ZERO, Vector2.ZERO, _walls([[900.0, -400.0, 900.0, 400.0]]), CFG, 0.0)
	var ok := near.size() == 1 and far.size() == 1 and float(near[0]["strength"]) > float(far[0]["strength"]) and too_far.is_empty()
	return _ok(ok, "a farther wall is fainter, and one beyond the reach is silent")


static func _test_bond_carries_further() -> int:
	var w := _walls([[900.0, -400.0, 900.0, 400.0]])   # path 1800: past 1500, inside 2200
	var fresh := EchoField.echoes(Vector2.ZERO, Vector2.ZERO, w, CFG, 0.0)
	var bonded := EchoField.echoes(Vector2.ZERO, Vector2.ZERO, w, CFG, 1.0)
	return _ok(fresh.is_empty() and bonded.size() == 1, "a bonded howl carries to a wall a fresh one cannot reach")


static func _test_a_wall_in_the_way_blocks_the_echo() -> int:
	# a near wall hides the far one behind it
	var w := _walls([EAST, [500.0, -400.0, 500.0, 400.0]])
	var e := EchoField.echoes(Vector2.ZERO, Vector2.ZERO, w, CFG, 1.0)
	var only_near := e.size() == 1 and (e[0]["point"] as Vector2).is_equal_approx(Vector2(300, 0))
	return _ok(only_near, "a wall in the way stops the voice reaching the one behind it")


static func _test_two_walls_two_echoes_in_order() -> int:
	var w := _walls([EAST, [-500.0, -400.0, -500.0, 400.0]])
	var e := EchoField.echoes(Vector2.ZERO, Vector2.ZERO, w, CFG, 0.0)
	var ok := e.size() == 2 and float(e[0]["arrive"]) < float(e[1]["arrive"]) and (e[0]["point"] as Vector2).x > 0.0
	return _ok(ok, "two walls answer, the nearer first")


static func _test_separate_ears_bounce_at_the_midpoint() -> int:
	# voice at y=-50, ears at y=+50: the bounce is level with the middle of them
	var e := EchoField.echoes(Vector2(0, -50), Vector2(0, 50), _walls([EAST]), CFG, 0.0)
	return _ok(e.size() == 1 and absf((e[0]["point"] as Vector2).y) < 0.01, "the bounce is where the mirror line meets the wall")


static func _test_wrong_echo_range_and_timing() -> int:
	var near := EchoField.wrong_echo(Vector2.ZERO, Vector2.ZERO, CAVE, CFG, 0.0, 1)
	var far := EchoField.wrong_echo(Vector2(0, 1200), Vector2(0, 1200), CAVE, CFG, 0.0, 1)
	var ok := not near.is_empty() and far.is_empty()
	ok = ok and is_equal_approx(float(near["t_birth"]), 700.0 / 700.0 + 0.35)
	ok = ok and is_equal_approx(float(near["arrive"]), float(near["t_birth"]) + 700.0 / 700.0)
	return _ok(ok, "the cave answers only within earshot, late: out-and-back plus a hollow beat")


static func _test_wrong_echo_is_late_and_repeatable() -> int:
	var a := EchoField.wrong_echo(Vector2.ZERO, Vector2.ZERO, CAVE, CFG, 0.5, 42)
	var b := EchoField.wrong_echo(Vector2.ZERO, Vector2.ZERO, CAVE, CFG, 0.5, 42)
	var wall := EchoField.echoes(Vector2.ZERO, Vector2.ZERO, _walls([EAST]), CFG, 0.5)
	var ok := (a["origin"] as Vector2).is_equal_approx(b["origin"]) and float(a["arrive"]) > float(wall[0]["arrive"])
	ok = ok and absf((a["origin"] as Vector2).length() - 700.0) < 0.01
	return _ok(ok, "the same howl seeds the same error, the apparent origin keeps its distance, and it is later than a wall's")


static func _test_wrong_bearing_is_truer_when_bonded_and_near() -> int:
	var worst_fresh := 0.0
	var worst_bonded := 0.0
	var worst_near := 0.0
	for s in range(1, 60):
		worst_fresh = maxf(worst_fresh, absf(float(EchoField.wrong_echo(Vector2.ZERO, Vector2.ZERO, CAVE, CFG, 0.0, s)["error"])))
		worst_bonded = maxf(worst_bonded, absf(float(EchoField.wrong_echo(Vector2.ZERO, Vector2.ZERO, CAVE, CFG, 1.0, s)["error"])))
		worst_near = maxf(worst_near, absf(float(EchoField.wrong_echo(Vector2.ZERO, Vector2.ZERO, Vector2(0, -150), CFG, 0.0, s)["error"])))
	return _ok(worst_bonded < worst_fresh * 0.6 and worst_near < worst_fresh * 0.5, "a bonded companion and a nearer howl give a truer bearing")


static func _test_two_bearings_find_the_cave() -> int:
	# from two different spots the apparent origins' lines cross close to the true cave
	var cave := Vector2(400, -800)
	var p1 := Vector2(-300, 0)
	var p2 := Vector2(500, 100)
	var w1 := EchoField.wrong_echo(p1, p1, cave, CFG, 1.0, 5)
	var w2 := EchoField.wrong_echo(p2, p2, cave, CFG, 1.0, 9)
	var hit: Variant = Geometry2D.line_intersects_line(p1, ((w1["origin"] as Vector2) - p1).normalized(), p2, ((w2["origin"] as Vector2) - p2).normalized())
	var ok: bool = hit != null and (hit as Vector2).distance_to(cave) < 260.0
	return _ok(ok, "two howls from two places cross near the cave")


static func _test_unit_is_in_range_and_repeatable() -> int:
	var ok := true
	var seen_neg := false
	var seen_pos := false
	for s in 200:
		var u := EchoField.unit(s)
		ok = ok and u >= -1.0 and u <= 1.0 and u == EchoField.unit(s)
		seen_neg = seen_neg or u < -0.3
		seen_pos = seen_pos or u > 0.3
	return _ok(ok and seen_neg and seen_pos, "the seeded error is in [-1, 1], repeatable, and goes both ways")


static func _test_howl_cooldown_and_bond() -> int:
	var g := _guide()
	var first := g.howl(Vector2.ZERO, Vector2.ZERO, 0.0)
	var second := g.howl(Vector2.ZERO, Vector2.ZERO, 0.0)
	g.update(3.9, Vector2(0, 900), 0.0)
	var third := g.howl(Vector2.ZERO, Vector2.ZERO, 0.0)
	g.update(0.2, Vector2(0, 900), 0.0)
	var fourth := g.howl(Vector2.ZERO, Vector2.ZERO, 0.0)
	var ok := bool(first["ok"]) and not bool(second["ok"]) and not bool(third["ok"]) and bool(fourth["ok"])
	ok = ok and g.cooldown_for(1.0) < g.cooldown_for(0.0)
	return _ok(ok, "a howl has a cooldown, shorter for a bonded companion")


static func _test_a_friends_howl_costs_us_nothing() -> int:
	var g := _guide()
	g.howl(Vector2.ZERO, Vector2.ZERO, 0.0)
	var heard := g.hear(Vector2(100, 0), 0.5)
	return _ok(bool(heard["ok"]) and not g.can_howl(), "hearing a friend's howl works during our own cooldown and does not reset it")


static func _test_hints_fire_once() -> int:
	var g := EchoGuide.new([EAST], Vector2(0, -400), Vector2(0, -300), CFG)
	var a := g.howl(Vector2.ZERO, Vector2.ZERO, 0.0)
	g.update(10.0, Vector2(0, 900), 0.0)
	var b := g.howl(Vector2.ZERO, Vector2.ZERO, 0.0)
	var ok: bool = (a["events"] as Array).has("first_echo") and (a["events"] as Array).has("wrong") \
		and not (b["events"] as Array).has("first_echo") and not (b["events"] as Array).has("wrong")
	var quiet := EchoGuide.new([EAST], Vector2(0, -2000), Vector2(0, -1900), CFG)
	var s := quiet.howl(Vector2(-1500, 0), Vector2(-1500, 0), 0.0)
	return _ok(ok and (s["events"] as Array).has("silence"), "the first echo, the first wrong answer and silence are each told once")


static func _test_cave_reveals_on_walking_up_and_stays() -> int:
	var g := _guide()
	var far := g.update(0.1, Vector2(0, 100), 0.0)
	var near := g.update(0.1, Vector2(0, -450), 0.0)
	var later := g.update(0.1, Vector2(0, 100), 0.0)
	var ok: bool = not (far["events"] as Array).has("reveal") and (near["events"] as Array).has("reveal") and g.is_revealed() \
		and not (later["events"] as Array).has("reveal")
	return _ok(ok, "walking up to the cave opens it, once, and it stays open")


static func _test_companion_notices_the_cave_by_bond() -> int:
	var fresh := _guide()
	var bonded := _guide()
	var p := Vector2(0, -250)   # 350 from the mouth: outside a fresh notice (300), inside a bonded one (600)
	var f := fresh.update(0.1, p, 0.0)
	var b := bonded.update(0.1, p, 1.0)
	return _ok(not bool(f["point"]) and bool(b["point"]) and (b["events"] as Array).has("notice"),
		"a bonded companion notices the cave from further off than a fresh one")


static func _test_noticing_never_reveals_or_resets() -> int:
	var g := _guide()
	var p := Vector2(0, -150)   # 450 from the mouth, 250 outside the reveal edge
	var pointed := 0
	var t := 0.0
	var revealed := false
	while t < 30.0:
		var r := g.update(0.1, p, 1.0)
		if bool(r["point"]):
			pointed += 1
		revealed = revealed or (r["events"] as Array).has("reveal")
		t += 0.1
	# it points for 2.0 s, rests 4.0 s (bonded), points again: several windows in 30 s, never the reveal
	return _ok(pointed > 40 and pointed < 200 and not revealed, "it points in bursts with rests between, and a point alone reveals nothing")
