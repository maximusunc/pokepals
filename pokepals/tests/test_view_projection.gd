class_name TestViewProjection
## Pure tests for the perspective camera (ViewProjection) and how it moves (ViewRig): the focus draws at native
## size, projecting then unprojecting returns the same ground point at any heading, the sky is sky, farther is
## smaller and higher up the screen, the heading turns the world, and the rig swings behind you, doesn't flip
## when you step back, and settles while you linger.

static func run_all() -> int:
	var fails := 0
	print("TestViewProjection")
	fails += _test_focus_is_native()
	fails += _test_round_trip()
	fails += _test_sky_is_sky()
	fails += _test_depth_order()
	fails += _test_heading_turns_the_world()
	fails += _test_pitch_raises_horizon()
	fails += _test_visible_bounds()
	fails += _test_rig_swings_behind()
	fails += _test_rig_steps_back_without_flipping()
	fails += _test_rig_sideways_is_gentle()
	fails += _test_rig_lingers()
	return fails


static func _check(name: String, ok: bool) -> int:
	print("  %s  %s" % [("PASS" if ok else "FAIL"), name])
	return 0 if ok else 1


static func _cam(yaw := 0.0, pitch_deg := 0.0) -> ViewProjection:
	var v := ViewProjection.new().configure({ "height": 53.0, "back": 220.0, "pitch_deg": pitch_deg, "shift": 52.0, "far": 1400.0 })
	v.center = Vector2(500, 300)
	v.yaw = yaw
	return v


static func _test_focus_is_native() -> int:
	var v := _cam(0.7, 12.0)
	var p := v.project(v.center)
	var ok := is_equal_approx(p.z, 1.0) and absf(p.x) < 0.001
	# ...and a sideways step at the focus is a step of the same size on screen
	var q := v.project(v.center + v.right() * 10.0)
	ok = ok and absf(q.x - 10.0) < 0.01
	return _check("the focus draws at native size, centred", ok)


static func _test_round_trip() -> int:
	var ok := true
	for yaw in [0.0, 0.9, -2.4, PI]:
		for pitch in [0.0, 15.0]:
			var v := _cam(yaw, pitch)
			for d in [Vector2(0, 0), Vector2(40, -300), Vector2(-120, -900), Vector2(10, 60)]:
				var w: Vector2 = v.center + d.rotated(yaw)
				var s := v.project(w)
				var back: Variant = v.unproject(Vector2(s.x, s.y))
				if back == null or (back as Vector2).distance_to(w) > 0.01:
					ok = false
	return _check("projecting then unprojecting returns the same ground point, at any heading and tilt", ok)


static func _test_sky_is_sky() -> int:
	var v := _cam(0.3)
	var above: Variant = v.unproject(Vector2(0, v.horizon_y() - 5.0))
	var below: Variant = v.unproject(Vector2(0, v.horizon_y() + 5.0))
	return _check("above the horizon is sky, just below it is far ground", above == null and below != null and v.ahead_of_focus(below) > 2000.0)


static func _test_depth_order() -> int:
	var v := _cam()
	var near := v.project(v.center + Vector2(0, -100))
	var far := v.project(v.center + Vector2(0, -600))
	return _check("farther is smaller and higher up the screen", far.z < near.z and far.y < near.y and near.z < 1.0)


static func _test_heading_turns_the_world() -> int:
	# Facing east, a point east of you is straight ahead (centred, above you on screen); one north is to your left.
	var v := _cam(PI / 2.0)
	var east := v.project(v.center + Vector2(300, 0))
	var north := v.project(v.center + Vector2(0, -50))
	var me := v.project(v.center)
	return _check("facing east, east is ahead and north is to the left", absf(east.x) < 0.01 and east.y < me.y and north.x < -10.0)


static func _test_pitch_raises_horizon() -> int:
	return _check("tilting down raises the horizon", _cam(0.0, 10.0).horizon_y() < _cam(0.0, 0.0).horizon_y())


static func _test_visible_bounds() -> int:
	var v := _cam(0.0)
	var r := v.visible_bounds(Vector2(640, 360))
	var ok := r.has_point(v.center) and r.has_point(v.center + Vector2(0, -1300)) and not r.has_point(v.center + Vector2(0, -2000))
	var turned := _cam(PI / 2.0).visible_bounds(Vector2(640, 360))
	ok = ok and turned.has_point(v.center + Vector2(1300, 0)) and not turned.has_point(v.center + Vector2(-600, 0))
	return _check("the visible ground runs ahead to the draw distance, and turns with the heading", ok)


static func _rig() -> ViewRig:
	return ViewRig.new().configure({})


static func _run(rig: ViewRig, vel: Vector2, secs: float) -> void:
	var t := 0.0
	while t < secs:
		rig.step(vel, 1.0 / 60.0)
		t += 1.0 / 60.0


static func _test_rig_swings_behind() -> int:
	var rig := _rig()
	_run(rig, Vector2(90, -90), 3.0)  # walking north-east, diagonally across the view
	return _check("walking a new way, the camera comes round behind you", absf(angle_difference(rig.yaw, PI / 4.0)) < deg_to_rad(5.0))


static func _test_rig_steps_back_without_flipping() -> int:
	var rig := _rig()
	_run(rig, Vector2(0, 90), 3.0)  # walking south, straight back toward the camera
	return _check("stepping back toward the camera doesn't flip it round", absf(rig.yaw) < 0.001)


static func _test_rig_sideways_is_gentle() -> int:
	var a := _rig()
	_run(a, Vector2(90, 0).rotated(0.0), 0.5)  # across the screen
	var b := _rig()
	_run(b, Vector2(90, 0).rotated(-PI / 4.0) , 0.5)  # 45 degrees: diagonal ahead
	var sideways := absf(a.yaw) / (PI / 2.0)
	var diagonal := absf(b.yaw) / (PI / 4.0)
	return _check("walking straight across turns it more gently than walking ahead (%.2f vs %.2f of the way)" % [sideways, diagonal], sideways < diagonal and sideways > 0.0)


static func _test_rig_lingers() -> int:
	var rig := _rig()
	_run(rig, Vector2.ZERO, 1.0)
	var early := rig.linger
	_run(rig, Vector2.ZERO, 5.0)
	var settled := rig.linger
	_run(rig, Vector2(0, -90), 0.5)
	return _check("standing a while settles the camera, walking lifts it again", early == 0.0 and settled == 1.0 and rig.linger < 0.1)
