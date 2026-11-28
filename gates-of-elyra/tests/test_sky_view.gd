class_name TestSkyView
## Tests for SkyView, the pure logic of Loftreach's secret: the companion's flight (ascend, stay, descend), the
## bond scaling of how long and how high, holding and ending early, "seen" only when the bird has really looked
## at the islet and the head of the bridge from high enough, and the companion noticing the unreachable islet.

const HOME := Vector2(0, 0)
const VANTAGE := Vector2(800, -400)
const NEST := Vector2(1200, -600)
const HEAD := Vector2(500, -250)
const VIEW := Vector2(640, 360)
const CFG := {
	"rise_secs": 1.0, "fly_speed": 1000.0, "travel_min": 0.5, "travel_max": 2.0, "stay_low": 3.0, "stay_high": 6.0,
	"hold_add": 2.0, "stay_cap": 10.0, "descend_secs": 1.0, "min_flight": 0.4, "zoom_low": 0.40, "zoom_high": 0.30,
	"see_alt": 0.7, "see_secs": 1.0, "view_margin": 20.0, "reveal_secs": 2.0, "after_reveal_stay": 1.0,
	"notice_range_low": 500.0, "notice_range_high": 1000.0, "notice_cooldown_low": 10.0, "notice_cooldown_high": 4.0, "notice_hold": 2.0,
}


static func run_all() -> int:
	var fails := 0
	print("TestSkyView")
	fails += _test_a_flight_goes_up_stays_and_comes_home()
	fails += _test_bond_makes_it_stay_longer_and_climb_higher()
	fails += _test_a_tap_ends_it_but_not_at_once()
	fails += _test_holding_extends_the_stay_up_to_a_cap()
	fails += _test_it_sees_only_what_is_in_view_from_high_enough()
	fails += _test_seeing_keeps_it_up_for_the_reveal()
	fails += _test_the_picture_fades_in_with_altitude()
	fails += _test_it_comes_back_to_where_the_companion_is_now()
	fails += _test_noticing_the_islet()
	fails += _test_a_second_launch_while_up_is_refused()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _make() -> SkyView:
	return SkyView.new(VANTAGE, [NEST, HEAD], CFG)


## Step `seconds`; returns { events, last }.
static func _run(v: SkyView, seconds: float, home := HOME, bond := 0.5) -> Dictionary:
	var events: Array = []
	var last := {}
	var t := 0.0
	while t < seconds:
		last = v.update(0.05, home, VIEW, bond)
		events.append_array(last["events"])
		t += 0.05
	return { "events": events, "last": last }


static func _test_a_flight_goes_up_stays_and_comes_home() -> int:
	var f := 0
	var v := _make()
	f += _ok(not v.is_flying(), "grounded to begin with")
	f += _ok(v.launch(HOME, 0.5), "it launches")
	var r := _run(v, 1.6)
	f += _ok(v.phase == SkyView.Phase.STAY and is_equal_approx(float(r["last"]["alt"]), 1.0), "after the climb it hangs at the top")
	f += _ok((r["last"]["pos"] as Vector2).distance_to(VANTAGE) < 1.0, "...over the vantage")
	r = _run(v, 14.0)
	f += _ok(not v.is_flying() and "landed" in r["events"], "after its stay it lands (events %s)" % str(r["events"]))
	f += _ok((r["last"]["pos"] as Vector2).distance_to(HOME) < 1.0, "...where it began")
	return f


static func _test_bond_makes_it_stay_longer_and_climb_higher() -> int:
	var f := 0
	var v := _make()
	f += _ok(v.stay_for(1.0) > v.stay_for(0.0) + 2.0, "a bonded companion stays up longer (%.1f vs %.1f)" % [v.stay_for(1.0), v.stay_for(0.0)])
	f += _ok(v.zoom_top(1.0) < v.zoom_top(0.0), "...and climbs higher, the view wider (%.2f vs %.2f)" % [v.zoom_top(1.0), v.zoom_top(0.0)])
	f += _ok(is_equal_approx(v.zoom_at(0.0, 0.5), 1.0), "the ground view is the ordinary one")
	return f


static func _test_a_tap_ends_it_but_not_at_once() -> int:
	var f := 0
	var v := _make()
	v.launch(HOME, 0.5)
	_run(v, 0.1)
	f += _ok(not v.request_end(), "a tap in the first instant is ignored (the one that launched it)")
	_run(v, 0.6)
	f += _ok(v.request_end() and v.phase == SkyView.Phase.DESCEND, "a tap after that turns it for home")
	var r := _run(v, 1.2)
	f += _ok(not v.is_flying() and "landed" in r["events"], "...and it lands")
	return f


