extends SceneTree
## Headless smoke test for shared presence (the PresenceDirector). Loads the real World scene (the Vale)
## offline, then drives the director's Net-facing handlers directly — a peer joining, sending its
## identity + live transforms, and leaving, to prove the roster keeps everyone, the puppet pair spawns into
## the Scenery once a position arrives, adopts the peer's state (clamped to bounds), and despawns cleanly.
## Then a crowd (SC-2): 300 peers in a world with interest cells, to prove only the budgeted puppets are
## built (and over several frames), that the tiers follow the local player as they walk, that peers leaving
## sight free their nodes, and that the place chip still counts everyone in the world. Net is inactive
## throughout, so this exercises the logic without a server. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_presence.gd

var _world: Node
var _frames := 0
var _step := 0
var _wait := 0
var _fails := 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(router.VALE_ID, WorldData.load_json("res://tests/world_fixtures/vale.json"))
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		# world_controller defers its build until a join confirms the live spec; this is that confirmation.
		net.emit_signal("world_spec_unchanged", router.VALE_ID)
		return false
	if _frames < 6:
		return false
	var pres = _world._presence_dir
	match _step:
		0:
			_basics(pres)
			_crowd_arrives(pres)
			_step = 1
		1:
			# The place chip counts the whole world (the roster), not who is drawn. The world updates the chip
			# every frame it runs, so let it run a couple (offline, the connect gate keeps it paused).
			paused = false
			_wait += 1
			if _wait >= 3:
				_ok(_world._gear._place_count == 301, "the place chip counts all 300 peers and us (%d)" % _world._gear._place_count)
				paused = true
				_crowd_walk(pres)
				_step = 2
		2:
			print("")
			if _fails == 0:
				print("ALL PRESENCE SMOKE CHECKS PASSED")
				quit(0)
			else:
				print("PRESENCE SMOKE FAILED: %d" % _fails)
				quit(1)
			return true
	return false


## One peer at a time: join, identity, state, the early identity, leaving and a disconnect.
func _basics(pres) -> void:
	_ok(pres != null, "the presence director exists")
	_ok(pres.peer_count() == 0, "no peers at the start")

	# A peer joins: it is in the roster at once, but has no puppets until its position arrives.
	pres._on_peer_joined("peer_a")
	_ok(pres.peer_count() == 1, "a joining peer is in the roster")
	pres.flush_puppets()
	_ok(pres.drawn_count() == 0, "with no position yet it is not drawn")
	var bounds: Rect2 = _world._bounds_rect
	var near: Vector2 = _world._player.position + Vector2(40, 0)
	pres._on_state_received("peer_a", { "p": near, "pf": Vector2.DOWN, "c": near + Vector2(-20, 10), "cl": Vector2.DOWN })
	pres.flush_puppets()
	var pair: Dictionary = pres._remote_pairs.get("peer_a", {})
	_ok(not pair.is_empty(), "once its position arrives its pair is built")
	if not pair.is_empty():
		_ok((pair["player"] as Node).get_parent() == _world._scenery, "the remote player parents into Scenery")
		_ok(pair.get("companion") != null, "a near peer in a small crowd is drawn fully, with its companion")
		_ok((pair["player"] as Node2D).position == near, "it appears where it stands, not where we do")

	# An identity packet dresses the existing puppet (no crash on a valid payload).
	pres._on_identity_received("peer_a", { "appearance": {}, "companion_look": {} })

	# A live-state packet moves the puppet, clamped to the world bounds. A wildly out-of-bounds x is
	# pulled back inside; a valid y is kept.
	pres._on_state_received("peer_a", { "p": Vector2(999999, bounds.position.y + 10.0), "pf": Vector2.DOWN, "c": Vector2.ZERO, "cl": Vector2.DOWN })
	_ok(pres._roster["peer_a"]["p"].x <= bounds.end.x, "an out-of-bounds remote x is clamped inside the world")
	# That was a jump of well over a few hundred px: the puppet is put there at once, not slid across the map.
	if not pair.is_empty():
		_ok((pair["player"] as Node2D).position == pres._roster["peer_a"]["p"], "a big jump snaps the puppet")

	# An identity that races ahead of a peer's join is stashed, then kept on join.
	pres._on_identity_received("peer_b", { "appearance": {}, "companion_look": {}, "name": "Bea" })
	_ok(pres._pending_identity.has("peer_b"), "an early identity is stashed until the peer joins")
	pres._on_peer_joined("peer_b")
	_ok(not pres._pending_identity.has("peer_b") and not pres._roster["peer_b"]["ident"].is_empty(), "the stashed identity is kept on join")
	_ok(pres.peer_count() == 2 and pres.peer_name("peer_b") == "Bea", "both peers are present, with names")

	# A peer leaving despawns its pair; a full disconnect clears the rest.
	var left: Node = pair.get("player")
	pres._on_peer_left("peer_a")
	_ok(pres.peer_count() == 1 and not pres._remote_pairs.has("peer_a"), "a leaving peer is dropped")
	_ok(left == null or not left.visible, "and its puppet vanishes at once")
	pres._on_disconnected()
	_ok(pres.peer_count() == 0 and pres.drawn_count() == 0, "a disconnect clears every remote pair")


