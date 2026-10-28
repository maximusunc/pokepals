extends SceneTree
## Headless smoke test for the Vale's Gateway. Loads the real World scene (the Vale) offline as if we'd
## just come home through the gateway, then checks: the gateway sits beside the four small direct
## portals; we arrived standing clear of it (disarmed, no instant reopen); walking into it offline only
## shows a hint; the picker opens over a paused world, shows the server's cards (dropping a stale
## answer), backs out cleanly, and picking a world closes it and starts the trip; and WorldRouter sends
## the trip home back to the gateway exactly once. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_gateway.gd

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
		net.prime_world_spec(router.VALE_ID, WorldData.load_json("res://tests/world_fixtures/vale.json"))
		router.current_world = router.VALE_ID
		router.arrival_portal_id = router.HUB_GATEWAY_ID
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", router.VALE_ID)
		return false
	if _frames < 6:
		return false
	_done = true

	var fails := 0
	var router := root.get_node("/root/WorldRouter")

	# The layout: one gateway plus the four small direct portals.
	var gw := _find_portal(router.HUB_GATEWAY_ID)
	fails += _check(not gw.is_empty() and gw.get("gateway", false), "the Vale has its gateway")
	var small := 0
	for p in _world._portals:
		if not p.get("gateway", false):
			small += 1
	fails += _check(small == 4, "the four small direct portals are still there (%d)" % small)
	fails += _check(_world._return_world == "", "the hub itself offers no Return to the Vale")
	if gw.is_empty():
		return _finish(fails + 1)

	# Arriving home through the gateway sets us down beside it, clear of its reach, and it starts quiet.
	var d: float = _world._player.position.distance_to(gw["pos"])
	fails += _check(d > _world.GATEWAY_RANGE and d < 90.0, "arrived beside the gateway, clear of its reach (%.0f px)" % d)
	fails += _check(not bool(gw["armed"]), "the gateway we arrived at starts disarmed")

	# Offline, walking in just explains itself (the directory lives on the server).
	gw["armed"] = true
	_world._player.position = gw["pos"]
	_world._update_portals(0.016)
	fails += _check(_world._picker == null, "offline, the gateway doesn't open a picker")
	fails += _check(not bool(gw["armed"]), "…and it disarms so it doesn't nag every frame")

	# The picker: opens over a paused world and asks for the first page.
	_world._show_world_picker(gw)
	var picker = _world._picker
	fails += _check(picker != null and paused, "the picker opens over a paused world")
	var net := root.get_node("/root/Net")
	var cards := [
		{ "world_id": "r", "name": "The Ruin", "blurb": "doors", "featured": true, "players": 2, "accent": [0.5, 0.7, 0.5] },
		{ "world_id": "b", "name": "The Bazaar", "blurb": "market", "featured": false, "players": 0 },
	]
	net.emit_signal("world_list_received", 99, 0, [{ "world_id": "x", "name": "Stale" }], false)
	fails += _check(_card_count(picker) == 0, "a stale directory answer is ignored")
	net.emit_signal("world_list_received", 1, 0, cards, false)
	fails += _check(_card_count(picker) == 2, "the server's cards are listed (%d)" % _card_count(picker))

	# Backing out resumes the world and leaves the gateway quiet until we step away.
	picker._close()
	fails += _check(_world._picker == null and not paused, "backing out closes the picker and unpauses")
	_world._update_portals(0.016)
	fails += _check(_world._picker == null, "standing in the gateway after backing out doesn't reopen it")

	# A dropped link takes the picker down but leaves the pause to the lobby gate.
	_world._show_world_picker(gw)
	net.emit_signal("disconnected")
	fails += _check(_world._picker == null and paused, "a disconnect dismisses the picker, leaving the world paused for the lobby")
	paused = false

	# Picking a world closes the picker and starts the fade-out trip.
	_world._show_world_picker(gw)
	picker = _world._picker
	net.emit_signal("world_list_received", 1, 0, cards, false)
	picker._on_card_pressed("r", "The Ruin")
	fails += _check(_world._picker == null and not paused, "choosing a world closes the picker")
	fails += _check(_world._transitioning, "…and the trip begins")

	# WorldRouter: the trip home after a gateway journey lands at the gateway, once.
	router.gateway_departure = { "world": router.VALE_ID, "portal": router.HUB_GATEWAY_ID }
	fails += _check(router.resolve_arrival(router.BAZAAR_ID, "bazaar_entry") == "bazaar_entry", "a trip elsewhere keeps its own arrival")
	fails += _check(router.resolve_arrival(router.VALE_ID, "vale_ruin_portal") == router.HUB_GATEWAY_ID, "the trip home arrives at the gateway we left from")
	fails += _check(router.resolve_arrival(router.VALE_ID, "vale_ruin_portal") == "vale_ruin_portal", "…only once")
	router.gateway_departure = {}

	return _finish(fails)


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL GATEWAY SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("GATEWAY SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _find_portal(id: String) -> Dictionary:
	for p in _world._portals:
		if String(p["id"]) == id:
			return p
	return {}


func _card_count(picker) -> int:
	var n := 0
	for child in picker._list.get_children():
		if child is Button and child.custom_minimum_size.y >= 40:
			n += 1
	return n


func _check(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1
