class_name TestTrailGuide
## Tests for TrailGuide, the pure logic of Drifthallow's tracks: a fox companion catching a scent and
## leading you along an authored trail, waiting when you fall behind, and letting go (without losing its
## place) when it isn't a fox any more. No nodes: the "companion" is a point this test walks toward the
## target the guide names, exactly as the brain's GuideAction does in the game.

const START := Vector2(0, 0)
const TRAIL := [Vector2(100, 0), Vector2(200, 0), Vector2(200, 100)]
const CFG := {
	"species": "fox", "scent_radius": 100.0, "player_radius": 200.0, "sniff_seconds": 1.0,
	"waypoint_reach": 10.0, "wait_distance": 150.0, "resume_distance": 80.0, "give_up_distance": 500.0,
	"print_spacing": 20.0, "waypoint_patience": 5.0,
}


static func run_all() -> int:
	var fails := 0
	print("TestTrailGuide")
	fails += _test_only_a_fox_catches_the_scent()
	fails += _test_the_scent_needs_company()
	fails += _test_sniffs_then_leads_to_the_den()
	fails += _test_waits_for_a_player_who_falls_behind()
	fails += _test_losing_the_shape_keeps_progress()
	fails += _test_wandering_far_away_lets_go()
	fails += _test_leaves_a_print_every_spacing()
	fails += _test_skips_a_waypoint_it_cannot_reach()
	fails += _test_done_is_final()
	fails += _test_data_overrides_defaults()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _guide() -> TrailGuide:
	return TrailGuide.new(START, TRAIL, CFG)


## Walk the companion at `speed` toward whatever target the guide gives, `secs` seconds in 0.1 s steps,
## with the player at `player` (or trailing 40 px behind the companion when player is null). Returns the
## final companion position; every event seen and every print dropped are collected into `log`.
static func _drive(g: TrailGuide, companion: Vector2, player: Variant, form: String, secs: float, log: Dictionary, speed := 80.0) -> Vector2:
	var t := 0.0
	while t < secs:
		var p: Vector2 = player if player is Vector2 else companion - Vector2(40, 0)
		var r := g.update(0.1, companion, p, form)
		for e in r["events"]:
			log["events"].append(e)
		for pr in r["prints"]:
			log["prints"].append(pr)
		if String(r["command"]) == "guide" and not bool(r["hold"]):
			var to: Vector2 = (r["target"] as Vector2) - companion
			companion += to.normalized() * minf(speed * 0.1, to.length())
		t += 0.1
	return companion


static func _log() -> Dictionary:
	return { "events": [], "prints": [] }


static func _test_only_a_fox_catches_the_scent() -> int:
	var fails := 0
	var g := _guide()
	var log := _log()
	_drive(g, Vector2(20, 0), Vector2(0, 30), "cat", 3.0, log)
	fails += _ok(g.phase == TrailGuide.Phase.IDLE and log["events"].is_empty(), "a cat near the scent spot does nothing")
	_drive(g, Vector2(20, 0), Vector2(0, 30), "", 3.0, log)
	fails += _ok(g.phase == TrailGuide.Phase.IDLE, "no form at all does nothing")
	_drive(g, Vector2(20, 0), Vector2(0, 30), "fox", 0.2, log)
	fails += _ok(g.phase == TrailGuide.Phase.SNIFF and "sniff" in log["events"], "a fox near the scent spot puts its nose down")
	return fails


static func _test_the_scent_needs_company() -> int:
	var g := _guide()
	var log := _log()
	_drive(g, Vector2(20, 0), Vector2(900, 0), "fox", 3.0, log)
	var fails := _ok(g.phase == TrailGuide.Phase.IDLE, "it won't catch the scent with you nowhere near")
	var far := _guide()
	_drive(far, Vector2(400, 0), Vector2(380, 0), "fox", 3.0, _log())
	fails += _ok(far.phase == TrailGuide.Phase.IDLE, "…nor from far away from the scent spot")
	return fails


static func _test_sniffs_then_leads_to_the_den() -> int:
	var fails := 0
	var g := _guide()
	var log := _log()
	var end := _drive(g, Vector2(20, 0), null, "fox", 30.0, log)
	fails += _ok("set_off" in log["events"], "after a sniff it sets off")
	fails += _ok(log["events"].count("reached") == 3, "it reaches every waypoint in order (%d)" % log["events"].count("reached"))
	fails += _ok(g.is_done() and "done" in log["events"], "the last waypoint is the den: the trail is done")
	fails += _ok(end.distance_to(g.den()) <= 12.0, "it ends at the den")
	fails += _ok(is_equal_approx(g.fraction(), 1.0), "fraction reads 1.0 when done")
	return fails


