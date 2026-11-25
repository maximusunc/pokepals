class_name TestCircuit
## Tests for Ohmstead's pure logic: CircuitBoard (the ribbon boards' rules and the hint solver) and RunnerRoutes
## (where the runners are, by the clock). No nodes. The board is held to the SAME vectors as the server's Elixir
## twin, Server.Circuit.Board (tests/world_fixtures/circuit_vectors.json).


static func run_all() -> int:
	var fails := 0
	print("TestCircuit")
	fails += _test_board_matches_the_shared_vectors()
	fails += _test_hints_match_the_shared_vectors()
	fails += _test_hint_walks_a_board_closed()
	fails += _test_stuck()
	fails += _test_node_near()
	fails += _test_route_length_and_wrap()
	fails += _test_runners_spread_and_reverse()
	fails += _test_sidestep()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _ints(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(v))
	return out


static func _test_board_matches_the_shared_vectors() -> int:
	var doc: Dictionary = WorldData.load_json("res://tests/world_fixtures/circuit_vectors.json")
	var fails := 0
	for c in doc["cases"]:
		var b := CircuitBoard.from_dict(c["board"])
		var good := true
		for s in c["steps"]:
			var node := int(s["node"])
			if String(s["op"]) == "run":
				var lit: Array = b.run_to(node)
				if _ints(lit) != _ints(s["lit"]):
					good = false
				b.extend(lit)
			else:
				if b.wind_to(node) != bool(s["ok"]):
					good = false
			if _ints(b.path) != _ints(s["path"]) or b.is_closed() != bool(s["closed"]):
				good = false
		fails += _ok(good, "vectors: " + String(c["name"]))
	return fails


static func _test_hints_match_the_shared_vectors() -> int:
	var doc: Dictionary = WorldData.load_json("res://tests/world_fixtures/circuit_vectors.json")
	var good := true
	for h in doc["hints"]:
		var d: Dictionary = (h["board"] as Dictionary).duplicate()
		d["path"] = h["path"]
		if CircuitBoard.from_dict(d).hint() != int(h["hint"]):
			good = false
	return _ok(good, "the hint: the source first, the way on, or -2 when the ribbon has to wind back")


static func _test_hint_walks_a_board_closed() -> int:
	# Following the hint from nothing closes the board, on the sector's board and on a bigger one with holes.
	var fails := 0
	for d in [
		{ "cols": 5, "rows": 4, "holes": [15, 16], "source": 10, "sink": 17 },
		{ "cols": 7, "rows": 5, "holes": [0, 34], "source": 1, "sink": 33 },
	]:
		var b := CircuitBoard.from_dict(d)
		var steps := 0
		while not b.is_closed() and steps < 60:
			var n := b.hint(20000)
			if n < 0:
				break
			b.extend(b.run_to(n))
			steps += 1
		fails += _ok(b.is_closed() and b.path.size() == b.live_count(), "following the hint closes a %d by %d board" % [int(d["cols"]), int(d["rows"])])
	var closed := CircuitBoard.from_dict({ "cols": 2, "rows": 1, "holes": [], "source": 0, "sink": 1, "path": [0, 1] })
	fails += _ok(closed.hint() == -1, "a closed board has no hint")
	return fails


static func _test_stuck() -> int:
	var b := CircuitBoard.from_dict({ "cols": 3, "rows": 3, "holes": [], "source": 0, "sink": 8, "path": [0, 1, 2, 5, 8, 7, 6, 3, 4] })
	var fails := _ok(b.is_stuck() and not b.is_closed(), "every node lit with the head off the sink is stuck, not closed")
	b.set_path([0, 1])
	fails += _ok(not b.is_stuck(), "a ribbon with somewhere to go is not stuck")
	b.clear()
	fails += _ok(not b.is_stuck() and b.head() == -1, "no ribbon is not stuck")
	return fails


