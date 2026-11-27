extends SceneTree
## Headless smoke test for GLINTWOLD's look (the ground, the water, the visitors). Loads the real World scene from
## the fixture, with the look fragment (tools/lowpoly/glintwold_look.json) merged over its art block the way the
## world generator does, and checks:
##   * the ground is ONE faceted shader (FacetGround) in place of any floor, and WorldArt draws no paths, ponds or
##     grass of its own;
##   * the baked mask knows the water (with its bands, far side first), the paths and the open grass;
##   * you and your companion share one faceted material, and the ground turns its light;
##   * a step makes the facet underfoot flash;
##   * the per-frame work stays small.
## Run on its own:
##   godot --headless --path gates-of-elyra --script res://tests/smoke_glintwold_look.gd

const GLINTWOLD_ID := "17171717-1717-1717-1717-171717171717"

var _world: Node
var _frames := 0
var _done := false


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	for k in b:
		if b[k] is Dictionary and a.get(k) is Dictionary:
			_merge(a[k], b[k])
		else:
			a[k] = b[k]
	return a


func _spec() -> Dictionary:
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/glintwold.json")
	var look: Dictionary = WorldData.load_json("res://tools/lowpoly/glintwold_look.json")
	look.erase("_comment")
	if not spec.has("art"):
		spec["art"] = {}
	_merge(spec["art"], look)
	return spec


func _process(_delta: float) -> bool:
	_frames += 1
	if _done:
		return true
	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(GLINTWOLD_ID, _spec())
		router.current_world = GLINTWOLD_ID
		router.arrival_portal_id = ""
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", GLINTWOLD_ID)
		return false
	if _frames < 8:
		return false
	_done = true
	var fails := 0
	var spec := _spec()
	var art = _world._world_art
	var ground = art.facet_ground()
	fails += _check(ground != null and ground.material is ShaderMaterial, "the ground is the faceted shader")
	if ground == null:
		quit(fails)
		return true
	fails += _check((ground.material as ShaderMaterial).shader.resource_path == "res://assets/gw_facet.gdshader",
		"drawn by gw_facet.gdshader")
	fails += _check(art.grid_ground() == null and art._ground == null, "and no other ground beneath it")
	fails += _check(art._grass.is_empty(), "no blades of grass drawn over the facets")

	# the mask: water (bands from the far, north bank), paths, grass
	var ponds: Array = spec.get("ponds", [])
	if not ponds.is_empty():
		var big: Dictionary = ponds[0]
		for p in ponds:
			if float(p["radius"]) > float(big["radius"]):
				big = p
		var c := WorldData.to_vec2(big["center"])
		var r := float(big["radius"])
		var mid: Dictionary = ground.mask_at(c)
		fails += _check(float(mid["water"]) > 0.5, "a pond's middle is water")
		var north: Dictionary = ground.mask_at(c + Vector2(0, -r * 0.7))
		var south: Dictionary = ground.mask_at(c + Vector2(0, r * 0.7))
		fails += _check(float(north["band"]) < float(south["band"]), "its bands run from the far (north) bank to the near one")
		fails += _check(float(ground.mask_at(c + Vector2(r * 2.2, 0))["water"]) < 0.5, "well past its bank is dry")
	var paths: Array = spec.get("paths", [])
	if not paths.is_empty():
		var a := WorldData.to_vec2(paths[0]["from"])
		fails += _check(float(ground.mask_at(a)["path"]) > 0.5, "a path's start is on the path")

	# the visitors
	var pm := _world._player.material as ShaderMaterial
	var cm := _world._companion.material as ShaderMaterial
	fails += _check(pm != null and pm.shader == OtherworldLook.FACET_SHADER and cm == pm,
		"you and your companion share one faceted material")

	# the light turns, and the ground hands it to the visitors
	var la: float = ground.light_angle()
	fails += _check(pm != null and is_equal_approx(float(pm.get_shader_parameter("light_angle")), la),
		"the visitors are lit by the ground's light")
	ground._cfg["light_start"] = float(ground._cfg.get("light_start", -135.0)) + 90.0
	ground._process(0.016)
	fails += _check(absf(angle_difference(la, ground.light_angle())) > 1.0, "the light angle follows the clock and config")

	# a step flashes the facet underfoot
	var before: int = ground._next
	ground.add_pulse(Vector2(10, 10))
	fails += _check(ground._next != before, "a step is handed to the shader")

	# per-frame cost
	var t0 := Time.get_ticks_usec()
	for i in 200:
		ground._process(0.016)
	var per := float(Time.get_ticks_usec() - t0) / 200.0
	print("  (FacetGround._process: %.1f us a frame)" % per)
	fails += _check(per < 300.0, "the ground's per-frame work is small (%.1f us)" % per)

	print("")
	print("smoke_glintwold_look: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(fails)
	return true


func _check(cond: bool, label: String) -> int:
	print(("  PASS  " if cond else "  FAIL  ") + label)
	return 0 if cond else 1
