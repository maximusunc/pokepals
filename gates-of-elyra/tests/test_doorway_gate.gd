class_name TestDoorwayGate
## Tests for DoorwayGate, the pure logic of Lingerlong's Late Arch: a door that only opens while your companion
## waits inside its picture. No nodes: the "companion" is a point this test walks toward the target the gate names,
## exactly as the brain's GuideAction does in the game, and the "player" is a point we step about.

const AT := Vector2(620, -900)
const BACK := Vector2(100, -1812)
const CFG := {
	"ask_range": 380.0, "tap_radius": 48.0, "threshold": 18.0, "reach": 10.0, "go_speed": 100.0, "run_speed": 130.0,
	"run_distance": 240.0, "go_patience": 6.0, "pet_pause": 2.0, "sniff_low": 1.8, "sniff_high": 1.0, "step_seconds": 1.0,
	"vanish": 0.3, "hold_low": 7.0, "hold_high": 16.0, "out_seconds": 1.0, "cooldown": 1.0, "door_half_width": 20.0,
	"line": 4.0, "step_max": 48.0, "notice_range_low": 260.0, "notice_range_high": 560.0, "notice_cooldown_low": 16.0,
	"notice_cooldown_high": 7.0, "notice_hold": 2.0,
}
const DT := 0.05


static func run_all() -> int:
	var fails := 0
	print("TestDoorwayGate")
	fails += _test_crossing_from_the_front_only()
	fails += _test_crossing_needs_the_doorway_not_the_legs()
	fails += _test_a_teleport_is_not_a_step()
	fails += _test_the_back_arch_counts_both_ways()
	fails += _test_walking_through_a_shut_door_does_nothing()
	fails += _test_the_trip_goes_sniffs_and_steps_in()
	fails += _test_the_body_hides_only_once_it_is_in_the_picture()
	fails += _test_the_open_door_takes_you_through()
	fails += _test_the_door_is_held_longer_with_bond()
	fails += _test_it_comes_back_out_if_you_dont_follow()
	fails += _test_a_call_brings_it_out_early()
	fails += _test_a_call_on_the_way_calls_it_off()
	fails += _test_a_pet_on_the_way_is_enjoyed()
	fails += _test_it_gives_up_a_way_it_cannot_find()
	fails += _test_cannot_ask_while_busy_or_cooling()
	fails += _test_the_way_back_works_mid_trip()
	fails += _test_notice_range_and_cooldown_follow_the_bond()
	fails += _test_no_notice_while_busy()
	fails += _test_taps_and_ask_range()
	fails += _test_data_overrides_defaults()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


## Step the gate `secs` seconds with a companion that walks toward any guide target (and stays put when held or
## controlled). Returns every event seen, and leaves `state` with the last companion position and result.
static func _run(g: DoorwayGate, state: Dictionary, secs: float, pending := "") -> Array:
	var events: Array = []
	var t := 0.0
	while t < secs:
		var ctx := {
			"companion_pos": state["c"], "player_pos": state["p"], "player_prev": state.get("prev", state["p"]),
			"bond": state.get("bond", 0.0), "pending": pending,
		}
		state["prev"] = state["p"]
		var r := g.update(DT, ctx)
		state["r"] = r
		events.append_array(r["events"])
		if String(r["command"]) == "guide" and not bool(r["hold"]):
			var c: Vector2 = state["c"]
			state["c"] = c.move_toward(r["target"], float(r["speed"]) * DT)
		elif bool(r["control"]):
			state["c"] = (r["body"] as Dictionary)["pos"]
		t += DT
	return events


static func _fresh(bond := 0.0) -> Array:
	var g := DoorwayGate.new(AT, BACK, CFG)
	var state := { "c": AT + Vector2(-40, 120), "p": AT + Vector2(0, 140), "bond": bond }
	return [g, state]


