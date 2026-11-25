extends SceneTree
## Headless smoke test for OHMSTEAD, the machine behind the Gateway. Loads the real World scene from the test
## fixture as if we'd come through the Vale's Gateway and checks what makes it its own place:
##   * it re-skins itself: a grid ground (GridGround) in place of any floor, wireframe trees, and its visitors
##     redrawn as linework (the wire look) in two colours;
##   * runners follow the bright lines and keep out of the sector with no power;
##   * the ribbon boards: the dark sector is known from the spec and played offline by the real rules (a tap on
##     the wrong node does nothing, a bird lays nothing, the companion carries the ribbon node by node, a lit
##     node winds it back, a Call puts it out, and closing it brings the power back and the secret up); the
##     Arcade's boards appear when the server describes them, and a reward is said with its time;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_ohmstead.gd

const OHMSTEAD_ID := "16161616-1616-1616-1616-161616161616"

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
		net.prime_world_spec(OHMSTEAD_ID, WorldData.load_json("res://tests/world_fixtures/ohmstead.json"))
		router.current_world = OHMSTEAD_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", OHMSTEAD_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/ohmstead.json")
	var secret: Dictionary = spec["secret"]
	var circuits: Dictionary = spec["circuits"]

	# The look.
	var grid: GridGround = _world._world_art.grid_ground()
	fails += _check(grid != null and grid.material is ShaderMaterial, "the ground is the grid shader, and nothing else")
	var ground: Color = _world._style.color("ground_top")
	fails += _check(ground.v < 0.1, "under it, the dark")
	var trees := 0
	for c in _world._scenery.get_children():
		if c is TreeView and (c as TreeView).trunk_tex != null:
			trees += 1
	fails += _check(trees >= 300, "wireframe trees stand in the world (%d)" % trees)
	var pm := _world._player.material as ShaderMaterial
	var cm := _world._companion.material as ShaderMaterial
	fails += _check(pm != null and pm.shader == OtherworldLook.WIRE_SHADER and cm != null and cm.shader == OtherworldLook.WIRE_SHADER,
		"you and your companion are redrawn as linework")
	if pm != null and cm != null:
		var pc: Color = pm.get_shader_parameter("line_color")
		var cc: Color = cm.get_shader_parameter("line_color")
		fails += _check(pc.b > pc.g and cc.g > cc.b, "a person in magenta, a companion in amber")
	grid.add_pulse(Vector2(10, 10), false)
	fails += _check(is_equal_approx(grid.sector_power(0), 0.0), "the dark sector starts with no power")

	# The runners.
	var runners = _world._world_art.get_node_or_null("GridRunners")   # (untyped: it names the Net autoload, which a --script run compiles before autoloads exist)
	fails += _check(runners != null, "the runners are out on the lines")
	if runners != null:
		var where: Array = runners.positions()
		var sr: Array = circuits["boards"][0]["sector"]
		var dark := Rect2(float(sr[0]), float(sr[1]), float(sr[2]), float(sr[3]))
		var on_lines := true
		var outside := true
		for r in where:
			var p: Vector2 = r["pos"]
			if absf(fposmod(p.x + 64.0, 128.0) - 64.0) > 0.01 and absf(fposmod(p.y + 64.0, 128.0) - 64.0) > 0.01:
				on_lines = false
			if dark.has_point(p):
				outside = false
		fails += _check(where.size() == 16 and on_lines, "sixteen of them, each on a bright line")
		fails += _check(outside, "and none inside the sector with no power")

	# The boards.
	var cd = _world._circuit_dir   # (untyped, for the same reason)
	fails += _check(cd.active() and cd.board("sector").get("model") != null, "the dark sector's board is known from the spec")
	fails += _check(cd.board("table").get("model") == null and cd.board("today").get("model") == null,
		"the Arcade's boards wait for the server to deal them")
	fails += _check(String(secret["reveal"]["type"]) == "circuit" and not _has_secret_entry(), "the spark is hidden until the sector is closed")
	var b: Dictionary = cd.board("sector")
	var model: CircuitBoard = b["model"]
	var origin: Vector2 = b["origin"]
	var spacing := float(circuits["node"])
	var comp = _world._companion
	var player = _world._player
	player.position = origin + Vector2(-60, 60)
	comp._form_species = "fox"

	fails += _check(not cd.on_tap(origin + Vector2(-300, 0)), "a tap away from every node is not the boards' business")
	fails += _check(cd.on_tap(model.pos_of(0, origin, spacing)) and cd.engaged_board() == "" and model.path.is_empty(),
		"a tap on a node that isn't where the live line comes in starts nothing")
	comp._form_species = "bird"
	fails += _check(cd.on_tap(model.pos_of(model.source, origin, spacing)) and cd.engaged_board() == "", "a bird lays nothing")
	comp._form_species = "fox"

	# Carry the ribbon: tap, let the companion arrive, and the node lights.
	var sol: Array = [10, 11, 6, 5, 0, 1, 2, 7, 12, 13, 8, 3, 4, 9, 14, 19, 18, 17]
	fails += _check(_lay(cd, model, origin, spacing, sol.slice(0, 4)) and model.path == [10, 11, 6, 5], "the companion carries the ribbon node by node")
	fails += _check(cd.engaged_board() == "sector", "and is working on that board")
	# a straight run lights every node it passes
	fails += _check(_lay(cd, model, origin, spacing, [0, 2]) and model.path == [10, 11, 6, 5, 0, 1, 2], "a straight run lights the node in between")
	# a node it cannot run straight to is refused
	cd.on_tap(model.pos_of(13, origin, spacing))
	fails += _check(model.path.size() == 7 and cd._target == -1, "a node off its line is refused")
	# a lit node winds it back
	cd.on_tap(model.pos_of(6, origin, spacing))
	fails += _check(model.path == [10, 11, 6], "tapping a lit node winds the ribbon back to it")
	# a Call puts it out
	comp.issue_command("come", player.position)
	cd.update(0.1)
	fails += _check(model.path.is_empty() and cd.engaged_board() == "", "a Call ends the work and puts the ribbon out")

	# Close it.
	var closed_seen := [false]
	cd.board_closed.connect(func(id: String, fresh: bool) -> void:
		if id == "sector" and fresh:
			closed_seen[0] = true)
	fails += _check(_lay(cd, model, origin, spacing, sol) and model.is_closed(), "one ribbon through every node closes the board")
	fails += _check(bool(cd.board("sector")["closed"]) and closed_seen[0], "the director says so")
	fails += _check(_has_secret_entry(), "and the steady spark is waiting in the middle of it")
	for _i in 40:
		cd.update(0.1)
	fails += _check(is_equal_approx(grid.sector_power(0), 1.0), "the power sweeps back across the sector")
	fails += _check(cd.on_tap(model.pos_of(3, origin, spacing)) and model.path.size() == sol.size(), "a closed board takes no more moves")

	# The server's word: the Arcade's table is dealt, played by someone else, and closed.
	var table := { "id": "table", "kind": "dealt", "cols": 5, "rows": 4, "holes": [0, 19], "source": 1, "sink": 18, "path": [], "closed": false, "seq": 1 }
	cd._on_boards([table])
	var tm: CircuitBoard = cd.board("table").get("model")
	fails += _check(tm != null and tm.live_count() == 18 and tm.source == 1, "the table appears when the server deals it")
	var grown: Dictionary = table.duplicate()
	grown["path"] = [1, 2, 3]
	grown["seq"] = 2
	cd._on_board(grown)
	fails += _check(tm.path == [1, 2, 3] and cd.board("table").get("model") == tm, "a friend's ribbon grows on it")
	var redealt := { "id": "table", "kind": "dealt", "cols": 5, "rows": 4, "holes": [4, 15], "source": 0, "sink": 19, "path": [], "closed": false, "seq": 9 }
	cd._on_board(redealt)
	fails += _check(cd.board("table").get("model") != tm and (cd.board("table")["model"] as CircuitBoard).source == 0, "a fresh deal replaces it")
	cd._on_reward({ "board": "table", "coins": 5, "sparks": 1, "time_ms": 83500, "balance": 42 })
	fails += _check(String(_world._hint.text).contains("1:24") and String(_world._hint.text).contains("5 coins and 1 spark."), "closing one says your time and what it paid")
	fails += _check(cd.clock(59400) == "0:59" and cd.clock(600000) == "10:00", "times read as minutes and seconds")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")
	comp = null
	player = null
	return _finish(fails)


## Tap each node in turn and set the companion down on it, so the ribbon runs there. True if every tap was taken.
func _lay(cd, model: CircuitBoard, origin: Vector2, spacing: float, nodes: Array) -> bool:
	var ok := true
	for n in nodes:
		if model.is_lit(int(n)):
			continue
		if not cd.on_tap(model.pos_of(int(n), origin, spacing)):
			ok = false
		_world._companion.position = model.pos_of(int(n), origin, spacing)
		cd.update(0.05)
	return ok


func _has_secret_entry() -> bool:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret":
			return true
	return false


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL OHMSTEAD SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("OHMSTEAD SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
