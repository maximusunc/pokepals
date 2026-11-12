extends SceneTree
## Headless smoke test for the FISH TANK at home (usable items, step 3; docs/usable-items-design.md): loads
## the real World scene in a home (tests/world_fixtures/home.json, whose tank has two fish), and plays the
## server's side by hand through Net. Checks the tank stands by the journal with its fish swimming, that
## examining it opens its window (Take out for each fish, Put in for the rare fish you carry), that a change
## broadcast by the server updates the tank, that a friend's tank is look-only, and that your companion
## wanders over to watch. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_tank.gd

const OWNER := "owner-under-test"  # the fixture's home.owner_id

var _world: Node
var _net: Node
var _frames := 0
var _step := 0
var _fails := 0


func _ok(cond: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fails += 1


func _build() -> void:
	var router := root.get_node("/root/WorldRouter")
	_net = root.get_node("/root/Net")
	var home_id: String = router.HOME_PREFIX + OWNER
	_net.prime_world_spec(home_id, WorldData.load_json("res://tests/world_fixtures/home.json"))
	router.current_world = home_id
	router.arrival_portal_id = ""
	router.pending_transition = true
	_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	_net._my_id = OWNER
	_net.emit_signal("world_spec_unchanged", home_id)
	paused = false


# Panels are matched by script, not class name: naming them here would compile them before the Net autoload.
# The newest one (a closed one fades out for a moment before it's gone).
func _panel(script_file: String) -> Node:
	var found: Node = null
	for c in _world.get_node("UI").get_children():
		var sc: Variant = c.get_script()
		if sc != null and String((sc as Script).resource_path).ends_with(script_file):
			found = c
	return found


func _texts(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append("[%s]" % (c as Button).text)
		_texts(c, out)
	return out


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		_build()
		return false
	if _frames < 8:
		return false
	if _frames > 3000:
		print("TANK SMOKE FAILED: timed out at step %d" % _step)
		quit(1)
		return true
	var tank = _world._tank_dir
	match _step:
		0:
			print("SmokeTank")
			_ok(tank.has_tank(), "the home has a tank")
			var view: Node2D = _world.get_node_or_null("Scenery/FishTank")
			_ok(view != null and view.position.distance_to(Vector2(110, 160)) < 100.0, "it stands by the journal")
			_ok(view != null and view.fish_count() == 2, "two fish swim in it")
			var entry: Dictionary = {}
			for e in _world._interactables:
				if bool(e.get("tank", false)):
					entry = e
			_ok(not entry.is_empty(), "it can be examined")
			_net._dispatch("inventory", { "items": [
				{ "item_def_id": 221, "name": "Ember Trout", "category": "rare_fish", "key": "ember_trout", "color": [0.94, 0.48, 0.28], "quantity": 1 },
				{ "item_def_id": 200, "name": "Silver Minnow", "category": "fish", "key": "minnow", "quantity": 4, "sell": 2 },
			] })
			_world._player.set_process(false)
			_world._player.position = entry["pos"] + Vector2(0, 20)
			_world._invalidate_nearest()
			_net._my_id = OWNER   # (the headless lobby's failed connect resets Net, so say who we are again)
			_world._try_interact()
			_step = 1
		1:
			var p := _panel("tank_panel.gd")
			_ok(p != null, "examining it opens its window")
			var t := _texts(p) if p != null else []
			_ok(t.has("Your tank") and t.has("SWIMMING (2 OF 3)"), "your tank, two of three")
			_ok(t.count("[Take out]") == 2, "each fish can be taken out")
			_ok(t.has("Ember Trout") and t.has("[Put in]"), "the rare fish you carry can be put in")
			_ok(not t.any(func(s: String) -> bool: return s.begins_with("Silver Minnow")), "common fish aren't offered")
			# The server's answer to Put in: the tank, broadcast to everyone in the home.
			_net._dispatch("tank", { "owner": OWNER, "fish": [
				{ "item_def_id": 220, "key": "koi", "name": "Moonscale Koi", "color": [0.96, 0.94, 0.88] },
				{ "item_def_id": 222, "key": "old_whiskers", "name": "Old Whiskers", "color": [0.36, 0.4, 0.34] },
				{ "item_def_id": 221, "key": "ember_trout", "name": "Ember Trout", "color": [0.94, 0.48, 0.28] },
			] })
			_net._dispatch("inventory", { "items": [{ "item_def_id": 200, "name": "Silver Minnow", "category": "fish", "key": "minnow", "quantity": 4, "sell": 2 }] })
			_step = 2
		2:
			var view: Node2D = _world.get_node("Scenery/FishTank")
			_ok(view.fish_count() == 3, "the trout joins the others in the tank")
			var t := _texts(_panel("tank_panel.gd"))
			_ok(t.has("SWIMMING (3 OF 3)") and t.count("[Take out]") == 3 and not t.has("[Put in]"), "the window shows it full")
			_panel("tank_panel.gd").close()
			# Your companion comes over to watch, now and then, while you're nearby.
			tank._watch_in = 0.0
			_step = 3
		3:
			_ok(tank._watching > 0.0, "your companion wanders over to watch the fish")
			# A friend's tank: look, don't touch.
			tank._owner_id = "a-friend"
			tank._owner_name = "Mossy Wren"
			tank.examine({})
			_step = 4
		4:
			var p := _panel("tank_panel.gd")
			var t := _texts(p) if p != null else []
			_ok(t.has("Mossy Wren's tank") and not t.has("[Take out]") and not t.has("[Put in]"), "a friend's tank is look-only")
			_step = 9
		9:
			print("")
			if _fails == 0:
				print("ALL TANK SMOKE CHECKS PASSED")
				quit(0)
			else:
				print("TANK SMOKE FAILED: %d" % _fails)
				quit(1)
			return true
	return false
