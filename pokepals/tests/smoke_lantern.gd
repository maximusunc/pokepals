extends SceneTree
## Headless smoke test for the LANTERN in the dark (usable items; docs/usable-items-design.md) and the hotbar
## surviving a world hop: loads the real World scene in Underroot (dark as night), puts a lantern on the
## hotbar, selects it, and checks the dark is pushed back round you (MistVeil's lamp eases in, widening your
## clear circle); then rebuilds the world, as a portal does, and checks the lantern is still the one in your
## hand and still lit; then puts it away and checks the dark closes in again. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_lantern.gd

const UNDERROOT_ID := "cccccccc-cccc-cccc-cccc-cccccccccccc"

var _world: Node
var _net: Node
var _frames := 0
var _step := 0
var _step_frame := 0
var _fails := 0


func _ok(cond: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fails += 1


func _build() -> void:
	var router := root.get_node("/root/WorldRouter")
	_net = root.get_node("/root/Net")
	_net.prime_world_spec(UNDERROOT_ID, WorldData.load_json("res://tests/world_fixtures/underroot.json"))
	router.current_world = UNDERROOT_ID
	router.arrival_portal_id = ""
	_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	_net.emit_signal("world_spec_unchanged", UNDERROOT_ID)
	paused = false


func _next() -> void:
	_step += 1
	_step_frame = _frames


func _veil():
	return _world.get_node_or_null("MistVeil")


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		_build()
		_step_frame = _frames
		return false
	if _frames - _step_frame < 8 and _step in [0, 3]:
		return false
	if _frames > 9000:
		print("LANTERN SMOKE FAILED: timed out at step %d" % _step)
		quit(1)
		return true
	match _step:
		0:
			print("SmokeLantern")
			_ok(_veil() != null, "Underroot is dark (it has a veil)")
			_net._dispatch("hotbar", { "slots": [10, 4, null, null, null] })
			_net._dispatch("inventory", { "items": [
				{ "item_def_id": 10, "name": "Fishing Rod", "category": "tool", "key": "rod", "quantity": 1 },
				{ "item_def_id": 4, "name": "Lantern", "category": "tool", "key": "lantern", "quantity": 1 }] })
			_ok(_veil().lamp() == 0.0, "no lantern in hand: the dark is close")
			_world._fishing_dir.select_slot(1)
			_next()
		1:
			# (wait on the light itself: headless frames come far faster than real time)
			if _veil().lamp() < 0.99 and _frames - _step_frame < 2000:
				return false
			_ok(_world._fishing_dir.held_key() == "lantern", "select it: the lantern is in your hand")
			_ok(_veil().lamp() > 0.95, "and the dark is pushed back round you")
			# A portal rebuilds the whole world scene.
			_world.queue_free()
			_world = null
			_step = 3
			_step_frame = _frames
		3:
			if _world == null:
				return false
			_ok(_net.hotbar_selected == 1 and _world._fishing_dir._selected == 1, "after a world hop the same slot is still selected")
			_ok(_world._fishing_dir.held_key() == "lantern", "and the lantern is still in your hand")
			_next()
		4:
			if _veil().lamp() < 0.99 and _frames - _step_frame < 2000:
				return false
			_ok(_veil().lamp() > 0.95, "still lit in the new world")
			_world._fishing_dir.select_slot(0)
			_next()
		5:
			if _veil().lamp() > 0.0 and _frames - _step_frame < 2000:
				return false
			_ok(_veil().lamp() == 0.0, "put it away: the dark closes in again")
			_step = 9
		9:
			print("")
			if _fails == 0:
				print("ALL LANTERN SMOKE CHECKS PASSED")
				quit(0)
			else:
				print("LANTERN SMOKE FAILED: %d" % _fails)
				quit(1)
			return true
	return false
