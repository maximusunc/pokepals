class_name TestFollowGuide
## Tests for FollowGuide, the pure logic of Underroot's root-heart: a companion leading you along a planned
## route through the dark, waiting when you fall behind, holding back (and in the end letting go) when you
## push ahead, running out of scent sooner when the bond is young, and noticing the heart from further off
## as the bond deepens. No nodes: the "companion" is a point this test walks toward the target the guide
## names, exactly as the brain's GuideAction does in the game.

const HEART := Vector2(300, 0)
const ROUTE := [Vector2(100, 0), Vector2(200, 0), Vector2(300, 0)]
const CFG := {
	"reach_low": 150.0, "reach_high": 99999.0, "pace_low": 60.0, "pace_high": 100.0,
	"wait_low": 120.0, "wait_high": 180.0, "resume_distance": 70.0, "give_up_distance": 600.0,
	"waypoint_reach": 10.0, "waypoint_patience": 5.0,
	"ahead_margin_low": 60.0, "ahead_margin_high": 100.0, "ahead_lateral": 40.0, "ahead_look": 500.0,
	"ahead_patience_low": 3.0, "ahead_patience_high": 8.0,
	"arrive_player": 50.0, "arrive_companion": 80.0,
	"notice_range_low": 150.0, "notice_range_high": 400.0, "notice_cooldown_low": 10.0, "notice_cooldown_high": 4.0,
	"notice_hold": 2.0,
}


static func run_all() -> int:
	var fails := 0
	print("TestFollowGuide")
	fails += _test_no_route_no_lead()
	fails += _test_leads_the_whole_route_when_you_follow()
	fails += _test_waits_for_a_player_who_falls_behind()
	fails += _test_holds_back_when_you_push_ahead()
	fails += _test_resumes_when_you_fall_in_behind()
	fails += _test_lets_go_if_you_keep_pushing_on()
	fails += _test_off_the_route_is_not_ahead()
	fails += _test_wandering_far_away_lets_go()
	fails += _test_a_young_bond_runs_out_of_scent()
	fails += _test_a_deep_bond_leads_all_the_way()
	fails += _test_asking_again_goes_on_from_where_it_stands()
	fails += _test_arriving_on_your_own_counts()
	fails += _test_pace_grows_with_bond()
	fails += _test_light_tells_the_state()
	fails += _test_notice_range_grows_with_bond()
	fails += _test_notice_holds_then_cools_down()
	fails += _test_no_notice_while_leading()
	fails += _test_done_is_final()
	fails += _test_data_overrides_defaults()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _guide() -> FollowGuide:
	return FollowGuide.new(HEART, CFG)


## Walk the companion toward whatever the guide names (at its pace, or standing when told to hold), `secs`
## seconds in 0.1 s steps, with the player `behind` px behind it on the x axis (or at `player` when given).
## Events are collected into `log`. Returns the companion's final position.
static func _drive(g: FollowGuide, companion: Vector2, player: Variant, bond: float, secs: float, log: Array) -> Vector2:
	var t := 0.0
	while t < secs:
		var p: Vector2 = player if player is Vector2 else companion - Vector2(40, 0)
		var r := g.update(0.1, companion, p, bond)
		for e in r["events"]:
			log.append(e)
		if String(r["command"]) == "guide" and not bool(r["hold"]):
			var to: Vector2 = (r["target"] as Vector2) - companion
			var step := minf(to.length(), float(r["speed"]) * 0.1)
			if to.length() > 0.001:
				companion += to.normalized() * step
		t += 0.1
	return companion


static func _test_no_route_no_lead() -> int:
	var g := _guide()
	var fails := 0
	fails += _ok(not g.begin([], 0.5), "asking with no route to follow does nothing")
	fails += _ok(g.phase == FollowGuide.Phase.IDLE, "...and it stays idle")
	var r := g.update(0.1, Vector2.ZERO, Vector2(-40, 0), 0.5)
	fails += _ok(String(r["command"]) == "", "an idle guide gives no orders")
	return fails