static func _test_node_near() -> int:
	var b := CircuitBoard.from_dict({ "cols": 5, "rows": 4, "holes": [15, 16], "source": 10, "sink": 17 })
	var o := Vector2(832, -736)
	var fails := _ok(b.pos_of(7, o, 64.0) == Vector2(832 + 128, -736 + 64), "node 7 of a 5-wide board is at column 2, row 1")
	fails += _ok(b.node_near(Vector2(965, -670), o, 64.0, 22.0) == 7, "a tap near a node finds it")
	fails += _ok(b.node_near(Vector2(992, -640), o, 64.0, 22.0) == -1, "a tap between nodes finds none")
	fails += _ok(b.node_near(Vector2(832, -544), o, 64.0, 22.0) == -1, "a tap on a hole finds none")
	fails += _ok(b.node_near(Vector2(700, -736), o, 64.0, 22.0) == -1, "a tap off the board finds none")
	return fails


static func _square() -> Array:
	return [Vector2(0, 0), Vector2(128, 0), Vector2(128, 128), Vector2(0, 128)]


static func _test_route_length_and_wrap() -> int:
	var r := _square()
	var fails := _ok(is_equal_approx(RunnerRoutes.length(r), 512.0), "a 128 square is 512 round")
	var a := RunnerRoutes.at(r, 64.0)
	fails += _ok((a["pos"] as Vector2).is_equal_approx(Vector2(64, 0)) and (a["dir"] as Vector2).is_equal_approx(Vector2.RIGHT), "64 along is halfway down the first leg, heading east")
	var b := RunnerRoutes.at(r, 128.0 + 32.0)
	fails += _ok((b["pos"] as Vector2).is_equal_approx(Vector2(128, 32)) and (b["dir"] as Vector2).is_equal_approx(Vector2.DOWN), "past the corner it heads south")
	var c := RunnerRoutes.at(r, 512.0 * 3.0 + 64.0)
	fails += _ok((c["pos"] as Vector2).is_equal_approx(Vector2(64, 0)), "the route wraps")
	var back := RunnerRoutes.at(r, -32.0)
	fails += _ok((back["pos"] as Vector2).is_equal_approx(Vector2(0, 32)), "and wraps backward")
	return fails


static func _test_runners_spread_and_reverse() -> int:
	var r := _square()
	var t := 1_800_000_000.0   # a clock reading as large as a real one
	var a := RunnerRoutes.runner(r, 0, 2, 42.0, t)
	var b := RunnerRoutes.runner(r, 1, 2, 42.0, t)
	var fails := _ok(is_equal_approx((a["pos"] as Vector2).distance_to(b["pos"]), 128.0 * sqrt(2.0)) or is_equal_approx((a["pos"] as Vector2).distance_to(b["pos"]), 128.0),
		"two runners on a square route are half the route apart")
	var later := RunnerRoutes.runner(r, 0, 2, 42.0, t + 1.0)
	fails += _ok(absf((later["pos"] as Vector2).distance_to(a["pos"]) - 42.0) < 0.01 or (later["pos"] as Vector2).distance_to(a["pos"]) < 42.0,
		"a second later a runner is its speed further on (or round a corner)")
	var same := RunnerRoutes.runner(r, 0, 2, 42.0, t)
	fails += _ok((same["pos"] as Vector2).is_equal_approx(a["pos"]), "the same time gives the same place")
	var rev := RunnerRoutes.runner(r, 0, 2, 42.0, 1.0, true)
	fails += _ok((rev["pos"] as Vector2).is_equal_approx(Vector2(0, 42)) and (rev["dir"] as Vector2).is_equal_approx(Vector2.DOWN), "a reversed route runs the other way round")
	return fails


static func _test_sidestep() -> int:
	var off := RunnerRoutes.sidestep(Vector2(0, 0), Vector2.RIGHT, Vector2(4, 10), 46.0, 12.0)
	var fails := _ok(off.x == 0.0 and off.y < -4.0, "a runner leans off its line, away from someone standing beside it")
	fails += _ok(RunnerRoutes.sidestep(Vector2(0, 0), Vector2.RIGHT, Vector2(200, 0), 46.0, 12.0) == Vector2.ZERO, "and not at all when nobody is near")
	var edge := RunnerRoutes.sidestep(Vector2(0, 0), Vector2.RIGHT, Vector2(0, 45), 46.0, 12.0)
	fails += _ok(edge.length() < 0.2, "the lean is gone by the edge of its radius")
	return fails
