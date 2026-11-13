extends SceneTree
## Headless smoke test for CRAFTING and the LANTERN (usable items; docs/usable-items-design.md): loads the
## real World scene in the Bazaar and plays the server's side by hand through Net. Finds the tinker; her
## window lists the lantern with what it takes, Craft disabled while a material is missing and enabled once
## you have it all; a craft (the server's answer) updates your coins and puts the lantern on the hotbar;
## selecting it puts it in your hand and tells friends; a carried lantern clears a warm pocket in a world's
## fog; and a friend's lantern is drawn and lights the dark too. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_crafting.gd

var _world: Node
var _net: Node
var _frames := 0
var _step := 0
var _fails := 0

const RECIPES := [{
	"id": "lantern", "fee": 10, "line": "A driftwood frame, a sea-glass window, and a firefly who'd like to stay.",
	"makes": { "item_def_id": 4, "quantity": 1, "name": "Lantern", "category": "tool", "key": "lantern", "color": [1.0, 0.8, 0.42] },
	"needs": [
		{ "item_def_id": 241, "quantity": 1, "name": "Sea-glass", "category": "material", "key": "sea_glass", "color": [0.52, 0.8, 0.74] },
		{ "item_def_id": 250, "quantity": 1, "name": "Firefly", "category": "material", "key": "firefly", "color": [1.0, 0.92, 0.5] },
		{ "item_def_id": 242, "quantity": 1, "name": "Driftwood", "category": "material", "key": "driftwood", "color": [0.62, 0.5, 0.36] },
	],
}]


func _ok(cond: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fails += 1


func _build() -> void:
	var router := root.get_node("/root/WorldRouter")
	_net = root.get_node("/root/Net")
	router.current_world = router.BAZAAR_ID
	router.arrival_portal_id = "bazaar_entry"
	router.pending_transition = true
	_net.prime_world_spec(router.BAZAAR_ID, WorldData.load_json("res://tests/world_fixtures/bazaar.json"))
	_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	_net.emit_signal("world_spec_unchanged", router.BAZAAR_ID)
	paused = false


func _item(id: int, name: String, cat: String, key: String, qty: int) -> Dictionary:
	return { "item_def_id": id, "name": name, "category": cat, "key": key, "quantity": qty }


# Panels are matched by script, not class name: naming them here would compile them before the Net autoload.
# The newest one (a closed one fades out for a moment before it's gone).
func _panel(script_file: String) -> Node:
	var found: Node = null
	for c in _world.get_node("UI").get_children():
		var sc: Variant = c.get_script()
		if sc != null and String((sc as Script).resource_path).ends_with(script_file):
			found = c
	return found


func _buttons(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Button:
			out.append(c)
		_buttons(c, out)
	return out


func _labels(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		_labels(c, out)
	return out


func _craft_button() -> Button:
	for b in _buttons(_panel("crafter_panel.gd")):
		if (b as Button).text == "Craft":
			return b
	return null


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		_build()
		return false
	if _frames < 6:
		return false
	if _frames > 2000:
		print("CRAFTING SMOKE FAILED: timed out at step %d" % _step)
		quit(1)
		return true
	match _step:
		0:
			print("SmokeCrafting")
			var tinker: Dictionary = {}
			for e in _world._interactables:
				if bool(e.get("crafts", false)):
					tinker = e
			_ok(not tinker.is_empty(), "the Bazaar has a tinker to examine")
			_net._dispatch("economy", { "currency": "coins", "balance": 40, "colors": [] })
			_net._dispatch("recipes", { "recipes": RECIPES })
			_net._dispatch("hotbar", { "slots": [10, null, null, null, null] })
			_net._dispatch("inventory", { "items": [_item(10, "Fishing Rod", "tool", "rod", 1), _item(241, "Sea-glass", "material", "sea_glass", 1),
				_item(250, "Firefly", "material", "firefly", 2)] })
			_world._player.set_process(false)
			_world._player.position = tinker["pos"] + Vector2(0, -16)
			_world._invalidate_nearest()
			_world._try_interact()
			_step = 1
		1:
			var p := _panel("crafter_panel.gd")
			_ok(p != null, "examining her opens her window")
			var t := _labels(p) if p != null else []
			_ok(t.has("Lantern"), "she can make a lantern")
			_ok(t.has("✓  Sea-glass  (1 of 1)") and t.has("✓  Firefly  (1 of 1)") and t.has("·  Driftwood  (0 of 1)"), "it shows what you have of what it takes")
			_ok(t.has("✓  10 coins for the tinker") and t.has("You have 40 coins."), "and her fee against your coins")
			_ok(_craft_button() != null and _craft_button().disabled, "no driftwood: Craft waits")
			_net._dispatch("inventory", { "items": [_item(10, "Fishing Rod", "tool", "rod", 1), _item(241, "Sea-glass", "material", "sea_glass", 1),
				_item(250, "Firefly", "material", "firefly", 2), _item(242, "Driftwood", "material", "driftwood", 1)] })
			_step = 2
		2:
			_ok(_craft_button() != null and not _craft_button().disabled, "with driftwood too: Craft is ready")
			# The server's answer to Craft.
			_net._dispatch("crafted", { "item_def_id": 4, "name": "Lantern", "balance": 30 })
			_net._dispatch("inventory", { "items": [_item(10, "Fishing Rod", "tool", "rod", 1), _item(4, "Lantern", "tool", "lantern", 1),
				_item(250, "Firefly", "material", "firefly", 1)] })
			_net._dispatch("hotbar", { "slots": [10, 4, null, null, null] })
			_step = 3
		3:
			_ok(_world._shop_dir.balance() == 30 and _labels(_panel("crafter_panel.gd")).has("You have 30 coins."), "crafted: the fee is paid")
			_ok(_world.hint_text().contains("lantern") and _world.hint_text().contains("hotbar"), "a hint says it's on your hotbar")
			_panel("crafter_panel.gd").close()
			var fish = _world._fishing_dir
			fish.select_slot(1)
			_ok(fish.held_key() == "lantern" and _world._player.get_node("Lantern").visible, "select it: the lantern is in your hand")
			_ok(_world._presence_dir._held == "lantern", "friends are told you carry a lantern")
			# (our own lantern's light widens our own clear circle in a dark world: smoke_lantern.gd)
			_ok(_world._mist_pockets().is_empty(), "our own lantern adds no pocket (it widens our own light)")
			fish.select_slot(0)
			_ok(fish.held_key() == "rod" and not _world._player.get_node("Lantern").visible, "the rod again: the lantern is put away")
			# A friend with a lantern.
			_net.emit_signal("peer_joined", "friend")
			_net.emit_signal("identity_received", "friend", { "held": "lantern" })
			_step = 4
		4:
			var pair: Dictionary = _world._presence_dir._remote_pairs.get("friend", {})
			var lantern = pair.get("lantern")
			_ok(lantern != null and lantern.visible, "a friend's lantern is drawn")
			var pockets: Array = _world._mist_pockets()
			_ok(pockets.size() == 1 and float(pockets[0]["radius"]) >= 200.0, "and it lights a big pocket of the dark round them")
			_step = 9
		9:
			print("")
			if _fails == 0:
				print("ALL CRAFTING SMOKE CHECKS PASSED")
				quit(0)
			else:
				print("CRAFTING SMOKE FAILED: %d" % _fails)
				quit(1)
			return true
	return false
