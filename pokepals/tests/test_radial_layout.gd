class_name TestRadialLayout
## Tests for the companion radial's two-arc layout (CompanionRadial.arc_layout): actions on the inner
## arc, shapes on the outer one. Pinned: no two buttons (or a button and the chip) ever come within
## BUTTON_GAP of each other, however many there are; the shapes sit further out than the actions; and
## every button fans up-and-left of the chip, never below or right of it.

const ORIGIN := Vector2(700, 320)
const CHIP := Rect2(Vector2(650, 300), Vector2(100, 40))


static func run_all() -> int:
	var fails := 0
	print("TestRadialLayout")
	fails += _test_the_usual_set_never_touches()
	fails += _test_many_long_labels_still_never_touch()
	fails += _test_shapes_sit_outside_the_actions()
	fails += _test_everything_fans_up_and_left()
	fails += _test_a_single_ring_works()
	return fails


static func _ok(cond: bool, label: String) -> int:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	return 0 if cond else 1


static func _sizes(n: int, w := 54.0) -> Array:
	var out: Array = []
	for i in n:
		out.append(Vector2(w, 30))
	return out


static func _rects(sizes: Array, placed: Array) -> Array:
	var out: Array = []
	for r in sizes.size():
		for i in (sizes[r] as Array).size():
			out.append(Rect2(placed[r][i], sizes[r][i]))
	return out


static func _all_clear(rects: Array) -> bool:
	var everything: Array = rects + [CHIP]
	for i in everything.size():
		for j in range(i + 1, everything.size()):
			if (everything[i] as Rect2).grow(CompanionRadial.BUTTON_GAP - 0.5).intersects(everything[j]):
				return false
	return true


static func _test_the_usual_set_never_touches() -> int:
	var sizes := [_sizes(3), _sizes(5)]
	return _ok(_all_clear(_rects(sizes, CompanionRadial.arc_layout(ORIGIN, sizes, CHIP))), "Pet/Call/Go look + five shapes: nothing touches")


static func _test_many_long_labels_still_never_touch() -> int:
	var sizes := [_sizes(4, 90.0), _sizes(10, 90.0)]
	return _ok(_all_clear(_rects(sizes, CompanionRadial.arc_layout(ORIGIN, sizes, CHIP))), "fourteen wide buttons: the arcs grow rather than overlap")


static func _test_shapes_sit_outside_the_actions() -> int:
	var sizes := [_sizes(3), _sizes(5)]
	var placed := CompanionRadial.arc_layout(ORIGIN, sizes, CHIP)
	var dist := func(p: Vector2) -> float: return (p + Vector2(27, 15) - ORIGIN).length()
	var inner_max := 0.0
	for p in placed[0]:
		inner_max = maxf(inner_max, dist.call(p))
	var outer_min := INF
	for p in placed[1]:
		outer_min = minf(outer_min, dist.call(p))
	return _ok(outer_min > inner_max, "the shapes ring sits outside the actions ring")


static func _test_everything_fans_up_and_left() -> int:
	var sizes := [_sizes(3), _sizes(5)]
	var ok := true
	for rc in _rects(sizes, CompanionRadial.arc_layout(ORIGIN, sizes, CHIP)):
		var c: Vector2 = (rc as Rect2).get_center()
		if c.x > ORIGIN.x + 30.0 or c.y > ORIGIN.y + 1.0:
			ok = false
	return _ok(ok, "every button fans up-and-left of the chip")


static func _test_a_single_ring_works() -> int:
	var sizes := [_sizes(5)]
	var placed := CompanionRadial.arc_layout(ORIGIN, sizes, CHIP)
	return _ok(placed.size() == 1 and (placed[0] as Array).size() == 5 and _all_clear(_rects(sizes, placed)), "a single ring (no actions, only shapes) lays out cleanly")
