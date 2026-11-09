class_name TestFetchTrip
## Tests for FetchTrip, the pure logic of Thimblewick's lost thimble: a companion slipping through a gap in
## the fence that is too small for you, gone a few seconds, and back with a find that depends on the gap and
## on the bond (a pebble, then a button, then the thimble). No nodes: the "companion" is a point this test
## walks toward the target the trip names, exactly as the brain's GuideAction does in the game.

const MOUTH := Vector2(100, 100)
const INSIDE := Vector2(100, 70)
const CACHE := Vector2(140, 40)
const PLAYER := Vector2(60, 160)
const FINDS := [
	{ "item": "pebble", "min_bond": 0.0 },
	{ "item": "button", "min_bond": 0.3 },
	{ "item": "thimble", "min_bond": 0.55 },
]
const CFG := {
	"ask_range": 300.0, "species": ["rabbit"], "mouth_reach": 8.0, "go_speed": 100.0, "go_patience": 10.0, "go_run_distance": 240.0,
	"poke_seconds": 1.5, "squeeze_seconds": 0.5, "away_low": 8.0, "away_high": 4.0, "hurry_seconds": 1.0,
	"emerge_seconds": 0.5, "bring_speed": 120.0, "drop_distance": 30.0, "bring_patience": 20.0, "cooldown": 2.0,
	"pet_pause": 2.0, "warm": 0.05, "warm_decay": 0.5, "warm_min": 0.01,
	"notice_range_low": 150.0, "notice_range_high": 400.0, "notice_cooldown_low": 10.0, "notice_cooldown_high": 4.0,
	"notice_hold": 2.0, "rustle_every": 1.0,
}


static func run_all() -> int:
	var fails := 0
	print("TestFetchTrip")
	fails += _test_best_find_follows_the_bond()
	fails += _test_next_find_is_the_one_a_deeper_bond_brings()
	fails += _test_warmth_tapers_and_has_a_floor()
	fails += _test_away_shrinks_with_bond()
	fails += _test_nearest_gap_respects_range()
	fails += _test_a_rabbit_squeezes_through_and_brings_a_pebble()
	fails += _test_a_deep_bond_brings_the_thimble()
	fails += _test_the_middle_bond_brings_a_button()
	fails += _test_the_body_is_hidden_only_while_away()
	fails += _test_a_moment_of_missing_it()
	fails += _test_other_shapes_poke_and_give_up()
	fails += _test_a_call_in_go_calls_it_off()
	fails += _test_a_call_while_away_brings_it_back_early()
	fails += _test_a_pet_is_enjoyed_and_the_trip_carries_on()
	fails += _test_it_finds_you_wherever_you_wander()
	fails += _test_it_sets_the_find_down_if_it_cannot_reach_you()
	fails += _test_cooldown_between_trips()
	fails += _test_repeat_trips_warm_less()
	fails += _test_cannot_ask_while_busy()
	fails += _test_gives_up_the_way_after_patience()
	fails += _test_a_far_off_companion_is_given_time_to_arrive()
	fails += _test_notice_range_grows_with_bond()
	fails += _test_notice_holds_then_cools_down()
	fails += _test_no_notice_while_busy()
	fails += _test_data_overrides_defaults()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _trip() -> FetchTrip:
	return FetchTrip.new([{ "id": "g1", "mouth": MOUTH, "inside": INSIDE, "cache": CACHE, "finds": FINDS }], CFG)


## Step the trip `secs` seconds in 0.05 s steps with the companion walking where it is told (at the pace it is
## told; instantly placed where the trip controls the body). Returns the log { events, drop, pos, hidden_frames,
## carry_seen, max_hidden_run }. `player` is the player's position, `pending` the order in flight.
static func _drive(t: FetchTrip, pos: Vector2, player: Vector2, bond: float, species: String, secs: float, pending := "") -> Dictionary:
	var log := { "events": [], "drop": {}, "pos": pos, "hidden_frames": 0, "carry": [], "frames": 0 }
	var elapsed := 0.0
	var dt := 0.05
	while elapsed < secs:
		var r := t.update(dt, { "companion_pos": pos, "player_pos": player, "bond": bond, "species": species, "pending": pending })
		for e in r["events"]:
			(log["events"] as Array).append(e)
		if bool(r["control"]):
			pos = (r["body"] as Dictionary)["pos"]
			if bool((r["body"] as Dictionary)["hidden"]):
				log["hidden_frames"] += 1
		elif String(r["command"]) == "guide" and not bool(r["hold"]):
			var to: Vector2 = (r["target"] as Vector2) - pos
			var step := minf(to.length(), float(r["speed"]) * dt)
			if to.length() > 0.001:
				pos += to.normalized() * step
		if String(r["carry"]) != "" and not (log["carry"] as Array).has(r["carry"]):
			(log["carry"] as Array).append(r["carry"])
		if not (r["drop"] as Dictionary).is_empty():
			log["drop"] = r["drop"]
		log["frames"] += 1
		elapsed += dt
	log["pos"] = pos
	return log


