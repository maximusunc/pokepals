extends SceneTree
## Headless smoke test for THIMBLEWICK, the tiny cottage garden. Loads the real World scene from the test fixture
## as if we'd come through the Vale's Gateway and checks what makes it its own place:
##   * it re-skins itself (a warm garden floor, flowers and clover for trees, a fence of pickets);
##   * the fence is a real wall: no body walks through a gap (a gap is one missing picket), anywhere along it;
##   * the secret is the silver thimble (reveal "fetch"): hidden at first, the FetchDirector running and "Go look" on
##     offer once the companion is yours; a new companion, in rabbit form, goes through the thimble gap and comes back
##     with a PEBBLE (an ordinary find), a deeply bonded one with the THIMBLE (the secret's prop, at the player's
##     feet); a companion in any other shape cannot fit and brings nothing;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_thimblewick.gd

const THIMBLEWICK_ID := "13131313-1313-1313-1313-131313131313"

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
		net.prime_world_spec(THIMBLEWICK_ID, WorldData.load_json("res://tests/world_fixtures/thimblewick.json"))
		router.current_world = THIMBLEWICK_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", THIMBLEWICK_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/thimblewick.json")
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]

	# The look.
	var ground: Color = _world._style.color("ground_top")
	fails += _check(ground.g > ground.b and ground.r > 0.4, "the garden floor is a warm green")
	var trees := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
	fails += _check(trees >= 600, "stalks, clover, grass and pickets stand in the garden (%d)" % trees)
	var pickets := 0
	for t in spec["trees"]:
		if String(t[2]) == "picket":
			pickets += 1
	fails += _check(pickets >= 250, "the fence is a long row of pickets (%d)" % pickets)

	# The fence is a wall: walk a body at every gap and at the picket beside it, from the open side, straight across.
	var solids := Solids.build(spec, [], spec["collision"])
	var body_r := float(spec["collision"]["body_radius"])
	var margin := float(spec["collision"]["margin"])
	var bounds := Rect2(WorldData.to_vec2(spec["bounds"]["min"]), WorldData.to_vec2(spec["bounds"]["max"]) - WorldData.to_vec2(spec["bounds"]["min"]))
	var gaps: Array = reveal["gaps"]
	var leaked := 0
	for g in gaps:
		var mouth := WorldData.to_vec2(g["mouth"])
		for dx in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			if _crosses(Vector2(mouth.x + dx, mouth.y), solids, body_r, bounds, margin):
				leaked += 1
	fails += _check(leaked == 0, "no body gets through any of the %d gaps (leaks: %d)" % [gaps.size(), leaked])
	# ...and the check can tell: with the picket beside one gap gone too (two missing), a body does get through.
	var widened: Dictionary = spec.duplicate()
	var wide_trees: Array = []
	var g0 := WorldData.to_vec2((gaps[0] as Dictionary)["mouth"])
	for t in spec["trees"]:
		if String(t[2]) == "picket" and absf(float(t[0]) - (g0.x + 12.0)) < 1.0:
			continue
		wide_trees.append(t)
	widened["trees"] = wide_trees
	fails += _check(_crosses(Vector2(g0.x + 6.0, g0.y), Solids.build(widened, [], spec["collision"]), body_r, bounds, margin), "(control) two missing pickets would let a body through")

	# The secret: a thimble to be fetched.
	fails += _check(String(reveal["type"]) == "fetch", "the secret is a thimble fetched through the fence")
	var dir = _world._secret_dir
	var fd = dir.get_node_or_null("FetchDirector")
	fails += _check(fd != null, "the fetch director is running")
	fails += _check(not _has_secret_entry(), "the thimble is hidden until it is brought")
	if fd == null:
		return _finish(fails)
	var comp = _world._companion
	var player = _world._player
	var thimble_gap: Dictionary = {}
	for g in gaps:
		if String(g["id"]) == "gap_thread":
			thimble_gap = g
	var mouth := WorldData.to_vec2(thimble_gap["mouth"])

	comp._brain.get_self().met = true
	fails += _check(dir.can_go_look(), "Go look is on offer once the companion is yours")

	# A new companion, in rabbit form: a pebble.
	player.position = mouth + Vector2(0, 150)
	comp.position = mouth + Vector2(30, 120)
	comp._brain.get_self().bond = 0.05
	comp._form_species = "rabbit"
	var before := _lying_labels()
	fd.ask()
	fails += _check(fd.is_busy(), "asking sends it off")
	_run(fd, comp, 40.0)
	var found := _new_find(before)
	fails += _check(found == "a pebble", "a new companion brings back a pebble (%s)" % found)
	fails += _check(not _has_secret_entry(), "...and the thimble stays where it is")
	fails += _check(comp.visible and comp.scale == Vector2.ONE and comp.is_processing(), "its body and its mind are its own again")
	fails += _check(comp.bond_value() > 0.05, "the trip warmed the bond a little (%.3f)" % comp.bond_value())

	# A deeply bonded one: the thimble, at the player's feet.
	comp._brain.get_self().bond = 0.9
	comp.position = mouth + Vector2(30, 120)
	comp._form_species = "rabbit"
	_run(fd, comp, 4.0)   # let the cooldown pass
	fd.ask()
	_run(fd, comp, 40.0)
	fails += _check(_has_secret_entry(), "a deeply bonded companion brings back the thimble")
	var entry := _secret_entry()
	fails += _check(not entry.is_empty() and (entry["pos"] as Vector2).distance_to(player.position) < 60.0, "...set down at the player's feet")

	# Another shape cannot fit: it brings nothing.
	comp.position = mouth + Vector2(30, 120)
	comp._form_species = "wolf"
	var lying_before := _lying_labels().size()
	_run(fd, comp, 4.0)
	fd.ask()
	_run(fd, comp, 20.0)
	fails += _check(_lying_labels().size() == lying_before, "a wolf cannot fit through, and brings nothing")
	fails += _check(comp.visible and not fd.is_busy(), "...and it gives up gently")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")
	return _finish(fails)


## Whether a body, walked straight "up" from `from` across the fence line, ends up on the far side of it.
func _crosses(from: Vector2, solids: Array, radius: float, bounds: Rect2, margin: float) -> bool:
	var p := from
	for _i in 60:
		p = Solids.resolve(p + Vector2(0, -2.0), radius, solids, bounds, margin)
	return p.y < -700.0 - 12.0


## Step the companion body and the director together, the way the game loop does, `secs` seconds in 0.05 s frames.
func _run(fd: Node, comp: Node, secs: float) -> void:
	var t := 0.0
	while t < secs:
		if comp.is_processing():
			comp._process(0.05)
		fd.update(0.05)
		t += 0.05


func _lying_labels() -> Array:
	var out: Array = []
	for e in _world._interactables:
		if String(e.get("id", "")).begins_with("fetched_") and not bool(e.get("_taken", false)):
			out.append(String(e.get("label", "")))
	return out


func _new_find(before: Array) -> String:
	var now := _lying_labels()
	return String(now[now.size() - 1]) if now.size() > before.size() else ""


func _has_secret_entry() -> bool:
	return not _secret_entry().is_empty()


func _secret_entry() -> Dictionary:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret" and not bool(e.get("_taken", false)):
			return e
	return {}


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL THIMBLEWICK SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("THIMBLEWICK SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
