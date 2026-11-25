class_name TestGlyphNotice
## Tests for GlyphNotice, the pure logic of Glyphfall's wrong glyph: a companion that notices one wrong
## character in a world made of text, stops and looks at it, and looks again and again as you close in, until
## you are near enough to see it for yourself. No nodes: the tests feed it positions exactly as the
## MisprintDirector does.

const GLYPH := Vector2(1000, 0)
const CFG := {
	"notice_range_low": 150.0, "notice_range_high": 400.0, "notice_cooldown_low": 10.0, "notice_cooldown_high": 4.0,
	"notice_hold": 2.0, "near_radius": 100.0, "near_cooldown_factor": 0.5, "companion_radius": 150.0,
	"find_radius": 30.0, "glow_radius": 90.0,
}


static func run_all() -> int:
	var fails := 0
	print("TestGlyphNotice")
	fails += _test_far_away_it_notices_nothing()
	fails += _test_in_range_it_stops_and_looks()
	fails += _test_the_look_ends_and_comes_again()
	fails += _test_range_grows_with_bond()
	fails += _test_a_bonded_companion_looks_more_often()
	fails += _test_it_looks_more_often_close_in()
	fails += _test_it_must_be_beside_you()
	fails += _test_grass_until_it_has_looked()
	fails += _test_the_glyph_shines_as_you_close_in()
	fails += _test_found_once_and_for_good()
	fails += _test_data_overrides_defaults()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _notice() -> GlyphNotice:
	return GlyphNotice.new(GLYPH, CFG)


## Stand at `at` with the companion 30 px beside you for `secs`, in 0.1 s steps. Returns the last result;
## events are appended to `log`, and `looked` counts the frames spent looking.
static func _stand(n: GlyphNotice, at: Vector2, secs: float, bond: float, log: Array = [], looked: Array = [0]) -> Dictionary:
	var r := {}
	var t := 0.0
	while t < secs:
		r = n.update(0.1, at, at + Vector2(-30, 0), bond)
		log.append_array(r["events"])
		if bool(r["point"]):
			looked[0] += 1
		t += 0.1
	return r


static func _test_far_away_it_notices_nothing() -> int:
	var n := _notice()
	var log: Array = []
	var r := _stand(n, GLYPH + Vector2(-900, 0), 30.0, 1.0, log)
	return _ok(not bool(r["point"]) and log.is_empty() and not n.has_noticed(), "far from the glyph it notices nothing")


static func _test_in_range_it_stops_and_looks() -> int:
	var n := _notice()
	var r := n.update(0.1, GLYPH + Vector2(-120, 0), GLYPH + Vector2(-150, 0), 0.0)
	return _ok(bool(r["point"]) and (r["target"] as Vector2) == GLYPH and r["events"] == ["notice"],
		"in range, it stops and looks at the glyph")


static func _test_the_look_ends_and_comes_again() -> int:
	var n := _notice()
	var log: Array = []
	var at := GLYPH + Vector2(-140, 0)
	var r := _stand(n, at, 2.5, 0.0, log)
	var fails := _ok(not bool(r["point"]), "a look lasts its hold and then it walks on")
	_stand(n, at, 12.0, 0.0, log)
	fails += _ok(log.count("notice") == 1 and log.count("again") >= 1, "after the cooldown it looks again (said differently)")
	return fails


static func _test_range_grows_with_bond() -> int:
	var n := _notice()
	var at := GLYPH + Vector2(-300, 0)
	var fresh := n.update(0.1, at, at, 0.0)
	var bonded := _notice().update(0.1, at, at, 1.0)
	return _ok(not bool(fresh["point"]) and bool(bonded["point"]) and n.notice_range(1.0) > n.notice_range(0.0),
		"a bonded companion notices from further off")


static func _test_a_bonded_companion_looks_more_often() -> int:
	var at := GLYPH + Vector2(-140, 0)
	var fresh: Array = []
	var bonded: Array = []
	_stand(_notice(), at, 60.0, 0.0, fresh)
	_stand(_notice(), at, 60.0, 1.0, bonded)
	return _ok(bonded.size() > fresh.size(), "a bonded companion looks more often (%d against %d)" % [bonded.size(), fresh.size()])


static func _test_it_looks_more_often_close_in() -> int:
	var n := _notice()
	return _ok(n.cooldown(0.5, 40.0) < n.cooldown(0.5, 140.0) and is_equal_approx(n.cooldown(0.0, 500.0), 10.0),
		"the looks come quicker the nearer you are")


static func _test_it_must_be_beside_you() -> int:
	var n := _notice()
	var at := GLYPH + Vector2(-100, 0)
	var r := n.update(0.1, at, at + Vector2(-400, 0), 1.0)
	return _ok(not bool(r["point"]), "a companion that has wandered off shows you nothing")


static func _test_grass_until_it_has_looked() -> int:
	var n := _notice()
	# on the glyph, but the companion is far away: it is only grass
	var r := n.update(0.1, GLYPH, GLYPH + Vector2(-600, 0), 1.0)
	return _ok(not bool(r["found"]) and is_zero_approx(float(r["glow"])), "until it has looked, the glyph is only grass to you")


static func _test_the_glyph_shines_as_you_close_in() -> int:
	var n := _notice()
	_stand(n, GLYPH + Vector2(-140, 0), 0.2, 0.5)
	var far := float(_stand(n, GLYPH + Vector2(-140, 0), 0.1, 0.5)["glow"])
	var mid := float(_stand(n, GLYPH + Vector2(-60, 0), 0.1, 0.5)["glow"])
	return _ok(is_zero_approx(far) and mid > 0.1 and mid < 1.0, "once noticed, it catches the light as you close in (%.2f)" % mid)


static func _test_found_once_and_for_good() -> int:
	var n := _notice()
	var log: Array = []
	_stand(n, GLYPH + Vector2(-140, 0), 0.2, 0.5, log)
	var r := _stand(n, GLYPH + Vector2(-20, 0), 0.3, 0.5, log)
	var fails := _ok(bool(r["found"]) and is_equal_approx(float(r["glow"]), 1.0) and not bool(r["point"]) and n.is_found(),
		"walk to where it looked and you see it")
	_stand(n, GLYPH + Vector2(-500, 0), 20.0, 0.5, log)
	fails += _ok(log.count("found") == 1 and log.count("near") == 1 and n.is_found(), "found is said once, and stays found")
	return fails


static func _test_data_overrides_defaults() -> int:
	var n := GlyphNotice.new(GLYPH, { "notice_range_low": 50.0, "notice_range_high": 60.0, "made_up": 1.0 })
	return _ok(is_equal_approx(n.notice_range(0.0), 50.0) and is_equal_approx(n.notice_range(1.0), 60.0), "the world's data sets the numbers")
