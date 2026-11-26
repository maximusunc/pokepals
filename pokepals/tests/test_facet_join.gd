class_name TestFacetJoin
## Pure tests for Glintwold's Unfinished (FacetJoin): from afar it hangs loosely apart and nothing moves; near,
## the shards slide with where each half's viewer stands (near and far ones opposite ways); the magnet puts a
## half exactly home inside tolerance; both halves held for the hold close it, once; leaving lets go; friends
## serve the marks by who is nearest, never one body for both; and the companion's Go look and glance scale
## with bond.

const DT := 1.0 / 30.0


static func run_all() -> int:
	var fails := 0
	print("TestFacetJoin")
	fails += _test_far_away_rests()
	fails += _test_slides_with_viewer()
	fails += _test_magnet()
	fails += _test_hold_completes_once()
	fails += _test_leaving_lets_go()
	fails += _test_nearest_actor_serves()
	fails += _test_go_look_by_bond()
	fails += _test_glance_by_bond()
	fails += _test_settle_and_floor()
	return fails


static func _check(name: String, ok: bool) -> int:
	print("  %s  %s" % [("PASS" if ok else "FAIL"), name])
	return 0 if ok else 1


static func _block() -> Dictionary:
	return {
		"position": [0, 0], "marks": { "you": [0, 170], "companion": [-160, -60] },
		"reach": 320, "tolerance": 16, "hold_s": 2.0, "floor_radius": 230,
	}


static func _shards() -> Array:
	return [
		{ "home": [-20, -80], "depth": 0.9, "owner": "you" },
		{ "home": [20, -80], "depth": -0.8, "owner": "you" },
		{ "home": [0, -40], "depth": 0.3, "owner": "you" },
		{ "home": [-20, -40], "depth": 0.7, "owner": "companion" },
		{ "home": [20, -40], "depth": -0.6, "owner": "companion" },
	]


static func _join() -> FacetJoin:
	return FacetJoin.new(_block(), _shards())


static func _test_far_away_rests() -> int:
	var j := _join()
	var a: Array = j.update(DT, [Vector2(900, 0), Vector2(920, 10)], 0.5)["offsets"]
	var b: Array = j.update(DT, [Vector2(-700, 600), Vector2(-690, 610)], 0.5)["offsets"]
	var same := true
	var apart := true
	for i in a.size():
		same = same and (a[i] as Vector2).is_equal_approx(b[i])
		apart = apart and is_equal_approx((a[i] as Vector2).length(), j.cfg("spread"))
	return _check("from afar it hangs apart at its resting spread, and nothing moves as you walk", same and apart)


static func _test_slides_with_viewer() -> int:
	var j := _join()
	var comp := Vector2(400, 400)   # out of the way: well off the companion's mark
	var left: Array = j.update(DT, [Vector2(-60, 170), comp], 0.5)["offsets"]
	var right: Array = j.update(DT, [Vector2(60, 170), comp], 0.5)["offsets"]
	# step right: the near shard (depth 0.9) slides left, the far one (-0.8) right, compared to stepping left
	var near_moves := (right[0] as Vector2).x < (left[0] as Vector2).x
	var far_moves := (right[1] as Vector2).x > (left[1] as Vector2).x
	var big := (left[0] as Vector2).length() > 5.0
	var capped := true
	for o in right:
		capped = capped and (o as Vector2).length() <= j.cfg("max_offset") + 0.001
	var a_little: Array = j.update(DT, [Vector2(40, 170), comp], 0.5)["offsets"]
	var a_lot: Array = j.update(DT, [Vector2(110, 170), comp], 0.5)["offsets"]
	var grows := (a_lot[0] as Vector2).length() > (a_little[0] as Vector2).length()
	return _check("near and far shards slide opposite ways as you step, more the further off the mark, capped",
		near_moves and far_moves and big and capped and grows)


static func _test_magnet() -> int:
	var j := _join()
	var r := j.update(DT, [Vector2(10, 178), Vector2(400, 400)], 0.5)
	var off: Array = r["offsets"]
	var home_zero := (off[0] as Vector2) == Vector2.ZERO and (off[1] as Vector2) == Vector2.ZERO and (off[2] as Vector2) == Vector2.ZERO
	var other_open := (off[3] as Vector2).length() > 1.0
	var just_out := j.update(DT, [Vector2(0, 170 + 24), Vector2(400, 400)], 0.5)
	return _check("inside tolerance your half is exactly home, the other still apart; just outside it is nearly home",
		home_zero and other_open and bool(r["home"]["you"]) and float(r["closeness"]["you"]) == 1.0
		and not bool(just_out["home"]["you"]) and float(just_out["closeness"]["you"]) > 0.8)


