class_name TestListenGuide
## Tests for ListenGuide, the pure logic of Steamhollow's faint bell: a companion that hears what you
## cannot, but only when it is calm and settled beside you, and whose range, speed and clarity grow with
## the bond. No nodes: the tests feed it positions and speeds exactly as the ListenDirector does.

const BELL := Vector2(500, 0)
const CFG := {
	"hear_range_low": 300.0, "hear_range_high": 700.0, "still_speed": 30.0, "companion_still_speed": 26.0,
	"companion_radius": 90.0, "settle_low": 2.0, "settle_high": 1.0, "lose_seconds": 2.0,
	"tell_cap_low": 0.7, "tell_cap_high": 1.0, "aim_error_low": 0.6, "aim_error_high": 0.2, "aim_residual": 0.1,
	"wobble_rate": 0.7, "near_radius": 200.0, "near_settle_factor": 0.5, "visible_radius": 120.0,
	"found_radius": 60.0, "aim_distance": 100.0,
}


static func run_all() -> int:
	var fails := 0
	print("TestListenGuide")
	fails += _test_hears_nothing_while_you_move()
	fails += _test_hears_when_settled_in_range()
	fails += _test_needs_the_companion_close_and_calm()
	fails += _test_out_of_range_is_silent()
	fails += _test_range_grows_with_bond()
	fails += _test_a_bonded_companion_hears_sooner()
	fails += _test_a_fresh_companion_tells_less()
	fails += _test_walking_on_loses_the_sound_gradually()
	fails += _test_it_comes_back_when_you_stop_again()
	fails += _test_the_aim_settles_toward_the_bell()
	fails += _test_near_the_bell_is_sharper_and_quicker()
	fails += _test_the_bell_shows_only_when_close()
	fails += _test_events_fire_once()
	fails += _test_calm_is_you_still_with_it_close()
	fails += _test_data_overrides_defaults()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _guide() -> ListenGuide:
	return ListenGuide.new(BELL, CFG)


## Stand still together (player at `at`, companion 40 px beside) for `secs` in 0.1 s steps. Returns the last
## result; events are appended to `log`.
static func _settle(g: ListenGuide, at: Vector2, secs: float, bond: float, log: Array = []) -> Dictionary:
	var r := {}
	var t := 0.0
	while t < secs:
		r = g.update(0.1, at, 0.0, at + Vector2(-40, 0), 0.0, bond)
		log.append_array(r["events"])
		t += 0.1
	return r


## Walk (player speed 118) for `secs` with the companion trailing.
static func _walk(g: ListenGuide, from: Vector2, secs: float, bond: float, log: Array = []) -> Dictionary:
	var r := {}
	var t := 0.0
	var p := from
	while t < secs:
		p += Vector2(11.8, 0)
		r = g.update(0.1, p, 118.0, p - Vector2(50, 0), 100.0, bond)
		log.append_array(r["events"])
		t += 0.1
	return r


static func _test_hears_nothing_while_you_move() -> int:
	var r := _walk(_guide(), Vector2(0, 0), 4.0, 0.5)
	return _ok(float(r["tell"]) == 0.0 and not bool(r["listening"]), "walking, it hears nothing")


static func _test_hears_when_settled_in_range() -> int:
	var r := _settle(_guide(), Vector2(200, 0), 4.0, 0.5)
	return _ok(float(r["tell"]) > 0.6 and bool(r["listening"]), "still beside you, in range, it hears (%.2f)" % float(r["tell"]))


static func _test_needs_the_companion_close_and_calm() -> int:
	var fails := 0
	var g := _guide()
	var r := {}
	for _i in 50:
		r = g.update(0.1, Vector2(200, 0), 0.0, Vector2(200, 0) + Vector2(-200, 0), 0.0, 0.5)   # 200 px away
	fails += _ok(float(r["tell"]) == 0.0, "a companion far from you does not hear")
	g = _guide()
	for _i in 50:
		r = g.update(0.1, Vector2(200, 0), 0.0, Vector2(160, 0), 90.0, 0.5)   # close but trotting about
	fails += _ok(float(r["tell"]) == 0.0, "a companion on the move does not hear")
	g = _guide()
	for _i in 50:
		r = g.update(0.1, Vector2(200, 0), 20.0, Vector2(160, 0), 5.0, 0.5)   # you creeping slowly counts as still
	fails += _ok(float(r["tell"]) > 0.5, "moving slowly still counts as settled")
	return fails


