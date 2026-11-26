extends SceneTree
## Headless smoke test for LINGERLONG's secret way, the Late Arch (DoorwayDirector over DoorwayGate). Loads the real
## World scene from the test fixture and plays it through:
##   * the doorway director is running, the place card is already on the terrace (reveal "doorway": being there IS
##     the reveal), and walking through the Late Arch yourself does nothing but bring you out the other side;
##   * near the arch your companion notices it and points; "Go look" is on offer; a tap on the arch is an order;
##   * it trots to the threshold, sniffs, and steps into the picture: its body hidden (and set down on the terrace,
##     where a friend's screen sees it), its mind paused, drawn small in the doorway, and the door is open;
##   * stepping into the doorway from the front takes you both to the terrace: the sky goes to evening, the camera
##     is put there, your companion is beside you and its own again;
##   * the place card is examined and claimed (the server's answer is played as it would arrive), and taken;
##   * the terrace's arch takes you both back to the pool in the afternoon, from either side, also after a "resume";
##   * if you don't follow in time it trots back out and rejoins you; a Call brings it out early.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_lingerlong_secret.gd

const LINGERLONG_ID := "17171717-1717-1717-1717-171717171717"
const FIXTURE := "res://tests/world_fixtures/lingerlong.json"
const DT := 0.05

var _world: Node
var _frames := 0
var _started := false
var _fails := 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(LINGERLONG_ID, WorldData.load_json(FIXTURE))
		router.current_world = LINGERLONG_ID
		router.arrival_portal_id = ""
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", LINGERLONG_ID)
		paused = false
		return false
	paused = false   # (offline, the lobby gate would hold the tree; the crossing's fade is a tween that needs it running)
	if _frames >= 8 and not _started:
		_started = true
		_play()
	return false


