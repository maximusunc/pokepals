extends SceneTree
## Headless smoke test for GLYPHFALL, the world made of text. Loads the real World scene from the test fixture
## as if we'd come through the Vale's Gateway and checks what makes it its own place:
##   * the page: a GlyphPage layer sits over the world, under the vignette and the HUD, with its atlas, its
##     sentences and the wrong glyph's cell; you and your companion are marked for its fine print;
##   * the secret, played through the real directors: far away your companion notices nothing; in range it stops
##     and looks at the glyph; until it has looked the glyph is only grass; walk to where it looked and the
##     glyph shines and can be examined; taking it corrects the page;
##   * it gets home to the Gateway like any catalog world.
## Headless draws nothing, so what the page LOOKS like is checked by eye with tests/shot_world.gd.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_glyphfall.gd

const GLYPHFALL_ID := "19191919-1919-1919-1919-191919191919"

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
		net.prime_world_spec(GLYPHFALL_ID, WorldData.load_json("res://tests/world_fixtures/glyphfall.json"))
		router.current_world = GLYPHFALL_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", GLYPHFALL_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/glyphfall.json")
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]
	var glyph := WorldData.to_vec2(secret["position"])

	# The page.
	var page: GlyphPage = _world.glyph_page()
	fails += _check(page != null, "a page of text lies over the world")
	if page == null:
		return _finish(fails)
	fails += _check(page.get_index() < _world.get_node("Vignette").get_index() and page.get_index() < _world.get_node("UI").get_index(),
		"...under the vignette and the HUD, which stay as they are")
	var mat := (page.get_node("Page") as ColorRect).material as ShaderMaterial
	fails += _check(mat != null and mat.get_shader_parameter("atlas") is Texture2D, "it has its atlas of characters")
	var text_size: Vector2 = mat.get_shader_parameter("text_size")
	fails += _check(is_equal_approx(float(mat.get_shader_parameter("text_on")), 1.0) and int(text_size.y) == (spec["atmosphere"]["glyphs"]["sentences"] as Array).size(),
		"the paths are written in the writer's sentences (%d lines)" % int(text_size.y))
	fails += _check(page.special_index("&") >= 0, "the atlas holds the wrong glyph")
	var pm := _world._player.material as ShaderMaterial
	var cm := _world._companion.material as ShaderMaterial
	fails += _check(pm != null and pm.shader == OtherworldLook.GLYPH_SHADER and cm != null and cm.shader == OtherworldLook.GLYPH_SHADER,
		"you and your companion are marked, so the page writes you in fine print")
	var trees := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
	fails += _check(trees >= 300, "the trees stand in their paragraphs (%d)" % trees)

	# The secret.
	fails += _check(String(reveal["type"]) == "misprint", "the secret is a wrong glyph")
	var dir = _world._secret_dir
	var md = dir.get_node_or_null("MisprintDirector")
	fails += _check(md != null, "the misprint director is running")
	if md == null:
		return _finish(fails)
	var comp = _world._companion
	var player = _world._player
	comp._brain.get_self().bond = 0.5
	md.update(0.1)
	fails += _check((mat.get_shader_parameter("wrong_cell") as Vector2) == page.cell_of(glyph), "the wrong glyph stands in its cell on the page")
	fails += _check(not _has_secret_entry(), "...and is only grass to you: nothing to examine yet")

	player.position = Vector2(-900, 600)
	comp.position = player.position + Vector2(-30, 0)
	for _i in 100:
		md.update(0.1)
	fails += _check(comp._point_t < 0.05 and not md.notice().has_noticed(), "far away your companion notices nothing")

	player.position = glyph   # standing on it, with the companion far off: still grass
	comp.position = glyph + Vector2(-700, 0)
	for _i in 20:
		md.update(0.1)
	fails += _check(not _has_secret_entry(), "standing on it without your companion, it is still only grass")

	player.position = glyph + Vector2(-140, 40)
	comp.position = player.position + Vector2(-30, 0)
	md.update(0.1)
	fails += _check(comp._point_t > 0.9 and (comp._point_pos - glyph).length() < 1.0, "in range, your companion stops and looks at it")
	for _i in 40:
		md.update(0.1)
	fails += _check(comp._point_t < 0.05, "...for a moment, and then walks on")
	player.position = glyph + Vector2(-60, 0)
	comp.position = player.position + Vector2(-30, 0)
	md.update(0.1)
	var glow := float(mat.get_shader_parameter("wrong_glow"))
	fails += _check(glow > 0.05 and glow < 1.0, "as you close in the glyph catches the light (%.2f)" % glow)
	player.position = glyph + Vector2(-12, 6)
	md.update(0.1)
	fails += _check(_has_secret_entry(), "walk to where it looked and the ampersand can be examined")
	fails += _check(is_equal_approx(float(mat.get_shader_parameter("wrong_glow")), 1.0) and comp._point_t < 0.05, "it shines, and your companion is let go")

	dir._take()
	fails += _check((mat.get_shader_parameter("wrong_cell") as Vector2) != page.cell_of(glyph), "taking it corrects the page: grass stands there now")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")
	return _finish(fails)


func _has_secret_entry() -> bool:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret" and not bool(e.get("_taken", false)):
			return true
	return false


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL GLYPHFALL SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("GLYPHFALL SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