static func _test_crossing_from_the_front_only() -> int:
	var f := 0
	f += _ok(DoorwayGate.crosses(AT + Vector2(0, 2), AT + Vector2(0, -6), AT, 20.0, 4.0, false, 48.0), "a step north into the doorway counts")
	f += _ok(not DoorwayGate.crosses(AT + Vector2(0, -6), AT + Vector2(0, 2), AT, 20.0, 4.0, false, 48.0), "a step south out of it does not (front only)")
	f += _ok(not DoorwayGate.crosses(AT + Vector2(0, 20), AT + Vector2(0, 10), AT, 20.0, 4.0, false, 48.0), "nor a step that stops short of the line")
	return f


static func _test_crossing_needs_the_doorway_not_the_legs() -> int:
	var f := 0
	f += _ok(not DoorwayGate.crosses(AT + Vector2(30, 2), AT + Vector2(30, -6), AT, 20.0, 4.0, false, 48.0), "beside the doorway is not in it")
	f += _ok(DoorwayGate.crosses(AT + Vector2(-26, 6), AT + Vector2(-10, -14), AT, 20.0, 4.0, false, 48.0), "a diagonal step judged where it crossed")
	return f


static func _test_a_teleport_is_not_a_step() -> int:
	var f := 0
	f += _ok(not DoorwayGate.crosses(AT + Vector2(0, 200), AT + Vector2(0, -6), AT, 20.0, 4.0, true, 48.0), "a jump is not a step")
	f += _ok(not DoorwayGate.crosses(Vector2.INF, AT + Vector2(0, -6), AT, 20.0, 4.0, true, 48.0), "nor is the first frame")
	return f


static func _test_the_back_arch_counts_both_ways() -> int:
	var f := 0
	f += _ok(DoorwayGate.crosses(BACK + Vector2(0, 4), BACK + Vector2(0, -8), BACK, 20.0, 4.0, true, 48.0), "into the way back from the front")
	f += _ok(DoorwayGate.crosses(BACK + Vector2(0, -12), BACK + Vector2(0, -2), BACK, 20.0, 4.0, true, 48.0), "and from behind")
	var g := DoorwayGate.new(AT, BACK, CFG)
	var r := g.update(DT, { "companion_pos": BACK, "player_pos": BACK + Vector2(0, -8), "player_prev": BACK + Vector2(0, 4), "bond": 0.0, "pending": "" })
	f += _ok(bool(r["back"]) and not bool(r["through"]), "the gate says: back to the pool")
	return f


static func _test_walking_through_a_shut_door_does_nothing() -> int:
	var g := DoorwayGate.new(AT, BACK, CFG)
	var r := g.update(DT, { "companion_pos": AT, "player_pos": AT + Vector2(0, -8), "player_prev": AT + Vector2(0, 4), "bond": 0.0, "pending": "" })
	return _ok(not bool(r["through"]) and (r["events"] as Array).has("plain_through") and not g.is_busy(), "through a shut door you come out the other side")


static func _test_the_trip_goes_sniffs_and_steps_in() -> int:
	var f := 0
	var gs := _fresh()
	var g: DoorwayGate = gs[0]
	var st: Dictionary = gs[1]
	f += _ok(g.ask(0.0) and g.phase == DoorwayGate.Phase.GO, "asking sends it off")
	var ev := _run(g, st, 1.6)
	f += _ok(ev.has("sniff") and (st["c"] as Vector2).distance_to(g.threshold()) <= 10.5, "it trots to the threshold and sniffs")
	f += _ok(g.phase == DoorwayGate.Phase.SNIFF and (st["r"]["look"] as Vector2).is_equal_approx(g.door_middle()), "looking into the doorway")
	ev = _run(g, st, 3.2)
	f += _ok(ev.has("inside") and g.is_open(), "then it steps into the picture and the door is open")
	f += _ok((st["r"]["figure"] as Dictionary).get("facing", "") == "down", "turned to look back at you")
	return f


