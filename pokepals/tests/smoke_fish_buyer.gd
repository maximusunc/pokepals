extends SceneTree
## Headless smoke test for SELLING (usable items, step 2; docs/usable-items-design.md): loads the real World
## scene in the Bazaar, finds the fishmonger, examines them to open their window, and plays the server's side
## by hand through Net: the window lists what they buy with prices and Sell 1 / Sell all, keeps rare fish
## aside as yours to keep, takes a sale (the coin line and the wallet update), and refreshes from the new
## inventory. Also opens the bag. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_fish_buyer.gd

var _world: Node
var _net: Node
var _frames := 0
var _step := 0
var _fails := 0
var _panel: Node = null


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
	var scene: PackedScene = load("res://scenes/world.tscn")
	_world = scene.instantiate()
	root.add_child(_world)
	_net.emit_signal("world_spec_unchanged", router.BAZAAR_ID)
	paused = false


func _items(minnows: int) -> Array:
	var out: Array = [
		{ "item_def_id": 10, "name": "Fishing Rod", "category": "tool", "key": "rod", "quantity": 1 },
		{ "item_def_id": 220, "name": "Moonscale Koi", "category": "rare_fish", "key": "koi", "color": [0.96, 0.94, 0.88], "quantity": 1 },
		{ "item_def_id": 240, "name": "Old Boot", "category": "material", "key": "old_boot", "color": [0.42, 0.3, 0.22], "sell": 1, "quantity": 1 },
	]
	if minnows > 0:
		out.append({ "item_def_id": 200, "name": "Silver Minnow", "category": "fish", "key": "minnow", "color": [0.78, 0.82, 0.86], "sell": 2, "quantity": minnows })
	return out


# Every Button under `n` (the panel's Sell pills), by its text.
func _buttons(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Button:
			out.append((c as Button).text)
		_buttons(c, out)
	return out


# Panels are matched by script, not class name: naming them here would compile them before the Net autoload.
func _is(n: Node, script_file: String) -> bool:
	var sc: Variant = n.get_script()
	return sc != null and String((sc as Script).resource_path).ends_with(script_file)


func _labels(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		_labels(c, out)
	return out


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		_build()
		return false
	if _frames < 6:
		return false
	if _frames > 2000:
		print("FISH BUYER SMOKE FAILED: timed out at step %d" % _step)
		quit(1)
		return true
	match _step:
		0:
			print("SmokeFishBuyer")
			var buyer: Dictionary = {}
			for e in _world._interactables:
				if String(e.get("buys", "")) == "fish":
					buyer = e
			_ok(not buyer.is_empty(), "the Bazaar has a fishmonger to examine")
			_net._dispatch("economy", { "currency": "coins", "balance": 50, "colors": [] })
			_net._dispatch("inventory", { "items": _items(3) })
			_world._player.set_process(false)
			_world._player.position = buyer["pos"] + Vector2(0, 16)
			_world._invalidate_nearest()
			_world._try_interact()
			_step = 1
		1:
			_panel = null
			for c in _world.get_node("UI").get_children():
				if _is(c, "fish_buyer_panel.gd"):
					_panel = c
			_ok(_panel != null, "examining them opens their window")
			if _panel == null:
				_step = 9
				return false
			var buttons := _buttons(_panel)
			var labels := _labels(_panel)
			_ok(buttons.has("Sell 1") and buttons.has("Sell all (6)"), "minnows: Sell 1, and Sell all for 3 x 2 coins")
			_ok(labels.any(func(t: String) -> bool: return t.begins_with("Old Boot")), "odds and ends are bought too")
			_ok(labels.any(func(t: String) -> bool: return t.begins_with("Moonscale Koi")) and labels.has("Too fine for the barrel: a tank at home"), "a rare fish is shown as yours to keep")
			_ok(not labels.any(func(t: String) -> bool: return t.begins_with("Fishing Rod")), "the rod isn't for sale")
			_ok(labels.has("You have 50 coins."), "your coins are shown")
			# The server's answer to Sell all.
			_net._dispatch("sold", { "item_def_id": 200, "quantity": 3, "coins": 6, "balance": 56, "left": 0, "currency": "coins" })
			_net._dispatch("inventory", { "items": _items(0) })
			_step = 2
		2:
			var labels := _labels(_panel)
			_ok(labels.has("You have 56 coins.") and _world._shop_dir.balance() == 56, "sold: the coin line and the wallet update")
			_ok(not labels.any(func(t: String) -> bool: return t.begins_with("Silver Minnow")), "the minnows are gone from the list")
			_ok(_world.hint_text() == "Sold 3 for 6 coins.", "a hint says what it fetched")
			_panel.close()
			_world._on_gear_item("bag")
			_step = 3
		3:
			var bag: Node = null
			for c in _world.get_node("UI").get_children():
				if _is(c, "bag_panel.gd"):
					bag = c
			var labels := _labels(bag) if bag != null else []
			_ok(bag != null and labels.has("Fishing Rod") and labels.has("Moonscale Koi") and labels.has("Old Boot"), "the bag lists what you carry")
			_ok(labels.has("TOOLS") and labels.has("RARE FISH") and labels.has("ODDS AND ENDS"), "grouped by what it is")
			_step = 9
		9:
			print("")
			if _fails == 0:
				print("ALL FISH BUYER SMOKE CHECKS PASSED")
				quit(0)
			else:
				print("FISH BUYER SMOKE FAILED: %d" % _fails)
				quit(1)
			return true
	return false
