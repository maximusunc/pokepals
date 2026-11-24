extends SceneTree
## Dev tool for the HUD: screenshot the Vale with the item bar filled, then the menu sheet open, then the
## companion's shapes row out. Needs a real renderer (not --headless), e.g.:
##   xvfb-run -s "-screen 0 1688x780x24" godot --path pokepals --resolution 844x390 \
##     --script res://tests/shot_hud.gd -- <out_dir>
## (844x390 is a phone held sideways, in points.)

var _world: Node
var _net: Node
var _frames := 0
var _out := "user://"


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_out = args[0]
		var router := root.get_node("/root/WorldRouter")
		_net = root.get_node("/root/Net")
		_net.prime_world_spec(router.VALE_ID, WorldData.load_json("res://tests/world_fixtures/vale.json"))
		router.current_world = router.VALE_ID
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		_net.emit_signal("world_spec_unchanged", router.VALE_ID)
		paused = false
		return false
	paused = false
	if _frames == 30:
		_net._dispatch("inventory", { "items": [
			{ "item_def_id": 10, "key": "rod", "name": "Fishing rod", "category": "tool", "quantity": 1 },
			{ "item_def_id": 11, "key": "lantern", "name": "Lantern", "category": "tool", "quantity": 1 },
			{ "item_def_id": 12, "key": "axe", "name": "Axe", "category": "tool", "quantity": 1 },
		] })
		_net._dispatch("hotbar", { "slots": [10, 11, 12, null, null] })
		_world._companion._brain.get_self().bond = 1.0
	if _frames == 120:
		# The world's own per-frame refresh only offers the menu's items in a live session; stop it and
		# show what a connected player sees.
		_world.set_process(false)
		_world._gear.set_place("The Vale", 2)
		_world._gear.set_profile("Mossy Wren", "K7Q-2MX")
		_world._gear.set_items([
			{ "id": "new_companion", "label": "New Companion" }, { "id": "friends", "label": "Friends" },
			{ "id": "journal", "label": "Journal" }, { "id": "bag", "label": "Bag" },
			{ "id": "wardrobe", "label": "Wardrobe" }, { "id": "welcome", "label": "Welcome" },
			{ "id": "sound", "label": "Sound" }, { "id": "leave", "label": "Leave game" },
			{ "id": "perspective", "label": "Inside view (dev)" }, { "id": "dbg", "label": "Debug readout" },
		])
		_world._hint.text = "Wander with arrows / WASD or drag.  Step up to something and Examine to look closer."
		_world._hint.modulate.a = 1.0
		_world._layout_hint()
	if _frames == 125:
		# No server here: put the connection gate away so the world shows.
		var lobby := _world.get_node_or_null("UI/Lobby")
		if lobby != null:
			lobby.visible = false
	if _frames == 130:
		_shot("hud_resting")
	if _frames == 135:
		_world._gear._open_sheet()
	if _frames == 160:
		_shot("hud_menu")
	if _frames == 162:
		_world._gear._dev_open = true
		_world._gear._build_sheet()
	if _frames == 166:
		_shot("hud_menu_dev")
		_world._gear._close()
	if _frames == 190:
		_world._radial._open_row()
	if _frames == 210:
		_shot("hud_shapes")
		_world._radial._close()
		_world._radial.set_actions([
			{ "id": "pet", "label": "Pet" }, { "id": "call", "label": "Call" }, { "id": "seek", "label": "Go look" },
			{ "id": "howl", "label": "Howl" },
			{ "id": "form:wolf", "label": "Wolf" }, { "id": "form:fox", "label": "Fox" },
		])
		_world._use_button.set_ready(false)
		_world._use_button.set_verb("Find water")
	if _frames == 230:
		_shot("hud_trick")
		quit(0)
	return false


func _shot(label: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := _out.path_join("%s.png" % label)
	img.save_png(path)
	print("SHOT %s" % path)
