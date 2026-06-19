extends SceneTree
## Headless smoke test for the Riverbank world + portal wiring. Points WorldRouter at the
## riverbank as if we'd just stepped through the Vale's portal, loads the real World scene,
## and checks: the hunt is laid out (10 salamanders over its rocks), the entry portal exists
## and the player arrives beside it, examining every rock finds all ten and completes the goal,
## and a second "way home" portal opens on completion. Proves the goal/portal wiring runs
## without errors. Run on its own:
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
		router.current_world = "res://data/riverbank.json"
		router.arrival_portal_id = "riverbank_entry"
		router.pending_transition = true
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		return false
	if _frames < 6:
		return false
	_done = true

	var fails := 0

	# The hunt was laid out: 10 salamanders hidden over the riverbank's 24 rocks.
	fails += _check(_world._goal_active, "goal is active in the riverbank")
	fails += _check(_world._hunt != null and _world._hunt.total == 10, "hunt hides 10 salamanders")
	fails += _check(_world._rocks.size() == 24, "24 rocks were laid out (got %d)" % _world._rocks.size())

	# The entry portal exists, and the player arrived beside it (not back in the Vale).
	var entry := _find_portal("riverbank_entry")
	fails += _check(not entry.is_empty(), "the entry portal exists")
	if not entry.is_empty():
		var d: float = _world._player.position.distance_to(entry["pos"])
		fails += _check(d < 80.0, "player arrived beside the entry portal (%.0f px)" % d)
		fails += _check(d > 22.0, "player arrived clear of the portal's trigger range (no instant bounce-back)")
	fails += _check(not _world._transitioning, "arriving did not start a transition back")

	# Examine every rock: we should find exactly 10 salamanders and complete the hunt.
	var found_salamanders := 0
	for entry_i in _world._interactables:
		if String(entry_i.get("kind", "")) == "rock":
			var before: int = _world._hunt.found
			_world._examine_rock(entry_i)
			if _world._hunt.found > before:
				found_salamanders += 1
	fails += _check(found_salamanders == 10, "examining all rocks found 10 salamanders (got %d)" % found_salamanders)
	fails += _check(_world._hunt.is_complete(), "the hunt reports complete")

	# Completing the hunt opened a second way home.
	var done_portal := _find_portal("riverbank_exit_complete")
	fails += _check(not done_portal.is_empty(), "a completion portal opened on the last salamander")
	if not done_portal.is_empty():
		fails += _check(String(done_portal["target_world"]).ends_with("world.json"), "the completion portal leads back to the Vale")

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
