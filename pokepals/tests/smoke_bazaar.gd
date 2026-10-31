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


var _phase := 1        # 1: the first build and its checks; 2: a second build of the same world
var _fails := 0
var _cache_props := 0  # how many props the cached spec held before we built anything


func _build() -> void:
	var router := root.get_node("/root/WorldRouter")
	var net := root.get_node("/root/Net")
	router.current_world = router.BAZAAR_ID
	router.arrival_portal_id = "bazaar_entry"
	router.pending_transition = true
	var scene: PackedScene = load("res://scenes/world.tscn")
	_world = scene.instantiate()
	root.add_child(_world)
	# world_controller defers its build until a join confirms the live spec; this is that confirmation.
	net.emit_signal("world_spec_unchanged", router.BAZAAR_ID)


func _process(_delta: float) -> bool:
	_frames += 1
	if _done:
		return true

	if _world == null:
		if _phase == 1:
			var router := root.get_node("/root/WorldRouter")
			var net := root.get_node("/root/Net")
			net.prime_world_spec(router.BAZAAR_ID, WorldData.load_json("res://tests/world_fixtures/bazaar.json"))
			_cache_props = (net.cached_spec_core(router.BAZAAR_ID).get("props", []) as Array).size()
		_build()
		_frames = 0
		return false
	if _frames < 6:
		return false
	if _phase == 2:
		return _second_build_checks()

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

	# The world's secret (the river-drop) is in the examine list exactly once, and laying the world out
	# didn't write into the shared cached spec (it used to, so a second build doubled the secret).
	fails += _check(_secret_entries() == 1, "the secret is in the world once (got %d)" % _secret_entries())
	fails += _check(_cached_props() == _cache_props, "building didn't change the cached spec (%d props, was %d)" % [_cached_props(), _cache_props])

	# Now build the same world again from the same cache, as a revisit in one session does.
	_fails = fails
	_world.queue_free()
	_world = null
	_phase = 2
	return false


func _second_build_checks() -> bool:
	_done = true
	var fails := _fails
	fails += _check(_secret_entries() == 1, "a second build still has the secret once (got %d)" % _secret_entries())
	fails += _check(_cached_props() == _cache_props, "the cached spec is still untouched (%d props)" % _cached_props())
	if fails == 0:
		print("ALL BAZAAR SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("BAZAAR SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _secret_entries() -> int:
	var n := 0
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret":
			n += 1
	return n


func _cached_props() -> int:
	var router := root.get_node("/root/WorldRouter")
	return (root.get_node("/root/Net").cached_spec_core(router.BAZAAR_ID).get("props", []) as Array).size()


func _shopkeeper_entry() -> Dictionary:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "shopkeeper":
			return e
	return {}


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