static func _test_leads_the_whole_route_when_you_follow() -> int:
	var g := _guide()
	var fails := 0
	fails += _ok(g.begin(ROUTE, 1.0), "asking with a route starts the lead")
	var log: Array = []
	var end := _drive(g, Vector2.ZERO, null, 1.0, 12.0, log)
	fails += _ok(log.has("reached"), "it reaches the waypoints")
	fails += _ok(log.has("at_heart") or log.has("arrived"), "it brings you to the heart")
	fails += _ok(end.distance_to(HEART) < 15.0, "...and stands there")
	fails += _ok(not log.has("wait") and not log.has("balk"), "a player right behind it never makes it wait or balk")
	return fails


static func _test_waits_for_a_player_who_falls_behind() -> int:
	var g := _guide()
	g.begin(ROUTE, 0.0)
	var fails := 0
	var log: Array = []
	var pos := _drive(g, Vector2.ZERO, Vector2(-300, 0), 0.0, 3.0, log)
	fails += _ok(log.has("wait"), "far behind, it waits")
	fails += _ok(g.phase == FollowGuide.Phase.WAIT, "...and stays waiting")
	var r := g.update(0.1, pos, Vector2(-300, 0), 0.0)
	fails += _ok(bool(r["hold"]) and String(r["command"]) == "guide", "waiting is a guide HOLD")
	log.clear()
	_drive(g, pos, pos - Vector2(30, 0), 0.0, 1.0, log)
	fails += _ok(log.has("resume") and g.phase == FollowGuide.Phase.LEAD, "back within reach, it sets off again")
	return fails


static func _test_holds_back_when_you_push_ahead() -> int:
	var g := _guide()
	g.begin(ROUTE, 0.0)
	var fails := 0
	var log: Array = []
	# the player stands in the tunnel 120 px up the route from the companion at the origin
	var pos := _drive(g, Vector2.ZERO, Vector2(120, 0), 0.0, 0.5, log)
	fails += _ok(log.has("balk"), "walk past it and it balks")
	fails += _ok(g.phase == FollowGuide.Phase.HOLD, "...holding back")
	fails += _ok(pos.distance_to(Vector2.ZERO) < 1.0, "...without taking a step")
	var r := g.update(0.1, pos, Vector2(120, 0), 0.0)
	fails += _ok(bool(r["hold"]), "holding back is a guide HOLD")
	return fails


static func _test_resumes_when_you_fall_in_behind() -> int:
	var g := _guide()
	g.begin(ROUTE, 0.0)
	var fails := 0
	var log: Array = []
	_drive(g, Vector2.ZERO, Vector2(120, 0), 0.0, 1.0, log)
	fails += _ok(g.phase == FollowGuide.Phase.HOLD, "(holding back)")
	log.clear()
	_drive(g, Vector2.ZERO, Vector2(-30, 0), 0.0, 0.3, log)
	fails += _ok(log.has("resume") and g.phase == FollowGuide.Phase.LEAD, "step back behind it and it leads again")
	return fails


static func _test_lets_go_if_you_keep_pushing_on() -> int:
	var g := _guide()
	g.begin(ROUTE, 0.0)
	var fails := 0
	var log: Array = []
	_drive(g, Vector2.ZERO, Vector2(120, 0), 0.0, 5.0, log)
	fails += _ok(log.has("let_go"), "keep pushing on and it lets the lead go")
	fails += _ok(g.phase == FollowGuide.Phase.IDLE and not g.is_done(), "...back to idle, never a failure")
	var r := g.update(0.1, Vector2.ZERO, Vector2(120, 0), 0.0)
	fails += _ok(String(r["command"]) == "", "...and it stops giving orders (the ordinary companion follows you)")
	# a bonded companion is more patient
	var g2 := _guide()
	g2.begin(ROUTE, 1.0)
	var log2: Array = []
	_drive(g2, Vector2.ZERO, Vector2(160, 0), 1.0, 5.0, log2)
	fails += _ok(not log2.has("let_go") and g2.phase == FollowGuide.Phase.HOLD, "a bonded companion holds back for longer (5 s in, still holding)")
	return fails


