class_name TestReflectionWalker
## Tests for ReflectionWalker, the pure logic of Stillglass's secret: the lake mirrors your companion until
## it has stood settled at the edge, then its reflection turns into someone else and walks the shore a little
## ahead of you, waits when you fall behind, lets go (keeping its progress) if the companion or you wander
## off, and stops over the last waypoint. No nodes: the "companion" and "player" are points this test moves.

const START := Vector2(0, 0)
const TRAIL := [Vector2(100, 0), Vector2(200, 0), Vector2(300, 0)]
const CFG := {
	"edge_radius": 120.0, "player_radius": 200.0, "linger_seconds": 1.0, "linger_speed": 30.0,
	"approach_offset": [0.0, -20.0], "settle_seconds": 1.0, "settle_speed": 14.0, "turn_seconds": 1.0,
	"pace": 100.0, "wait_distance": 150.0, "resume_distance": 80.0, "companion_radius": 250.0,
	"give_up_distance": 500.0, "waypoint_reach": 5.0, "done_hold": 3.0,
	"notice_range_low": 150.0, "notice_range_high": 400.0, "notice_cooldown_low": 10.0, "notice_cooldown_high": 4.0,
	"notice_hold": 2.0,
}


static func run_all() -> int:
	var fails := 0
	print("TestReflectionWalker")
	fails += _test_mirrors_until_settled_at_the_edge()
	fails += _test_a_moving_companion_does_not_settle()
	fails += _test_a_far_companion_is_asked_to_the_edge()
	fails += _test_no_approach_for_a_player_passing_by()
	fails += _test_turns_then_walks_the_whole_shore()
	fails += _test_waits_for_a_player_who_falls_behind()
	fails += _test_companion_leaving_lets_go_and_keeps_progress()
	fails += _test_resumes_from_where_it_stopped()
	fails += _test_wandering_far_away_lets_go()
	fails += _test_hold_stands_it_still_and_never_lets_go()
	fails += _test_turn_is_cancelled_if_you_both_leave()
	fails += _test_done_is_final_and_counts_up()
	fails += _test_reset_starts_afresh()
	fails += _test_notice_range_grows_with_bond()
	fails += _test_notice_holds_then_cools_down()
	fails += _test_no_notice_once_walking()
	fails += _test_data_overrides_defaults()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _make() -> ReflectionWalker:
	return ReflectionWalker.new(START, TRAIL, CFG)


## Step the walker `seconds` with the given companion and player (still points), collecting the events.
static func _run(w: ReflectionWalker, seconds: float, comp: Vector2, player: Vector2, comp_speed := 0.0, player_speed := 0.0) -> Array:
	var events: Array = []
	var t := 0.0
	while t < seconds:
		var r := w.update(0.05, comp, comp_speed, player, player_speed)
		events.append_array(r["events"])
		t += 0.05
	return events


static func _test_mirrors_until_settled_at_the_edge() -> int:
	var w := _make()
	var ev := _run(w, 0.5, Vector2(20, -20), Vector2(10, -40))
	var fails := _ok(w.phase == ReflectionWalker.Phase.MIRROR and not w.is_independent(), "settling for less than the time keeps mirroring")
	fails += _ok(ev.has("gather"), "...but the water stirs as it settles")
	fails += _ok(w.gather_fraction() > 0.3, "...and the stir grows (%.2f)" % w.gather_fraction())
	ev = _run(w, 0.8, Vector2(20, -20), Vector2(10, -40))
	fails += _ok(ev.has("turn") and w.phase == ReflectionWalker.Phase.TURN, "settled long enough, it turns")
	return fails


static func _test_a_moving_companion_does_not_settle() -> int:
	var w := _make()
	_run(w, 4.0, Vector2(20, -20), Vector2(10, -40), 60.0, 0.0)
	return _ok(w.phase == ReflectionWalker.Phase.MIRROR and w.gather_fraction() == 0.0, "a companion on the move never settles")


static func _test_a_far_companion_is_asked_to_the_edge() -> int:
	var w := _make()
	var asked := false
	var target := Vector2.ZERO
	for _i in 60:
		var r := w.update(0.05, Vector2(-400, 0), 0.0, Vector2(10, -40), 0.0)
		if String(r["command"]) == "approach":
			asked = true
			target = r["target"]
	var fails := _ok(asked, "a player lingering by the water sends a far companion to the edge")
	fails += _ok(target.distance_to(Vector2(0, -20)) < 0.01, "...to stand just beside the water, not in it")
	return fails


static func _test_no_approach_for_a_player_passing_by() -> int:
	var w := _make()
	var asked := false
	for _i in 100:
		var r := w.update(0.05, Vector2(-400, 0), 0.0, Vector2(10, -40), 90.0)
		asked = asked or String(r["command"]) == "approach"
	return _ok(not asked, "a player merely walking past does not hijack the companion")