## 300 peers in a world with interest cells (cell 480, 40 full, 80 lite): 200 round us in the west, 100 far
## off in the east (out of sight).
func _crowd_arrives(pres) -> void:
	pres.set_crowd({ "cell": 480, "full": 40, "lite": 80 })
	_world._player.position = Vector2(-500, 0)
	pres._track_my_cell()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 300:
		var id := "c%d" % i
		var at := Vector2(-500, 100) if i < 200 else Vector2(600, 100)
		at += Vector2(rng.randf_range(-140, 140), rng.randf_range(-140, 140))
		pres._on_peer_joined(id)
		pres._on_identity_received(id, { "name": "C%d" % i, "appearance": {}, "companion_form": { "species": "fox", "variant": 0 }, "held": "lantern" })
		pres._on_state_received(id, { "p": at, "pf": Vector2.DOWN, "c": at + Vector2(-20, 10), "cl": Vector2.DOWN })
	_ok(pres.peer_count() == 300, "the roster holds all 300")
	# One budget pass, then one frame of work with no time to spare: only one puppet is built.
	pres._rebudget()
	pres._work_queue(0)
	_ok(pres.drawn_count() == 1, "a crowd arriving is built a little at a time, not in one frame")
	pres.flush_puppets()
	_ok(pres.drawn_count() == 120, "only the budget is drawn: 40 full and 80 lite (%d)" % pres.drawn_count())
	var full := 0
	var west_only := true
	var lite_bare := true
	for id in pres._remote_pairs:
		var pair: Dictionary = pres._remote_pairs[id]
		if pair.get("companion") != null:
			full += 1
		elif pair.get("lantern") != null or pair.get("rod") != null:
			lite_bare = false
		west_only = west_only and int(String(id).substr(1)) < 200
	_ok(full == 40, "the nearest 40 have companions (%d)" % full)
	_ok(lite_bare, "a lite figure carries nothing in its hands")
	_ok(west_only, "nobody out of sight in the east is drawn")
	_ok(pres.remote_actors().size() == 160, "remote_actors gives every drawn player and companion")
	_ok(pres.remote_lantern_positions().size() == 120, "every drawn friend's lantern still lights the dark")
	var in_scenery := 0
	for c in _world._scenery.get_children():
		if String(c.name).begins_with("Remote") and c.visible:
			in_scenery += 1
	_ok(in_scenery == 160, "the Scenery holds just those puppets (%d)" % in_scenery)


## Walk east: the east group comes into sight and is drawn, the west group leaves sight and its nodes go.
## Where we last placed the east group is forgotten as those cells come into sight (they may have moved while
## we could not hear); the server's snapshot of the new cells then places everyone really there. One of them,
## c299, walked off unseen and is not in the snapshot: it must not stand there as a ghost.
func _crowd_walk(pres) -> void:
	var west_node: Node = null
	for id in pres._remote_pairs:
		west_node = pres._remote_pairs[id]["player"]
		break
	_world._player.position = Vector2(600, 0)
	pres._track_my_cell()
	_ok(not pres._roster["c250"]["seen"], "stepping into a new cell forgets where we last saw people in the cells now in sight")
	_ok(pres._roster["c10"]["seen"], "but not people left behind")
	for i in range(200, 299):
		var id := "c%d" % i
		var at: Vector2 = pres._roster[id]["p"]
		pres._on_state_received(id, { "p": at, "pf": Vector2.DOWN, "c": at + Vector2(-20, 10), "cl": Vector2.DOWN })
	pres.flush_puppets()
	var east_only := true
	for id in pres._remote_pairs:
		east_only = east_only and int(String(id).substr(1)) >= 200
	_ok(pres.drawn_count() == 99 and east_only, "after the walk only the east group is drawn (%d)" % pres.drawn_count())
	_ok(not pres._remote_pairs.has("c299"), "and nobody stands where someone was before they left unseen")
	_ok(west_node != null and (not is_instance_valid(west_node) or west_node.is_queued_for_deletion()), "the west group's nodes are freed")
	_ok(pres.peer_count() == 300, "and everyone is still in the roster")
	pres._on_disconnected()


func _ok(cond: bool, label: String) -> void:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	if not cond:
		_fails += 1