func _play() -> void:
	var spec: Dictionary = WorldData.load_json(FIXTURE)
	var dw: Dictionary = spec["doorway"]
	var at := WorldData.to_vec2(dw["at"])
	var back_at := WorldData.to_vec2(dw["back_at"])
	var through := WorldData.to_vec2(dw["through"])
	var back_to := WorldData.to_vec2(dw["back_to"])
	var comp = _world._companion
	var player = _world._player
	var dd = _world.doorway_director()
	var pg: PlazaGround = _world._world_art.plaza_ground()
	var late: ArchView = _world.arch_view("late_arch")
	_check(dd != null, "the doorway director is running")
	if dd == null:
		_finish()
		return
	var gate = dd.gate()
	comp._brain.get_self().met = true
	comp._brain.get_self().bond = 0.5
	comp._form_species = "fox"

	# The place card is on the terrace from the start, as the secret's prop.
	var card := _secret_entry()
	_check(not card.is_empty() and (card["pos"] as Vector2).distance_to(WorldData.to_vec2(spec["secret"]["position"])) < 1.0,
		"the place card waits on the terrace table (a doorway secret is simply there)")

	# A shut door: you come out the other side.
	player.position = at + Vector2(0, 10)
	comp.position = at + Vector2(-30, 40)
	_step(dd, comp, 1)
	player.position = at + Vector2(0, -10)
	_step(dd, comp, 1)
	_check(not dd.is_crossing() and player.position.distance_to(at + Vector2(0, -10)) < 0.1, "walking through the Late Arch yourself does nothing")

	# Noticing, and the offer.
	player.position = at + Vector2(0, 220)
	comp.position = at + Vector2(-30, 240)
	gate._notice_cd = 0.0
	_step(dd, comp, 2)
	_check(comp._point_t > 0.0, "near the arch your companion points at it")
	_check(_world._secret_dir.can_go_look(), "Go look is on offer near the arch")
	player.position = at + Vector2(0, 600)
	_check(not _world._secret_dir.can_go_look(), "and not from far off")
	player.position = at + Vector2(0, 140)

	# The order: a tap on the arch.
	_check(dd.on_tap(gate.door_middle()), "a tap on the arch is an order")
	_check(gate.is_busy(), "it sets off")
	var opened := _run_until(dd, comp, func() -> bool: return gate.is_open(), 15.0)
	_check(opened, "it trots over, sniffs, and steps into the picture")
	_check(not comp.visible and not comp.is_processing(), "its body is hidden and its mind paused while it waits in there")
	_check(PlazaRealm.floor_at(spec["plaza"], comp.position).get("id", "") == "evening_terrace", "its real place is the terrace (a friend sees it vanish)")
	_check(late._between.is_valid() and late._animated, "the arch draws it in the doorway, and glows")

	# Step in after it.
	player.position = at + Vector2(0, 8)
	_step(dd, comp, 1)
	player.position = at + Vector2(0, -6)
	_step(dd, comp, 1)
	_check(dd.is_crossing(), "stepping into the open doorway from the front takes you through")
	await create_timer(1.1).timeout
	_check(not dd.is_crossing() and player.position.distance_to(through) < 1.0, "you land on the evening terrace")
	_check(comp.visible and comp.is_processing() and comp.position.distance_to(through) < 40.0, "with your companion beside you, its own again")
	_check(pg != null and pg.evening() > 0.99, "and the sky is evening")
	var cam: Camera2D = _world._camera
	_check(cam.global_position.distance_to(through) < 200.0, "the camera is put there, not slid (%.0f px off)" % cam.global_position.distance_to(through))
	_check(not late._between.is_valid(), "the Late Arch is a still picture again")

	# The place card.
	player.position = WorldData.to_vec2(spec["secret"]["position"]) + Vector2(0, 24)
	_world._invalidate_nearest()
	var near: int = _world._nearest_interactable()
	_check(near >= 0 and String(_world._interactables[near].get("kind", "")) == "secret", "the place card is the thing to examine at the table")
	if near >= 0:
		_world._try_interact()
		var net := root.get_node("/root/Net")
		net.secret_found.emit(String(spec["secret"]["id"]), true, [])
		await create_timer(_world.MOMENT_FADE_IN + 0.3).timeout
		_check(_secret_entry().is_empty(), "claimed, and taken from the table")

	# Back to the afternoon, through the terrace's arch from the front.
	player.position = back_at + Vector2(0, 10)
	_step(dd, comp, 1)
	player.position = back_at + Vector2(0, -8)
	_step(dd, comp, 1)
	_check(dd.is_crossing(), "the terrace's arch takes you back")
	await create_timer(1.1).timeout
	_check(player.position.distance_to(back_to) < 1.0 and comp.position.distance_to(back_to) < 80.0, "both of you, to the pool (%s, %s)" % [player.position, comp.position])
	_check(pg.evening() < 0.01, "and it is afternoon again")

	# A player who resumes on the terrace (no last step) walks back out the way they came, from behind the arch.
	player.position = through
	comp.position = through + Vector2(-20, 12)
	dd._prev = Vector2.INF
	_step(dd, comp, 1)
	player.position = back_at + Vector2(0, -14)
	_step(dd, comp, 1)
	player.position = back_at + Vector2(0, -2)
	# (the jump from `through` to just behind the arch is a teleport, never a step; take two real steps)
	_step(dd, comp, 1)
	if not dd.is_crossing():
		player.position = back_at + Vector2(0, -12)
		_step(dd, comp, 1)
		player.position = back_at + Vector2(0, 0)
		_step(dd, comp, 1)
	_check(dd.is_crossing(), "a player resumed on the terrace can always walk back")
	await create_timer(1.1).timeout
	_check(player.position.distance_to(back_to) < 1.0, "(back in the pool)")

	# Didn't follow in time: it trots back out and rejoins you.
	player.position = at + Vector2(0, 120)
	comp.position = at + Vector2(-30, 110)
	await create_timer(1.3).timeout   # past the crossing's cooldown
	dd.ask()
	_check(_run_until(dd, comp, func() -> bool: return gate.is_open(), 15.0), "(asked again: it is waiting in the picture)")
	var hold: float = gate.hold_for(comp.bond_value())
	_check(hold > 7.0 and hold < 16.0, "the door is held %.1f s at this bond" % hold)
	var out := _run_until(dd, comp, func() -> bool: return not gate.is_busy(), hold + 4.0)
	_check(out and comp.visible and comp.is_processing(), "you didn't come, so it trots back out and is yours again (%s %s %s %s)" % [out, comp.visible, comp.is_processing(), gate.phase])
	_check(comp.position.distance_to(gate.threshold()) < 30.0, "at the threshold, beside the arch")
	_check(not late._between.is_valid(), "and the picture is just a picture again")

	# A Call brings it out early.
	_run(dd, comp, 1.5)
	dd.ask()
	_check(_run_until(dd, comp, func() -> bool: return gate.is_open(), 15.0), "(asked again)")
	_world._try_call()
	var called := _run_until(dd, comp, func() -> bool: return not gate.is_busy(), 4.0)
	_check(called and comp.visible and comp.is_processing(), "a Call brings it back out early (%s %s %s %s)" % [called, comp.visible, comp.is_processing(), gate.phase])
	_finish()


## Step the companion body and the director together, the way the game loop does, `n` frames of DT.
func _step(dd, comp, n: int) -> void:
	for i in n:
		if comp.is_processing():
			comp._process(DT)
		dd.update(DT)


func _run(dd, comp, secs: float) -> void:
	_step(dd, comp, int(secs / DT))


func _run_until(dd, comp, cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		_step(dd, comp, 1)
		if bool(cond.call()):
			return true
		t += DT
	return false


func _secret_entry() -> Dictionary:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret" and not bool(e.get("_taken", false)):
			return e
	return {}


func _finish() -> void:
	if _fails == 0:
		print("ALL LINGERLONG SECRET SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("LINGERLONG SECRET SMOKE FAILED: %d" % _fails)
		quit(1)


func _check(cond: bool, label: String) -> void:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	if not cond:
		_fails += 1
