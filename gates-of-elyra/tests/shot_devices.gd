extends SceneTree
## Dev tool for DEVICES (issue 175): screenshot the Devices sheet (the list, a code with its countdown,
## the enter-a-code piece waiting), the "Let it in?" card, the welcome card's Enter a code, and the gate's
## two held states. No server: Net is fed the server's words by hand. Needs a real renderer, e.g.:
##   xvfb-run -a -s "-screen 0 1688x780x24" godot --path gates-of-elyra --resolution 844x390 \
##     --script res://tests/shot_devices.gd -- <out_dir>
## Like smoke_devices, it uses its own identity file and reaches the sheets by path.

const ID_PATH := "user://shot_devices_id.json"

var _world: Node
var _net: Node
var _frames := 0
var _out := "user://"
var _sheet: Node


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_out = args[0]
		var router := root.get_node("/root/WorldRouter")
		_net = root.get_node("/root/Net")
		var ident: Node = load("res://scripts/world/player_identity.gd").new()
		ident.path = ID_PATH
		root.add_child(ident)
		_net.identity = ident
		_net.prime_world_spec(router.VALE_ID, WorldData.load_json("res://tests/world_fixtures/vale.json"))
		router.current_world = router.VALE_ID
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		_net.emit_signal("world_spec_unchanged", router.VALE_ID)
		return false
	paused = false
	var lobby: Node = _world.get_node("UI/Lobby")
	if _frames == 5:
		_net.leave()
	if _frames == 60:
		lobby.visible = false
		_world.set_process(false)
		_sheet = load("res://scripts/presentation/devices_panel.gd").new()
		_sheet.companion_met = true
		_world.open_sheet(_sheet)
		var now := int(Time.get_unix_time_from_system() * 1000.0)
		_net._dispatch("devices", { "devices": [
			{ "id": "d1", "name": "Windows PC", "last_seen_ms": now, "current": true },
			{ "id": "d2", "name": "Chrome on Android", "last_seen_ms": now - 3 * 3_600_000, "current": false },
			{ "id": "d3", "name": "iPad", "last_seen_ms": now - 4 * 86_400_000, "current": false },
		] })
	if _frames == 90:
		_shot("devices_sheet")
		_net._dispatch("link_code", { "code": "K7QM2XPA", "expires_in": 600 })
	if _frames == 110:
		_shot("devices_code")
		for n in _sheet.find_children("*", "VBoxContainer", true, false):
			if n.get_script() != null and n.get_script().get_global_name() == "LinkJoinBox":
				n.set_code("hb4n-r7tw")
		_net.redeem_changed.emit("waiting")
		_sheet.find_children("*", "ScrollContainer", true, false)[0].scroll_vertical = 140
	if _frames == 130:
		_shot("devices_waiting")
		_sheet.close()
	if _frames == 150:
		_net._dispatch("link_request", { "device_name": "Safari on iPhone" })
	if _frames == 180:
		_shot("devices_let_in")
		for c in _world.get_node("UI").get_children():
			if c is ChoiceCard:
				c.close()
	if _frames == 200:
		_world._open_cards(["welcome"], true, Callable(), true)
	if _frames == 230:
		_shot("devices_welcome_link")
		for c in _world.get_node("UI").get_children():
			if c is CozySheet:
				c.queue_free()
	if _frames == 240:
		_net._dispatch("superseded", {})
	if _frames == 260:
		_shot("gate_superseded")
		_net._dispatch("signed_out", {})
	if _frames == 280:
		_shot("gate_signed_out")
		lobby._on_second_pressed()
	if _frames == 300:
		_shot("gate_start_fresh")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ID_PATH))
		quit(0)
	return false


func _shot(label: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := _out.path_join("%s.png" % label)
	img.save_png(path)
	print("SHOT %s" % path)