static func _test_off_the_route_is_not_ahead() -> int:
	var g := _guide()
	g.begin(ROUTE, 0.0)
	var fails := 0
	var log: Array = []
	# 120 px along, but 100 px to the side (the next tunnel over): not on its route
	_drive(g, Vector2.ZERO, Vector2(120, 100), 0.0, 0.5, log)
	fails += _ok(not log.has("balk"), "being alongside, across a wall, is not pushing ahead")
	return fails


static func _test_wandering_far_away_lets_go() -> int:
	var g := _guide()
	g.begin(ROUTE, 0.0)
	var fails := 0
	var log: Array = []
	_drive(g, Vector2.ZERO, Vector2(-700, 0), 0.0, 1.0, log)
	fails += _ok(log.has("lost") and g.phase == FollowGuide.Phase.IDLE, "go far enough away and the lead lapses")
	return fails


static func _test_a_young_bond_runs_out_of_scent() -> int:
	var g := _guide()
	g.begin(ROUTE, 0.0)
	var fails := 0
	var log: Array = []
	var pos := _drive(g, Vector2.ZERO, null, 0.0, 12.0, log)
	fails += _ok(log.has("scent_lost"), "a young bond leads only so far before it loses the scent")
	fails += _ok(pos.x < 260.0, "...short of the heart (%.0f)" % pos.x)
	fails += _ok(g.phase == FollowGuide.Phase.IDLE, "...and rests until asked again")
	return fails


static func _test_a_deep_bond_leads_all_the_way() -> int:
	var g := _guide()
	g.begin(ROUTE, 1.0)
	var log: Array = []
	var pos := _drive(g, Vector2.ZERO, null, 1.0, 12.0, log)
	return _ok(not log.has("scent_lost") and pos.distance_to(HEART) < 15.0, "a deep bond leads the whole way in one ask")


static func _test_asking_again_goes_on_from_where_it_stands() -> int:
	var g := _guide()
	g.begin(ROUTE, 0.0)
	var fails := 0
	var log: Array = []
	var pos := _drive(g, Vector2.ZERO, null, 0.0, 12.0, log)
	fails += _ok(g.phase == FollowGuide.Phase.IDLE, "(rested)")
	var rest: Array = [Vector2(200, 0), Vector2(300, 0)]
	fails += _ok(g.begin(rest, 0.0), "ask again with the route from here")
	log.clear()
	pos = _drive(g, pos, null, 0.0, 6.0, log)
	fails += _ok(pos.distance_to(HEART) < 15.0 or log.has("at_heart"), "it carries on to the heart (%.0f)" % pos.x)
	return fails


static func _test_arriving_on_your_own_counts() -> int:
	var g := _guide()
	var fails := 0
	var r := g.update(0.1, HEART + Vector2(-60, 0), HEART + Vector2(-30, 0), 0.5)
	fails += _ok(g.is_done() and (r["events"] as Array).has("arrived"), "find your own way there, companion in tow: that is arrival")
	var g2 := _guide()
	g2.update(0.1, HEART + Vector2(-200, 0), HEART + Vector2(-30, 0), 0.5)
	fails += _ok(not g2.is_done(), "you alone are not enough: it has to be there too")
	var g3 := _guide()
	g3.update(0.1, HEART + Vector2(-60, 0), HEART + Vector2(-90, 0), 0.5)
	fails += _ok(not g3.is_done(), "nor is it nearly there")
	return fails


