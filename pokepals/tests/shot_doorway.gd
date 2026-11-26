extends SceneTree
## Dev tool: screenshot LINGERLONG's Late Arch at its moments, to LOOK at them. Needs a real renderer:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path pokepals --resolution 1280x720 \
##     --script res://tests/shot_doorway.gd -- <out_dir> [species]
## Saves doorway_notice.png (the companion pointing at the arch), doorway_inside.png (it waits in the picture, the
## door glowing), doorway_inside_close.png (the same, zoomed in), doorway_arrival.png (just landed on the terrace),
## doorway_terrace.png (the terrace laid out, with the home keepsake set beside the table to compare).

const LINGERLONG_ID := "18181818-1818-1818-1818-181818181818"
const DT := 1.0 / 60.0

var _world: Node
var _frames := 0
var _out := "user://"
var _species := "fox"
var _started := false


func _process(_delta: float) -> bool:
	_frames += 1
	paused = false
	if _world == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_out = args[0]
		if args.size() > 1:
			_species = args[1]
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(LINGERLONG_ID, WorldData.load_json("res://tests/world_fixtures/lingerlong.json"))
		router.current_world = LINGERLONG_ID
		router.arrival_portal_id = ""
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", LINGERLONG_ID)
		return false
	if _frames > 90 and not _started:
		_started = true
		_play()
	return false


func _play() -> void:
	for n in ["UI", "DebugOverlay"]:
		var layer := _world.get_node_or_null(n) as CanvasLayer
		if layer != null:
			layer.visible = false
	var dd = _world.doorway_director()
	var gate = dd.gate()
	var comp = _world._companion
	var player = _world._player
	comp._brain.get_self().met = true
	comp._brain.get_self().bond = 0.8
	comp.instruct_form(_species)
	var at: Vector2 = gate.arch_foot()

	# 1. Noticing.
	player.position = at + Vector2(30, 96)
	comp.position = at + Vector2(-16, 104)
	_world._camera.snap_to(player.position + Vector2(0, -60))
	await _frames_pass(30)
	gate._notice_cd = 0.0
	gate._notice_left = 0.0
	await _frames_pass(12)
	print("pointing: ", comp._point_t, " vis ", comp._point_vis, " species ", comp.current_form_species())
	await _shot("notice")

	# 2. It goes in, and waits.
	dd.ask()
	var t := 0.0
	while not gate.is_open() and t < 20.0:
		await process_frame
		t += 1.0 / 60.0
	await _frames_pass(40)
	await _shot("inside")
	var cam: Camera2D = _world._camera
	cam._cinematic = true
	cam.zoom = Vector2(2.4, 2.4)
	cam.global_position = at + Vector2(0, -50)
	await _frames_pass(20)
	await _shot("inside_close")
	cam.zoom = Vector2.ONE
	cam._cinematic = false

	# 3. Step in after it.
	player.position = at + Vector2(0, 10)
	await _frames_pass(2)
	player.position = at + Vector2(0, -6)
	await _frames_pass(3)
	await _frames_pass(36)
	await _shot("arrival")

	# 4. The terrace as laid out, the keepsake beside the table for comparison.
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/lingerlong.json")
	var keep_at := WorldData.to_vec2(spec["secret"]["position"]) + Vector2(-90, 70)
	_world._world_art.add_interactable(keep_at, Color(1.0, 0.97, 0.9), "kept_place_card")
	player.position = Vector2(150, -1770)
	comp.position = Vector2(170, -1780)
	_world._camera.snap_to(Vector2(0, -1870))
	await _frames_pass(40)
	await _shot("terrace")
	cam._cinematic = true
	cam.zoom = Vector2(2.6, 2.6)
	cam.global_position = keep_at + Vector2(20, -30)
	await _frames_pass(10)
	await _shot("keepsake_close")
	quit(0)


func _frames_pass(n: int) -> void:
	for i in n:
		await process_frame


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/doorway_%s.png" % [_out, tag]
	img.save_png(path)
	print("SHOT saved ", path)
