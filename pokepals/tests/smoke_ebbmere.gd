extends SceneTree
## Headless smoke test for EBBMERE, the tidal flats. Loads the real World scene from the test fixture as if we'd
## come through the Vale's Gateway and checks what makes it its own place:
##   * it re-skins itself (sand, dune trees, the lighthouse) and walls the open sea's edge with invisible posts;
##   * the tide layer is up and follows the shared clock: the level at high water and at the lowest, driven here
##     through the director's debug clock;
##   * the secret is the sand-dollar (reveal "tide"): hidden at first; the far bar is only uncovered in the
##     lowest window; a companion that can dig, sent to it, brings it up, a cat cannot, and outside the window
##     there is nothing to dig;
##   * ordinary dig spots give up shells; and the world gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_ebbmere.gd

const EBBMERE_ID := "14141414-1414-1414-1414-141414141414"

var _world: Node
var _frames := 0
var _done := false


func _process(_delta: float) -> bool:
	_frames += 1
	if _done:
		return true

	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(EBBMERE_ID, WorldData.load_json("res://tests/world_fixtures/ebbmere.json"))
		router.current_world = EBBMERE_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", EBBMERE_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/ebbmere.json")
	var tide: Dictionary = spec["tide"]
	var dig: Dictionary = spec["dig"]
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]

	var ground: Color = _world._style.color("ground_top")
	fails += _check(ground.r > 0.7 and ground.b < ground.r, "the ground is sand")
	var trees := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
	fails += _check(trees >= 100, "dune pines, thorn and tamarisk stand at the back of the beach, and the lighthouse (%d)" % trees)
	var posts := 0
	for p in spec["props"]:
		if String(p["type"]) == "eb_shore":
			posts += 1
	fails += _check(posts > 150 and not bool(spec["collision"]["pond_blocks"]), "the open sea's edge is walled by invisible posts (%d)" % posts)

	# The tide: the same numbers in the spec's tide and the secret's reveal, so the client and the server agree.
	var same := true
	for k in ["period_s", "epoch_s", "level_low", "level_high", "yield_level"]:
		same = same and is_equal_approx(float(tide[k]), float(reveal["tide"][k]))
	fails += _check(same, "the server's low-window check reads the very tide the client draws")

	var dir = _world._secret_dir
	var td = dir.tide_director()
	fails += _check(td != null, "the tide director is running")
	if td == null:
		return _finish(fails)
	var layer = td.layer()
	fails += _check(layer != null and layer.extent().size.y > 600.0, "the sea is drawn over the flats")
	var field = td.field()
	fails += _check(not field.is_empty() and field.deep_elev > 0.2, "the baked seabed is read")
	var dollar_pos := WorldData.to_vec2(dig["spots"][0]["position"])
	fails += _check(String(dig["spots"][0]["id"]) == String(dig["dollar_spot"]), "the first spot is the far bar's")
	var bar_elev: float = field.elev_at(dollar_pos)
	fails += _check(absf(bar_elev - (float(tide["yield_level"]) + float(tide["expose_margin"]))) < 0.006, "the far bar's top is at the lowest-tide level (%.4f)" % bar_elev)
	fails += _check(not field.is_deep(WorldData.to_vec2(spec["player_spawn"])) and field.elev_at(WorldData.to_vec2(spec["player_spawn"])) > float(tide["level_high"]), "you arrive on ground the highest tide never reaches")
	var in_sea := 0
	for p in spec["props"]:
		if not String(p["id"]).begins_with("shore_") and field.is_deep(WorldData.to_vec2(p["position"])):
			in_sea += 1
	fails += _check(in_sea == 0, "nothing stands in the open sea")

	var period_ms := int(float(tide["period_s"]) * 1000.0)
	var cycle_base := 5000 * period_ms
	# ── high water: the flats are under the sea, nothing is uncovered, the secret is hidden
	td.debug_set_time_ms(cycle_base)
	td.update(0.05)
	fails += _check(is_equal_approx(td.level(), float(tide["level_high"])) and is_equal_approx(layer.level(), td.level()), "at high water the sea is at its highest, in the layer too")
	var high_visible: int = td.visible_spots().size()
	fails += _check(not _has_secret_entry(), "the sand-dollar is hidden until it is dug")

	# ── the lowest water: the far bar is bare, a companion that can dig brings it up
	td.debug_set_time_ms(cycle_base + period_ms / 2)
	td.update(0.05)
	fails += _check(is_equal_approx(td.level(), float(tide["level_low"])) and TideClock.in_low_window(tide, td.now_ms()), "at the lowest the level is the lowest and the low window is open")
	var low_visible: int = td.visible_spots().size()
	fails += _check(low_visible > high_visible and low_visible >= 6, "more of the flats are uncovered at low water (%d vs %d)" % [low_visible, high_visible])
	var bar_up := false
	for s in td.visible_spots():
		bar_up = bar_up or String(s["id"]) == "bar_dollar"
	fails += _check(bar_up, "the far bar is bare at the lowest water")

	var comp = _world._companion
	var player = _world._player
	comp._brain.get_self().met = true
	# the companion is a bird: it cannot dig; a tap on the (seen) spot sends it over with the cue
	player.position = dollar_pos + Vector2(-30, 40)
	comp.position = dollar_pos + Vector2(-20, 30)
	comp.instruct_form("bird", 0)
	td.update(0.05)
	var cant: bool = td.on_spot_tap(dollar_pos)
	fails += _check(cant and td._order.is_empty(), "a bird is sent over but is not sent to dig (the cue)")
	for _i in 30:
		td.update(0.05)
	fails += _check(not _has_secret_entry(), "...and the sand-dollar stays buried")
	# a fox can
	comp.instruct_form("fox", 0)
	var ordered: bool = td.on_spot_tap(dollar_pos)
	fails += _check(ordered and not td._order.is_empty(), "a fox taps-to-dig: an order is in flight")
	comp.position = dollar_pos + Vector2(10, 8)
	for _i in 80:
		td.update(0.05)
		if _has_secret_entry():
			break
	fails += _check(_has_secret_entry(), "the fox digs the far bar in the lowest water and the sand-dollar comes up")

	# ── outside the window the bar is covered and there is nothing to tap
	td.debug_set_time_ms(cycle_base + int(0.3 * period_ms))
	td.update(0.05)
	var covered := true
	for s in td.visible_spots():
		covered = covered and String(s["id"]) != "bar_dollar"
	fails += _check(covered and not td.on_spot_tap(dollar_pos), "ebbing, the far bar is still under the sea: nothing to dig")
	fails += _check(td.level() > float(tide["yield_level"]) + 0.05, "(the level is well over the lowest)")

	# ── an ordinary spot, in a later tide: it gives up a shell or a crab, never the sand-dollar
	td.debug_set_time_ms(cycle_base + 3 * period_ms + period_ms / 2 + 5000)
	td.update(0.05)
	var other: Dictionary = {}
	for s in td.visible_spots():
		if String(s["id"]) != "bar_dollar":
			other = s
			break
	fails += _check(not other.is_empty(), "other spots are alive in the next tide")
	if not other.is_empty():
		var op: Vector2 = other["pos"]
		player.position = op + Vector2(-20, 30)
		comp.position = op + Vector2(8, 6)
		comp.instruct_form("rabbit", 0)
		td.update(0.05)
		fails += _check(td._noticed.has(String(other["id"])), "a spot you walk up to shows its sign")
		comp.position = op + Vector2(120, 40)
		td.on_spot_tap(op)
		comp.issue_command("come")   # a Call takes over from the dig order, and nothing is lost
		td.update(0.05)
		fails += _check(td._order.is_empty() and not td._dug.has(String(other["id"])), "a Call cancels a dig on its way; the spot is still buried")
		comp.position = op + Vector2(8, 6)
		td.on_spot_tap(op)
		for _i in 80:
			td.update(0.05)
		fails += _check(td._dug.has(String(other["id"])) and String(td._dug[other["id"]]["kind"]) != "dollar", "a rabbit digs it up: a shell, sea-glass or a crab")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")
	return _finish(fails)


func _has_secret_entry() -> bool:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret":
			return true
	return false


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL EBBMERE SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("EBBMERE SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