static func _test_best_find_follows_the_bond() -> int:
	var fails := 0
	fails += _ok(String(FetchTrip.find_for(FINDS, 0.0)["item"]) == "pebble", "a new companion brings a pebble")
	fails += _ok(String(FetchTrip.find_for(FINDS, 0.29)["item"]) == "pebble", "just under the button's bond is still a pebble")
	fails += _ok(String(FetchTrip.find_for(FINDS, 0.3)["item"]) == "button", "at the button's bond: a button")
	fails += _ok(String(FetchTrip.find_for(FINDS, 0.54)["item"]) == "button", "just under the thimble's bond is a button")
	fails += _ok(String(FetchTrip.find_for(FINDS, 0.55)["item"]) == "thimble", "at the thimble's bond: the thimble")
	fails += _ok(String(FetchTrip.find_for(FINDS, 1.0)["item"]) == "thimble", "a full bond: still the thimble")
	fails += _ok(FetchTrip.find_for([], 0.5).is_empty(), "a gap with nothing behind it finds nothing")
	return fails


static func _test_next_find_is_the_one_a_deeper_bond_brings() -> int:
	var fails := 0
	fails += _ok(String(FetchTrip.next_find(FINDS, 0.0)["item"]) == "button", "from nothing, a button is the next find up")
	fails += _ok(String(FetchTrip.next_find(FINDS, 0.4)["item"]) == "thimble", "from a button, the thimble is next")
	fails += _ok(FetchTrip.next_find(FINDS, 0.9).is_empty(), "at the best find there is no next")
	return fails


static func _test_warmth_tapers_and_has_a_floor() -> int:
	var fails := 0
	fails += _ok(is_equal_approx(FetchTrip.warmth(0.05, 0.5, 0, 0.01), 0.05), "the first trip warms the full amount")
	fails += _ok(is_equal_approx(FetchTrip.warmth(0.05, 0.5, 1, 0.01), 0.025), "the second warms half")
	fails += _ok(is_equal_approx(FetchTrip.warmth(0.05, 0.5, 9, 0.01), 0.01), "it never warms less than the floor")
	return fails


static func _test_away_shrinks_with_bond() -> int:
	var t := _trip()
	return _ok(is_equal_approx(t.at_bond("away", 0.0), 8.0) and is_equal_approx(t.at_bond("away", 1.0), 4.0)
		and t.at_bond("away", 0.5) < t.at_bond("away", 0.1), "a bonded companion is gone a shorter time")


static func _test_nearest_gap_respects_range() -> int:
	var t := FetchTrip.new([
		{ "id": "a", "mouth": Vector2(0, 0), "inside": Vector2(0, -30), "cache": Vector2(0, -60), "finds": FINDS },
		{ "id": "b", "mouth": Vector2(200, 0), "inside": Vector2(200, -30), "cache": Vector2(200, -60), "finds": FINDS },
	], CFG)
	var fails := 0
	fails += _ok(t.nearest_gap(Vector2(10, 0)) == 0, "the near gap is picked")
	fails += _ok(t.nearest_gap(Vector2(180, 20)) == 1, "the other is picked from the other side")
	fails += _ok(t.nearest_gap(Vector2(100, 500)) == -1, "nothing is in range from far away")
	fails += _ok(t.nearest_gap(Vector2(100, 500), 9999.0) == 1 or t.nearest_gap(Vector2(100, 500), 9999.0) == 0, "an explicit range reaches further")
	return fails


static func _test_a_rabbit_squeezes_through_and_brings_a_pebble() -> int:
	var t := _trip()
	var fails := 0
	fails += _ok(t.ask(0, 0.1), "asked")
	var log := _drive(t, Vector2(100, 200), PLAYER, 0.1, "rabbit", 40.0)
	fails += _ok((log["events"] as Array).has("squeeze"), "it squeezes through")
	fails += _ok((log["events"] as Array).has("gone") and (log["events"] as Array).has("emerge"), "it goes and it comes back")
	fails += _ok((log["carry"] as Array) == ["pebble"], "a new companion carries a pebble")
	fails += _ok(String((log["drop"] as Dictionary).get("item", "")) == "pebble", "and drops a pebble")
	fails += _ok(bool((log["drop"] as Dictionary).get("more", false)), "with a hint that a deeper bond finds more")
	fails += _ok(t.phase == FetchTrip.Phase.IDLE, "then it is idle again")
	return fails


