extends SceneTree
## Headless smoke test for STILLGLASS, the mirror lake. Loads the real World scene from the test fixture as if
## we'd come through the Vale's Gateway and checks what makes it its own place:
##   * it re-skins itself (silver-green trees, silver water) and walls its real shoreline with invisible posts;
##   * the reflection layer is up: the water's mask, the shore trees' images, the phantoms (trees in the water
##     with nothing on the shore) and a waterline under the bank where the walk begins;
##   * the secret is the mirror stone (reveal "reflection"): hidden at first, the ReflectionDirector running;
##     with the companion settled at the edge the lake turns its reflection into a different animal, which
##     walks the shore to the end (driven here through the director's own update), and only then does the
##     stone rise on the bank;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_stillglass.gd

const STILLGLASS_ID := "ffffffff-ffff-ffff-ffff-ffffffffffff"

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
		net.prime_world_spec(STILLGLASS_ID, WorldData.load_json("res://tests/world_fixtures/stillglass.json"))
		router.current_world = STILLGLASS_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", STILLGLASS_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/stillglass.json")
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]

	var ground: Color = _world._style.color("ground_top")
	fails += _check(ground.v > 0.55, "the shore is pale (the sky matches the water)")
	var trees := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
	fails += _check(trees >= 100, "willows, birches and poplars stand on the shores (%d)" % trees)
	var posts := 0
	for p in spec["props"]:
		if String(p["type"]) == "sg_shore":
			posts += 1
	fails += _check(posts > 200 and not bool(spec["collision"]["pond_blocks"]), "the real shoreline is walled by invisible posts, not the pond circles (%d)" % posts)

	# The mirror.
	var layer = _world._world_art.get_node_or_null("ReflectionLayer")
	fails += _check(layer != null and layer is ReflectionLayer, "the reflection layer is up")
	if layer == null:
		return _finish(fails)
	fails += _check(layer.has_water() and layer.mask().rect().size.x > 2000.0, "it knows where the water is")
	var chunks := 0
	var phantom_chunks := 0
	for c in layer.get_children():
		if String(c.name).begins_with("Trees_"):
			chunks += 1
		if String(c.name).begins_with("Phantoms_"):
			phantom_chunks += 1
	fails += _check(chunks >= 3, "the shore trees' images are baked into chunks (%d)" % chunks)
	fails += _check(phantom_chunks >= 3, "...and so are the phantoms: trees in the water with nothing on the shore (%d)" % phantom_chunks)
	var start := WorldData.to_vec2(reveal["start"])
	var axis: float = layer.waterline_below(start + Vector2(0, -20))
	fails += _check(not is_nan(axis) and absf(axis - start.y) < 3.0, "the walk begins on the true waterline (%.1f vs %.1f)" % [axis, start.y])
	# every authored waypoint stands on the north bank: water just below, dry just above
	var on_bank := true
	for p in reveal["trail"]:
		var v := WorldData.to_vec2(p)
		on_bank = on_bank and layer.mask().is_water(v + Vector2(0, 8)) and not layer.mask().is_water(v + Vector2(0, -16))
	fails += _check(on_bank, "every waypoint of the shore path stands on the bank")

	# The secret: a stone that only exists in the reflection.
	fails += _check(String(reveal["type"]) == "reflection", "the secret is a stone behind a reflection")
	var dir = _world._secret_dir
	var rd = dir.get_node_or_null("ReflectionDirector")
	fails += _check(rd != null, "the reflection director is running")
	fails += _check(not _has_secret_entry(), "the stone is hidden until the reflection has walked to it")
	if rd == null:
		return _finish(fails)

	var comp = _world._companion
	var player = _world._player
	var w: ReflectionWalker = rd.walker()
	fails += _check(w.phase == ReflectionWalker.Phase.MIRROR, "to begin with the lake only mirrors")
	# Stand the companion at the edge and let it settle: it turns, then walks (the director's own update).
	player.position = start + Vector2(-20, -50)
	comp.position = start + Vector2(0, -26)
	var turned := false
	var iterations := 0
	while not w.is_done() and iterations < 4000:
		iterations += 1
		if w.phase == ReflectionWalker.Phase.MIRROR or w.phase == ReflectionWalker.Phase.TURN:
			comp.position = w.pos + Vector2(0, -26)
			player.position = w.pos + Vector2(-20, -50)
		else:
			comp.position = w.pos + Vector2(0, -26)
			player.position = w.pos + Vector2(-60, -50)
		rd.update(0.05)
		turned = turned or w.phase == ReflectionWalker.Phase.TURN
	fails += _check(turned, "a settled companion's reflection turns")
	fails += _check(w.is_done() and w.pos.distance_to(WorldData.to_vec2(reveal["trail"][reveal["trail"].size() - 1])) < 1.0, "...and walks the shore to its end (%d steps)" % iterations)
	fails += _check(rd._species != "" and rd._species != comp.current_form_species(), "...as an animal that is not the one your companion wears (%s vs %s)" % [rd._species, comp.current_form_species()])
	# the stone follows a beat after it stops
	for _i in 40:
		rd.update(0.05)
	fails += _check(_has_secret_entry(), "the stone rises on the bank")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")
	return _finish(fails)


func _has_secret_entry() -> bool:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret":
			return true
	return false


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL STILLGLASS SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("STILLGLASS SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
