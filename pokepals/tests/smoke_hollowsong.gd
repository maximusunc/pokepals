extends SceneTree
## Headless smoke test for HOLLOWSONG, the echo canyon. Loads the real World scene from the test fixture as
## if we'd come through the Vale's Gateway and checks what makes it its own place:
##   * it re-skins itself (sun-baked ground, junipers and cottonwoods, banded cliffs as CliffViews);
##   * the arches can be walked through (only their legs collide) and the cliffs' edges are the echo walls;
##   * the secret is a hidden cave (reveal "echo"): the howl director is running, the stone is NOT in the
##     world yet, the radial offers Howl, only a wolf howls, the canyon answers with ripples, one answer is
##     the cave's wrong one, walking up opens the crack and the stone is there;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_hollowsong.gd

const HOLLOWSONG_ID := "dddddddd-dddd-dddd-dddd-dddddddddddd"

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
		net.prime_world_spec(HOLLOWSONG_ID, WorldData.load_json("res://tests/world_fixtures/hollowsong.json"))
		router.current_world = HOLLOWSONG_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", HOLLOWSONG_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/hollowsong.json")
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]

	var ground: Color = _world._style.color("ground_top")
	fails += _check(ground.r > ground.b and ground.v > 0.5, "the ground is warm and sun-baked")
	var trees := 0
	var cliffs := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
		elif c is CliffView:
			cliffs += 1
	fails += _check(trees > 250, "junipers, sage and cottonwoods stand in the canyon (%d)" % trees)
	fails += _check(cliffs == (spec["buildings"] as Array).size() and cliffs >= 30, "the cliffs are CliffViews (%d)" % cliffs)

	# An arch can be walked through; its legs cannot.
	var solids := Solids.build(spec, [], spec.get("collision", {}))
	var gap := Vector2(0, -150)        # beneath the great arch
	var leg := Vector2(-150, -150)
	fails += _check(_free(solids, gap), "you can walk through the great arch")
	fails += _check(not _free(solids, leg), "...but not through its legs")

	# The walls the echoes bounce off.
	var walls := EchoField.walls_from(reveal["walls"])
	fails += _check(walls.size() > 100, "the cliffs' edges are the canyon's echoing walls (%d)" % walls.size())

	# The secret: a hidden cave, a howling wolf.
	fails += _check(String(reveal["type"]) == "echo", "the secret is a cave that answers wrong")
	var dir = _world._secret_dir
	var hd = dir.get_node_or_null("HowlDirector")
	fails += _check(hd != null, "the howl director is running")
	fails += _check(not _has_secret_entry(), "the stone is not in the world until the cave opens")
	fails += _check(dir.howl_available(), "the radial offers Howl")
	if hd == null:
		return _finish(fails)

	var comp = _world._companion
	var player = _world._player
	comp._brain.get_self().met = true
	comp.instruct_form("dog_that_does_not_exist")   # a no-op: just make sure a wrong species is harmless
	var guide: EchoGuide = hd.guide()

	# Not a wolf: no howl, a kind hint.
	player.position = Vector2(-1500, 420)
	comp.position = player.position + Vector2(-40, 0)
	if comp.current_form_species() == "wolf":
		comp.instruct_form("cat")
	var before := guide.howl_count()
	hd.try_howl()
	fails += _check(guide.howl_count() == before, "a companion that is not a wolf cannot howl")

	# A wolf howls near a cliff and the ripples appear.
	_world._on_radial_action("form:wolf")
	fails += _check(comp.current_form_species() == "wolf", "the radial turns it into a wolf")
	player.position = Vector2(300, 150)    # the Choir, near cliffs
	comp.position = player.position + Vector2(-40, 0)
	_world._on_radial_action("howl")
	fails += _check(guide.howl_count() == before + 1, "a wolf howls on the radial's Howl")
	fails += _check(hd.ripples().active_count() == 1, "the canyon's answer is drawn")
	_world._on_radial_action("howl")
	fails += _check(guide.howl_count() == before + 1, "a second howl straight away waits out the cooldown")

	# The wrong answer comes from the cave, and only within earshot.
	guide.update(10.0, Vector2(300, 150), 1.0)
	var cave := guide.cave_origin()
	var near := EchoField.wrong_echo(cave + Vector2(0, 600), cave + Vector2(0, 600), cave, reveal, 1.0, 3)
	var far := EchoField.wrong_echo(cave + Vector2(-3000, 1200), cave + Vector2(-3000, 1200), cave, reveal, 1.0, 3)
	fails += _check(not near.is_empty() and far.is_empty(), "the cave answers a howl from 600 px but not from across the world")

	# A friend's howl is drawn too.
	var heard_before: int = hd.ripples().active_count()
	root.get_node("/root/Net").emit_signal("howl_heard", 100.0, 200.0)
	fails += _check(hd.ripples().active_count() == heard_before + 1, "a friend's howl draws its ripples here too")

	# Walking up opens the cave and brings the stone up.
	var mouth := guide.cave_mouth()
	player.position = mouth + Vector2(0, 150)
	comp.position = player.position + Vector2(-30, 0)
	for _i in 5:
		dir.update(0.1)
	fails += _check(guide.is_revealed(), "walking up to the cave opens it")
	fails += _check(_has_secret_entry(), "...and the answering stone is there to examine")

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")
	return _finish(fails)


func _free(solids: Array, p: Vector2) -> bool:
	return Solids.resolve(p, 6.0, solids, Rect2(-1800, -1300, 3600, 2600), 2.0).distance_to(p) < 0.5


func _has_secret_entry() -> bool:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret":
			return true
	return false


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL HOLLOWSONG SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("HOLLOWSONG SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