## Walk the whole way: the player trails the reflection by 60 px. Returns the events and seconds taken.
static func _walk_all(w: ReflectionWalker, max_seconds := 30.0) -> Dictionary:
	var events: Array = []
	var t := 0.0
	while t < max_seconds and not w.is_done():
		var comp := w.pos + Vector2(0, -20)
		var player := w.pos + Vector2(-60, -40)
		var r := w.update(0.05, comp, 0.0, player, 10.0)
		events.append_array(r["events"])
		t += 0.05
	return { "events": events, "time": t }


static func _test_turns_then_walks_the_whole_shore() -> int:
	var w := _make()
	var res := _walk_all(w)
	var ev: Array = res["events"]
	var fails := _ok(w.is_done(), "a settled companion's reflection walks the whole shore (%.1f s)" % float(res["time"]))
	fails += _ok(ev.has("turn") and ev.has("set_off") and ev.has("done"), "...turning, setting off and arriving")
	fails += _ok(ev.count("reached") == TRAIL.size(), "...reaching every waypoint")
	fails += _ok(w.pos.distance_to(TRAIL[-1]) < 0.01, "...and stopping over the last one")
	fails += _ok(float(res["time"]) > 3.0 and float(res["time"]) < 9.0, "...in about the time a 300 px walk at its pace takes")
	return fails


static func _test_waits_for_a_player_who_falls_behind() -> int:
	var w := _make()
	_run(w, 2.5, Vector2(20, -20), Vector2(10, -40))   # settle + turn
	var ev := _run(w, 3.0, w.pos + Vector2(0, -20), Vector2(-300, -40))
	var fails := _ok(ev.has("wait") and w.phase == ReflectionWalker.Phase.WAIT, "you fall far behind: it waits")
	var held := w.pos
	_run(w, 4.0, w.pos + Vector2(0, -20), Vector2(-300, -40))
	fails += _ok(w.pos.distance_to(held) < 0.01 and w.phase == ReflectionWalker.Phase.WAIT, "...and keeps waiting, however long")
	ev = _run(w, 0.5, w.pos + Vector2(0, -20), w.pos + Vector2(-40, -40))
	fails += _ok(ev.has("resume") and w.phase == ReflectionWalker.Phase.WALK, "...walking on again once you are back")
	return fails


static func _test_companion_leaving_lets_go_and_keeps_progress() -> int:
	var w := _make()
	_run(w, 2.5, Vector2(20, -20), Vector2(10, -40))
	for _i in 40:
		w.update(0.05, w.pos + Vector2(0, -20), 0.0, w.pos + Vector2(-50, -40), 10.0)
	var progressed := w.pos
	var ev := _run(w, 0.5, progressed + Vector2(0, 400), progressed + Vector2(-50, -40))
	var fails := _ok(ev.has("lost") and w.phase == ReflectionWalker.Phase.MIRROR, "the companion leaving the shore sends it back to mirroring")
	fails += _ok(w.pos.distance_to(progressed) < 0.01 and w.next_index >= 1, "...with its progress kept (stopped at x=%.0f)" % w.pos.x)
	return fails


static func _test_resumes_from_where_it_stopped() -> int:
	var w := _make()
	_run(w, 2.5, Vector2(20, -20), Vector2(10, -40))
	for _i in 40:
		w.update(0.05, w.pos + Vector2(0, -20), 0.0, w.pos + Vector2(-50, -40), 10.0)
	var stopped := w.pos
	_run(w, 0.5, stopped + Vector2(0, 400), stopped + Vector2(-50, -40))   # let go
	# Standing at the START again does nothing (the walk is not there any more)...
	_run(w, 4.0, Vector2(0, -20), Vector2(0, -40))
	var fails := _ok(w.phase == ReflectionWalker.Phase.MIRROR, "back at the start, nothing happens: the walk resumes where it stopped")
	# ...stand the companion at the edge THERE and it goes on.
	var ev := _run(w, 2.5, stopped + Vector2(0, -20), stopped + Vector2(-20, -40))
	fails += _ok(ev.has("turn"), "settled at the edge where it stopped, it turns again")
	var from := w.pos
	var res := _walk_all(w)
	fails += _ok(w.is_done() and w.pos.x > from.x - 0.01, "...and finishes the shore from there")
	return fails


static func _test_wandering_far_away_lets_go() -> int:
	var w := _make()
	_run(w, 2.5, Vector2(20, -20), Vector2(10, -40))
	var ev := _run(w, 1.0, w.pos + Vector2(0, -20), w.pos + Vector2(-900, 0))
	return _ok(ev.has("lost") and w.phase == ReflectionWalker.Phase.MIRROR, "you wander far off: the reflection goes back to mirroring")


