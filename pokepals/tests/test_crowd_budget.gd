class_name TestCrowdBudget
## Pure tests for the client's drawing budget (CrowdBudget): who is drawn fully, who as the person only,
## who not at all, and who is out of sight, with the hysteresis that keeps a peer near a cut from flickering.

static func run_all() -> int:
	var fails := 0
	print("TestCrowdBudget")
	fails += _test_settings_default_and_parse()
	fails += _test_a_small_crowd_is_all_full()
	fails += _test_tiers_by_distance()
	fails += _test_a_peer_with_no_position_is_out()
	fails += _test_an_incumbent_keeps_its_tier_against_a_slightly_nearer_newcomer()
	fails += _test_a_clearly_nearer_newcomer_takes_the_place()
	fails += _test_the_caps_hold_whatever_the_hysteresis()
	fails += _test_interest_cells()
	fails += _test_sight_hysteresis_at_the_block_edge()
	fails += _test_tiers_follow_the_local_player()
	fails += _test_departed_peers_are_forgotten()
	fails += _test_a_large_crowd_is_cheap()
	return fails


static func _line(n: int, step: float, from := Vector2.ZERO) -> Dictionary:
	var peers := {}
	for i in n:
		peers["p%d" % i] = from + Vector2(step * float(i + 1), 0.0)
	return peers


static func _test_settings_default_and_parse() -> int:
	var fails := 0
	var d := CrowdBudget.settings_from(null)
	fails += _check("no block: no cells, 40 full, 80 lite", d["cell"] == 0.0 and d["full"] == 40 and d["lite"] == 80)
	var s := CrowdBudget.settings_from({ "cell": 480, "full": 12, "lite": 30 })
	fails += _check("a block is read", s["cell"] == 480.0 and s["full"] == 12 and s["lite"] == 30)
	var junk := CrowdBudget.settings_from({ "cell": "big", "full": -5, "lite": [1] })
	fails += _check("junk falls back or clamps", junk["cell"] == 0.0 and junk["full"] == 0 and junk["lite"] == 80)
	var b := CrowdBudget.new({ "cell": 480 })
	fails += _check("a raw block configures it", b.cell == 480.0 and b.full == 40 and b.lite == 80)
	return fails


static func _test_a_small_crowd_is_all_full() -> int:
	var b := CrowdBudget.new()
	var t := b.rank(Vector2.ZERO, _line(10, 50.0))
	var all_full := true
	for id in t:
		all_full = all_full and t[id] == CrowdBudget.FULL
	return _check("ten peers in a world with no crowd block are all drawn fully", t.size() == 10 and all_full)


static func _test_tiers_by_distance() -> int:
	var fails := 0
	var b := CrowdBudget.new({ "full": 3, "lite": 4 })
	var t := b.rank(Vector2.ZERO, _line(10, 100.0))
	fails += _check("the nearest three are full", t["p0"] == CrowdBudget.FULL and t["p2"] == CrowdBudget.FULL)
	fails += _check("the next four are lite", t["p3"] == CrowdBudget.LITE and t["p6"] == CrowdBudget.LITE)
	fails += _check("the rest are hidden", t["p7"] == CrowdBudget.HIDDEN and t["p9"] == CrowdBudget.HIDDEN)
	fails += _check("counts add up", b.counts() == [3, 4, 3, 0])
	return fails


static func _test_a_peer_with_no_position_is_out() -> int:
	var b := CrowdBudget.new()
	var t := b.rank(Vector2.ZERO, { "a": Vector2(10, 0), "b": null })
	return _check("a peer with no position is out, and an unknown one too", t["b"] == CrowdBudget.OUT and b.tier_of("nobody") == CrowdBudget.OUT)


static func _test_an_incumbent_keeps_its_tier_against_a_slightly_nearer_newcomer() -> int:
	var b := CrowdBudget.new({ "full": 1, "lite": 0 })
	b.rank(Vector2.ZERO, { "old": Vector2(200, 0) })
	# A newcomer 20 px nearer: not clearly nearer, so the one already drawn keeps its place.
	var t := b.rank(Vector2.ZERO, { "old": Vector2(200, 0), "new": Vector2(180, 0) })
	var fails := _check("the incumbent stays full", t["old"] == CrowdBudget.FULL and t["new"] == CrowdBudget.HIDDEN)
	# And it keeps holding while the two jostle a little.
	t = b.rank(Vector2.ZERO, { "old": Vector2(205, 0), "new": Vector2(175, 0) })
	fails += _check("and holds through small moves", t["old"] == CrowdBudget.FULL)
	return fails


