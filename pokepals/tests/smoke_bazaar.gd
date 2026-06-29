extends SceneTree
## Headless smoke test for the Bazaar world (the colour shop). Points WorldRouter at the bazaar, loads
## the real World scene, and checks the shop mechanism wires up: the merchant's stationary companion
## puppet spawns, the shopkeeper is an examinable interactable, an economy snapshot from the server is
## adopted, examining the merchant opens the shop with that stock, and a purchase echo marks a colour
## owned. Proves the shop mechanism runs without errors. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_bazaar.gd

var _world: Node
var _frames := 0
var _done := false


func _process(_delta: float) -> bool:
	_frames += 1
	if _done:
		return true

	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(router.BAZAAR_ID, WorldData.load_json("res://tests/world_fixtures/bazaar.json"))
		router.current_world = router.BAZAAR_ID
		router.arrival_portal_id = "bazaar_entry"
		router.pending_transition = true
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		return false
	if _frames < 6:
		return false
	_done = true

	var fails := 0

	# The merchant's bonded companion stands beside them as a stationary puppet.
	fails += _check(_world._shop_dir._npc_companion != null, "the merchant's companion puppet spawned")

	# The shopkeeper is an examinable interactable (Examining it opens the shop, not a cozy beat).
	var keeper := _shopkeeper_entry()
	fails += _check(not keeper.is_empty(), "the shopkeeper is an examinable interactable")

	# An economy snapshot from the server is adopted (wallet + colour stock).
	var stock := [
		{ "item_def_id": 1, "name": "Dawn", "swatch": [0.9, 0.6, 0.5], "price": 10, "owned": false },
		{ "item_def_id": 2, "name": "Moss", "swatch": [0.4, 0.6, 0.4], "price": 12, "owned": false },
	]
	_world._shop_dir._on_economy_loaded("coins", 50, stock)
	fails += _check(_world._shop_dir._shop_balance == 50, "the wallet balance was adopted (got %d)" % _world._shop_dir._shop_balance)
	fails += _check(_world._shop_dir._shop_colors.size() == 2, "the colour stock was adopted (got %d)" % _world._shop_dir._shop_colors.size())

	# Examining the merchant opens the shop window with that stock.
	if not keeper.is_empty():
		_world._shop_dir.open_shop(keeper)
		fails += _check(_world._shop.is_open(), "examining the merchant opens the shop")

	# A purchase echo from the server marks the colour owned and adopts the new balance.
	_world._shop_dir._on_purchase_succeeded(1, 40)
	fails += _check(_world._shop_dir._shop_balance == 40, "a purchase adopts the new balance (got %d)" % _world._shop_dir._shop_balance)
	var owned := false
	for c in _world._shop_dir._shop_colors:
		if int(c.get("item_def_id", 0)) == 1:
			owned = bool(c.get("owned", false))
	fails += _check(owned, "the purchased colour is marked owned")

	if fails == 0:
		print("ALL BAZAAR SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("BAZAAR SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _shopkeeper_entry() -> Dictionary:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "shopkeeper":
			return e
	return {}


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