static func _test_out_of_range_is_silent() -> int:
	var r := _settle(_guide(), Vector2(-400, 0), 6.0, 0.0)   # 900 px from the bell
	return _ok(float(r["tell"]) == 0.0 and not bool(r["listening"]), "too far from the bell, it hears nothing")


static func _test_range_grows_with_bond() -> int:
	var g := _guide()
	var fails := 0
	fails += _ok(is_equal_approx(g.hear_range(0.0), 300.0) and is_equal_approx(g.hear_range(1.0), 700.0), "hearing range runs from low to high with the bond")
	var at := BELL + Vector2(-500, 0)   # 500 px out: beyond a fresh companion, within a bonded one
	var fresh := _settle(_guide(), at, 5.0, 0.0)
	var bonded := _settle(_guide(), at, 5.0, 1.0)
	fails += _ok(float(fresh["tell"]) == 0.0 and float(bonded["tell"]) > 0.5, "at 500 px only the bonded companion hears")
	return fails


static func _test_a_bonded_companion_hears_sooner() -> int:
	var at := BELL + Vector2(-250, 0)
	var fresh := _settle(_guide(), at, 1.0, 0.0)
	var bonded := _settle(_guide(), at, 1.0, 1.0)
	return _ok(float(bonded["tell"]) > float(fresh["tell"]) + 0.3, "after one second the bonded companion is further along (%.2f vs %.2f)" % [float(bonded["tell"]), float(fresh["tell"])])


static func _test_a_fresh_companion_tells_less() -> int:
	var at := BELL + Vector2(-290, 0)
	var fresh := _settle(_guide(), at, 6.0, 0.0)
	var bonded := _settle(_guide(), at, 6.0, 1.0)
	return _ok(float(fresh["tell"]) <= 0.7 + 0.001 and float(bonded["tell"]) > 0.95, "a fresh companion's tell is capped lower (%.2f vs %.2f)" % [float(fresh["tell"]), float(bonded["tell"])])


static func _test_walking_on_loses_the_sound_gradually() -> int:
	var fails := 0
	var g := _guide()
	var log: Array = []
	_settle(g, Vector2(100, 0), 4.0, 0.5, log)
	fails += _ok(log.has("hear"), "it heard")
	var r := _walk(g, Vector2(100, 0), 0.5, 0.5, log)
	fails += _ok(float(r["tell"]) > 0.3, "half a second into walking the sound is still half there (%.2f)" % float(r["tell"]))
	r = _walk(g, Vector2(150, 0), 3.0, 0.5, log)
	fails += _ok(float(r["tell"]) == 0.0 and log.has("lost"), "walk on and it is lost")
	return fails


static func _test_it_comes_back_when_you_stop_again() -> int:
	var g := _guide()
	_settle(g, Vector2(100, 0), 4.0, 0.5)
	_walk(g, Vector2(100, 0), 4.0, 0.5)
	var r := _settle(g, Vector2(200, 0), 4.0, 0.5)
	return _ok(float(r["tell"]) > 0.6, "stop again and it listens again")


static func _test_the_aim_settles_toward_the_bell() -> int:
	var at := BELL + Vector2(-300, 0)
	var comp := at + Vector2(-40, 0)
	var true_dir := (BELL - comp).normalized()
	# the worst wobble over a stretch, early and late in the listening
	var g := _guide()
	var early_worst := 0.0
	for _i in 8:
		var r := g.update(0.1, at, 0.0, comp, 0.0, 0.0)
		early_worst = maxf(early_worst, absf(true_dir.angle_to(((r["target"] as Vector2) - comp).normalized())))
	var late_worst := 0.0
	for _i in 80:
		var r := g.update(0.1, at, 0.0, comp, 0.0, 0.0)
		if _i > 60:
			late_worst = maxf(late_worst, absf(true_dir.angle_to(((r["target"] as Vector2) - comp).normalized())))
	var fresh_late := late_worst
	var gb := _guide()
	var bonded_late := 0.0
	for _i in 80:
		var r := gb.update(0.1, at, 0.0, comp, 0.0, 1.0)
		if _i > 60:
			bonded_late = maxf(bonded_late, absf(true_dir.angle_to(((r["target"] as Vector2) - comp).normalized())))
	var fails := 0
	fails += _ok(early_worst > fresh_late, "the aim narrows as it listens (%.2f then %.2f rad)" % [early_worst, fresh_late])
	fails += _ok(bonded_late < fresh_late or bonded_late < 0.05, "a bonded companion's aim is truer (%.3f vs %.3f rad)" % [bonded_late, fresh_late])
	return fails