static func _test_holding_extends_the_stay_up_to_a_cap() -> int:
	var f := 0
	var v := _make()
	v.launch(HOME, 0.0)
	_run(v, 1.6)   # now in STAY with about 3 s to go
	var extended := 0
	for _i in 10:
		if v.hold():
			extended += 1
	f += _ok(extended >= 3 and extended <= 6, "holding adds time, a few presses at most (%d)" % extended)
	var r := _run(v, 20.0)
	f += _ok("landed" in r["events"], "...and never forever")
	return f


static func _test_it_sees_only_what_is_in_view_from_high_enough() -> int:
	var f := 0
	var v := _make()
	v.launch(HOME, 0.5)
	var r := _run(v, 4.0)
	f += _ok("seen" in r["events"] and v.is_seen(), "from the vantage, with both in view, it sees the way")
	# a view too small to take both in: never seen
	var small := SkyView.new(VANTAGE, [NEST, HEAD], CFG.merged({ "zoom_low": 0.9, "zoom_high": 0.9 }, true))
	small.launch(HOME, 0.5)
	var events: Array = []
	for _i in 120:
		events.append_array(small.update(0.05, HOME, VIEW, 0.5)["events"])
	f += _ok(not ("seen" in events), "a view that cannot hold the islet and the bridge head sees nothing")
	var far := SkyView.new(VANTAGE, [Vector2(5000, 5000)], CFG)
	far.launch(HOME, 0.5)
	events = []
	for _i in 120:
		events.append_array(far.update(0.05, HOME, VIEW, 0.5)["events"])
	f += _ok(not ("seen" in events), "an islet out of the view is not seen")
	return f


static func _test_seeing_keeps_it_up_for_the_reveal() -> int:
	var f := 0
	var v := _make()
	v.launch(HOME, 0.0)   # stay_low is 3 s; the climb takes 1 s
	var seen_at := -1.0
	var landed_at := -1.0
	var t := 0.0
	while t < 14.0 and landed_at < 0.0:
		var r := v.update(0.05, HOME, VIEW, 0.0)
		t += 0.05
		if "seen" in r["events"] and seen_at < 0.0:
			seen_at = t
		if "landed" in r["events"]:
			landed_at = t
	f += _ok(seen_at > 0.0, "it saw the way (t = %.1f)" % seen_at)
	f += _ok(landed_at - seen_at >= 3.0, "it stays up to watch the reveal (%.1f s after seeing)" % (landed_at - seen_at))
	return f


static func _test_the_picture_fades_in_with_altitude() -> int:
	var f := 0
	var v := _make()
	f += _ok(v.picture_at(0.0) == 0.0 and v.picture_at(0.2) == 0.0, "no picture near the ground")
	f += _ok(v.picture_at(1.0) == 1.0, "all of it at the top")
	f += _ok(v.picture_at(0.5) > 0.0 and v.picture_at(0.5) < 1.0, "part of it between")
	return f


static func _test_it_comes_back_to_where_the_companion_is_now() -> int:
	var f := 0
	var v := _make()
	v.launch(HOME, 0.5)
	_run(v, 2.0)
	v.request_end()
	var elsewhere := Vector2(-300, 120)
	var r := _run(v, 1.2, elsewhere)
	f += _ok((r["last"]["pos"] as Vector2).distance_to(elsewhere) < 1.0, "it lands beside the companion, wherever that is now")
	return f


static func _test_noticing_the_islet() -> int:
	var f := 0
	var v := _make()
	var r := v.notice(0.1, NEST + Vector2(2000, 0), 0.5)
	f += _ok(not r["point"], "out of range, nothing")
	r = v.notice(0.1, NEST + Vector2(400, 0), 0.5)
	f += _ok(r["point"] and r["started"], "in range it stops and looks toward the islet")
	f += _ok((r["target"] as Vector2).is_equal_approx(NEST), "...at the islet itself")
	var held := 0
	for _i in 60:
		if v.notice(0.1, NEST + Vector2(400, 0), 0.5)["point"]:
			held += 1
	f += _ok(held >= 15 and held <= 22, "it holds the look about its hold time, then cools down (%d frames)" % held)
	f += _ok(not _make().notice(0.1, NEST + Vector2(700, 0), 0.0)["point"], "a new bond notices from nearer...")
	f += _ok(_make().notice(0.1, NEST + Vector2(700, 0), 1.0)["point"], "...than a deep one")
	var seen := _make()
	seen.mark_seen()
	f += _ok(not seen.notice(0.1, NEST + Vector2(100, 0), 0.5)["point"], "once the way is seen it stops pointing")
	return f


static func _test_a_second_launch_while_up_is_refused() -> int:
	var f := 0
	var v := _make()
	v.launch(HOME, 0.5)
	f += _ok(not v.launch(HOME, 0.5), "already flying: refused")
	return f
