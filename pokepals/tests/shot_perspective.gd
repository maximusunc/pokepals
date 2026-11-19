extends SceneTree
## Dev tool for the perspective view (PerspectiveView): screenshot a world top-down, then in perspective, and
## time the projection pass. It walks north, then holds "right" (so the camera swings round), shoots mid-walk,
## then stands still long enough to linger and shoots again. Needs a real renderer (not --headless), e.g.:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path pokepals --resolution 1280x720 \
##     --script res://tests/shot_perspective.gd -- <fixture> <out_dir> [<world id>]
## A fixture whose spec asks for perspective starts in it; others are switched into it after the top-down shot.

var _world: Node
var _frames := 0
var _fixture := "vale"
var _out := "user://"
var _id := ""
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
			_id = args[2]
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		var id: String = _id if _id != "" else router.VALE_ID
		var path := _fixture if _fixture.ends_with(".json") else "res://tests/world_fixtures/%s.json" % _fixture
		net.prime_world_spec(id, WorldData.load_json(path))
		_fixture = _fixture.get_file().get_basename()
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
		pv.set_on(true)
	if _frames > 210:
		_samples.append(pv.last_project_usec)
	if _frames == 210:
		Input.action_press("ui_up")
	if true:
		if _frames == 260:
			Input.action_release("ui_up")
			Input.action_press("ui_right")
		if _frames == 400:
			print("SPIKE yaw after turning: %.0f deg" % rad_to_deg(PerspectiveView.view_yaw))
			_shot("inside_walking")
			# a tap on the companion's feet resolves to where it stands
			var cpos: Vector2 = _world._companion.position
			var at := PerspectiveView.to_screen(_world, cpos)
			var back := PerspectiveView.to_world(_world, Vector2(at.x, at.y))
			print("SPIKE tap round trip error: %.2f" % back.distance_to(cpos))
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