static func _test_hold_stands_it_still_and_never_lets_go() -> int:
	var w := _make()
	_run(w, 2.5, Vector2(20, -20), Vector2(10, -40))
	for _i in 40:
		w.update(0.05, w.pos + Vector2(0, -20), 0.0, w.pos + Vector2(-50, -40), 10.0)
	var at := w.pos
	var lost := false
	for _i in 200:   # ten seconds of a pet, with the companion far off and the player wandering
		var r := w.update(0.05, at + Vector2(0, 600), 0.0, at + Vector2(-700, 0), 0.0, true)
		lost = lost or (r["events"] as Array).has("lost")
	var fails := _ok(not lost and w.phase == ReflectionWalker.Phase.WALK and w.pos.distance_to(at) < 0.01, "held: it stands still and never lets go, whatever else is going on")
	var r2 := w.update(0.05, at + Vector2(0, -20), 0.0, at + Vector2(-50, -40), 10.0)
	fails += _ok(bool(r2["moving"]), "...and walks on the moment the hold ends")
	return fails


static func _test_turn_is_cancelled_if_you_both_leave() -> int:
	var w := _make()
	_run(w, 1.2, Vector2(20, -20), Vector2(10, -40))
	var in_turn := w.phase == ReflectionWalker.Phase.TURN
	var ev := _run(w, 0.3, Vector2(900, 0), Vector2(900, 0))
	var fails := _ok(in_turn, "(it was turning)")
	fails += _ok(ev.has("lost") and w.phase == ReflectionWalker.Phase.MIRROR, "both of you leave mid-turn: it goes quietly back to mirroring")
	return fails


static func _test_done_is_final_and_counts_up() -> int:
	var w := _make()
	_run(w, 2.5, Vector2(20, -20), Vector2(10, -40))
	_walk_all(w)
	var r := w.update(1.0, w.pos, 0.0, w.pos, 0.0)
	var fails := _ok(w.is_done() and String(r["command"]) == "" and not bool(r["moving"]), "done: no more orders, standing over the stone")
	fails += _ok(w.done_time >= 1.0, "...and the time over the stone counts up (%.1f s)" % w.done_time)
	return fails


static func _test_reset_starts_afresh() -> int:
	var w := _make()
	_run(w, 2.5, Vector2(20, -20), Vector2(10, -40))
	_walk_all(w)
	w.reset()
	return _ok(w.phase == ReflectionWalker.Phase.MIRROR and w.next_index == 0 and w.pos.distance_to(START) < 0.01 and w.fraction() == 0.0, "reset: a fresh walk from the start")


static func _test_notice_range_grows_with_bond() -> int:
	var w := _make()
	var near := w.notice(0.05, Vector2(120, 0), 0.0)
	var w2 := _make()
	var mid_low := w2.notice(0.05, Vector2(300, 0), 0.0)
	var w3 := _make()
	var mid_high := w3.notice(0.05, Vector2(300, 0), 1.0)
	var fails := _ok(near["point"] and near["started"], "close by, even a fresh companion notices")
	fails += _ok(not mid_low["point"], "a fresh companion does not notice from 300 px")
	fails += _ok(mid_high["point"], "a bonded one does")
	return fails


static func _test_notice_holds_then_cools_down() -> int:
	var w := _make()
	var first := w.notice(0.05, Vector2(50, 0), 0.0)
	var held := w.notice(1.0, Vector2(50, 0), 0.0)
	var released := w.notice(1.5, Vector2(50, 0), 0.0)
	var cooling := w.notice(1.0, Vector2(50, 0), 0.0)
	var fails := _ok(first["point"] and held["point"] and not released["point"], "it points for the hold, then lets go")
	fails += _ok(not cooling["point"], "...and cools down before the next one")
	return fails


static func _test_no_notice_once_walking() -> int:
	var w := _make()
	_run(w, 2.5, Vector2(20, -20), Vector2(10, -40))
	return _ok(not w.notice(0.05, Vector2(10, -40), 1.0)["point"], "no noticing once the reflection is walking")


static func _test_data_overrides_defaults() -> int:
	var slow := ReflectionWalker.new(START, TRAIL, { "pace": 20.0, "settle_seconds": 0.2, "turn_seconds": 0.1 })
	_run(slow, 0.5, Vector2(20, -20), Vector2(10, -40))
	var before := slow.pos
	for _i in 20:
		slow.update(0.05, slow.pos + Vector2(0, -20), 0.0, slow.pos + Vector2(-30, -40), 10.0)
	var fails := _ok(slow.pos.x > before.x and slow.pos.x < before.x + 40.0, "the spec's pace is what it walks at (%.0f px in 1 s)" % (slow.pos.x - before.x))
	var empty := ReflectionWalker.new(START, [], CFG)
	fails += _ok(String(empty.update(0.05, START, 0.0, START, 0.0)["command"]) == "", "an empty trail does nothing")
	return fails
