extends SceneTree
## SPIKE (Horizon): screenshot a world top-down, then in a perspective view, and time the projection.
## Needs a real renderer (not --headless), e.g.:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path pokepals --resolution 1280x720 \
##     --script res://tests/spike_perspective_shot.gd -- <fixture> <out_dir> [shoulder|inside]
## Shoulder: walks north a little, then shoots. Inside: walks north, then holds "right" (so the camera swings
## round), shoots mid-walk, then stands still long enough to linger and shoots again.

var _world: Node
var _frames := 0
var _fixture := "vale"
var _out := "user://"
var _mode := "shoulder"
var _samples: Array = []
var _quit_at := -1


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_fixture = args[0]
		if args.size() > 1:
			_out = args[1]
		if args.size() > 2:
			_mode = args[2]
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
	if _frames == _quit_at:
		quit(0)
		return true
	var pv: PerspectiveView = _world._perspective
	if _frames == 200:
		_hide_ui()
		_shot("flat")
		# a bonded companion keeps close, so it's in the shots
		_world._companion._brain.get_self().bond = 1.0
	if _frames == 203:
		pv.set_mode(PerspectiveView.Mode.INSIDE if _mode == "inside" else PerspectiveView.Mode.SHOULDER)
	if _frames > 210:
		_samples.append(pv.last_project_usec)
	if _frames == 210:
		Input.action_press("ui_up")
	if _mode == "shoulder" and _frames == 330:
		Input.action_release("ui_up")
		_shot("shoulder")
		_finish()
	if _mode == "inside":
		if _frames == 260:
			Input.action_release("ui_up")
			Input.action_press("ui_right")
		if _frames == 400:
			print("SPIKE yaw after turning: %.0f deg" % rad_to_deg(PerspectiveView.view_yaw))
			_shot("inside_walking")
		if _frames == 420:
			Input.action_release("ui_right")
		if _frames == 900:
			_shot("inside_linger")
			_finish()
	return false


func _finish() -> void:
	_samples.sort()
	print("SPIKE project pass usec: median %d, p95 %d" % [_samples[_samples.size() / 2], _samples[int(_samples.size() * 0.95)]])
	_quit_at = _frames + 5


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
