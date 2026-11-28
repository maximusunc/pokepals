extends SceneTree
## Headless smoke test for GLINTWOLD's secret, the Unfinished. Loads the real World scene from the test fixture as
## if we'd come through the Vale's Gateway and checks:
##   * the world builds, and the stone stands in the Scenery layer at the heartstone's position, in pieces;
##   * the secret is the offcut (reveal "facets"): hidden at first, the FacetsDirector is running;
##   * a tap off the Turning Floor does nothing, a tap on it stands your companion there, a tap near its mark
##     settles it right onto it; "Go look" is on offer near the stone and sends it off;
##   * standing on both marks and holding (but walking off before the hold is up lets the hold go and the pieces
##     drift apart again), then holding the whole time: it closes, and once the chip has dropped the offcut is
##     there at the stone's foot to be claimed;
##   * on a return visit once it is found, the stone hangs in pieces again and still closes, but nothing falls;
##   * it gets home to the Gateway like any catalog world.
## Run on its own:
##   godot --headless --path gates-of-elyra --script res://tests/smoke_glintwold.gd

const GLINTWOLD_ID := "17171717-1717-1717-1717-171717171717"
const FIXTURE := "res://tests/world_fixtures/glintwold.json"

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
		net.prime_world_spec(GLINTWOLD_ID, WorldData.load_json(FIXTURE))
		router.current_world = GLINTWOLD_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", GLINTWOLD_ID)
		return false
	if _frames < 8:
		return false
	_done = true

	var fails := 0
	var spec: Dictionary = WorldData.load_json(FIXTURE)
	var secret: Dictionary = spec["secret"]
	var reveal: Dictionary = secret["reveal"]
	var hs: Dictionary = spec["heartstone"]
	var center := WorldData.to_vec2(hs["position"])
	var you_mark := WorldData.to_vec2(hs["marks"]["you"])
	var comp_mark := WorldData.to_vec2(hs["marks"]["companion"])

	var trees := 0
	for c in _world._scenery.get_children():
		if c is TreeView:
			trees += 1
	fails += _check(_world._world_built and trees >= 50, "the world builds (%d trees)" % trees)

	fails += _check(String(reveal["type"]) == "facets", "the secret is the Unfinished's last face")
	var dir = _world._secret_dir
	var fd: FacetsDirector = dir.get_node_or_null("FacetsDirector")
	fails += _check(fd != null, "the facets director is running")
	fails += _check(not _has_secret_entry(), "the offcut is hidden until the stone closes")
	if fd == null:
		return _finish(fails)
	var view: HeartstoneView = fd.view()
	fails += _check(view != null and view.get_parent() == _world._scenery and view.position.is_equal_approx(center),
		"the stone stands in the Scenery layer at the heartstone's position")
	fails += _check(view != null and view.shards.size() == 9, "in nine shards")
	var join: FacetJoin = fd.join()
	fails += _check(join.marks["you"] == you_mark and join.marks["companion"] == comp_mark and is_equal_approx(join.cfg("hold_s"), float(hs["hold_s"])),
		"the marks and the hold come from the spec")

	var player = _world._player
	var comp = _world._companion

	# Placing the companion.
	fails += _check(not dir.on_ground_tap(center + Vector2(0, float(hs["floor_radius"]) + 60.0)), "a tap off the Turning Floor does nothing")
	fails += _check(dir.on_ground_tap(center + Vector2(60, 40)) and fd.is_posing(), "a tap on the floor stands your companion there")
	fd.release()
	fails += _check(dir.on_ground_tap(comp_mark + Vector2(14, -12)) and fd._pose_at == comp_mark, "a tap close to its mark settles it right onto it")
	fd.release()
	player.position = center + Vector2(0, 120)
	fails += _check(dir.can_go_look(), "Go look is on offer near the stone")
	dir.go_look()
	fails += _check(fd.is_posing() and fd._pose_at.distance_to(comp_mark) <= join.go_look_error(comp.bond_value()) + 0.5, "Go look sends it to find its own mark")
	fd.release()
	player.position = center + Vector2(1400, 0)
	fails += _check(not dir.can_go_look(), "...and is greyed far from it")

	# Far away: the stone hangs apart and nothing slides.
	player.position = center + Vector2(900, 300)
	comp.position = player.position + Vector2(20, 0)
	_run(fd, 0.5)
	var resting := true
	for o in view._want:
		resting = resting and is_equal_approx((o as Vector2).length(), join.cfg("spread"))
	fails += _check(resting, "from afar the pieces hang loosely apart")

	# Both marks, but walk off before the hold is up: it lets go and drifts apart again.
	player.position = you_mark
	comp.position = comp_mark
	_run(fd, float(hs["hold_s"]) * 0.6)
	fails += _check(join.held > 0.5 and not join.done, "standing on both marks, the hold builds")
	player.position = you_mark + Vector2(-70, 40)
	_run(fd, 0.2)
	var apart := false
	for i in view.shards.size():
		if String(view.shards[i]["owner"]) == "you" and (view._want[i] as Vector2).length() > 3.0:
			apart = true
	fails += _check(join.held == 0.0 and not join.done and apart and not _has_secret_entry(), "walking off lets the hold go, and your half drifts apart again")

	# Back on it and held the whole time: it closes and the offcut drops.
	player.position = you_mark + Vector2(5, -4)   # inside the magnet's tolerance
	comp.position = comp_mark
	_run(fd, float(hs["hold_s"]) + 0.3)
	fails += _check(join.done and view.is_whole(), "both halves held: the stone closes")
	for _i in 30:
		view._process(0.1)   # the snap, the flash, the light across the faces, and the chip dropping
	var entry := _secret_entry()
	fails += _check(not entry.is_empty() and (entry["pos"] as Vector2).distance_to(WorldData.to_vec2(secret["position"])) < 1.0,
		"the offcut has dropped at the stone's foot, there to be claimed")
	fails += _check(not view.is_animating() and view.is_whole(), "and the stone stands whole")
	fails += _check(not dir.can_go_look(), "Go look is no longer offered")

	# A return visit once it is found: the stone is in pieces again and still closes, but nothing falls.
	var again := FacetsDirector.new()
	dir.add_child(again)
	again.setup(_world, comp, _world._world_art, player)
	again.configure(hs, secret, true)
	var fell := [0]
	again.offcut_fell.connect(func(_p: Vector2, _l: String) -> void: fell[0] += 1)
	player.position = center + Vector2(900, 300)
	_run(again, 0.2)
	fails += _check(not again.view().is_whole(), "found already: on a return visit the stone hangs in pieces again")
	player.position = you_mark
	comp.position = comp_mark
	_run(again, float(hs["hold_s"]) + 0.3)
	for _i in 30:
		again.view()._process(0.1)
	fails += _check(again.join().done and again.view().is_whole() and fell[0] == 0, "...and still closes, a quiet toy, but no second offcut falls")
	again.queue_free()

	var router := root.get_node("/root/WorldRouter")
	fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")
	return _finish(fails)


## Drive the director for `secs` in small steps, all inside this frame (so nothing else moves the bodies).
func _run(fd: FacetsDirector, secs: float) -> void:
	var t := 0.0
	while t < secs:
		fd.update(0.05)
		t += 0.05


func _secret_entry() -> Dictionary:
	for e in _world._interactables:
		if String(e.get("kind", "")) == "secret":
			return e
	return {}


func _has_secret_entry() -> bool:
	return not _secret_entry().is_empty()


func _finish(fails: int) -> bool:
	if fails == 0:
		print("ALL GLINTWOLD SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("GLINTWOLD SMOKE FAILED: %d" % fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