static func _test_a_clearly_nearer_newcomer_takes_the_place() -> int:
	var b := CrowdBudget.new({ "full": 1, "lite": 1 })
	b.rank(Vector2.ZERO, { "old": Vector2(200, 0) })
	var t := b.rank(Vector2.ZERO, { "old": Vector2(200, 0), "new": Vector2(100, 0) })
	return _check("a newcomer half the distance away takes the full place; the old one drops to lite",
		t["new"] == CrowdBudget.FULL and t["old"] == CrowdBudget.LITE)


static func _test_the_caps_hold_whatever_the_hysteresis() -> int:
	var b := CrowdBudget.new({ "full": 5, "lite": 5 })
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ok := true
	for round in 20:
		var peers := {}
		for i in 40:
			peers["p%d" % i] = Vector2(rng.randf_range(-600, 600), rng.randf_range(-600, 600))
		b.rank(Vector2.ZERO, peers)
		var c := b.counts()
		ok = ok and c[0] == 5 and c[1] == 5 and c[2] == 30
	return _check("never more than full and lite are drawn, as the crowd shuffles", ok)


static func _test_interest_cells() -> int:
	var fails := 0
	var b := CrowdBudget.new({ "cell": 100 })
	# We stand in cell (0, 0); the 3 x 3 block round it is -100..200 on each axis.
	var t := b.rank(Vector2(50, 50), {
		"here": Vector2(60, 60), "next": Vector2(150, -50), "corner": Vector2(-99, 199),
		"two_away": Vector2(250, 50), "far": Vector2(50, -250),
	})
	fails += _check("our own cell and the neighbours are in sight",
		t["here"] == CrowdBudget.FULL and t["next"] == CrowdBudget.FULL and t["corner"] == CrowdBudget.FULL)
	fails += _check("two cells away is out of sight", t["two_away"] == CrowdBudget.OUT and t["far"] == CrowdBudget.OUT)
	return fails


static func _test_sight_hysteresis_at_the_block_edge() -> int:
	var fails := 0
	var b := CrowdBudget.new({ "cell": 100 })
	# A new peer just past the block's edge is not let in...
	var t := b.rank(Vector2(50, 50), { "edge": Vector2(205, 50) })
	fails += _check("a new peer just past the edge is out", t["edge"] == CrowdBudget.OUT)
	# ...but one already in sight that steps just past the edge stays (margin 20 px here).
	b.rank(Vector2(50, 50), { "edge": Vector2(195, 50) })
	t = b.rank(Vector2(50, 50), { "edge": Vector2(210, 50) })
	fails += _check("a peer already in sight stays a little past the edge", t["edge"] == CrowdBudget.FULL)
	t = b.rank(Vector2(50, 50), { "edge": Vector2(230, 50) })
	fails += _check("and leaves once clearly past it", t["edge"] == CrowdBudget.OUT)
	return fails


static func _test_tiers_follow_the_local_player() -> int:
	var fails := 0
	var b := CrowdBudget.new({ "full": 2, "lite": 2 })
	var peers := { "w1": Vector2(-100, 0), "w2": Vector2(-120, 0), "e1": Vector2(1000, 0), "e2": Vector2(1020, 0), "m": Vector2(450, 0) }
	var t := b.rank(Vector2.ZERO, peers)
	fails += _check("near the west pair, they are full", t["w1"] == CrowdBudget.FULL and t["w2"] == CrowdBudget.FULL and t["e1"] == CrowdBudget.LITE)
	t = b.rank(Vector2(1000, 0), peers)
	fails += _check("walk east and the east pair become full", t["e1"] == CrowdBudget.FULL and t["e2"] == CrowdBudget.FULL)
	fails += _check("and the west pair fall back", t["w1"] == CrowdBudget.LITE and t["w2"] == CrowdBudget.HIDDEN)
	return fails


static func _test_departed_peers_are_forgotten() -> int:
	var b := CrowdBudget.new()
	b.rank(Vector2.ZERO, { "a": Vector2(10, 0), "b": Vector2(20, 0) })
	b.rank(Vector2.ZERO, { "a": Vector2(10, 0) })
	return _check("a peer left out of an ask is forgotten", b.tier_of("b") == CrowdBudget.OUT and b.counts() == [1, 0, 0, 0])


static func _test_a_large_crowd_is_cheap() -> int:
	var b := CrowdBudget.new({ "cell": 480 })
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var peers := {}
	for i in 2000:
		peers["p%d" % i] = Vector2(rng.randf_range(-700, 700), rng.randf_range(-700, 700))
	b.rank(Vector2.ZERO, peers)
	var t0 := Time.get_ticks_usec()
	b.rank(Vector2(10, 0), peers)
	var us := Time.get_ticks_usec() - t0
	print("    (2000 peers ranked in %.2f ms)" % (float(us) / 1000.0))
	var c := b.counts()
	# Generous: it is a few ms on a desktop; this only catches an accidental quadratic.
	return _check("2000 peers rank quickly and the caps hold", us < 100000 and c[0] == 40 and c[1] == 80)


static func _check(label: String, cond: bool) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
