extends SceneTree
## Perf harness: what a crowd of other players costs THIS client (docs/scaling-design.md, SC-2). It loads the
## Vale offline, then fills it with synthetic peers fed through the same Net signals the real protocol uses
## (peer_joined, identity_received, state_received), so every byte of the presence path runs as it would live.
## Only the socket and the JSON decode are skipped.
##
## For each crowd size it waits for the crowd to settle (lazy puppets spawn over a few frames), then measures
## a few hundred frames:
##   - script ms: the frame's own work on the main thread, from the first node's _process to the end of the
##     deferred calls that follow the last one (which is where every queued _draw runs), so it holds every
##     node's _process, the Net handlers and the redraws, and nothing the engine sleeps or renders. Median
##     and 95th percentile. Two bracket nodes (process_priority at both extremes) take the times.
##   - frame ms: wall time between frames. Only meaningful with a renderer, where the run is uncapped (no
##     vsync, no fps cap) so a frame takes exactly as long as its work plus the rendering. Headless runs at a
##     60 fps cap, so the eased motion sees real frame steps.
##   - draws: draw calls per frame (only with a renderer; 0 headless).
##   - nodes: live nodes in the tree, and how many peers have puppet nodes (drawn) versus are in the roster.
## The synthetic states are fed from this script's own _process, timed on their own ("inject ms"), outside
## the script bracket; the real Net handling would be inside it, so add the two for the live cost.
##
## Headless (script time only):
##   godot --headless --path pokepals --script res://tests/perf_crowd.gd -- [sizes] [walk%] [cell]
## With a renderer (draw calls and frame time), under Xvfb with the opengl3 driver:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path pokepals --rendering-driver opengl3 \
##     --resolution 1280x720 --script res://tests/perf_crowd.gd -- [sizes] [walk%] [cell]
## sizes: comma list, default 0,50,100,200,500. walk%: the share of peers walking (the rest stand), default 50.
## cell: an interest cell size to test a crowd world's rule (a `crowd` block in the spec), default none.
## Peers stand in a disc round where you arrive (radius 700, the whole Vale), so some are on screen and most
## are not. Walkers circle their spot at an easy walking pace and send 20 states a second (by wall time);
## standers send one. Compare runs on the same machine only: the numbers are relative.

const WARMUP := 150      # frames to settle after a crowd arrives (lazy spawns, first redraws)
const MEASURE := 240     # frames measured per crowd size
const SPREAD := 700.0    # radius of the disc the crowd stands in
const SPECIES := ["cat", "fox", "rabbit", "bird", "wolf"]

var _world: Node
var _net: Node
var _frames := 0
var _sizes: Array = [0, 50, 100, 200, 500]
var _walk_share := 0.5
var _cell := 0.0
var _at := -1
var _phase_frame := 0
var _peers: Array = []   # [{ id, home, walk, phase }]
var _last_usec := 0
var _samples: Dictionary = {}
var _rows: Array = []
var _rng := RandomNumberGenerator.new()
var _feed_usec := 0
var _bracket_start := 0
var _script_us: Array = []   # finished brackets, collected each frame


## Runs before every other node each frame: the start of the bracket.
class FirstNode extends Node:
	var harness
	func _process(_d: float) -> void:
		harness._bracket_start = Time.get_ticks_usec()