static func _test_a_deep_bond_brings_the_thimble() -> int:
	var t := _trip()
	t.ask(0, 0.9)
	var log := _drive(t, Vector2(100, 200), PLAYER, 0.9, "rabbit", 30.0)
	var drop: Dictionary = log["drop"]
	return _ok(String(drop.get("item", "")) == "thimble" and not bool(drop.get("more", true)), "a deeply bonded companion brings the thimble, and nothing better is left")


static func _test_the_middle_bond_brings_a_button() -> int:
	var t := _trip()
	t.ask(0, 0.4)
	var log := _drive(t, Vector2(100, 200), PLAYER, 0.4, "rabbit", 30.0)
	return _ok(String((log["drop"] as Dictionary).get("item", "")) == "button", "a middling bond brings a button")


static func _test_the_body_is_hidden_only_while_away() -> int:
	var t := _trip()
	t.ask(0, 0.5)
	var log := _drive(t, MOUTH, PLAYER, 0.5, "rabbit", 3.0)
	var fails := 0
	fails += _ok(int(log["hidden_frames"]) == 0 or t.is_hidden() or t.phase != FetchTrip.Phase.SQUEEZE, "it is not hidden while it squeezes")
	var t2 := _trip()
	t2.ask(0, 0.5)
	var hidden_seen := false
	var shown_after := false
	var pos := MOUTH
	for i in 600:
		var r := t2.update(0.05, { "companion_pos": pos, "player_pos": PLAYER, "bond": 0.5, "species": "rabbit", "pending": "" })
		if bool(r["control"]):
			var b: Dictionary = r["body"]
			pos = b["pos"]
			if bool(b["hidden"]):
				hidden_seen = true
			elif hidden_seen:
				shown_after = true
		elif String(r["command"]) == "guide":
			pos = pos.move_toward(r["target"], float(r["speed"]) * 0.05)
	fails += _ok(hidden_seen and shown_after, "hidden while away, shown again when it slips back out")
	return fails


static func _test_a_moment_of_missing_it() -> int:
	var t := _trip()
	t.ask(0, 0.0)
	var log := _drive(t, MOUTH, PLAYER, 0.0, "rabbit", 40.0)
	var misses := 0
	for e in log["events"]:
		if e == "missing":
			misses += 1
	var t2 := _trip()
	t2.ask(0, 0.0)
	var log2 := _drive(t2, MOUTH, PLAYER, 0.0, "rabbit", 3.0, "")
	return _ok(misses == 1 and (log["events"] as Array).has("found"), "one small moment of missing it per trip (and the find cue before it)") + _ok(not (log2["events"] as Array).has("missing"), "...not before it has been gone a while")


static func _test_other_shapes_poke_and_give_up() -> int:
	var t := _trip()
	t.ask(0, 0.9)
	var log := _drive(t, Vector2(100, 200), PLAYER, 0.9, "wolf", 20.0)
	var fails := 0
	fails += _ok((log["events"] as Array).has("too_big"), "a wolf finds it too big")
	fails += _ok((log["events"] as Array).has("gave_up_big"), "and gives it up")
	fails += _ok(not (log["events"] as Array).has("squeeze") and (log["drop"] as Dictionary).is_empty(), "it brings nothing, and loses nothing")
	fails += _ok(t.phase == FetchTrip.Phase.IDLE, "and it can be asked again")
	return fails


static func _test_a_call_in_go_calls_it_off() -> int:
	var t := _trip()
	t.ask(0, 0.5)
	var r := t.update(0.05, { "companion_pos": Vector2(100, 400), "player_pos": PLAYER, "bond": 0.5, "species": "rabbit", "pending": "come" })
	return _ok((r["events"] as Array).has("called_off") and t.phase == FetchTrip.Phase.IDLE, "a Call while it is on its way calls it off")


