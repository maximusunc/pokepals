extends SceneTree
## SPIKE (Horizon): screenshot a world top-down, then in perspective, and time the projection.
## Needs a real renderer (not --headless), e.g.:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path pokepals --resolution 1280x720 \
##     --script res://tests/spike_perspective_shot.gd -- <fixture> <out_dir>

var _world: Node
var _frames := 0
var _fixture := "vale"
var _out := "user://"
var _samples: Array = []
var _frame_usec: Array = []
var _last_t := 0
var _flat_usec: Array = []


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_fixture = args[0]
		if args.size() > 1:
			_out = args[1]
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		var id: String = router.VALE_ID
		net.prime_world_spec(id, WorldData.load_json("res://tests/world_fixtures/%s.json" % _fixture))
		router.current_world = id
		router.arrival_portal_id = ""
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", id)
		paused = false
		return false
	paused = false
	if _frames > 120 and _frames < 200:
		var t := Time.get_ticks_usec()
		if _last_t > 0:
			_flat_usec.append(t - _last_t)
		_last_t = t
	if _frames == 200:
		_last_t = 0
		_hide_ui()
		_shot("flat")
	if _frames == 203:
		_world._perspective.set_on(true)
	if _frames > 210 and _frames <= 330:
		_samples.append(_world._perspective.last_project_usec)
		var now := Time.get_ticks_usec()
		if _last_t > 0:
			_frame_usec.append(now - _last_t)
		_last_t = now
		# walk north so the shot has motion and the companion follows
		var p: Node2D = _world.get_node("Scenery/Player")
		p.position += Vector2(0, -1.2)
	if _frames == 331:
		_shot("perspective")
		_samples.sort()
		_frame_usec.sort()
		print("SPIKE project pass usec: median %d, p95 %d" % [_samples[_samples.size() / 2], _samples[int(_samples.size() * 0.95)]])
		print("SPIKE frame usec (llvmpipe, not representative of a GPU): median %d" % _frame_usec[_frame_usec.size() / 2])
		_flat_usec.sort()
		print("SPIKE flat frame usec: median %d" % _flat_usec[_flat_usec.size() / 2])
		print("SPIKE scenery children: %d" % _world._scenery.get_child_count())
		quit(0)
	return false


func _hide_ui() -> void:
	var ui := _world.get_node_or_null("UI") as CanvasLayer
	if ui != null:
		ui.visible = false
	var dbg := _world.get_node_or_null("DebugOverlay") as CanvasLayer
	if dbg != null:
		dbg.visible = false


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [_out, _fixture, tag]
	img.save_png(path)
	print("SPIKE saved ", path)
