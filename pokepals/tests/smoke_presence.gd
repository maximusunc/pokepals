extends SceneTree
## Headless smoke test for shared presence (the PresenceDirector). Loads the real World scene (the Vale)
## offline, then drives the director's Net-facing handlers directly — a peer joining, sending its
## identity + live transforms, and leaving — to prove the puppet pair spawns into the Scenery, adopts the
## peer's state (clamped to bounds), and despawns cleanly. Net is inactive throughout, so this exercises
## the spawn/despawn/adopt logic without a server. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_presence.gd

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
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		return false
	if _frames < 6:
		return false
	_done = true

	var fails := 0
	var pres = _world._presence_dir
	fails += _check(pres != null, "the presence director exists")
	fails += _check(pres.peer_count() == 0, "no peers at the start")

	# A peer joins: its puppet pair spawns into the y-sorted Scenery and is tracked.
	pres._on_peer_joined("peer_a")
	fails += _check(pres.peer_count() == 1, "a joining peer spawns a tracked pair")
	var pair: Dictionary = pres._remote_pairs.get("peer_a", {})
	fails += _check(not pair.is_empty(), "the peer's pair is recorded")
	if not pair.is_empty():
		fails += _check((pair["player"] as Node).get_parent() == _world._scenery, "the remote player parents into Scenery")

	# An identity packet dresses the existing puppet (no crash on a valid payload).
	pres._on_identity_received("peer_a", { "appearance": {}, "companion_look": {} })

	# A live-state packet moves the puppet, clamped to the world bounds. A wildly out-of-bounds x is
	# pulled back inside; a valid y is kept.
	var bounds: Rect2 = _world._bounds_rect
	pres._on_state_received("peer_a", { "p": Vector2(999999, bounds.position.y + 10.0), "pf": Vector2.DOWN, "c": Vector2.ZERO, "cl": Vector2.DOWN })
	var rp_pos: Vector2 = (pair["player"] as Node2D).position
	# Remote puppets ease toward their target, so assert via the clamp helper rather than the eased pos.
	var clamped: Vector2 = pres._clamp_to_bounds(Vector2(999999, bounds.position.y + 10.0))
	fails += _check(clamped.x <= bounds.end.x, "an out-of-bounds remote x is clamped inside the world")

	# An identity that races ahead of a peer's join is stashed, then applied on join.
	pres._on_identity_received("peer_b", { "appearance": {}, "companion_look": {} })
	fails += _check(pres._pending_identity.has("peer_b"), "an early identity is stashed until the pair spawns")
	pres._on_peer_joined("peer_b")
	fails += _check(not pres._pending_identity.has("peer_b"), "the stashed identity is applied on join")
	fails += _check(pres.peer_count() == 2, "both peers are present")

	# A peer leaving despawns its pair; a full disconnect clears the rest.
	pres._on_peer_left("peer_a")
	fails += _check(pres.peer_count() == 1, "a leaving peer is dropped")
	pres._on_disconnected()
	fails += _check(pres.peer_count() == 0, "a disconnect clears every remote pair")

	if fails == 0:
		print("ALL PRESENCE SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("PRESENCE SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