## Runs after every other node, then defers once more so it lands after the queued redraws: the end.
class LastNode extends Node:
	var harness
	func _process(_d: float) -> void:
		_end.call_deferred()
	func _end() -> void:
		if harness._bracket_start > 0:
			harness._script_us.append(Time.get_ticks_usec() - harness._bracket_start)


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0 and String(args[0]) != "":
			_sizes = []
			for s in String(args[0]).split(","):
				_sizes.append(int(s))
		if args.size() > 1:
			_walk_share = clampf(float(args[1]) / 100.0, 0.0, 1.0)
		if args.size() > 2:
			_cell = float(args[2])
		if DisplayServer.get_name() == "headless":
			Engine.max_fps = 60
		else:
			Engine.max_fps = 0
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var first := FirstNode.new()
		first.harness = self
		first.process_priority = -1000000
		root.add_child(first)
		var last := LastNode.new()
		last.harness = self
		last.process_priority = 1000000
		root.add_child(last)
		var router := root.get_node("/root/WorldRouter")
		_net = root.get_node("/root/Net")
		var core: Dictionary = WorldData.load_json("res://tests/world_fixtures/vale.json")
		if _cell > 0.0:
			core["crowd"] = { "cell": _cell, "full": 40, "lite": 80 }
		_net.prime_world_spec(router.VALE_ID, core)
		router.current_world = router.VALE_ID
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		_net.emit_signal("world_spec_unchanged", router.VALE_ID)
		paused = false
		return false
	# Offline, the connect gate (lobby.gd) keeps the world paused; lift it, as shot_world.gd does, so every
	# node runs as it would in a joined session.
	paused = false
	if _frames < 90:
		return false
	if _at < 0:
		_next_size()
		return false

	var inject_t := Time.get_ticks_usec()
	_feed()
	var inject_us := Time.get_ticks_usec() - inject_t

	var t := _frames - _phase_frame
	var now := Time.get_ticks_usec()
	if t > WARMUP:
		for us in _script_us:
			_sample("script", float(us) / 1000.0)
		_sample("frame", float(now - _last_usec) / 1000.0)
		_sample("draws", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_sample("inject", float(inject_us) / 1000.0)
	_script_us.clear()
	_last_usec = now
	if t >= WARMUP + MEASURE:
		_finish_size()
		if _at + 1 >= _sizes.size():
			_report()
			quit(0)
			return true
		_next_size()
	return false


## Clear the last crowd and bring in the next one: every peer joins, sends its identity and one first state.
func _next_size() -> void:
	for p in _peers:
		_net.emit_signal("peer_left", p["id"])
	_peers.clear()
	_at += 1
	_phase_frame = _frames
	_samples = {}
	_rng.seed = 1234
	var n: int = _sizes[_at]
	var centre: Vector2 = _world._player.position
	var bounds: Rect2 = _world._bounds_rect
	for i in n:
		var id := "bot_%d_%d" % [_at, i]
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * SPREAD
		var home := centre + Vector2(cos(a), sin(a)) * r
		home = Vector2(clampf(home.x, bounds.position.x + 20, bounds.end.x - 20), clampf(home.y, bounds.position.y + 20, bounds.end.y - 20))
		var walk := _rng.randf() < _walk_share
		_peers.append({ "id": id, "home": home, "walk": walk, "phase": _rng.randf() * TAU })
		_net.emit_signal("peer_joined", id)
		_net.emit_signal("identity_received", id, {
			"name": "Bot %d" % i,
			"appearance": {},
			"companion_look": {},
			"companion_form": { "species": SPECIES[i % SPECIES.size()], "variant": 0 },
			"held": "",
		})
		_net.emit_signal("state_received", id, _state_of(_peers[-1], 0.0))


## Walkers send a fresh state 20 times a second, as the protocol does while
## something changes. Standers sent one state when they arrived and nothing since (only changes are sent).
func _feed() -> void:
	var now := Time.get_ticks_usec()
	if now - _feed_usec < 50000:
		return
	_feed_usec = now
	var time := float(now) / 1000000.0
	for p in _peers:
		if p["walk"]:
			_net.emit_signal("state_received", p["id"], _state_of(p, time))


func _state_of(p: Dictionary, time: float) -> Dictionary:
	var home: Vector2 = p["home"]
	if not p["walk"]:
		return { "p": home, "pf": Vector2.DOWN, "c": home + Vector2(-20, 10), "cl": Vector2.DOWN }
	# A 40 px circle at about 60 px/s.
	var ang: float = float(p["phase"]) + time * 1.5
	var pos := home + Vector2(cos(ang), sin(ang)) * 40.0
	var face := Vector2(-sin(ang), cos(ang))
	return { "p": pos, "pf": face, "c": pos - face * 22.0, "cl": face }


func _sample(key: String, v: float) -> void:
	if not _samples.has(key):
		_samples[key] = []
	(_samples[key] as Array).append(v)


func _finish_size() -> void:
	var pres = _world._presence_dir
	var drawn := 0
	if pres.has_method("drawn_count"):
		drawn = pres.drawn_count()
	else:
		drawn = pres.peer_count()
	_rows.append({
		"n": _sizes[_at],
		"script": _pct("script", 0.5), "script_p95": _pct("script", 0.95),
		"frame": _pct("frame", 0.5), "frame_p95": _pct("frame", 0.95),
		"draws": _avg("draws"),
		"inject": _avg("inject"),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"drawn": drawn,
		"roster": pres.peer_count(),
	})


func _avg(key: String) -> float:
	var a: Array = _samples.get(key, [])
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _pct(key: String, q: float) -> float:
	var a: Array = (_samples.get(key, []) as Array).duplicate()
	if a.is_empty():
		return 0.0
	a.sort()
	return float(a[mini(a.size() - 1, int(a.size() * q))])


func _report() -> void:
	print("")
	print("PERF CROWD (walk %d%%%s, %s)" % [int(_walk_share * 100.0), (", cell %d" % int(_cell)) if _cell > 0.0 else "",
		RenderingServer.get_current_rendering_driver_name() if DisplayServer.get_name() != "headless" else "headless"])
	print("| peers | script ms (median / p95) | inject ms | frame ms (median / p95) | draws | nodes | drawn / roster |")
	print("|---|---|---|---|---|---|---|")
	for r in _rows:
		print("| %d | %.2f / %.2f | %.2f | %.2f / %.2f | %d | %d | %d / %d |" % [r["n"], r["script"], r["script_p95"],
			r["inject"], r["frame"], r["frame_p95"], int(r["draws"]), r["nodes"], r["drawn"], r["roster"]])
