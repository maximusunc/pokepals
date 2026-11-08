extends SceneTree
## Headless smoke test for STEAMHOLLOW, the bathhouse village lost in fog. Loads the real World scene from
## the test fixture as if we'd come through the Vale's Gateway and checks what makes it its own place:
##   * it re-skins itself (damp ground, its own trees, hot-spring water, timber bathhouses, boardwalks);
##   * the fog (MistVeil) and the steam (SteamPuffs) are laid out, and lanterns/doors shine through;
##   * the secret is a faint bell (reveal "listen"): it hangs in the world from the start, the
##     ListenDirector is running, and the companion's gaze turns toward it only when settled and in range;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_steamhollow.gd

const STEAMHOLLOW_ID := "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

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
		net.prime_world_spec(STEAMHOLLOW_ID, WorldData.load_json("res://tests/world_fixtures/steamhollow.json"))
		router.current_world = STEAMHOLLOW_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", STEAMHOLLOW_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/steamhollow.json")
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]

	var ground: Color = _world._style.color("ground_top")
	fails += _check(ground.g > ground.r and ground.v < 0.6, "the ground is damp green-grey moss")
	var trees := 0
	var houses := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
		elif c is BathhouseView:
			houses += 1
	fails += _check(trees > 300, "cedars, maples and willows stand in the mist (%d)" % trees)
	fails += _check(houses == (spec["buildings"] as Array).size() and houses >= 6, "the bathhouses are timber (%d)" % houses)

	# The air: fog and steam.
	var veil = _world.get_node_or_null("MistVeil")
	fails += _check(veil != null and veil is MistVeil, "the mist veil is laid over the view")
	fails += _check(veil != null and veil.static_light_count() > 40, "lanterns and doorways shine through it (%d)" % (veil.static_light_count() if veil != null else 0))
	var steam = _world.get_node_or_null("SteamPuffs")
	fails += _check(steam != null and steam.column_count() > 20, "the springs breathe steam (%d columns)" % (steam.column_count() if steam != null else 0))

	# The secret: a bell in the fog, and a companion who listens.
	fails += _check(String(reveal["type"]) == "listen", "the secret is a faint bell")
	var dir = _world._secret_dir
	var ld = dir.get_node_or_null("ListenDirector")
	fails += _check(ld != null, "the listen director is running")
	fails += _check(_has_secret_entry(), "the bell hangs in the world")
	if ld == null:
		return _finish(fails)

	var bell := WorldData.to_vec2(secret["position"])
	var comp = _world._companion
	var player = _world._player
	var at: Vector2 = bell + Vector2(-260, 0)
	player.position = at
	comp.position = at + Vector2(-40, 0)
	player.velocity = Vector2.ZERO
	comp.velocity = Vector2.ZERO
	for _i in 40:
		ld.update(0.1)
	fails += _check(comp._listen_t > 0.3, "settled beside you in range, the companion listens (%.2f)" % comp._listen_t)
	fails += _check((comp._listen_pos - bell).length() < 400.0, "...and its gaze is toward the bell")
	player.velocity = Vector2(118, 0)
	for _i in 60:
		ld.update(0.1)
	fails += _check(comp._listen_t < 0.05, "walk on and it loses the sound")
	player.velocity = Vector2.ZERO
	player.position = Vector2(500, 500)   # far across the world
	comp.position = player.position + Vector2(-40, 0)
	for _i in 60:
		ld.update(0.1)
	fails += _check(comp._listen_t < 0.05, "far from the bell it hears nothing")

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
		print("ALL STEAMHOLLOW SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("STEAMHOLLOW SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