static func _test_waits_for_a_player_who_falls_behind() -> int:
	var fails := 0
	var g := _guide()
	var log := _log()
	# Set off (sniff for 1 s), then leave the player far behind at the scent spot.
	var pos := _drive(g, Vector2(20, 0), Vector2(0, 30), "fox", 1.3, log)
	pos = _drive(g, pos, Vector2(-300, 0), "fox", 6.0, log)
	fails += _ok(g.phase == TrailGuide.Phase.WAIT and "wait" in log["events"], "it waits when you fall behind")
	var held := pos
	pos = _drive(g, pos, Vector2(-300, 0), "fox", 4.0, log)
	fails += _ok(pos.distance_to(held) < 0.01, "…and stays where it is while you're away")
	fails += _ok(g.phase == TrailGuide.Phase.WAIT, "…for as long as it takes (no fail state)")
	# Catch up: back within resume_distance.
	pos = _drive(g, pos, pos - Vector2(30, 0), "fox", 0.5, log)
	fails += _ok("resume" in log["events"] and g.phase == TrailGuide.Phase.LEAD, "it sets off again when you catch up")
	return fails


static func _test_losing_the_shape_keeps_progress() -> int:
	var fails := 0
	var g := _guide()
	var log := _log()
	var pos := _drive(g, Vector2(20, 0), null, "fox", 3.0, log)
	var reached: int = g.next_index
	fails += _ok(reached >= 1, "it has led you part-way (waypoint %d)" % reached)
	_drive(g, pos, pos - Vector2(30, 0), "cat", 0.3, log)
	fails += _ok(g.phase == TrailGuide.Phase.IDLE and "lost" in log["events"], "shifting into a cat lets go of the lead")
	fails += _ok(g.next_index == reached, "…without losing its place on the trail")
	# Fox again, but far from where the trail resumes: nothing.
	var g_far := g
	_drive(g_far, Vector2(-500, 500), Vector2(-500, 480), "fox", 2.0, log)
	fails += _ok(g_far.phase == TrailGuide.Phase.IDLE, "a fox elsewhere doesn't pick it up")
	# Fox again, by where it stopped: resumes from the same place.
	var rp := g.resume_point()
	_drive(g, rp + Vector2(10, 0), rp + Vector2(0, 40), "fox", 3.0, log)
	fails += _ok(g.phase == TrailGuide.Phase.LEAD and g.next_index >= reached, "a fox by where it stopped picks the trail back up")
	return fails


static func _test_wandering_far_away_lets_go() -> int:
	var g := _guide()
	var log := _log()
	var pos := _drive(g, Vector2(20, 0), Vector2(0, 30), "fox", 1.3, log)
	_drive(g, pos, Vector2(-900, 0), "fox", 0.2, log)
	return _ok(g.phase == TrailGuide.Phase.IDLE and "lost" in log["events"], "if you wander far off, the lead lapses (it goes back to following you)")


static func _test_leaves_a_print_every_spacing() -> int:
	var g := _guide()
	var log := _log()
	_drive(g, Vector2(20, 0), null, "fox", 30.0, log)
	var fails := 0
	fails += _ok(log["prints"].size() >= 8, "it leaves prints as it goes (%d)" % log["prints"].size())
	var spaced := true
	for i in range(1, log["prints"].size()):
		if (log["prints"][i] as Vector2).distance_to(log["prints"][i - 1]) < 19.0:
			spaced = false
	fails += _ok(spaced, "prints are at least a spacing apart")
	var idle := _guide()
	var log2 := _log()
	_drive(idle, Vector2(20, 0), Vector2(0, 30), "cat", 5.0, log2)
	fails += _ok(log2["prints"].is_empty(), "no prints at all in any other shape")
	return fails


static func _test_skips_a_waypoint_it_cannot_reach() -> int:
	# A companion that never makes headway (stuck on a wall): after the patience it skips the waypoint.
	var g := _guide()
	var log := _log()
	for _i in 15:
		var r := g.update(0.1, Vector2(20, 0), Vector2(0, 30), "fox")
		for e in r["events"]:
			log["events"].append(e)
	for _i in 100:
		var r2 := g.update(0.1, Vector2(20, 0), Vector2(0, 30), "fox")
		for e in r2["events"]:
			log["events"].append(e)
	return _ok(g.next_index >= 1 and "reached" in log["events"], "a waypoint it can't get closer to is skipped, not stood at forever")


static func _test_done_is_final() -> int:
	var g := _guide()
	_drive(g, Vector2(20, 0), null, "fox", 30.0, _log())
	var r := g.update(0.1, g.den(), g.den() + Vector2(30, 0), "fox")
	return _ok(g.is_done() and String(r["command"]) == "" and r["events"].is_empty(), "once done it stays quiet")


static func _test_data_overrides_defaults() -> int:
	var fails := 0
	var g := TrailGuide.new(START, TRAIL, { "species": "wolf" })
	var log := _log()
	_drive(g, Vector2(20, 0), Vector2(0, 30), "fox", 3.0, log)
	fails += _ok(g.phase == TrailGuide.Phase.IDLE, "the species the trail reads is data (a wolf trail ignores a fox)")
	_drive(g, Vector2(20, 0), Vector2(0, 30), "wolf", 0.2, log)
	fails += _ok(g.phase == TrailGuide.Phase.SNIFF, "…and the wolf catches it")
	var from_pairs := TrailGuide.new(Vector2.ZERO, [[10, 0], [20, 0]], {})
	fails += _ok(from_pairs.den() == Vector2(20, 0), "a trail may be authored as [x, y] pairs")
	return fails