static func _test_the_body_hides_only_once_it_is_in_the_picture() -> int:
	var f := 0
	var gs := _fresh()
	var g: DoorwayGate = gs[0]
	var st: Dictionary = gs[1]
	g.ask(0.0)
	_run(g, st, 3.0)
	_run(g, st, 1.9)   # past the sniff, into the step
	f += _ok(g.phase == DoorwayGate.Phase.STEP_IN or g.phase == DoorwayGate.Phase.INSIDE, "(stepping in)")
	var seen_visible := false
	var seen_hidden := false
	var seen_figure_with_body := false
	g = DoorwayGate.new(AT, BACK, CFG)
	st = { "c": g.threshold(), "p": AT + Vector2(0, 60) }
	g.ask(0.0)
	for i in 120:
		var r := g.update(DT, { "companion_pos": st["c"], "player_pos": st["p"], "player_prev": st["p"], "bond": 0.0, "pending": "" })
		if bool(r["control"]):
			var body: Dictionary = r["body"]
			if bool(body["hidden"]):
				seen_hidden = true
			else:
				seen_visible = true
				if not (r["figure"] as Dictionary).is_empty():
					seen_figure_with_body = true
			st["c"] = body["pos"]
	f += _ok(seen_visible and seen_hidden, "the body walks under the arch, then is hidden")
	f += _ok(not seen_figure_with_body, "and never two of it at once")
	return f


static func _test_the_open_door_takes_you_through() -> int:
	var f := 0
	var gs := _fresh()
	var g: DoorwayGate = gs[0]
	var st: Dictionary = gs[1]
	g.ask(0.0)
	_run(g, st, 7.0)
	f += _ok(g.is_open(), "(the door is open)")
	st["p"] = AT + Vector2(0, 6)
	_run(g, st, DT)
	st["p"] = AT + Vector2(0, -6)
	var ev := _run(g, st, DT)
	f += _ok(bool(st["r"]["through"]) and ev.has("through"), "stepping in from the front takes you through")
	f += _ok(not g.is_busy() and not g.can_ask(), "and the trip is over (a short cooldown)")
	return f


static func _test_the_door_is_held_longer_with_bond() -> int:
	var g := DoorwayGate.new(AT, BACK, CFG)
	return _ok(is_equal_approx(g.hold_for(0.0), 7.0) and is_equal_approx(g.hold_for(1.0), 16.0) and g.hold_for(0.5) > 11.0,
		"the door is held 7 s fresh, 16 s deeply bonded")


static func _test_it_comes_back_out_if_you_dont_follow() -> int:
	var f := 0
	var gs := _fresh(0.0)
	var g: DoorwayGate = gs[0]
	var st: Dictionary = gs[1]
	g.ask(0.0)
	_run(g, st, 7.0)
	f += _ok(g.is_open(), "(open)")
	var ev := _run(g, st, 3.0)
	f += _ok(g.is_open(), "still waiting before its time is up")
	ev = _run(g, st, 3.2)
	f += _ok(ev.has("came_out") and not g.is_busy(), "then it comes back out, with no failure")
	f += _ok((st["c"] as Vector2).distance_to(g.threshold()) < 1.0, "to the threshold, where it is yours again")
	_run(g, st, 1.2)
	f += _ok(g.can_ask(), "and you can ask again")
	return f


static func _test_a_call_brings_it_out_early() -> int:
	var f := 0
	var gs := _fresh()
	var g: DoorwayGate = gs[0]
	var st: Dictionary = gs[1]
	g.ask(0.0)
	_run(g, st, 7.0)
	var ev := _run(g, st, 1.5, "come")
	f += _ok(ev.has("called_out") and not g.is_busy(), "a Call brings it back out of the picture")
	return f


static func _test_a_call_on_the_way_calls_it_off() -> int:
	var gs := _fresh()
	var g: DoorwayGate = gs[0]
	var st: Dictionary = gs[1]
	g.ask(0.0)
	_run(g, st, 0.3)
	var ev := _run(g, st, DT, "come")
	return _ok(ev.has("called_off") and not g.is_busy(), "a Call on the way there calls it off")


static func _test_a_pet_on_the_way_is_enjoyed() -> int:
	var f := 0
	var gs := _fresh()
	var g: DoorwayGate = gs[0]
	var st: Dictionary = gs[1]
	g.ask(0.0)
	_run(g, st, 0.2)
	var before: Vector2 = st["c"]
	_run(g, st, DT, "pet")
	_run(g, st, 1.0)
	f += _ok((st["c"] as Vector2).distance_to(before) < 0.5 and g.phase == DoorwayGate.Phase.GO, "a Pet is enjoyed (it stands for it)")
	var ev := _run(g, st, 4.0)
	f += _ok(ev.has("sniff"), "and the trip carries on")
	return f