static func _test_a_call_while_away_brings_it_back_early() -> int:
	var fails := 0
	var t := _trip()
	t.ask(0, 0.0)
	# squeeze through, then call it 1 s into its (8 s) time away
	var pos := MOUTH
	var emerge_at := -1.0
	var elapsed := 0.0
	var away_started := -1.0
	while elapsed < 30.0:
		var pending := ""
		if away_started >= 0.0 and elapsed - away_started > 1.0 and elapsed - away_started < 1.2:
			pending = "come"
		var r := t.update(0.05, { "companion_pos": pos, "player_pos": PLAYER, "bond": 0.0, "species": "rabbit", "pending": pending })
		if bool(r["control"]):
			pos = (r["body"] as Dictionary)["pos"]
		elif String(r["command"]) == "guide":
			pos = pos.move_toward(r["target"], float(r["speed"]) * 0.05)
		for e in r["events"]:
			if e == "gone":
				away_started = elapsed
			if e == "emerge":
				emerge_at = elapsed
		elapsed += 0.05
		if emerge_at >= 0.0:
			break
	fails += _ok(away_started >= 0.0 and emerge_at >= 0.0 and emerge_at - away_started < 3.0, "called one second in, it is back within about two more (not the full eight)")
	return fails


static func _test_a_pet_is_enjoyed_and_the_trip_carries_on() -> int:
	var t := _trip()
	t.ask(0, 0.5)
	var r := t.update(0.05, { "companion_pos": Vector2(100, 300), "player_pos": PLAYER, "bond": 0.5, "species": "rabbit", "pending": "pet" })
	var fails := 0
	fails += _ok(String(r["command"]) == "", "while it is petted we leave it alone")
	var log := _drive(t, Vector2(100, 300), PLAYER, 0.5, "rabbit", 40.0)
	fails += _ok(String((log["drop"] as Dictionary).get("item", "")) != "", "and the trip carries on afterwards")
	return fails


static func _test_it_finds_you_wherever_you_wander() -> int:
	var t := _trip()
	t.ask(0, 0.9)
	var fails := 0
	# the player wanders far off while it is away
	var far := Vector2(600, 500)
	var log := _drive(t, Vector2(100, 200), far, 0.9, "rabbit", 60.0)
	fails += _ok(String((log["drop"] as Dictionary).get("item", "")) == "thimble", "it still brings the thimble to a player who wandered off")
	fails += _ok(((log["drop"] as Dictionary)["pos"] as Vector2).distance_to(far) < 40.0, "and sets it down at their feet")
	return fails


static func _test_it_sets_the_find_down_if_it_cannot_reach_you() -> int:
	var t := _trip()
	t.ask(0, 0.5)
	# the "companion" never moves toward the player (boxed in): after its patience it sets the find down
	var pos := MOUTH
	var dropped := {}
	for i in 1200:
		var r := t.update(0.05, { "companion_pos": pos, "player_pos": Vector2(5000, 5000), "bond": 0.5, "species": "rabbit", "pending": "" })
		if bool(r["control"]):
			pos = (r["body"] as Dictionary)["pos"]
		elif String(r["command"]) == "guide" and t.phase == FetchTrip.Phase.GO:
			pos = pos.move_toward(r["target"], float(r["speed"]) * 0.05)
		if not (r["drop"] as Dictionary).is_empty():
			dropped = r["drop"]
			break
	return _ok(not dropped.is_empty() and (dropped["pos"] as Vector2).distance_to(MOUTH) < 40.0, "unable to reach you, it sets the find down where it stands (nothing lost)")


static func _test_cooldown_between_trips() -> int:
	var t := _trip()
	t.ask(0, 0.5)
	_drive(t, Vector2(100, 200), PLAYER, 0.5, "rabbit", 18.0)
	var fails := 0
	fails += _ok(t.phase == FetchTrip.Phase.IDLE, "done")
	var asked_now := t.ask(0, 0.5)
	# the drive ran past the cooldown, so it is allowed; check the cooldown right after a drop instead
	var t2 := _trip()
	t2.ask(0, 0.5)
	var pos := Vector2(100, 200)
	for i in 800:
		var r := t2.update(0.05, { "companion_pos": pos, "player_pos": PLAYER, "bond": 0.5, "species": "rabbit", "pending": "" })
		if bool(r["control"]):
			pos = (r["body"] as Dictionary)["pos"]
		elif String(r["command"]) == "guide":
			pos = pos.move_toward(r["target"], float(r["speed"]) * 0.05)
		if not (r["drop"] as Dictionary).is_empty():
			break
	fails += _ok(not t2.can_ask(), "right after a drop it cools down a moment")
	for i in 60:
		t2.update(0.05, { "companion_pos": pos, "player_pos": PLAYER, "bond": 0.5, "species": "rabbit", "pending": "" })
	fails += _ok(t2.can_ask() and asked_now, "and can be asked again after it")
	return fails


