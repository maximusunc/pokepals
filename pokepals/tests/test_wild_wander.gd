class_name TestWildWander
## Pure tests for the wild flock's milling-about logic (the first-meeting encounter). Seeded RNG,
## no nodes — documents the contract: pause, amble inside the anchor's disc, hurry away when
## examined, freeze for the ceremony, and never wedge forever on an unreachable target.

const DT := 0.1


static func run_all() -> int:
	var fails := 0
	print("TestWildWander")
	fails += _test_starts_paused()
	fails += _test_amble_targets_stay_inside_the_disc()
	fails += _test_arrival_returns_to_pause()
	fails += _test_walk_away_leaves_the_threat()
	fails += _test_freeze_holds_still()
	fails += _test_unreachable_target_times_out()
	return fails


static func _check(name: String, ok: bool) -> int:
	print("  %s  %s" % [("PASS" if ok else "FAIL"), name])
	return 0 if ok else 1


static func _cfg() -> Dictionary:
	return {
		"amble_speed": 40.0,
		"away_speed": 90.0,
		"arrive_distance": 8.0,
		"pause": [1.0, 2.0],
		"away_distance": [150.0, 230.0],
	}


static func _make(seed_v: int) -> WildWander:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	return WildWander.new(_cfg(), rng)


## Tick until the wanderer leaves pause (or the tick budget runs out); returns the last decision.
static func _tick_until_moving(w: WildWander, pos: Vector2, anchor: Vector2, radius: float) -> Dictionary:
	var d: Dictionary = { "state": "pause", "target": pos, "speed": 0.0 }
	for i in 100:
		d = w.update(DT, pos, anchor, radius)
		if float(d["speed"]) > 0.0:
			return d
	return d


static func _test_starts_paused() -> int:
	var w := _make(1)
	var d := w.update(0.0001, Vector2.ZERO, Vector2.ZERO, 100.0)
	return _check("begins standing about (speed 0)", is_zero_approx(float(d["speed"])))


static func _test_amble_targets_stay_inside_the_disc() -> int:
	var anchor := Vector2(500, -200)
	var fails := 0
	for seed_v in [2, 3, 4, 5, 6]:
		var w := _make(seed_v)
		var d := _tick_until_moving(w, anchor + Vector2(10, 0), anchor, 120.0)
		var target: Vector2 = d["target"]
		if float(d["speed"]) <= 0.0 or anchor.distance_to(target) > 120.001:
			fails += 1
	return _check("every amble target lands inside the anchor's radius", fails == 0)


static func _test_arrival_returns_to_pause() -> int:
	var w := _make(7)
	var d := _tick_until_moving(w, Vector2.ZERO, Vector2.ZERO, 100.0)
	# Step the body straight at the target like the view would, until it reports arrival.
	var pos := Vector2.ZERO
	for i in 200:
		if float(d["speed"]) <= 0.0:
			break
		pos = pos.move_toward(d["target"], float(d["speed"]) * DT)
		d = w.update(DT, pos, Vector2.ZERO, 100.0)
	return _check("arriving at the target drops back to a pause", w.state() == WildWander.STATE_PAUSE)


static func _test_walk_away_leaves_the_threat() -> int:
	var w := _make(8)
	var pos := Vector2(30, 0)
	var threat := Vector2.ZERO
	w.walk_away(pos, threat)
	var d := w.update(DT, pos, Vector2.ZERO, 100.0)
	var target: Vector2 = d["target"]
	var fails := 0
	fails += _check("walking away moves at away_speed", is_equal_approx(float(d["speed"]), 90.0))
	fails += _check("the exit point is farther from the examiner than where it stood",
		threat.distance_to(target) > threat.distance_to(pos))
	var hop := pos.distance_to(target)
	fails += _check("the exit distance respects away_distance", hop >= 149.0 and hop <= 231.0)
	fails += _check("reads as leaving while under way", w.is_leaving())
	return fails


static func _test_freeze_holds_still() -> int:
	var w := _make(9)
	w.freeze()
	var still := true
	for i in 100:
		var d := w.update(DT, Vector2.ZERO, Vector2.ZERO, 100.0)
		still = still and is_zero_approx(float(d["speed"]))
	return _check("a frozen creature never moves again", still and w.state() == WildWander.STATE_STILL)


static func _test_unreachable_target_times_out() -> int:
	var w := _make(10)
	var d := _tick_until_moving(w, Vector2.ZERO, Vector2.ZERO, 100.0)
	# The body never moves (a wall the logic can't see): the travel budget must lapse to a pause.
	var gave_up := false
	for i in 400:
		d = w.update(DT, Vector2.ZERO, Vector2.ZERO, 100.0)
		if w.state() == WildWander.STATE_PAUSE:
			gave_up = true
			break
	return _check("a blocked walk gives up into a pause instead of wedging", gave_up)
