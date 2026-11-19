class_name TestAlignGate
## Pure tests for Farmeadow's lining-up secret (AlignGate) and the view hold it leans on (ViewRig.hold_linger):
## walking past never sets it off; standing on the spot facing the right way captures the view; it needs the view
## lined up and held for the whole hold; turning away or moving lets go; the companion points from afar and sits
## on the spot once per approach; and a held view doesn't settle lower.

const DT := 1.0 / 60.0


static func run_all() -> int:
	var fails := 0
	print("TestAlignGate")
	fails += _test_walking_past()
	fails += _test_capture_needs_facing()
	fails += _test_hold_completes_once()
	fails += _test_moving_off_lets_go()
	fails += _test_companion_points_then_sits()
	fails += _test_held_view_doesnt_linger()
	return fails


static func _check(name: String, ok: bool) -> int:
	print("  %s  %s" % [("PASS" if ok else "FAIL"), name])
	return 0 if ok else 1


static func _gate() -> AlignGate:
	return AlignGate.new({ "spot": [100, 100], "facing_deg": 180.0, "hold_seconds": 2.0 })


static func _run(g: AlignGate, secs: float, pos: Vector2, speed: float, center: Vector2, yaw: float) -> Dictionary:
	var out := {}
	var completed := 0
	var t := 0.0
	while t < secs:
		out = g.update(DT, pos, speed, yaw, center, yaw, 0.5)
		if out["completed"]:
			completed += 1
		t += DT
	out["times"] = completed
	return out


static func _test_walking_past() -> int:
	var g := _gate()
	var out := _run(g, 3.0, Vector2(100, 100), 90.0, Vector2(100, 100), PI)
	return _check("walking across the spot (even facing south) never captures or completes it", not out["capture"] and out["times"] == 0)


static func _test_capture_needs_facing() -> int:
	var g := _gate()
	var north := g.update(DT, Vector2(104, 98), 0.0, 0.0, Vector2(104, 98), 0.0, 0.5)
	var south := g.update(DT, Vector2(104, 98), 0.0, PI + 0.3, Vector2(104, 98), PI + 0.3, 0.5)
	# the turn-around: you walked back down onto it (facing south) while the camera still looks north
	var back := g.update(DT, Vector2(104, 98), 0.0, PI, Vector2(104, 98), 0.0, 0.5)
	return _check("standing on the spot captures the view when YOU face (near enough) south, whichever way the camera looks", not north["capture"] and south["capture"] and not south["aligned"] and back["capture"] and not back["aligned"])


static func _test_hold_completes_once() -> int:
	var g := _gate()
	var early := _run(g, 1.5, Vector2(100, 100), 0.0, Vector2(100, 100), PI)
	var late := _run(g, 1.0, Vector2(100, 100), 0.0, Vector2(100, 100), PI)
	var after := _run(g, 2.0, Vector2(100, 100), 0.0, Vector2(100, 100), PI)
	return _check("lined up, it completes after the hold (not before), and only once", early["times"] == 0 and early["aligned"] and late["times"] == 1 and after["times"] == 0 and g.done)


static func _test_moving_off_lets_go() -> int:
	var g := _gate()
	_run(g, 1.5, Vector2(100, 100), 0.0, Vector2(100, 100), PI)
	_run(g, 0.1, Vector2(100, 100), 0.0, Vector2(100, 100), PI + 0.2)   # turned a little away
	var out := _run(g, 1.5, Vector2(100, 100), 0.0, Vector2(100, 100), PI)
	return _check("turning away lets the hold go back to zero", out["times"] == 0 and not g.done and out["progress"] < 0.8)


static func _test_companion_points_then_sits() -> int:
	var g := _gate()
	var pointed := false
	var visits := 0
	# walk in from 600 away to beside the spot, then away and back again
	for i in 600:
		var p := Vector2(100, 700 - i)
		var out := g.update(DT, p, 90.0, 0.0, p, 0.0, 1.0)
		pointed = pointed or out["point"]
		visits += 1 if out["visit"] else 0
	for i in 700:
		var out := g.update(DT, Vector2(100, 100 + i), 90.0, 0.0, Vector2(100, 100 + i), 0.0, 1.0)
		visits += 1 if out["visit"] else 0
	for i in 600:
		var out := g.update(DT, Vector2(100, 800 - i), 90.0, 0.0, Vector2(100, 800 - i), 0.0, 1.0)
		visits += 1 if out["visit"] else 0
	return _check("the companion points at it from afar, and sits on the spot once per approach (%d)" % visits, pointed and visits == 2)


static func _test_held_view_doesnt_linger() -> int:
	var rig := ViewRig.new().configure({})
	rig.hold_linger = true
	var t := 0.0
	while t < 6.0:
		rig.step(Vector2.ZERO, DT)
		t += DT
	var held := rig.linger
	rig.hold_linger = false
	t = 0.0
	while t < 6.0:
		rig.step(Vector2.ZERO, DT)
		t += DT
	return _check("a held view doesn't settle lower; let go, it does", held == 0.0 and rig.linger == 1.0)
