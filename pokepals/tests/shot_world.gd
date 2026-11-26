extends SceneTree
## Dev tool: screenshot any world fixture at a few places, to LOOK at it. Needs a real renderer (not --headless):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path pokepals --resolution 1280x720 \
##     --script res://tests/shot_world.gd -- <fixture> <out_dir> [x,y ...]
## With no places it shoots where you arrive. At each place it sets you and your companion down, walks a few
## steps east (so footsteps, trails and a walking pose show), waits, and saves <fixture>_<n>.png. Add "ui" as a
## place to keep the HUD in the pictures. A place may name where your companion stands too, "x,y/cx,cy" (a tap on
## the ground there, so a world's tap-to-stand holds it; else it is just set down). Add "still" to skip the walk
## and wait longer at each place (Glintwold's stone closes after a two-second hold).

const SETTLE := 60
const WALK := 26

var _world: Node
var _frames := 0
var _fixture := "vale"
var _out := "user://"
var _places: Array = []
var _keep_ui := false
var _still := false            # "still": no walk, a longer wait (a held pose can complete)
var _companion_at: Array = []   # per place: where the companion is stood, or null
var _demo_circuits := false   # "circuits": show Ohmstead's boards mid-play (there is no server to deal them here)
var _at := -1
var _phase_start := 0
var _ready_at := 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_fixture = args[0]
		if args.size() > 1:
			_out = args[1]
		for i in range(2, args.size()):
			if args[i] == "ui":
				_keep_ui = true
				continue
			if args[i] == "circuits":
				_demo_circuits = true
				continue
			if args[i] == "still":
				_still = true
				continue
			var parts := String(args[i]).split("/")
			var xy := parts[0].split(",")
			if xy.size() == 2:
				_places.append(Vector2(float(xy[0]), float(xy[1])))
				var cxy := parts[1].split(",") if parts.size() > 1 else PackedStringArray()
				_companion_at.append(Vector2(float(cxy[0]), float(cxy[1])) if cxy.size() == 2 else null)
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		var id := "5407e5ee-0000-4000-8000-000000000001"
		net.prime_world_spec(id, WorldData.load_json("res://tests/world_fixtures/%s.json" % _fixture))
		router.current_world = id
		router.arrival_portal_id = ""
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", id)
		paused = false
		return false
	paused = false
	if _frames < 120:
		return false
	if _frames == 120:
		if not _keep_ui:
			for n in ["UI", "DebugOverlay"]:
				var layer := _world.get_node_or_null(n) as CanvasLayer
				if layer != null:
					layer.visible = false
		_world._companion._brain.get_self().bond = 1.0   # a bonded companion keeps close, so it's in the shots
		if _places.is_empty():
			_places.append(_world._player.position)
		if _demo_circuits and _world._circuit_dir.active():
			var cd = _world._circuit_dir
			cd._on_boards([
				{ "id": "sector", "kind": "fixed", "cols": 5, "rows": 4, "holes": [15, 16], "source": 10, "sink": 17, "path": [10, 11, 6, 5, 0, 1, 2, 7], "closed": false, "seq": 3 },
				{ "id": "table", "kind": "dealt", "cols": 5, "rows": 4, "holes": [0, 19], "source": 1, "sink": 18, "path": [1, 2, 3, 4, 9], "closed": false, "seq": 2 },
				{ "id": "today", "kind": "daily", "cols": 7, "rows": 5, "holes": [0, 6, 34], "source": 1, "sink": 33,
					"path": [1, 2, 3, 4, 5, 12, 13, 20, 27, 26, 19, 18, 11, 10, 17, 24, 25, 32, 31, 30, 23, 16, 9, 8, 7, 14, 15, 22, 21, 28, 29], "closed": false, "seq": 2 },
			])
		_next()
		return false
	var t := _frames - _phase_start
	var walk := 0 if _still else WALK
	var settle := SETTLE * 4 if _still else SETTLE
	if t == 2 and walk > 0:
		Input.action_press("ui_right")
	if t == 2 + walk and walk > 0:
		Input.action_release("ui_right")
	if t == 2 + walk + settle:
		_shot("%d" % _at)
	if t == 2 + walk + settle + 4:
		if _at + 1 >= _places.size():
			quit(0)
			return true
		_next()
	return false


func _next() -> void:
	_at += 1
	_phase_start = _frames
	var p: Vector2 = _places[_at]
	_world._player.position = p
	_world._companion.position = p + Vector2(-26, 14)
	var c: Variant = _companion_at[_at] if _at < _companion_at.size() else null
	if c != null:
		_world._companion.position = c
		_world._secret_dir.on_ground_tap(c)   # a world that stands it where you tap (Lanternfold, Glintwold) keeps it there


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [_out, _fixture, tag]
	img.save_png(path)
	print("SHOT saved ", path)
