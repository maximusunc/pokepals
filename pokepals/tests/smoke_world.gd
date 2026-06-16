extends SceneTree
## Headless smoke test for the world slice: loads the real World scene, drives the
## player programmatically, and checks that the companion (a) follows when the
## player moves away and (b) grows curious when told about a nearby interaction.
## Proves the logic<->presentation wiring runs without errors. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_world.gd

var _world: Node
var _player: Node2D
var _companion: Node2D
var _frames := 0
var _phase := 0
var _start_dist := 0.0
var _curious_seen := false
var _phase_frame := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/world.tscn")
	_world = scene.instantiate()
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false

	# Setup: grab nodes, stop the player driving itself, and place it far away. A FRESH
	# companion's comfort range is map-wide, so it would (by design) ignore this and
	# keep to its own life — following is a bonded beat now, so we bond it first, then
	# expect it to chase.
	if _player == null:
		_player = _world.get_node("Player")
		_companion = _world.get_node("Companion")
		_player.set_process(false)
		_companion._brain.get_self().bond = 1.0
		_player.position = _companion.position + Vector2(380, 0)
		_player.velocity = Vector2.ZERO
		_start_dist = _companion.position.distance_to(_player.position)
		_phase_frame = _frames
		return false

	if _phase == 0:
		if _frames - _phase_frame > 150:
			var now := _companion.position.distance_to(_player.position)
			var followed := now < _start_dist - 80.0
			print("SMOKE follow: start=%.0f now=%.0f -> %s" % [_start_dist, now, ("OK" if followed else "FAIL")])
			if not followed:
				print("SMOKE FAILED")
				quit(1)
				return true
			# Trigger curiosity about a spot right next to the companion.
			_companion.notify_interaction(_companion.position + Vector2(30, 0))
			_phase = 1
			_phase_frame = _frames
		return false

	if _phase == 1:
		if _companion._brain.behavior() == "curious":
			_curious_seen = true
		if _frames - _phase_frame > 30:
			print("SMOKE curiosity: %s" % ("OK" if _curious_seen else "FAIL"))
			if _curious_seen:
				print("ALL WORLD SMOKE CHECKS PASSED")
				quit(0)
			else:
				print("SMOKE FAILED")
				quit(1)
			return true
		return false

	return false
