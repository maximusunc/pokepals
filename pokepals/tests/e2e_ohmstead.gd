extends SceneTree
## Dev tool: play OHMSTEAD against a REAL server, end to end, and (with a renderer) screenshot it with the HUD.
## Needs a running, seeded server (see server/README.md) and connects as whoever user://player_id.json says:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path pokepals --resolution 1280x720 \
##     --script res://tests/e2e_ohmstead.gd -- ws://127.0.0.1:4000/ws <out_dir>
## It joins Ohmstead, checks the server described every board, lays the dark sector's ribbon node by node (the
## companion is set down on each node, the server judges each run), takes the spark, then closes the Arcade's
## table by following the hint and checks it paid. Not part of the headless suite (it needs the server), and it
## needs a display: `--headless` runs frames faster than real time, so the claim is sent before the server has
## heard where you are standing.

const OHMSTEAD_ID := "16161616-1616-1616-1616-161616161616"
const TIMEOUT := 900   # frames a step may wait

var _world: Node
var _frames := 0
var _url := "ws://127.0.0.1:4000/ws"
var _out := ""
var _steps: Array = []
var _waited := 0
var _fails := 0
var _coins_before := -1
var _reward := {}
var _found := false
var _started := false


func _process(_delta: float) -> bool:
	_frames += 1
	paused = false
	var net := root.get_node("/root/Net")
	if not _started:
		_started = true
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_url = args[0]
		if args.size() > 1:
			_out = args[1]
		net.connected.connect(_on_connected)
		net.connection_failed.connect(func() -> void:
			print("  FAIL  could not reach the server at ", _url)
			quit(1))
		net.circuit_reward.connect(func(info: Dictionary) -> void: _reward = info)
		net.secret_found.connect(func(_id: String, _new: bool, _with: Array) -> void: _found = true)
		net.connect_to(_url)
		_plan()
		return false
	if _steps.is_empty():
		print("ALL OHMSTEAD E2E CHECKS PASSED" if _fails == 0 else "OHMSTEAD E2E FAILED: %d" % _fails)
		quit(0 if _fails == 0 else 1)
		return true
	var step: Array = _steps[0]
	if (step[1] as Callable).call():
		_steps.pop_front()
		_waited = 0
		if String(step[0]) != "":
			print("  PASS  ", step[0])
		(step[2] as Callable).call()
	else:
		_waited += 1
		if _waited > TIMEOUT:
			print("  FAIL  (timed out) ", step[0])
			_fails += 1
			_steps.clear()
	return false


func _on_connected() -> void:
	var router := root.get_node("/root/WorldRouter")
	router.current_world = OHMSTEAD_ID
	router.arrival_portal_id = ""
	_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(_world)


func _cd():
	return _world._circuit_dir


func _model(id: String) -> CircuitBoard:
	return _cd().board(id).get("model")


## Queue: wait until `cond`, say `label` passed, then do `then`.
func _step(label: String, cond: Callable, then: Callable = func() -> void: pass) -> void:
	_steps.append([label, cond, then])


func _after(frames: int, then: Callable) -> void:
	var until := [0]
	_steps.append(["", func() -> bool:
		until[0] += 1
		return until[0] >= frames, then])


func _plan() -> void:
	_step("joined Ohmstead and the world is built", func() -> bool: return _world != null and _world._world_built)
	_step("the server described all three boards", func() -> bool:
		return _cd().active() and _model("sector") != null and _model("table") != null and _model("today") != null,
		func() -> void:
			var net := root.get_node("/root/Net")
			_coins_before = int(_world._shop_dir.balance()) if _world._shop_dir.has_method("balance") else -1
			print("    today's board: %d by %d, source %d, sink %d" % [_model("today").cols, _model("today").rows, _model("today").source, _model("today").sink])
			_world._companion._form_species = "fox"
			_world._companion._brain.get_self().bond = 1.0
			_go("sector", Vector2(-70, 96)))
	_after(40, func() -> void: _shot("arrive_sector"))
	# the dark sector: wind any ribbon someone left, then lay it by the hint, node by node
	_play("sector", "the dark sector")
	_step("the spark is waiting in the middle of the lit board", func() -> bool: return _has_secret_entry(), func() -> void:
		_world._player.position = _center("sector") + Vector2(0, 14))
	_after(150, func() -> void:
		_shot("sector_closed")
		for e in _world._interactables:
			if String(e.get("kind", "")) == "secret":
				_world._secret_dir.examine(e))
	_step("the server honoured the claim: the steady spark is ours", func() -> bool:
		return _found or root.get_node("/root/Net").has_discovery("steady_spark"))
	_after(260, func() -> void: _go("table", Vector2(-80, 100)))
	_after(60, func() -> void: _shot("arcade_table"))
	_play("table", "the Arcade's table")
	_step("closing the table paid coins and sparks", func() -> bool: return not _reward.is_empty(), func() -> void:
		print("    reward: ", _reward)
		if int(_reward.get("coins", 0)) <= 0 or int(_reward.get("sparks", 0)) <= 0:
			_fails += 1
			print("  FAIL  the reward was empty"))
	_after(30, func() -> void: _shot("table_closed"))
	_step("the table deals a fresh board a few seconds later", func() -> bool:
		var m := _model("table")
		return m != null and m.path.is_empty() and not bool(_cd().board("table")["closed"]))
	_after(20, func() -> void: _go("today", Vector2(-90, 96)))
	_after(60, func() -> void: _shot("arcade_today"))


## Lay board `id`'s ribbon to the end: each step taps the hinted node and sets the companion down on it, then
## waits for the server to say the ribbon grew.
func _play(id: String, name: String) -> void:
	_step("", func() -> bool: return true, func() -> void:
		var m := _model(id)
		if not m.path.is_empty():
			_cd().on_tap(m.pos_of(m.path[0], _cd().board(id)["origin"], 64.0)))
	_after(20, func() -> void: pass)
	for k in 40:
		var before := [-1]
		_step("", func() -> bool: return true, func() -> void:
			var m := _model(id)
			before[0] = m.path.size()
			if bool(_cd().board(id)["closed"]):
				return
			var n := m.hint(20000)
			if n < 0:
				return
			var at := m.pos_of(n, _cd().board(id)["origin"], 64.0)
			_cd().on_tap(at)
			_world._companion.position = at)
		_step("", func() -> bool:
			return bool(_cd().board(id)["closed"]) or _model(id).path.size() > before[0])
		if id == "sector" and k == 7:
			_after(20, func() -> void: _shot("sector_ribbon"))
	_step("%s is closed, by the server's word" % name, func() -> bool: return bool(_cd().board(id)["closed"]))


func _center(id: String) -> Vector2:
	var b: Dictionary = _cd().board(id)
	return (b["origin"] as Vector2) + Vector2(float(int(b["cols"]) - 1), float(int(b["rows"]) - 1)) * 32.0


## Set the pair down beside board `id` (offset from its top-left node).
func _go(id: String, off: Vector2) -> void:
	var o: Vector2 = _cd().board(id)["origin"]
	_world._player.position = o + off
	_world._companion.position = o + off + Vector2(20, 10)


func _has_secret_entry() -> bool:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret" and not bool(e.get("_taken", false)):
			return true
	return false


func _shot(tag: String) -> void:
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/e2e_%s.png" % [_out, tag])
	print("    shot ", tag)