static func _test_it_gives_up_a_way_it_cannot_find() -> int:
	var g := DoorwayGate.new(AT, BACK, CFG)
	var st := { "c": BACK, "p": AT + Vector2(0, 100) }
	g.ask(0.0)
	var ev: Array = []
	for i in 600:
		var r := g.update(DT, { "companion_pos": st["c"], "player_pos": st["p"], "player_prev": st["p"], "bond": 0.0, "pending": "" })
		ev.append_array(r["events"])   # (the companion never moves: an island it cannot leave)
	return _ok(ev.has("lost_way") and not g.is_busy(), "it gives up a way it cannot find, gently")


static func _test_cannot_ask_while_busy_or_cooling() -> int:
	var f := 0
	var gs := _fresh()
	var g: DoorwayGate = gs[0]
	var st: Dictionary = gs[1]
	g.ask(0.0)
	f += _ok(not g.ask(0.0), "no second trip while one is under way")
	_run(g, st, 0.3)
	_run(g, st, DT, "come")
	f += _ok(g.can_ask(), "a called-off trip can be asked again at once")
	return f


static func _test_the_way_back_works_mid_trip() -> int:
	var gs := _fresh()
	var g: DoorwayGate = gs[0]
	var st: Dictionary = gs[1]
	g.ask(0.0)
	_run(g, st, 0.5)
	var r := g.update(DT, { "companion_pos": st["c"], "player_pos": BACK + Vector2(0, -8), "player_prev": BACK + Vector2(0, 4), "bond": 0.0, "pending": "" })
	return _ok(bool(r["back"]) and not g.is_busy(), "the way back is never closed, whatever is under way")


static func _test_notice_range_and_cooldown_follow_the_bond() -> int:
	var f := 0
	var g := DoorwayGate.new(AT, BACK, CFG)
	var far := AT + Vector2(0, 400)
	f += _ok(not bool(g.notice(DT, far, 0.0)["point"]), "a fresh companion doesn't notice it from 400 px")
	var n := g.notice(DT, far, 1.0)
	f += _ok(bool(n["point"]) and bool(n["started"]) and (n["target"] as Vector2).is_equal_approx(g.door_middle()), "a bonded one does, and points at the doorway")
	var held := 0
	for i in 60:
		if bool(g.notice(DT, far, 1.0)["point"]):
			held += 1
	f += _ok(held >= 35 and held <= 40, "it holds the point about notice_hold seconds (%d frames)" % held)
	var again := false
	for i in 100:
		if bool(g.notice(DT, far, 1.0)["started"]):
			again = true
	f += _ok(not again, "then not again for a while")
	var later := false
	for i in 60:
		if bool(g.notice(DT, far, 1.0)["started"]):
			later = true
	f += _ok(later, "but again after the bonded cooldown (7 s)")
	return f


static func _test_no_notice_while_busy() -> int:
	var g := DoorwayGate.new(AT, BACK, CFG)
	g.ask(0.0)
	return _ok(not bool(g.notice(DT, AT + Vector2(0, 50), 1.0)["point"]), "no pointing while it is on its errand")


static func _test_taps_and_ask_range() -> int:
	var f := 0
	var g := DoorwayGate.new(AT, BACK, CFG)
	f += _ok(g.is_tap_on_arch(AT + Vector2(6, -40)) and not g.is_tap_on_arch(AT + Vector2(0, 60)), "a tap on the doorway is an order; one on the water in front is not")
	f += _ok(g.in_ask_range(AT + Vector2(0, 300)) and not g.in_ask_range(AT + Vector2(0, 500)), "Go look is offered near the arch only")
	return f


static func _test_data_overrides_defaults() -> int:
	var g := DoorwayGate.new(AT, BACK, { "hold_low": 3.0, "nonsense": 9 })
	return _ok(is_equal_approx(g.hold_for(0.0), 3.0) and is_equal_approx(float(g.cfg("hold_high")), 16.0), "the spec's numbers win; the rest are defaults")
