extends SceneTree
## Headless smoke test for DOZEWOOD, the drowsy forest. Loads the real World scene from the test fixture as
## if we'd come through the Vale's Gateway and checks what makes it its own place:
##   * it re-skins itself (dusky moss palette, its own ground atlas, round/oak/willow trees);
##   * the secret is a place the companion dreams of (reveal "dream"): nothing shows at first, the nap
##     director is laid out with the four nap spots, a companion pet by a spot starts it drifting off, and
##     only after a dream does arriving at the crooked arch (with the companion) bring up the dream-lantern;
##   * it gets home to the Gateway like any catalog world.
## (The real nap loop, where the companion moves by itself, is checked by a scratch harness, not here:
## this stands the companion where it needs to be.)
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_dozewood.gd

const DOZEWOOD_ID := "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

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
		net.prime_world_spec(DOZEWOOD_ID, WorldData.load_json("res://tests/world_fixtures/dozewood.json"))
		router.current_world = DOZEWOOD_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", DOZEWOOD_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/dozewood.json")
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]

	var ground: Color = _world._style.color("ground_top")
	fails += _check(ground.g > ground.r and ground.v < 0.65, "the ground is dusky moss")
	var trees := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
	fails += _check(trees > 300, "the forest has its trees (%d)" % trees)

	fails += _check(String(reveal["type"]) == "dream", "the secret is a dream")
	var dir = _world._secret_dir
	var dd = dir.get_node_or_null("DozeDirector")
	fails += _check(dd != null, "the doze director is laid out")
	fails += _check(not _has_secret_entry(), "the dream-lantern isn't there to find yet")
	fails += _check((reveal["spots"] as Array).size() == 4, "four nap spots")
	fails += _check(ResourceLoader.exists(String(reveal["picture"])), "the dream picture is baked")
	if dd == null:
		return _finish(fails)
	var comp = _world._companion
	var player = _world._player
	var gate: DreamGate = dd.gate()
	var spot := WorldData.to_vec2(reveal["spots"][0])
	var arch := WorldData.to_vec2(reveal["landmark_position"])

	if not comp.is_met():
		comp.mark_met(0.0)

	# At the arch with no dream behind us: nothing.
	comp.position = arch + Vector2(20, 0)
	player.position = arch
	for _i in 5:
		dd.update(0.1)
	fails += _check(not _has_secret_entry(), "walking up to the arch before any dream finds nothing")

	# Dozing: stand by a spot, welcomed pet noted, still; with the companion's mood forced calm the gate
	# runs the real director frames (the body's mood is the sim's business, the harness checks the loop).
	comp.position = spot + Vector2(10, 0)
	player.position = spot + Vector2(40, 0)
	gate.note_pet()
	for _i in 4:
		gate.update(0.1, comp.position, player.position, Vector2(0.2, 0.0), 1.0)
	fails += _check(gate.drowse > 0.0, "a pet by a nap spot starts the drowse")

	# After a dream, together at the arch: the lantern rises.
	gate.dreamt = true
	comp.position = arch + Vector2(20, 0)
	player.position = arch
	for _i in 5:
		dd.update(0.1)
	fails += _check(_has_secret_entry(), "after the dream, arriving together brings up the dream-lantern")

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
		print("ALL DOZEWOOD SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("DOZEWOOD SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
