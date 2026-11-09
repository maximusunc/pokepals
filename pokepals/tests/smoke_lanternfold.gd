extends SceneTree
## Headless smoke test for LANTERNFOLD, the shadow-puppet world. Loads the real World scene from the test fixture
## as if we'd come through the Vale's Gateway and checks what makes it its own place:
##   * it re-skins itself (warm paper ground, trees in three depths) and a pale screen stands at the north end
##     with the great lantern before it;
##   * the secret is the shadow mural (reveal "shadow"): hidden at first, the ShadowDirector is running, the
##     animals' silhouettes are read off the real sheets and only the bird's matches the gap's, the shadow
##     projection lands on the face, tapping the lit ground stands the companion there (tapping elsewhere
##     does not), the bird on the spot fills the gap and the door and the paper bird appear, a wolf never does;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_lanternfold.gd

const LANTERNFOLD_ID := "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"

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
		net.prime_world_spec(LANTERNFOLD_ID, WorldData.load_json("res://tests/world_fixtures/lanternfold.json"))
		router.current_world = LANTERNFOLD_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", LANTERNFOLD_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/lanternfold.json")
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]

	var ground: Color = _world._style.color("ground_top")
	fails += _check(ground.v > 0.8 and ground.r > ground.b, "the ground is warm paper")
	var trees := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
	fails += _check(trees >= 200, "paper-cut trees stand in the world (%d)" % trees)

	# The screen and the lantern.
	var screen: ShadowScreenView = null
	for c in _world._scenery.get_children():
		if c is ShadowScreenView:
			screen = c
	fails += _check(screen != null, "the cliff-face screen stands at the north end")
	var face: Dictionary = reveal["face"]
	if screen != null:
		fails += _check(is_equal_approx(float(screen.face_rect()["base_y"]), float(face["base_y"])) and is_equal_approx(float(screen.face_rect()["x1"]), float(face["x1"])),
			"the screen's face is where the reveal says it is")
	var lantern := WorldData.to_vec2(reveal["lantern"])
	var lantern_prop := false
	for p in spec["props"]:
		if String(p["id"]) == "great_lantern":
			lantern_prop = absf(float(p["position"][0]) - lantern.x) < 1.0 and absf(float(p["position"][1]) + 6.0 - lantern.y) < 1.0
	fails += _check(lantern_prop, "the great lantern stands at the reveal's lantern point")

	# The secret: a shadow mural to be filled.
	fails += _check(String(reveal["type"]) == "shadow", "the secret is a mural's missing bird")
	var dir = _world._secret_dir
	var sd: ShadowDirector = dir.get_node_or_null("ShadowDirector")
	fails += _check(sd != null, "the shadow director is running")
	fails += _check(not _has_secret_entry(), "the paper bird is hidden until the gap is filled")
	if sd == null or screen == null:
		return _finish(fails)

	var guide: MuralGuide = sd.guide()
	var spot := WorldData.to_vec2(reveal["spot"])
	var t := guide.target()
	fails += _check(bool(t["ok"]) and bool(t["on_face"]), "the bird's shadow from the spot lands on the face")
	fails += _check(float(t["v"]) > 5.0 and float(t["v"]) + 26.0 * float(t["s"]) < float(face["height"]), "...in the air, and inside the mural (v=%.0f, s=%.2f)" % [float(t["v"]), float(t["s"])])
	fails += _check(ShadowCast.in_cone(face, lantern, spot), "the spot is on the lit stage")

	# The animals' real silhouettes: only the bird's is the gap's.
	var comp = _world._companion
	for sp in ["wolf", "rabbit", "cat", "fox"]:
		var f := guide.fit_of(sp, spot)
		print("    %s on the spot: fit %.2f place %.2f shape %.2f" % [sp, f["fit"], f["place"], f["shape"]])
		fails += _check(float(f["fit"]) < 0.5, "a %s's shadow does not fill the gap even on the spot" % sp)
	fails += _check(float(guide.fit_of("bird", spot)["fit"]) > 0.99, "the bird's does")

	# Placing it: a tap on the lit ground stands the companion there; ground in the dark does nothing.
	var lit_tap := Vector2(lantern.x + 30.0, lantern.y - 50.0)
	fails += _check(not dir.on_ground_tap(Vector2(1000, 900)), "a tap far from the stage does not stand it there")
	fails += _check(not dir.on_ground_tap(Vector2(lantern.x, face["base_y"] - 20.0)), "a tap on the screen's own footprint does not either")
	fails += _check(dir.on_ground_tap(lit_tap) and sd.is_posing(), "a tap on the lit ground stands the companion in the light")
	sd.release()

	# Filling the gap (the real-loop run is a separate scratch harness; here the guide is fed directly).
	var log: Array = []
	for _i in 60:
		var r := guide.update(0.1, "bird", spot, 0.0, spot + Vector2(0, -40), 0.5)
		log.append_array(r["events"])
	fails += _check(guide.is_done() and log.has("complete"), "the bird on the spot fills the gap")
	var wolf_guide := MuralGuide.new(reveal)
	wolf_guide.set_masks(guide._masks)
	for _i in 600:
		wolf_guide.update(0.1, "wolf", spot, 0.0, spot, 1.0)
	fails += _check(not wolf_guide.is_done(), "a wolf on the spot never does")
	sd.mural_done.emit()
	fails += _check(_has_secret_entry(), "the door opens and the paper bird is on its threshold")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")
	comp = null
	return _finish(fails)


func _has_secret_entry() -> bool:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret":
			return true
	return false


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL LANTERNFOLD SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("LANTERNFOLD SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
