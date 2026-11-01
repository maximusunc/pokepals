extends SceneTree
## Headless smoke test for your own HOME (HomeDirector): with finds to choose from, your companion
## settles keepsakes in the glade's open spots. The fixture is a real home spec built by the server for
## an account with all five world secrets (tests/world_fixtures/home.json).
##
## Two arrivals, both of which once left the home bare because the choosing ran against the fresh
## scene's un-met placeholder companion:
##   1. warm: we're already connected, with our save in hand (the usual walk home from the Gateway);
##   2. cold: our id and save arrive only AFTER the world is built (they come after the join's welcome).
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_home.gd

const OWNER := "owner-under-test"  # the fixture's home.owner_id

var _world: Node
var _frames := 0
var _phase := 1
var _fails := 0


func _companion_save() -> Dictionary:
	var cfg := WorldData.load_json("res://data/companion.json")
	var s := CompanionSelf.make_default(cfg)
	s.met = true
	return s.to_dict()


func _appearance() -> Dictionary:
	return { "equipped": { "body": "base:body", "legwear": "base:pants", "footwear": "base:shoes" }, "colors": {} }


func _build() -> void:
	var router := root.get_node("/root/WorldRouter")
	var net := root.get_node("/root/Net")
	var home_id: String = router.HOME_PREFIX + OWNER
	net.prime_world_spec(home_id, WorldData.load_json("res://tests/world_fixtures/home.json"))
	router.current_world = home_id
	router.arrival_portal_id = ""
	router.pending_transition = true
	_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	# (Loading the scene headless resets Net, as the lobby tries to connect; so what we "know" on
	# arrival is set here, after the scene is in and before the world builds, which is the real order.)
	_arrive_knowing()
	net.emit_signal("world_spec_unchanged", home_id)
	_frames = 0


func _arrive_knowing() -> void:
	var net := root.get_node("/root/Net")
	if _phase == 1:
		# Warm: connected already, our id and save known before we walk in.
		net._my_id = OWNER
		net._session_save = { "companion": _companion_save(), "appearance": _appearance() }
	else:
		# Cold: nothing known yet when the world is built.
		net._my_id = ""
		net._session_save = {}


func _process(_delta: float) -> bool:
	_frames += 1
	var net := root.get_node("/root/Net")
	if _world == null:
		_build()
		return false
	if _frames < 8:
		return false

	if _phase == 1:
		_fails += _check(_keepsakes() == 3, "warm arrival: the companion settles 3 keepsakes (got %d)" % _keepsakes())
		_world.queue_free()
		_world = null
		_phase = 2
		return false

	if _phase == 2:
		_fails += _check(_keepsakes() == 0, "cold arrival: nothing is chosen before we know who we are (got %d)" % _keepsakes())
		# Now the welcome and our save arrive, as they do after a join.
		net._my_id = OWNER
		var save := _companion_save()
		net._session_save = { "companion": save, "appearance": _appearance() }
		net.emit_signal("save_loaded", save, _appearance())
		_phase = 3
		_frames = 0
		return false

	_fails += _check(_keepsakes() == 3, "cold arrival: once our save arrives, the companion settles 3 keepsakes (got %d)" % _keepsakes())
	if _fails == 0:
		print("ALL HOME SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("HOME SMOKE FAILED: %d" % _fails)
		quit(1)
	return true


func _keepsakes() -> int:
	var n := 0
	for e in _world._interactables:
		if String(e.get("keepsake", "")) != "" and not bool(e.get("_taken", false)):
			n += 1
	return n


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
