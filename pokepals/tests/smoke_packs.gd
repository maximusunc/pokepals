extends SceneTree
## Headless smoke test for WORLD PACKS at the controller: a world whose art lives in a pack we don't have
## (and can't fetch: nothing listens where the "server" is) must put up the short loading moment instead
## of building, fail gently, and then carry on and build with the plainer fallback look. A world with
## nothing to fetch must not show it at all. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_packs.gd

const NOCTHOLLOW_ID := "66666666-6666-6666-6666-666666666666"

var _world: Node
var _t := 0.0
var _saw_loading := false
var _loading_covered_world := false
var _done := false


func _process(delta: float) -> bool:
	if _done:
		return true
	_t += delta
	var packs := root.get_node("/root/AssetPacks")

	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(NOCTHOLLOW_ID, WorldData.load_json("res://tests/world_fixtures/nocthollow.json"))
		router.current_world = NOCTHOLLOW_ID
		router.arrival_portal_id = ""
		# Pretend the server said this world needs a pack, whose files we don't have, from a server that isn't there.
		packs.enabled = true
		packs.base_url_override = "http://127.0.0.1:1/"
		packs._worlds[NOCTHOLLOW_ID] = { "name": "Nocthollow", "packs": [{
			"id": "ghost", "url": "packs/ghost.000000000000.pck", "bytes": 10, "sha256": "00",
			"probe": "res://assets/this_file_does_not_exist.png" }] }
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		return false

	var loading: Node = null
	for c in _world.get_node("Fade").get_children():
		if c is PackLoading:
			loading = c
	if loading != null:
		_saw_loading = true
		_loading_covered_world = _world.get_node("Fade/Rect").color.a >= 0.99

	# Failing to connect is quick, the failure card holds 1.4 s, then it finishes: give it a few seconds.
	if _t < 5.0:
		return false
	_done = true

	var fails := 0
	fails += _check(_saw_loading, "the loading moment was put up while the pack was fetched")
	fails += _check(_loading_covered_world, "…over a fully covered screen")
	fails += _check(loading == null, "…and is gone again once the fetch has given up")
	fails += _check(not _world._world_built, "the world was not built before it was joined")

	# The server (here: us) now answers the join: the world builds even though its pack never came.
	var net := root.get_node("/root/Net")
	net.emit_signal("world_spec_unchanged", NOCTHOLLOW_ID)
	fails += _check(_world._world_built, "after the join, the world builds anyway (plainer fallback look)")

	# A world with nothing to fetch never shows the moment.
	packs._worlds["plain"] = { "name": "Plain", "packs": [] }
	fails += _check(packs.is_world_ready("plain"), "a world with no packs is ready at once")
	fails += _check(packs.is_world_ready("home:someone"), "a home is always ready (its art is in the base)")
	packs.enabled = false
	fails += _check(packs.is_world_ready(NOCTHOLLOW_ID), "with packs off (editor, native) every world is ready")

	if fails == 0:
		print("ALL PACKS SMOKE CHECKS PASSED")
	else:
		print("PACKS SMOKE FAILED: %d" % fails)
	quit(fails)
	return true


func _check(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1
