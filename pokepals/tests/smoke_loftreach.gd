extends SceneTree
## Headless smoke test for LOFTREACH, the sky-island world. Loads the real World scene from the test fixture as
## if we'd come through the Vale's Gateway and checks what makes it its own place:
##   * it is a sky: the SkyLayer stands behind the world (islands, bridges, windmill, kites), WorldArt paints no
##     ground of its own, and the world has no border ring of trees;
##   * you cannot walk off an island into the sky, you can cross a rope bridge, and the hidden bridge is shut;
##   * the secret is the nest (reveal "skyview"): in plain sight on an islet no foot can reach; the SkyDirector is
##     running; in bird form "Go up" sends the companion up (driven here through the director's own update): the
##     camera zooms out, the picture in the high clouds fades in, the bird sees the way, the bridge comes down,
##     and on landing the camera, the companion and the follow are all back;
##   * the nest can then be walked to; and it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_loftreach.gd

const LOFTREACH_ID := "12121212-1212-1212-1212-121212121212"

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
		net.prime_world_spec(LOFTREACH_ID, WorldData.load_json("res://tests/world_fixtures/loftreach.json"))
		router.current_world = LOFTREACH_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", LOFTREACH_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/loftreach.json")
	var sky: Dictionary = spec["sky"]
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]

	# The sky.
	var layer = _world._world_art.get_node_or_null("SkyLayer")
	fails += _check(layer != null and layer is SkyLayer, "the sky layer is up")
	fails += _check(layer != null and layer.air() != null, "...with its overhead layer (sails, kites, the picture)")
	fails += _check(_world._world_art.get_node_or_null("Ground") == null, "no pixel ground of the usual kind is laid under the sky")
	fails += _check(not spec.has("border"), "there is no ring of border trees round a sky")
	fails += _check((sky["islands"] as Array).size() == 9 and (sky["bridges"] as Array).size() == 10, "nine islands and ten bridges, one of them hidden")
	var trees := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
	fails += _check(trees >= 80, "trees stand on the islands (%d)" % trees)

	# The fence: islands are solid at their edges, bridges are walkable, the hidden bridge is shut.
	var player = _world._player
	var solids: Array = player._solids
	var bounds: Rect2 = _world._bounds_rect
	fails += _check(solids.size() > 200, "the islands are fenced (%d solids)" % solids.size())
	var landing := _island(sky, "landing")
	var c_land := SkyRealm.centroid(SkyRealm.poly_points(landing))
	var p := _walk(solids, bounds, c_land, c_land + Vector2(-1500, 0))
	fails += _check(Geometry2D.is_point_in_polygon(p, SkyRealm.poly_points(landing)), "walking at the edge of an island stops you on it (%s)" % str(p.round()))
	var lm := _bridge(sky, "landing_millstone")
	var a := WorldData.to_vec2(lm["a"])
	var b := WorldData.to_vec2(lm["b"])
	var across := _walk(solids, bounds, a - (b - a).normalized() * 40.0, b + (b - a).normalized() * 60.0)
	fails += _check((across - b).dot((b - a).normalized()) > 0.0 and across.distance_to(b) < 200.0, "a rope bridge can be walked across (%s)" % str(across.round()))
	var head := WorldData.to_vec2(reveal["head"])
	var pennant := SkyRealm.centroid(SkyRealm.poly_points(_island(sky, "pennant")))
	var hid := _bridge(sky, String(reveal["bridge"]))
	var far := WorldData.to_vec2(hid["b"])
	var shut := _walk(solids, bounds, head - (far - head).normalized() * 40.0, far)
	fails += _check(shut.distance_to(head) < 70.0 and not bool(SkyRealm.ground_test(sky).call(far)), "the hidden bridge is shut: it stops you at the head")

	# The nest: in plain sight, out of reach.
	var nest := WorldData.to_vec2(secret["position"])
	fails += _check(String(reveal["type"]) == "skyview", "the secret is a nest behind a bird's-eye view")
	fails += _check(_has_secret_entry(), "the nest is there to be seen from the start")
	var dir = _world._secret_dir
	var sd = dir.get_node_or_null("SkyDirector")
	fails += _check(sd != null, "the sky director is running")
	if sd == null or layer == null:
		return _finish(fails)

	# Go up, as a shape that cannot: it says so and nothing happens.
	var comp = _world._companion
	comp._brain.get_self().met = true
	comp._brain.get_self().bond = 0.5
	comp.position = pennant + Vector2(-60, 0)
	player.position = comp.position + Vector2(30, 0)
	_world._on_radial_action("form:wolf")
	_world._on_radial_action("up")
	fails += _check(not sd.is_flying(), "a wolf cannot climb that high")
	# As a bird it can.
	_world._on_radial_action("form:bird")
	fails += _check(comp.current_form_species() == "bird", "the companion is a bird")
	_world._on_radial_action("up")
	fails += _check(sd.is_flying() and not comp.visible, "a bird lifts off, and the body stays hidden while it is up")
	var min_zoom := 1.0
	var picture := 0.0
	var steps := 0
	var camera: Camera2D = _world._camera
	var was_up_at_vantage := false
	while sd.is_flying() and steps < 2000:
		steps += 1
		sd.update(0.05)
		min_zoom = minf(min_zoom, camera.zoom.x)
		picture = maxf(picture, layer.air().picture())
		if sd.view().phase == SkyView.Phase.STAY and sd.view().pos.distance_to(sd.view().vantage()) < 2.0:
			was_up_at_vantage = true
	fails += _check(was_up_at_vantage and min_zoom < 0.45, "the camera rose with it (zoom %.2f)" % min_zoom)
	fails += _check(picture > 0.9, "the picture in the high clouds showed (%.2f)" % picture)
	fails += _check(sd.bridge_open() and layer.bridge_reveal(String(reveal["bridge"])) >= 0.999, "the bird saw the way, and the bridge is down")
	fails += _check(comp.visible and is_equal_approx(camera.zoom.x, 1.0) and layer.air().picture() == 0.0, "landed: the companion is back, the zoom ordinary, the picture gone")
	fails += _check(not camera.get("_cinematic"), "the camera follows the player again")

	# The way is open now.
	var solids2: Array = player._solids
	var over := _walk(solids2, bounds, head - (far - head).normalized() * 40.0, far + (far - head).normalized() * 40.0)
	fails += _check((over - far).dot((far - head).normalized()) > 0.0 and over.distance_to(far) < 200.0, "the new bridge can be walked to the Rookery (%s)" % str(over.round()))
	var at_nest := _walk(solids2, bounds, far, nest + Vector2(0, 20))
	fails += _check(at_nest.distance_to(nest) < 60.0, "...and on to the nest (%s)" % str(at_nest.round()))

	# Leaving the world mid-flight must hand everything back.
	sd.update(1.2)   # (it rests a moment after a landing)
	_world._on_radial_action("up")
	sd.update(0.05)
	sd.update(0.05)
	fails += _check(sd.is_flying(), "(a second flight)")
	sd.finish()
	fails += _check(comp.visible and is_equal_approx(camera.zoom.x, 1.0), "dropping a flight at once puts everything back")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")
	return _finish(fails)


func _island(sky: Dictionary, id: String) -> Dictionary:
	return SkyRealm.find_island(sky, id)


func _bridge(sky: Dictionary, id: String) -> Dictionary:
	return SkyRealm.find_bridge(sky, id)


## Walk a body from `a` toward `b` through the world's real resolver; where it ends up.
func _walk(solids: Array, bounds: Rect2, a: Vector2, b: Vector2) -> Vector2:
	var p := a
	var dir := (b - a).normalized()
	for _i in int(a.distance_to(b) / 3.0) + 20:
		p += dir * 3.0
		p = Solids.resolve(p, 6.0, solids, bounds, 2.0)
	return p


func _has_secret_entry() -> bool:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret":
			return true
	return false


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL LOFTREACH SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("LOFTREACH SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
