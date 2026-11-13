extends SceneTree
## Headless smoke test for the FIREFLY JARS (usable items, crafting; docs/usable-items-design.md): loads the
## real World scene in Dozewood and plays the server's side by hand through Net. Each of the three glades has its
## fireflies and a glass jar on a little table; walking into a glade points at the jar; examining the jar plays a
## short cutscene (your steering rests, a firefly drifts down into it) and asks the server; when the server
## says yes the firefly is yours and steering comes back; carrying one already, the jar says so and no cutscene
## plays (one at a time). Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_fireflies.gd

const DOZEWOOD_ID := "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

var _world: Node
var _net: Node
var _frames := 0
var _step := 0
var _step_frame := 0
var _fails := 0
var _jar: Dictionary = {}


func _ok(cond: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fails += 1


func _build() -> void:
	var router := root.get_node("/root/WorldRouter")
	_net = root.get_node("/root/Net")
	_net.prime_world_spec(DOZEWOOD_ID, WorldData.load_json("res://tests/world_fixtures/dozewood.json"))
	router.current_world = DOZEWOOD_ID
	router.arrival_portal_id = ""
	_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	_net.emit_signal("world_spec_unchanged", DOZEWOOD_ID)
	paused = false


func _next() -> void:
	_step += 1
	_step_frame = _frames


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		_build()
		return false
	if _frames < 8:
		return false
	if _frames > 3000:
		print("FIREFLY SMOKE FAILED: timed out at step %d" % _step)
		quit(1)
		return true
	var fd = _world._firefly_dir
	var player = _world._player
	match _step:
		0:
			print("SmokeFireflies")
			var glades := 0
			for c in _world.get_node("Scenery").get_children():
				if String(c.name).begins_with("FireflyGlade_"):
					glades += 1
			var jars: Array = []
			for e in _world._interactables:
				if bool(e.get("firefly_jar", false)):
					jars.append(e)
			_ok(glades == 3 and jars.size() == 3, "three glades, each with a jar to examine")
			_jar = jars[0] if not jars.is_empty() else {}
			_net._dispatch("inventory", { "items": [] })
			player.set_process(false)
			player.position = _jar["pos"] + Vector2(0, 20)
			_next()
		1:
			_ok(_world.hint_text().contains("jar"), "walking into a glade points at the jar")
			_ok(not _world._use_button.visible, "there's nothing to tap on the use button with an empty hand")
			_world._invalidate_nearest()
			_world._try_interact()
			_ok(fd.is_playing() and not player.input_enabled, "examine the jar: the cutscene plays and steering rests")
			_next()
		2:
			# Let the firefly drift down for a moment, then the server says yes.
			if _frames - _step_frame < 30:
				return false
			_ok(fd.is_playing(), "it's still drifting down")
			_net._dispatch("firefly_caught", { "count": 1 })
			_net._dispatch("inventory", { "items": [{ "item_def_id": 250, "name": "Firefly", "category": "material", "key": "firefly", "quantity": 1 }] })
			_next()
		3:
			if fd.is_playing() and _frames - _step_frame < 600:
				return false
			_ok(not fd.is_playing() and player.input_enabled, "the scene ends and steering comes back")
			_ok(_world.hint_text().contains("in your bag"), "the firefly is yours")
			# Carrying one already: the jar says so, and no cutscene plays.
			_world._invalidate_nearest()
			_world._try_interact()
			_ok(not fd.is_playing() and player.input_enabled, "one at a time: no cutscene while you carry one")
			_ok(_world.hint_text().contains("already have a firefly"), "and it says why")
			_step = 9
		9:
			print("")
			if _fails == 0:
				print("ALL FIREFLY SMOKE CHECKS PASSED")
				quit(0)
			else:
				print("FIREFLY SMOKE FAILED: %d" % _fails)
				quit(1)
			return true
	return false