static func _test_repeat_trips_warm_less() -> int:
	var t := _trip()
	var warms: Array = []
	for n in 3:
		t.ask(0, 0.5)
		var log := _drive(t, Vector2(100, 200), PLAYER, 0.5, "rabbit", 40.0)
		warms.append(float((log["drop"] as Dictionary).get("warm", 0.0)))
		_drive(t, Vector2(100, 200), PLAYER, 0.5, "rabbit", 3.0)   # let the cooldown pass
	var fails := 0
	fails += _ok(is_equal_approx(warms[0], 0.05) and is_equal_approx(warms[1], 0.025) and is_equal_approx(warms[2], 0.0125), "each trip to the same gap warms less (so it cannot be farmed)")
	fails += _ok(t.trips_at("g1") == 3, "trips are counted per gap")
	return fails


static func _test_cannot_ask_while_busy() -> int:
	var t := _trip()
	var fails := 0
	fails += _ok(t.ask(0, 0.5), "first ask")
	fails += _ok(not t.ask(0, 0.5), "a second ask while it is on its way is ignored")
	fails += _ok(not t.ask(7, 0.5) and not _trip().ask(7, 0.5), "there is no gap 7")
	return fails


static func _test_gives_up_the_way_after_patience() -> int:
	var t := _trip()
	t.ask(0, 0.5)
	var events: Array = []
	var pos := Vector2(100, 900)   # never gets anywhere: we do not move it
	for i in 800:
		var r := t.update(0.05, { "companion_pos": pos, "player_pos": PLAYER, "bond": 0.5, "species": "rabbit", "pending": "" })
		for e in r["events"]:
			events.append(e)
	return _ok(events.has("lost_way") and t.phase == FetchTrip.Phase.IDLE, "a companion that cannot reach the gap gives up the way, gently")


static func _test_a_far_off_companion_is_given_time_to_arrive() -> int:
	# a fresh companion can be 1500 px from the gap: at a trot that is 15 s, longer than the bare slack
	var t := _trip()
	t.ask(0, 0.1)
	var log := _drive(t, Vector2(100, 1600), PLAYER, 0.1, "rabbit", 60.0)
	return _ok((log["events"] as Array).has("squeeze") and not (log["events"] as Array).has("lost_way") and String((log["drop"] as Dictionary).get("item", "")) != "", "a companion 1500 px away still gets there, runs, and brings its find")


static func _test_notice_range_grows_with_bond() -> int:
	var fails := 0
	var far := Vector2(MOUTH.x + 300.0, MOUTH.y)
	var t0 := _trip()
	fails += _ok(not bool(t0.notice(0.1, far, 0.0)["point"]), "a new companion does not notice a gap 300 px away")
	var t1 := _trip()
	var n := t1.notice(0.1, far, 1.0)
	fails += _ok(bool(n["point"]) and bool(n["started"]) and (n["target"] as Vector2) == MOUTH, "a bonded one does, and points at it")
	return fails


static func _test_notice_holds_then_cools_down() -> int:
	var t := _trip()
	var near := Vector2(MOUTH.x + 50.0, MOUTH.y)
	var fails := 0
	var n := t.notice(0.1, near, 0.5)
	fails += _ok(bool(n["started"]), "it starts pointing")
	var still_pointing := bool(t.notice(1.0, near, 0.5)["point"])
	fails += _ok(still_pointing, "and holds the point")
	t.notice(2.0, near, 0.5)   # the hold ends
	fails += _ok(not bool(t.notice(0.5, near, 0.5)["point"]), "then it stops, cooling down")
	var again := false
	for i in 400:
		if bool(t.notice(0.1, near, 0.5)["started"]):
			again = true
			break
	fails += _ok(again, "and points again after the cooldown")
	return fails


static func _test_no_notice_while_busy() -> int:
	var t := _trip()
	t.ask(0, 0.5)
	return _ok(not bool(t.notice(0.1, MOUTH, 1.0)["point"]), "no pointing at a gap it is already off to")


static func _test_data_overrides_defaults() -> int:
	var t := FetchTrip.new([], { "away_low": 3.0, "bogus": 1.0 })
	return _ok(is_equal_approx(float(t.cfg("away_low")), 3.0) and not t.can_ask(), "the spec's numbers win, and a world with no gaps has nothing to ask")