static func _test_near_the_bell_is_sharper_and_quicker() -> int:
	var fails := 0
	var far := _guide()
	var near := _guide()
	var rf := _settle(far, BELL + Vector2(-290, 0), 0.9, 0.0)
	var rn := _settle(near, BELL + Vector2(-60, 0), 0.9, 0.0)
	fails += _ok(float(rn["tell"]) > float(rf["tell"]), "right by the bell it hears sooner (%.2f vs %.2f)" % [float(rn["tell"]), float(rf["tell"])])
	var comp := BELL + Vector2(-100, 0)
	var g := _guide()
	var worst := 0.0
	for _i in 60:
		var r := g.update(0.1, BELL + Vector2(-60, 0), 0.0, comp, 0.0, 0.0)
		if _i > 30:   # once it has had a moment to listen
			worst = maxf(worst, absf((BELL - comp).normalized().angle_to(((r["target"] as Vector2) - comp).normalized())))
	fails += _ok(worst < 0.06, "by the bell its aim is true (%.3f rad)" % worst)
	fails += _ok(float(rn["near"]) > 0.6 and float(rf["near"]) == 0.0, "near_amount reads closeness")
	return fails


static func _test_the_bell_shows_only_when_close() -> int:
	var g := _guide()
	return _ok(g.visibility(300.0) == 0.0 and g.visibility(120.0) == 0.0 and g.visibility(60.0) == 1.0 and g.visibility(90.0) > 0.0 and g.visibility(90.0) < 1.0,
		"the bell shows through the fog only up close")


static func _test_events_fire_once() -> int:
	var fails := 0
	var g := _guide()
	var log: Array = []
	_settle(g, Vector2(100, 0), 4.0, 0.5, log)
	_settle(g, Vector2(100, 0), 4.0, 0.5, log)
	fails += _ok(log.count("hear") == 1, "'hear' fires once however long it listens")
	_walk(g, Vector2(100, 0), 4.0, 0.5, log)
	fails += _ok(log.count("lost") == 1, "'lost' fires once")
	var g2 := _guide()
	var log2: Array = []
	_walk(g2, Vector2(-100, 0), 5.0, 0.5, log2)   # walks right up past the bell
	fails += _ok(log2.count("near") == 1 and log2.count("close") == 1, "'near' and 'close' fire once as you approach")
	return fails


static func _test_calm_is_you_still_with_it_close() -> int:
	var fails := 0
	var g := _guide()
	var at := Vector2(200, 0)
	var r := g.update(0.1, at, 0.0, at + Vector2(-40, 0), 80.0, 0.5)   # it is close but trotting about
	fails += _ok(bool(r["calm"]) and not bool(r["listening"]), "you still, it close but moving: calm, not yet listening")
	r = g.update(0.1, at, 90.0, at + Vector2(-40, 0), 0.0, 0.5)
	fails += _ok(not bool(r["calm"]), "walking is never calm")
	r = g.update(0.1, at, 0.0, at + Vector2(-300, 0), 0.0, 0.5)
	fails += _ok(not bool(r["calm"]), "a companion far off is not calm beside you")
	r = g.update(0.1, Vector2(-800, 0), 0.0, Vector2(-840, 0), 0.0, 0.5)
	fails += _ok(not bool(r["calm"]), "out of range is not calm")
	return fails


static func _test_data_overrides_defaults() -> int:
	var g := ListenGuide.new(BELL, { "hear_range_low": 111.0, "hear_range_high": 222.0, "bogus": 5 })
	return _ok(is_equal_approx(g.hear_range(0.0), 111.0) and is_equal_approx(g.hear_range(1.0), 222.0), "the reveal block overrides the defaults")