static func _test_hold_completes_once() -> int:
	var j := _join()
	var actors := [Vector2(4, 166), Vector2(-150, -58)]
	var completed := 0
	var events: Array = []
	var t := 0.0
	var early_done := false
	while t < 4.0:
		var r := j.update(DT, actors, 0.5)
		events.append_array(r["events"])
		if r["completed"]:
			completed += 1
		if t < 1.9 and j.done:
			early_done = true
		t += DT
	var whole := true
	for o in j.update(DT, [Vector2(900, 900), Vector2(900, 900)], 0.5)["offsets"]:
		whole = whole and (o as Vector2) == Vector2.ZERO
	return _check("both halves home and held for hold_s close it, once, and it stays whole",
		completed == 1 and not early_done and events.has("both") and events.has("complete") and whole)


static func _test_leaving_lets_go() -> int:
	var j := _join()
	var on := [Vector2(0, 170), Vector2(-160, -60)]
	var events: Array = []
	for _i in 45:   # 1.5 s
		events.append_array(j.update(DT, on, 0.5)["events"])
	var r := j.update(DT, [Vector2(0, 230), Vector2(-160, -60)], 0.5)
	events.append_array(r["events"])
	var reset := j.held == 0.0 and not j.done and float(r["hold"]) == 0.0
	for _i in 45:
		j.update(DT, on, 0.5)
	return _check("walking off a mark lets the hold go back to zero; it says one half is waiting; standing again starts over",
		reset and events.has("half") and not j.done)


static func _test_nearest_actor_serves() -> int:
	var j := _join()
	# you and your companion stand together well away; a friend on each mark closes it
	var actors := [Vector2(300, 300), Vector2(310, 300), Vector2(2, 171), Vector2(-158, -61)]
	var v := j.assign_viewers(actors)
	var ok := int(v["you"]) == 2 and int(v["companion"]) == 3
	# one body near both marks never serves both while another is there
	var two := [Vector2(-80, 60), Vector2(500, 500)]
	var w := j.assign_viewers(two)
	var distinct := int(w["you"]) != int(w["companion"])
	var one := j.assign_viewers([Vector2(0, 170)])
	var lone := int(one["you"]) == 0 and int(one["companion"]) == 0
	var t := 0.0
	while t < 2.5:
		j.update(DT, actors, 0.0)
		t += DT
	return _check("each mark is served by the actor nearest it (friends close it together), never one body for both",
		ok and distinct and lone and j.done)


static func _test_go_look_by_bond() -> int:
	var j := _join()
	var m: Vector2 = j.marks["companion"]
	var fresh := j.go_look_target(0.0, 1.0).distance_to(m)
	var deep := j.go_look_target(1.0, 1.0).distance_to(m)
	var far_out := j.go_look_target(0.0, PI).distance_to(j.center) <= j.cfg("floor_radius")
	return _check("Go look lands well off the mark fresh (%.0f px) and inside tolerance when deep (%.0f px), on the floor" % [fresh, deep],
		fresh > 40.0 and deep < j.cfg("tolerance") and far_out)


static func _test_glance_by_bond() -> int:
	var fresh := _join()
	var deep := _join()
	var at := [Vector2(0, 400), Vector2(10, 400)]   # 400 px from the stone
	var gf := 0
	var gd := 0
	for _i in 900:   # 30 s
		if fresh.update(DT, at, 0.0)["glance"]:
			gf += 1
		if deep.update(DT, at, 1.0)["glance"]:
			gd += 1
	var close := _join()
	var gc := 0
	for _i in 900:
		if close.update(DT, [Vector2(0, 200), Vector2(10, 200)], 0.0)["glance"]:
			gc += 1
	var home := _join()
	var gh := 0
	for _i in 300:
		if home.update(DT, [Vector2(0, 200), Vector2(-160, -60)], 1.0)["glance"]:
			gh += 1
	return _check("it glances at its mark from further off and more often the deeper the bond, never once its half is home (%d/%d/%d/%d)" % [gf, gd, gc, gh],
		gf == 0 and gd >= 4 and gc >= 2 and gc < gd and gh == 0)


static func _test_settle_and_floor() -> int:
	var j := _join()
	var m: Vector2 = j.marks["companion"]
	return _check("a tap near the companion's mark settles onto it; elsewhere it stands where tapped; the floor is the floor_radius",
		j.settle_target(m + Vector2(20, 10)) == m and j.settle_target(m + Vector2(60, 0)) == m + Vector2(60, 0)
		and j.on_floor(Vector2(0, 220)) and not j.on_floor(Vector2(0, 240)))
