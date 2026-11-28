extends SceneTree
## Headless smoke test for LINGERLONG, the plaza in the sky. Loads the real World scene from the test fixture as if
## we'd come through the Vale's Gateway and checks what makes it its own place:
##   * its ground is the plaza shader (PlazaGround) in place of any floor, with every floor and the pool handed to it;
##   * you can stand only on the plaza: the floors and the pool are ground, the sky is not, you arrive on a floor,
##     a body walked at the pool's far edge stops there, and the evening terrace is an island no route reaches;
##   * the busts float over their plinths, the arches stand (the Late Arch and the terrace's arch with their
##     pictures), the fountain stands and swells;
##   * the evening comes on the terrace and goes again in the plaza, and wading rings the water;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path gates-of-elyra --script res://tests/smoke_lingerlong.gd

const LINGERLONG_ID := "18181818-1818-1818-1818-181818181818"
const FIXTURE := "res://tests/world_fixtures/lingerlong.json"

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
		net.prime_world_spec(LINGERLONG_ID, WorldData.load_json(FIXTURE))
		router.current_world = LINGERLONG_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", LINGERLONG_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json(FIXTURE)
	var plaza: Dictionary = spec["plaza"]

	# The look.
	var pg: PlazaGround = _world._world_art.plaza_ground()
	fails += _check(pg != null and pg.material is ShaderMaterial, "the ground is the plaza shader, and nothing else")
	if pg != null:
		var mat := pg.material as ShaderMaterial
		fails += _check(int(mat.get_shader_parameter("floor_count")) == (plaza["floors"] as Array).size(), "every floor is handed to it")
		var pool: Vector4 = mat.get_shader_parameter("pool")
		fails += _check(pool.z > pool.x and pool.w > pool.y, "and the pool")

	# Where you can stand.
	var ground := PlazaRealm.ground_test(plaza)
	var spawn := WorldData.to_vec2(spec["player_spawn"])
	fails += _check(not PlazaRealm.floor_at(plaza, spawn).is_empty() and not PlazaRealm.floor_at(plaza, _world._player.position).is_empty(),
		"you arrive on the floor")
	fails += _check(bool(ground.call(Vector2(0, -700))) and not bool(ground.call(Vector2(0, -1200))) and not bool(ground.call(Vector2(-1200, 800))),
		"the pool is ground, the sky beyond it and beside the court is not")
	var solids := Solids.build(spec, [], spec.get("collision", {}))
	var bounds := Rect2(WorldData.to_vec2(spec["bounds"]["min"]), WorldData.to_vec2(spec["bounds"]["max"]) - WorldData.to_vec2(spec["bounds"]["min"]))
	var end := _walk(solids, bounds, Vector2(0, -600), Vector2(0, -1400))
	fails += _check(end.y > -1000.0 and end.y < -970.0, "a body walked across the pool stops at its far edge (y = %.1f)" % end.y)
	end = _walk(solids, bounds, Vector2(-600, 400), Vector2(-600, 1200))
	fails += _check(end.y < 900.0, "and the court's south edge holds a body in (y = %.1f)" % end.y)
	end = _walk(solids, bounds, Vector2(0, -400), Vector2(0, -1900))
	fails += _check(end.y > -1000.0, "nobody walks to the evening terrace (y = %.1f)" % end.y)
	var grid := NavGrid.build(solids, bounds, 6.0, 2.0, 16.0, ground)
	var route := grid.find_path(spawn, WorldData.to_vec2(spec["doorway"]["through"]), 60000, 0)
	var reached := false
	for p: Vector2 in route:
		if p.y < -1500.0:
			reached = true
	fails += _check(not reached, "and no route the companion could plan reaches it either")
	var court_route := grid.find_path(spawn, Vector2(1140, 300), 60000)
	fails += _check(not court_route.is_empty() and (court_route.back() as Vector2).distance_to(Vector2(1140, 300)) < 24.0,
		"while a route from the steps to the Gallery is found")
	var terrace_floor := PlazaRealm.floor_at(plaza, WorldData.to_vec2(spec["doorway"]["through"]))
	fails += _check(String(terrace_floor.get("id", "")) == "evening_terrace", "the doorway sets you down on the evening terrace")

	# What stands on it.
	var floating := 0
	for c in _world._scenery.get_children():
		if c is TreeView and not (c as TreeView).float_cfg.is_empty():
			floating += 1
	fails += _check(floating == 4, "four busts float over their plinths (%d)" % floating)
	var late: BuildingView = _world.arch_view("late_arch")
	var back: BuildingView = _world.arch_view("return_arch")
	fails += _check(late is ArchView and back is ArchView, "the Late Arch and the terrace's arch stand")
	if late is ArchView and back is ArchView:
		fails += _check((late as ArchView).picture() == "dusk" and (back as ArchView).picture() == "noon" and (_world.arch_view("promenade_arch") as ArchView).picture() == "",
			"each with its picture under the frame (and an ordinary arch with none)")
		fails += _check(late.position.distance_to(WorldData.to_vec2(spec["doorway"]["at"])) < 1.0, "the Late Arch stands where the doorway says")
	end = _walk(solids, bounds, Vector2(0, 700), Vector2(0, 560))
	fails += _check(end.y < 580.0, "you walk through the promenade arch (y = %.1f)" % end.y)
	end = _walk(solids, bounds, Vector2(-40, 700), Vector2(-40, 560))
	fails += _check(end.y > 600.0, "but not through its leg (y = %.1f)" % end.y)
	var fv: FountainView = _world.fountain_view()
	fails += _check(fv != null and fv.position.distance_to(WorldData.to_vec2(spec["fountain"]["center"])) < 1.0, "the wishing fountain stands in the middle")
	if fv != null:
		fv.swell(1.0)
		fails += _check(fv.swelling() > 0.9, "and its jets can swell")
	var examinable := 0
	for e in _world._interactables:
		var id := String(e.get("id", ""))
		if id == "wishing_fountain" or id.begins_with("bust_") or id == "brass_plaque":
			examinable += 1
	fails += _check(examinable == 6, "the fountain, the plaque and the four busts can be examined (%d)" % examinable)
	end = _walk(solids, bounds, Vector2(30, 420), Vector2(30, 200))
	fails += _check(end.distance_to(Vector2(0, 240)) <= 60.0, "close enough to the fountain to examine it (%.1f away)" % end.distance_to(Vector2(0, 240)))

	# The evening, and the water.
	if pg != null:
		fails += _check(is_equal_approx(pg.evening(), 0.0), "it is afternoon in the plaza")
		_world._player.position = WorldData.to_vec2(spec["doorway"]["through"])
		for _i in 20:
			pg._process(0.1)
		fails += _check(pg.evening() > 0.99, "and evening on the terrace")
		_world._player.position = Vector2(0, -700)
		for _i in 20:
			pg._process(0.1)
		fails += _check(pg.evening() < 0.01, "and afternoon again back in the pool")
		var before: int = _ripple_count(pg)
		for k in 4:
			_world._player.position = Vector2(30.0 * k, -700)
			pg._process(0.12)
		fails += _check(_ripple_count(pg) > before, "wading rings the water")
		_world._player.position = Vector2(0, 600)
		var still: int = _ripple_count(pg)
		for k in 4:
			_world._player.position = Vector2(30.0 * k, 600)
			pg._process(0.12)
		fails += _check(_ripple_count(pg) == still, "but the marble keeps no prints")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")
	return _finish(fails)


func _ripple_count(pg: PlazaGround) -> int:
	var n := 0
	for r: Vector4 in pg._ripples:
		if r.w > 0.0:
			n += 1
	return n


## Walk a body from `a` toward `b` in small steps through the real resolver; where it ends up.
func _walk(solids: Array, bounds: Rect2, a: Vector2, b: Vector2) -> Vector2:
	var p := a
	var dir := (b - a).normalized()
	for _i in int(a.distance_to(b) / 2.0) + 40:
		p += dir * 2.0
		p = Solids.resolve(p, 6.0, solids, bounds, 2.0)
	return p


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL LINGERLONG SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("LINGERLONG SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
