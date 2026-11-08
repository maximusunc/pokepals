extends SceneTree
## Headless smoke test for UNDERROOT, the caves beneath the great tree. Loads the real World scene from the
## test fixture as if we'd come through the Vale's Gateway and checks what makes it its own place:
##   * it re-skins itself (cave floor, root pillars, root-tangle tunnel walls) and is held in the dark
##     (the MistVeil, with glow-moss shining through it);
##   * the secret is the root-heart (reveal "follow"): hidden at first, the FollowDirector is running, "Go look"
##     is on offer, the companion can plan a route through the tunnels to it and leads along it, and the heart
##     rises only once you and the companion have both arrived;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_underroot.gd

const UNDERROOT_ID := "cccccccc-cccc-cccc-cccc-cccccccccccc"

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
		net.prime_world_spec(UNDERROOT_ID, WorldData.load_json("res://tests/world_fixtures/underroot.json"))
		router.current_world = UNDERROOT_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", UNDERROOT_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/underroot.json")
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]

	var ground: Color = _world._style.color("ground_top")
	fails += _check(ground.v < 0.3, "the cave floor is dark earth")
	var trees := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
	fails += _check(trees >= 15, "root pillars, mounds and fungus stand in the chambers (%d)" % trees)
	fails += _check((spec["hedges"] as Array).size() > 80, "the tunnel walls are segments the nav grid understands (%d)" % (spec["hedges"] as Array).size())

	# The dark.
	var veil = _world.get_node_or_null("MistVeil")
	fails += _check(veil != null and veil is MistVeil, "the dark is laid over the view")
	fails += _check(veil != null and veil.static_light_count() > 30, "glow-moss shines through it (%d)" % (veil.static_light_count() if veil != null else 0))

	# The secret: a root-heart to be followed to.
	fails += _check(String(reveal["type"]) == "follow", "the secret is a root-heart led to")
	var dir = _world._secret_dir
	var fd = dir.get_node_or_null("FollowDirector")
	fails += _check(fd != null, "the follow director is running")
	fails += _check(not _has_secret_entry(), "the heart is hidden until you arrive")
	fails += _check(dir.can_go_look(), "Go look is on offer")
	if fd == null:
		return _finish(fails)

	var heart := WorldData.to_vec2(secret["position"])
	var comp = _world._companion
	var player = _world._player
	var route: Array = comp.plan_route(heart)
	fails += _check(route.size() >= 3, "the companion can plan a route through the tunnels (%d legs)" % route.size())
	fails += _check(route.size() > 0 and (route.back() as Vector2).distance_to(heart) < 60.0, "...and it ends at the heart")
	var length := 0.0
	var prev: Vector2 = comp.position
	for p in route:
		length += prev.distance_to(p)
		prev = p
	fails += _check(length > 3000.0 and length < 12000.0, "...a long winding way (%.0f px)" % length)

	# Asking leads: the guide has a route and the brain is given a guide order.
	fd.ask()
	fails += _check(fd.guide().is_leading(), "asking starts the lead")
	# Arrival, both of you at the heart: the heart rises.
	player.position = heart + Vector2(-60, 0)
	comp.position = heart + Vector2(-90, 0)
	for _i in 5:
		fd.update(0.1)
	fails += _check(_has_secret_entry(), "arriving together, the root-heart rises")
	fails += _check(not dir.can_go_look(), "...and Go look is greyed")

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
		print("ALL UNDERROOT SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("UNDERROOT SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
