extends SceneTree
## Headless smoke test for the FIREFLY GLADES (usable items, crafting; docs/usable-items-design.md): loads the
## real World scene in Dozewood and plays the server's side by hand through Net. The glades are there with
## their fireflies; walking into one says what to do; with the rod in hand the use button stays the rod's; with
## an empty hand it becomes an open jar in a glade (and isn't there outside one); tapping it asks the server,
## and a firefly comes along. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_fireflies.gd

const DOZEWOOD_ID := "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

var _world: Node
var _net: Node
var _frames := 0
var _step := 0
var _fails := 0
var _glade := Vector2.ZERO


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


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		_build()
		return false
	if _frames < 8:
		return false
	if _frames > 2000:
		print("FIREFLY SMOKE FAILED: timed out at step %d" % _step)
		quit(1)
		return true
	var use = _world._use_button
	match _step:
		0:
			print("SmokeFireflies")
			var glades: Array = []
			for c in _world.get_node("Scenery").get_children():
				if String(c.name).begins_with("FireflyGlade_"):
					glades.append(c)
			_ok(glades.size() == 3, "Dozewood has three firefly glades")
			_glade = (glades[0] as Node2D).position if not glades.is_empty() else Vector2.ZERO
			_net._dispatch("hotbar", { "slots": [10, null, null, null, null] })
			_net._dispatch("inventory", { "items": [{ "item_def_id": 10, "name": "Fishing Rod", "category": "tool", "key": "rod", "quantity": 1 }] })
			_world._player.set_process(false)
			_world._player.position = _glade + Vector2(400, 400)
			_world._fishing_dir.select_slot(1)   # an empty hand
			_step = 1
		1:
			_ok(not use.visible, "outside a glade, an empty hand has nothing to use")
			_world._player.position = _glade + Vector2(10, 10)
			_step = 2
		2:
			_ok(_world.hint_text().contains("Fireflies"), "walking into a glade says what to do")
			_ok(use.visible and use._key == "jar" and use._ready_now, "in a glade, an empty hand's use button is an open jar")
			_world._fishing_dir.select_slot(0)
			_step = 3
		3:
			_ok(use._key == "rod", "with the rod in hand, the use button stays the rod's")
			_world._fishing_dir.select_slot(1)
			_step = 4
		4:
			_world._fishing_dir.use_item()
			_ok(_world._firefly_dir._waiting, "tap the jar: the server is asked")
			_net._dispatch("firefly_caught", { "count": 1 })
			_ok(not _world._firefly_dir._waiting and _world.hint_text().contains("firefly"), "a firefly comes along")
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
