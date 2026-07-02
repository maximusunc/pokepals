extends SceneTree
## Headless smoke test for the Ruin world (the companion-as-actor ward puzzle). Points WorldRouter at
## the Ruin as if we'd stepped through its portal, loads the real World scene, and checks the ward
## mechanism wires up: all four wards build (a plain Threshold, a Warren, a light Cistern, a paired
## Hall), they start shut, "Go look" arms a search, the per-frame referee runs, and a server ward-state
## echo opens a gate (dropping its collider) for everyone. Proves the Ruin mechanism runs without
## errors. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_ruin.gd

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
		net.prime_world_spec(router.RUIN_ID, WorldData.load_json("res://tests/world_fixtures/ruin.json"))
		router.current_world = router.RUIN_ID
		router.arrival_portal_id = "ruin_entry"
		router.pending_transition = true
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		# world_controller defers its build until a join confirms the live spec; this is that confirmation.
		net.emit_signal("world_spec_unchanged", router.RUIN_ID)
		return false
	if _frames < 6:
		return false
	_done = true

	var fails := 0

	# All four wards built, and one of each special kind (plain x2, light, paired).
	fails += _check(_world._ruin._wards.size() == 4, "four wards built (got %d)" % _world._ruin._wards.size())
	var lights := 0
	var paireds := 0
	var open_at_start := 0
	for w in _world._ruin._wards:
		if bool(w["is_light"]):
			lights += 1
		if bool(w["is_paired"]):
			paireds += 1
		if bool(w["open"]):
			open_at_start += 1
	fails += _check(lights == 1, "exactly one light-ward (the Cistern) (got %d)" % lights)
	fails += _check(paireds == 1, "exactly one paired ward (the Hall) (got %d)" % paireds)
	fails += _check(open_at_start == 0, "every ward starts shut")
	fails += _check(_world._ruin.has_unopened_ward(), "the Ruin reports unsolved wards")

	# "Go look" at the Threshold (where we arrive) arms a delegated search.
	fails += _check(not _world._ruin._seeking, "no search is out before Go look")
	_world._ruin.try_seek()
	fails += _check(_world._ruin._seeking, "Go look arms a delegated search")

	# The per-frame ward referee runs without error.
	_world._ruin.update(0.016)

	# A server ward-state echo opens the Threshold gate for everyone (drops its collider).
	var solids_before: int = _world._player._solids.size()
	var thresh := _ward_by_id("threshold_gate")
	fails += _check(not thresh.is_empty(), "the threshold_gate ward exists")
	_world._ruin._on_ward_state([{ "id": "threshold_gate", "found": true, "open": true }])
	fails += _check(bool(thresh["open"]), "the server echo opened the threshold gate")
	var solids_after: int = _world._player._solids.size()
	fails += _check(solids_after < solids_before, "opening the gate dropped its collider (%d -> %d)" % [solids_before, solids_after])

	if fails == 0:
		print("ALL RUIN SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("RUIN SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _ward_by_id(id: String) -> Dictionary:
	for w in _world._ruin._wards:
		if String(w["id"]) == id:
			return w
	return {}


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
