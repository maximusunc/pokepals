extends SceneTree
## Headless smoke test for the Riverbank world + portal wiring. Points WorldRouter at the
## riverbank as if we'd just stepped through the Vale's portal, loads the real World scene,
## and checks: the hunt is laid out (10 salamanders over its rocks), the entry portal exists
## and the player arrives beside it, flipping exactly the salamander rocks (within the flip budget —
## what a perfect companion-read achieves) finds all ten and completes the goal, and a second "way
## home" portal opens on completion. Proves the goal/portal wiring runs without errors. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_riverbank.gd

var _world: Node
var _frames := 0
var _done := false


func _process(_delta: float) -> bool:
	_frames += 1
	if _done:
		return true

	# On the first frame the autoloads exist; point WorldRouter at the riverbank as if we'd
	# just stepped through the Vale's portal, then load the real World scene. (We fetch the
	# autoload by node path because this --script main loop compiles before its global name
	# is registered.)
	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		# World ids are platform UUIDs now; the spec is server-hosted (the client bundles none). Headless
		# and server-less, we prime Net's cache from a test fixture so the controller builds the Riverbank
		# synchronously, as it would from a cached server spec. (Mirrors server priv/world_seeds/riverbank.json.)
		var net := root.get_node("/root/Net")
		net.prime_world_spec(router.RIVERBANK_ID, WorldData.load_json("res://tests/world_fixtures/riverbank.json"))
		# Point at the Riverbank as if we'd just stepped through the Vale's portal.
		router.current_world = router.RIVERBANK_ID
		router.arrival_portal_id = "riverbank_entry"
		router.pending_transition = true
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		# world_controller defers its build until a join confirms the live spec; this is that confirmation.
		net.emit_signal("world_spec_unchanged", router.RIVERBANK_ID)
		return false
	if _frames < 6:
		return false
	_done = true

	var fails := 0

	# The hunt was laid out: 10 salamanders hidden over the riverbank's 24 rocks.
	fails += _check(_world._hunt_dir._goal_active, "goal is active in the riverbank")
	fails += _check(_world._hunt_dir._hunt != null and _world._hunt_dir._hunt.total == 10, "hunt hides 10 salamanders")
	fails += _check(_world._hunt_dir._rocks.size() == 24, "24 rocks were laid out (got %d)" % _world._hunt_dir._rocks.size())

	# The entry portal exists, and the player arrived beside it (not back in the Vale).
	var entry := _find_portal("riverbank_entry")
	fails += _check(not entry.is_empty(), "the entry portal exists")
	if not entry.is_empty():
		var d: float = _world._player.position.distance_to(entry["pos"])
		fails += _check(d < 80.0, "player arrived beside the entry portal (%.0f px)" % d)
		fails += _check(d > 22.0, "player arrived clear of the portal's trigger range (no instant bounce-back)")
	fails += _check(not _world._transitioning, "arriving did not start a transition back")

	# A flip budget caps how many rocks you may turn over — so flipping all 24 is no longer the
	# winning play. Flip exactly the salamander rocks (peeking at the hidden truth, as a perfect
	# companion-read would lead you to): all ten, within the 15-flip budget, completing the hunt.
	fails += _check(_world._hunt_dir._flip_budget > 0, "the riverbank hunt has a flip budget (%d)" % _world._hunt_dir._flip_budget)
	var found_salamanders := 0
	for entry_i in _world._interactables:
		if String(entry_i.get("kind", "")) == "rock" and _world._hunt_dir._hunt.content_kind(int(entry_i["hunt_index"])) == "salamander":
			var before: int = _world._hunt_dir._hunt.found
			_world._hunt_dir.examine_rock(entry_i)
			if _world._hunt_dir._hunt.found > before:
				found_salamanders += 1
	fails += _check(found_salamanders == 10, "flipping the salamander rocks found 10 salamanders (got %d)" % found_salamanders)
	fails += _check(_world._hunt_dir._hunt.is_complete(), "the hunt reports complete")
	fails += _check(_world._hunt_dir._hunt.flips_used == 10, "a perfect read used exactly 10 flips (got %d)" % _world._hunt_dir._hunt.flips_used)

	# Completing the hunt opened a second way home.
	var done_portal := _find_portal("riverbank_exit_complete")
	fails += _check(not done_portal.is_empty(), "a completion portal opened on the last salamander")
	if not done_portal.is_empty():
		var router2 := root.get_node("/root/WorldRouter")
		fails += _check(String(done_portal["target_world"]) == String(router2.VALE_ID), "the completion portal leads back to the Vale")

	if fails == 0:
		print("ALL RIVERBANK SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("RIVERBANK SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _find_portal(id: String) -> Dictionary:
	for p in _world._portals:
		if String(p["id"]) == id:
			return p
	return {}


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
