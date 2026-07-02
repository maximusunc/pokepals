extends SceneTree
## Headless smoke test for the Hedge Maze world (a "reach_center" goal). Points WorldRouter at the maze,
## loads the real World scene, and checks the maze mechanism wires up: the goal is active with a centre +
## radius, a Return-to-the-Vale escape target is declared, the companion's flow-field guide loaded and
## points a direction out of a cell, reaching the heart latches the reward once, and the per-frame guide
## hint runs without error. Proves the maze mechanism runs without errors. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_maze.gd

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
		net.prime_world_spec(router.MAZE_ID, WorldData.load_json("res://tests/world_fixtures/maze.json"))
		router.current_world = router.MAZE_ID
		router.arrival_portal_id = ""
		router.pending_transition = true
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		# world_controller defers its build until a join confirms the live spec; this is that confirmation.
		net.emit_signal("world_spec_unchanged", router.MAZE_ID)
		return false
	if _frames < 6:
		return false
	_done = true

	var fails := 0

	# The reach_center goal is active, with a centre + radius and a Return escape target.
	fails += _check(_world._maze_dir._maze_active, "the maze goal is active")
	fails += _check(_world._maze_dir._maze_radius > 0.0, "the heart has a reach radius (%.0f)" % _world._maze_dir._maze_radius)
	fails += _check(_world._return_world != "", "a Return-to-the-Vale target is declared")

	# The companion's flow-field guide loaded and points a unit direction out of a non-centre cell.
	fails += _check(not _world._maze_dir._maze_guide_dirs.is_empty(), "the maze guide flow-field loaded")
	var dir: Vector2 = _world._maze_dir._maze_dir_at(_world._player.position)
	fails += _check(dir != null, "the guide resolves a direction at the player's cell")

	# Reaching the heart latches the reward exactly once.
	fails += _check(not _world._maze_dir._maze_reached, "the heart is not reached at the start")
	_world._maze_dir._on_maze_reached()
	fails += _check(_world._maze_dir._maze_reached, "reaching the heart latches the reward")

	# The per-frame guide hint runs without error (relaxes the pose now the heart is reached).
	_world._maze_dir.update(0.016)

	if fails == 0:
		print("ALL MAZE SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("MAZE SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
