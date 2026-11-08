extends SceneTree
## Headless smoke test for DRIFTHALLOW, the snowfield at blue hour. Loads the real World scene from the
## test fixture as if we'd come through the Vale's Gateway and checks what makes it its own place:
##   * it re-skins itself (cold palette, its own snow ground atlas, frozen trees);
##   * footsteps are soft dents in the snow (GlowTrail, "snow" style);
##   * the secret is a snow-hare's den (reveal "tracks"): nothing shows at first; a companion in any
##     other shape just plays near the scent spot and leads nowhere; a FOX at the scent spot sniffs,
##     then leads you along the trail laying bright paw-prints, and at the den the frost-flower rises;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_drifthallow.gd

const DRIFTHALLOW_ID := "99999999-9999-9999-9999-999999999999"

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
		net.prime_world_spec(DRIFTHALLOW_ID, WorldData.load_json("res://tests/world_fixtures/drifthallow.json"))
		router.current_world = DRIFTHALLOW_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", DRIFTHALLOW_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/drifthallow.json")
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]

	# Re-skinned: a cold, bright ground; the shared meadow green is gone.
	var ground: Color = _world._style.color("ground_top")
	fails += _check(ground.b > ground.r and ground.v > 0.55, "the ground is pale blue snow")
	var trees := 0
	var pines := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
	fails += _check(trees > 300, "the snowfield has its frozen trees (%d)" % trees)
	pines = (spec["trees"] as Array).filter(func(t: Array) -> bool: return t[2] == "pine").size()
	fails += _check(pines > 100, "pines stand among the birches (%d)" % pines)

	# Footprints in snow.
	var trail = _world._world_art.get_node_or_null("GlowTrail")
	fails += _check(trail != null, "footprints are on")

	# The secret: nothing to see until a fox has led us to the den.
	fails += _check(String(reveal["type"]) == "tracks", "the secret is a trail of tracks")
	var dir = _world._secret_dir
	var td = dir.get_node_or_null("TracksDirector")
	fails += _check(td != null, "the tracks director is laid out")
	fails += _check(not _has_secret_entry(), "the frost-flower isn't there to find yet")
	if td == null:
		return _finish(fails)

	var start := WorldData.to_vec2(reveal["start"])
	var pts: Array = []
	for p in reveal["trail"]:
		pts.append(WorldData.to_vec2(p))
	var comp = _world._companion
	var player = _world._player

	# Another shape: it plays in the snow by the scent spot, and no trail begins.
	comp.instruct_form("cat")
	comp.position = start + Vector2(20, 0)
	player.position = start + Vector2(0, 40)
	for _i in 60:
		td.update(0.1)
	fails += _check(td.guide().next_index == 0 and td.guide().phase == TrailGuide.Phase.IDLE, "a cat by the scent spot leads nowhere")

	# A fox: sniffs, then leads. We play the companion's walking by standing it on each target in turn.
	comp.instruct_form("fox")
	fails += _check(comp.current_form_species() == "fox", "the companion can wear a fox")
	comp.position = start + Vector2(20, 0)
	player.position = start + Vector2(0, 40)
	var guard := 0
	while not td.guide().is_done() and guard < 600:
		guard += 1
		td.update(0.1)
		var g = td.guide()
		if g.phase == TrailGuide.Phase.LEAD and g.next_index < pts.size():
			comp.position = (pts[g.next_index] as Vector2)
			player.position = comp.position - Vector2(40, 0)
		comp.postpone_form_drift(30.0)
	fails += _check(td.guide().is_done(), "a fox led us along the whole trail (%d steps)" % guard)
	fails += _check(_count_scent(trail) >= 5, "it left paw-prints as it went (%d)" % _count_scent(trail))
	fails += _check(_has_secret_entry(), "at the den the frost-flower has risen")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")
	return _finish(fails)


func _has_secret_entry() -> bool:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret":
			return true
	return false


func _count_scent(trail) -> int:
	var n := 0
	for pr in trail._prints:
		if String(pr["kind"]) == "scent":
			n += 1
	return n


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL DRIFTHALLOW SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("DRIFTHALLOW SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
