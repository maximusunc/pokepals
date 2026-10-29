extends SceneTree
## Headless smoke test for NOCTHOLLOW, the night planet. Points WorldRouter at it as if we'd just come
## through the Vale's Gateway, loads the real World scene from the test fixture, and checks the things
## that make it another planet rather than a re-dressed meadow:
##   * the world RE-SKINS itself (its own art block: night ground, glowing growths of several kinds);
##   * our player + companion wear the planet's light (palette-shift material + a glow aura);
##   * its native creatures spawn, are examinable (reading their lore), and are NOT companion forms;
##   * touching a glow-plant flares it; footsteps of light are being laid down;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_nocthollow.gd

const NOCTHOLLOW_ID := "66666666-6666-6666-6666-666666666666"
const NATIVE := ["lumejelly", "glimmerhop", "stiltwhisk", "driftray", "lanternsnail"]

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
		# Server-less: prime Net's cache from the fixture (a copy of server/priv/world_seeds/nocthollow.json,
		# both written by tools/gen_nocthollow_world.py) so the controller builds it as from a cached spec.
		net.prime_world_spec(NOCTHOLLOW_ID, WorldData.load_json("res://tests/world_fixtures/nocthollow.json"))
		router.current_world = NOCTHOLLOW_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", NOCTHOLLOW_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0

	# The world re-skinned itself: night ground from its own palette, not the meadow green.
	var ground: Color = _world._style.color("ground_top")
	fails += _check(ground.v < 0.25, "the ground is night-dark (v=%.2f)" % ground.v)
	fails += _check(not _world._style.actor_look().is_empty(), "the world carries an actor_look")

	# Glowing growths of several kinds stand in the y-sorted scenery.
	var trees := 0
	var glowing := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
			if c.glow_radius > 0.0:
				glowing += 1
	fails += _check(trees > 300, "the world is thick with growths (%d)" % trees)
	fails += _check(glowing == trees, "every growth gives off light (%d of %d)" % [glowing, trees])

	# Our pair wears the planet's light: a palette-shift material and an aura behind each.
	fails += _check(_world._player.material is ShaderMaterial, "the player wears the planet's palette shift")
	fails += _check(_world._companion.material is ShaderMaterial, "the companion wears the planet's palette shift")
	fails += _check(_world._player.get_node_or_null("OtherworldAura") != null, "the player glows")
	fails += _check(_world._companion.get_node_or_null("OtherworldAura") != null, "the companion glows")

	# The companion stays a familiar animal: no native creature is in the form pool.
	var native_forms := 0
	for f in PalView.available_forms():
		if NATIVE.has(String(f["species"])):
			native_forms += 1
	fails += _check(native_forms == 0, "no native creature is a companion form")
	fails += _check(not PalView.available_forms().is_empty(), "the familiar animal forms are still there")

	# Native creatures spawned and are examinable.
	var creatures: Array = []
	for e in _world._interactables:
		if String(e.get("kind", "")) == "creature":
			creatures.append(e)
	fails += _check(creatures.size() >= 50, "native creatures are examinable (%d)" % creatures.size())
	if not creatures.is_empty():
		var c: Dictionary = creatures[0]
		_world._player.position = c["pos"] + Vector2(10, 0)
		_world._invalidate_nearest()
		var idx: int = _world._nearest_interactable()
		fails += _check(idx >= 0 and String(_world._interactables[idx]["kind"]) == "creature", "standing by a creature, it's the thing to examine")
		if idx >= 0:
			_world._try_interact()
			fails += _check(_world._hint.text == String(_world._interactables[idx]["lore"]) and _world._hint.text != "", "examining a creature reads its lore")

	# Touching a glow-plant flares it.
	# Try glow-plants until one is the nearest thing when we stand on it (a creature may be wandering
	# right beside the first one we pick).
	var bi := -1
	var any_flare := false
	for i in _world._interactables.size():
		var e: Dictionary = _world._interactables[i]
		if not bool(e.get("flare", false)):
			continue
		any_flare = true
		_world._player.position = e["pos"] + Vector2(0, 4)
		_world._invalidate_nearest()
		if _world._nearest_interactable() == i:
			bi = i
			break
	fails += _check(any_flare, "the world has glow-plants that flare")
	if any_flare:
		if bi >= 0:
			_world._try_interact()
			var ri := int(_world._interactables[bi]["render_index"])
			fails += _check(float(_world._world_art._interactables[ri]["flare"]) > 0.9, "the touched glow-plant blazed up")
		else:
			fails += _check(false, "standing by a glow-plant, it's the thing to examine")

	# Footsteps of light are being laid on the ground.
	fails += _check(_world._world_art.get_node_or_null("GlowTrail") != null, "footsteps of light are on")

	# A catalog world with no Return of its own goes home to the hub's Gateway.
	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")

	if fails == 0:
		print("ALL NOCTHOLLOW SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("NOCTHOLLOW SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
