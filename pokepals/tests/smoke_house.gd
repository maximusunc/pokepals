extends SceneTree
## Headless smoke test for YOUR HOUSE (home building; docs/usable-items-design.md "Home building"): loads the
## real World scene in a home whose house is being built (tests/world_fixtures/home_house_building.json, from
## Server.HomeWorld; its start time is set here so the build ends a few seconds in). Checks the house stands in
## the north of the glade as a frame, walled in, with its floor down; the carpenter is at work and examinable;
## no axe works at home; when the time is up it's finished in front of you: the rugs and shelves go down, the
## furniture walls in, and every find moves inside; walking in through the door lifts the roof away (the
## cutaway) and walking out puts it back. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_house.gd

const OWNER := "owner-under-test"  # the fixture's home.owner_id
const BUILD_MS := 3000

var _world: Node
var _net: Node
var _frames := 0
var _step := 0
var _fails := 0
var _wait := 0
var _solids_before := 0
var _plates_before := 0


func _ok(cond: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fails += 1


func _build() -> void:
	var router := root.get_node("/root/WorldRouter")
	_net = root.get_node("/root/Net")
	var home_id: String = router.HOME_PREFIX + OWNER
	var spec := WorldData.load_json("res://tests/world_fixtures/home_house_building.json")
	# Started a moment ago, and quick: it finishes a few seconds into the test.
	for b in spec["buildings"]:
		if String(b.get("view", "")) == "house":
			b["house"]["started_at"] = _net.server_unix_ms() - 500
			b["house"]["build_ms"] = BUILD_MS
	_net.prime_world_spec(home_id, spec)
	router.current_world = home_id
	router.arrival_portal_id = ""
	router.pending_transition = true
	_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	_net._my_id = OWNER
	_net.emit_signal("world_spec_unchanged", home_id)
	paused = false


func _count(key: String) -> int:
	var n := 0
	for e in _world._interactables:
		if String(e.get(key, "")) != "" and not bool(e.get("_taken", false)):
			n += 1
	return n


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		_build()
		return false
	if _frames < 8:
		return false
	if _frames > 6000:
		print("HOUSE SMOKE FAILED: timed out at step %d" % _step)
		quit(1)
		return true
	var hd = _world._house_dir
	var view = hd.view()
	match _step:
		0:
			print("SmokeHouse")
			_ok(hd.is_active() and view != null, "the home has a house")
			_ok(view != null and not view.built, "it's being built")
			var fp: Rect2 = view.footprint()
			_ok(fp.end.y < -330.0 and fp.size.x >= 500.0, "a big house, north of the glade as it was (%s)" % fp)
			_ok(_world.get_node_or_null("Scenery/Carpenter") != null, "the carpenter is here, at work")
			_ok(_world.get_node_or_null("Scenery/HouseBackWall") != null, "the frame's back wall stands")
			_ok(_count("curio") == 0, "nothing has moved in yet")
			_solids_before = _world._player._solids.size()
			_plates_before = _world._world_art._plates.size()
			# The carpenter tells you how long is left.
			var entry: Dictionary = {}
			for e in _world._interactables:
				if bool(e.get("house_builder", false)):
					entry = e
			_ok(not entry.is_empty(), "she can be examined")
			_world._player.set_process(false)
			_world._player.position = entry["pos"] + Vector2(0, 12)
			_world._invalidate_nearest()
			_world._try_interact()
			_ok(_world.hint_text().contains("minute") or _world.hint_text().contains("frame"), "she says how it's going: %s" % _world.hint_text())
			# No axe at home.
			_ok(not _world._harvest_dir._allowed, "no chopping at home")
			_wait = 0
			_step = 1
		1:
			_wait += 1
			if view.built:
				_ok(true, "the time's up: it's finished")
				_step = 2
			elif _wait > 3000:
				_ok(false, "the time's up: it's finished")
				_step = 9
		2:
			_ok(_world._world_art._plates.size() > _plates_before, "the rugs and shelves go down (%d -> %d plates)" % [_plates_before, _world._world_art._plates.size()])
			_ok(_world._player._solids.size() > _solids_before, "the furniture walls in (%d -> %d solids)" % [_solids_before, _world._player._solids.size()])
			var fp: Rect2 = view.footprint()
			var inside := 0
			for e in _world._interactables:
				if (String(e.get("curio", "")) != "" or String(e.get("keepsake", "")) != "") and not bool(e.get("_taken", false)):
					if fp.has_point(e["pos"]):
						inside += 1
			_ok(inside == 5, "every find has moved inside (%d of 5)" % inside)
			_ok(_world.hint_text().contains("finished"), "a hint says it's finished")
			# Walk in and out for real, through the walls' and furniture's collision (once it trapped you inside).
			var pl = _world._player
			var door_x: float = (float(view.house["door"][0]) + float(view.house["door"][1])) * 0.5
			var walk := func(from: Vector2, dir: Vector2, steps: int) -> Vector2:
				var q := from
				for k in steps:
					q = Solids.resolve(q + dir * 2.0, pl._body_radius, pl._solids, pl._bounds, pl._margin)
				return q
			var got_in: Vector2 = walk.call(Vector2(door_x, fp.end.y + 30.0), Vector2.UP, 40)
			_ok(got_in.y < fp.end.y - 40.0, "you can walk in through the door (reached %s)" % got_in)
			var side: Vector2 = walk.call(got_in, Vector2.LEFT, 20)
			var room: Vector2 = walk.call(side, Vector2.UP, 50)
			_ok(room.y < fp.end.y - 120.0, "and round the couch, deep into the living room (reached %s)" % room)
			var back: Vector2 = walk.call(walk.call(walk.call(room, Vector2.DOWN, 50), Vector2.RIGHT, 20), Vector2.DOWN, 40)
			_ok(back.y > fp.end.y + 10.0, "and back out again (reached %s)" % back)
			# Walk in through the door.
			var door: Array = view.house["door"]
			_world._player.position = Vector2((float(door[0]) + float(door[1])) * 0.5, fp.end.y - 30.0)
			_wait = 0
			_step = 3
		3:
			_wait += 1
			if _wait < 40:
				return false
			_ok(view._inside > 0.99, "inside: the roof lifts away")
			_ok(view._shell.modulate.a < 0.01 and view._strip.modulate.a > 0.99, "the front wall is a low strip")
			var shown := 0
			for fv in view._furniture:
				if fv.visible:
					shown += 1
			_ok(shown == view._furniture.size() and shown > 15, "the furniture is there (%d pieces)" % shown)
			_ok(_world.get_node("Scenery/HouseBackWall").visible, "and the back wall")
			_world._player.position = Vector2(_world._player.position.x, view.footprint().end.y + 40.0)
			_wait = 0
			_step = 4
		4:
			_wait += 1
			if _wait < 40:
				return false
			_ok(view._inside < 0.01 and view._shell.modulate.a > 0.99, "outside again: the roof is back")
			_step = 9
		9:
			print("")
			if _fails == 0:
				print("ALL HOUSE SMOKE CHECKS PASSED")
				quit(0)
			else:
				print("HOUSE SMOKE FAILED: %d" % _fails)
				quit(1)
			return true
	return false
