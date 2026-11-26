extends SceneTree
## Headless smoke test for HARVESTING (home building; docs/usable-items-design.md "Home building"): loads the
## real World scene on the Riverbank and plays the server's side by hand through Net. The bank has stones and
## driftwood to examine; one picked up (the server's answer) is gone for a while and comes back; the axe
## selected is carried and friends are told; the use button is ready only beside a tree; a tree the server says
## is felled topples to a stump and grows back; one already down when we arrive is a stump at once; a friend's
## axe is drawn. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_harvest.gd

const ME := "me-under-test"

var _world: Node
var _net: Node
var _frames := 0
var _step := 0
var _fails := 0
var _wait := 0


func _ok(cond: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fails += 1


func _build() -> void:
	var router := root.get_node("/root/WorldRouter")
	_net = root.get_node("/root/Net")
	router.current_world = router.RIVERBANK_ID
	router.arrival_portal_id = ""
	router.pending_transition = true
	_net.prime_world_spec(router.RIVERBANK_ID, WorldData.load_json("res://tests/world_fixtures/riverbank.json"))
	# Already down when we arrive: tree 5, for another four minutes.
	_net._dispatch("harvest", { "down": [{ "id": "t5", "left_ms": 240000 }], "chop_ms": 0 })
	_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	_net._my_id = ME
	_net.emit_signal("world_spec_unchanged", router.RIVERBANK_ID)
	paused = false


func _item(id: int, name: String, cat: String, key: String, qty: int) -> Dictionary:
	return { "item_def_id": id, "name": name, "category": cat, "key": key, "quantity": qty }


func _pickups() -> Array:
	var out: Array = []
	for e in _world._interactables:
		if String(e.get("kind", "")) == "pickup":
			out.append(e)
	return out


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		_build()
		return false
	if _frames < 8:
		return false
	if _frames > 4000:
		print("HARVEST SMOKE FAILED: timed out at step %d" % _step)
		quit(1)
		return true
	var hv = _world._harvest_dir
	var sc = _world._scenery
	match _step:
		0:
			print("SmokeHarvest")
			var pk := _pickups()
			var stones := pk.filter(func(e: Dictionary) -> bool: return e["tags"].has("stone"))
			_ok(stones.size() == 6 and pk.size() == 11, "the bank has 6 stones and 5 pieces of driftwood to pick up (got %d)" % pk.size())
			_ok(_world.get_node_or_null("Scenery/Pickup_rb_stone_1") != null, "each is drawn on the bank")
			_ok(sc.spec_tree(5) != null and sc.spec_tree(5).felled, "a tree already down when we arrive is a stump")
			_ok(sc.spec_tree(4) != null and not sc.spec_tree(4).felled, "the others stand")
			# Pick a stone up: examining it asks the server; it answers.
			var stone: Dictionary = stones[0]
			_world._player.set_process(false)
			_world._player.position = stone["pos"] + Vector2(0, -14)
			_world._invalidate_nearest()
			_ok(_world._nearest_interactable() >= 0 and String(_world._interactables[_world._nearest_interactable()].get("kind", "")) == "pickup", "standing by it, it's the thing to examine")
			_world._try_interact()
			_net._dispatch("harvested", { "id": String(stone["pickup"]), "left_ms": 400, "by": ME })
			_net._dispatch("harvest_got", { "id": String(stone["pickup"]), "key": "stone", "name": "River Stone", "count": 1, "total": 1 })
			_step = 1
		1:
			var stone: Dictionary = _pickups()[0]
			_ok(bool(stone.get("_taken", false)), "picked up: it's gone")
			_world._invalidate_nearest()
			var n: int = _world._nearest_interactable()
			_ok(n < 0 or _world._interactables[n] != stone, "and no longer prompts")
			_ok(_world.hint_text().contains("river stone") and _world.hint_text().contains("you have 1"), "a hint says what you picked up")
			_wait = 0
			_step = 2
		2:
			# It washes back after the server's regrow time.
			_wait += 1
			if not bool(_pickups()[0].get("_taken", false)):
				_ok(true, "after a while it's back")
				_step = 3
			elif _wait > 600:
				_ok(false, "after a while it's back")
				_step = 3
		3:
			# The axe.
			_net._dispatch("hotbar", { "slots": [11, null, null, null, null] })
			_net._dispatch("inventory", { "items": [_item(11, "Axe", "tool", "axe", 1)] })
			var fish = _world._fishing_dir
			fish.select_slot(0)
			_ok(fish.held_key() == "axe" and _world._player.get_node("Axe").visible, "select the axe: it's over your shoulder")
			_ok(_world._presence_dir._held == "axe", "friends are told you carry an axe")
			var tree: Vector2 = sc.spec_tree(20).position
			_world._player.position = tree + Vector2(200, 60)
			hv._invalidate_ready()
			_ok(not hv.can_chop(), "away from the trees there's nothing to chop")
			_world._player.position = tree + Vector2(0, 20)
			hv._invalidate_ready()
			_ok(hv.can_chop(), "beside a tree the axe is ready")
			fish.use_item()
			_ok(_world._player.get_node("Axe").is_swinging(), "Use: you swing")
			# The server's answer: the tree is down, and the wood is ours.
			_net._dispatch("harvested", { "id": "t20", "left_ms": 600, "by": ME })
			_net._dispatch("harvest_got", { "id": "t20", "key": "wood", "name": "Wood", "count": 2, "total": 2 })
			_step = 4
		4:
			_ok(sc.spec_tree(20).felled, "the tree topples")
			_ok(_world.hint_text().contains("+2 wood"), "and you have two pieces of wood")
			hv._invalidate_ready()
			_ok(not hv.can_chop() or hv._target() != 20, "a stump can't be chopped again")
			# A friend with an axe.
			_net.emit_signal("peer_joined", "friend")
			# Puppets are built once a position arrives and the drawing budget has run (SC-2): settle it now.
			var fp: Vector2 = _world._player.position + Vector2(30, 0)
			_net.emit_signal("state_received", "friend", { "p": fp, "pf": Vector2.DOWN, "c": fp + Vector2(-20, 10), "cl": Vector2.DOWN })
			_world._presence_dir.flush_puppets()
			_net.emit_signal("identity_received", "friend", { "held": "axe" })
			_wait = 0
			_step = 5
		5:
			var pair: Dictionary = _world._presence_dir._remote_pairs.get("friend", {})
			if _wait == 0:
				_ok(pair.get("axe") != null and pair.get("axe").visible, "a friend's axe is drawn")
			_wait += 1
			if not sc.spec_tree(20).felled:
				_ok(true, "the tree grows back")
				_step = 9
			elif _wait > 600:
				_ok(false, "the tree grows back")
				_step = 9
		9:
			print("")
			if _fails == 0:
				print("ALL HARVEST SMOKE CHECKS PASSED")
				quit(0)
			else:
				print("HARVEST SMOKE FAILED: %d" % _fails)
				quit(1)
			return true
	return false