static func _test_pace_grows_with_bond() -> int:
	var g := _guide()
	var fails := 0
	fails += _ok(is_equal_approx(g.pace(0.0), 60.0) and is_equal_approx(g.pace(1.0), 100.0), "pace runs from the low value to the high")
	fails += _ok(g.pace(0.5) > g.pace(0.1), "...and rises with bond")
	g.begin(ROUTE, 1.0)
	var r := g.update(0.1, Vector2.ZERO, Vector2(-30, 0), 1.0)
	fails += _ok(is_equal_approx(float(r["speed"]), 100.0), "the order carries the pace")
	return fails


static func _test_light_tells_the_state() -> int:
	var g := _guide()
	g.begin(ROUTE, 0.0)
	var fails := 0
	var r := g.update(0.1, Vector2.ZERO, Vector2(-30, 0), 0.0)
	fails += _ok(float(r["light"]) >= 0.99, "leading, its light shines full")
	var g2 := _guide()
	g2.begin(ROUTE, 0.0)
	var r2 := g2.update(0.1, Vector2.ZERO, Vector2(120, 0), 0.0)
	fails += _ok(float(r2["light"]) < 0.01, "holding back, its light is down")
	var g3 := _guide()
	g3.begin(ROUTE, 0.0)
	var r3 := g3.update(0.1, Vector2.ZERO, Vector2(-200, 0), 0.0)
	fails += _ok(float(r3["light"]) > 0.3 and float(r3["light"]) < 0.9, "waiting, it holds a steady, softer light")
	return fails


static func _test_notice_range_grows_with_bond() -> int:
	var fails := 0
	var player := HEART + Vector2(-250, 0)
	var a := _guide()
	fails += _ok(not bool(a.notice(0.1, player, 0.0)["point"]), "a fresh companion does not sense the heart from 250 px")
	var b := _guide()
	fails += _ok(bool(b.notice(0.1, player, 1.0)["point"]), "a bonded one does")
	var c := _guide()
	fails += _ok(not bool(c.notice(0.1, HEART + Vector2(-500, 0), 1.0)["point"]), "...but not from 500 px")
	return fails


static func _test_notice_holds_then_cools_down() -> int:
	var g := _guide()
	var fails := 0
	var player := HEART + Vector2(-100, 0)
	var first := g.notice(0.1, player, 0.0)
	fails += _ok(bool(first["started"]) and bool(first["point"]), "it points as you come near")
	fails += _ok(is_equal_approx((first["target"] as Vector2).x, HEART.x), "...toward the heart")
	var held := g.notice(1.0, player, 0.0)
	fails += _ok(bool(held["point"]) and not bool(held["started"]), "it holds the point")
	var ended := g.notice(1.5, player, 0.0)
	fails += _ok(not bool(ended["point"]), "then lets it go")
	var cooling := g.notice(5.0, player, 0.0)
	fails += _ok(not bool(cooling["point"]), "and does not point again right away")
	g.notice(6.0, player, 0.0)
	var again := g.notice(0.1, player, 0.0)
	fails += _ok(bool(again["started"]), "but does once the cooldown passes")
	return fails


static func _test_no_notice_while_leading() -> int:
	var g := _guide()
	g.begin(ROUTE, 1.0)
	return _ok(not bool(g.notice(0.1, HEART + Vector2(-50, 0), 1.0)["point"]), "it does not point while it is leading you")


static func _test_done_is_final() -> int:
	var g := _guide()
	g.update(0.1, HEART, HEART, 0.5)
	var fails := 0
	fails += _ok(g.is_done(), "(arrived)")
	fails += _ok(not g.begin(ROUTE, 0.5), "nothing more to lead once it is done")
	var r := g.update(0.1, Vector2.ZERO, Vector2(-40, 0), 0.5)
	fails += _ok(String(r["command"]) == "" and g.is_done(), "done stays done")
	return fails


static func _test_data_overrides_defaults() -> int:
	var g := FollowGuide.new(HEART, { "pace_low": 11.0, "pace_high": 33.0, "bogus": 1 })
	return _ok(is_equal_approx(g.pace(0.0), 11.0) and is_equal_approx(g.pace(1.0), 33.0), "the reveal block overrides the defaults")
