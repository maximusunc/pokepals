extends SceneTree
## Headless smoke test for FARMEADOW, the first world seen from inside (the perspective view). Loads the real
## World scene from the test fixture as if we'd come through the Vale's Gateway and checks what makes it its own:
##   * it asks for the perspective view, and gets it: the view is up, with its backdrop (hills, clouds), the
##     ground carried on past the edge, butterflies standing in the scenery;
##   * the upright things are drawn to be seen from any side: windmills from 8 bearings, fences and the
##     fingerpost as cards, the keep a landmark;
##   * a tap lands where it's drawn (screen -> world -> screen), anywhere in the view and at any heading;
##   * the joystick moves you relative to the screen: with the view turned east, "up" walks you east, and the
##     camera stays behind you; a walk back toward the camera never flips it;
##   * the long road runs to the keep, there's something to examine on the way, and the way home is the Gateway;
##   * the dev toggle can switch it off and back on, restoring everything.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_farmeadow.gd

const FARMEADOW_ID := "15151515-1515-1515-1515-151515151515"

var _world: Node
var _frames := 0
var _phase := 0
var _phase_frame := 0
var _fails := 0
var _start := Vector2.ZERO


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(FARMEADOW_ID, WorldData.load_json("res://tests/world_fixtures/farmeadow.json"))
		router.current_world = FARMEADOW_ID
		router.arrival_portal_id = ""
		var scene: PackedScene = load("res://scenes/world.tscn")
		_world = scene.instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", FARMEADOW_ID)
		paused = false
		return false
	paused = false
	if _frames < 8:
		return false
	match _phase:
		0:
			_static_checks()
			# Turn the view to face east, then hold "up": you should walk east, and the camera stay behind you.
			var pv: PerspectiveView = _world._perspective
			pv.rig.yaw = PI / 2.0
			_start = _world._player.position
			Input.action_press("ui_up")
			_phase = 1
			_phase_frame = _frames
		1:
			if _frames - _phase_frame >= 60:
				Input.action_release("ui_up")
				var moved: Vector2 = _world._player.position - _start
				_fails += _check(moved.x > 25.0 and absf(moved.y) < moved.x * 0.3, "facing east, \"up\" walks you east (%s)" % str(moved.round()))
				_fails += _check(absf(angle_difference(PerspectiveView.view_yaw, PI / 2.0)) < 0.15, "...and the camera stays behind you")
				_start = _world._player.position
				Input.action_press("ui_down")
				_phase = 2
				_phase_frame = _frames
		2:
			if _frames - _phase_frame >= 60:
				Input.action_release("ui_down")
				var moved: Vector2 = _world._player.position - _start
				_fails += _check(moved.x < -15.0, "\"down\" walks you back toward the camera (%s)" % str(moved.round()))
				_fails += _check(absf(angle_difference(PerspectiveView.view_yaw, PI / 2.0)) < 0.15, "...without the camera flipping round")
				_toggle_checks()
				return _finish()
	return false


func _static_checks() -> void:
	var spec: Dictionary = WorldData.load_json("res://tests/world_fixtures/farmeadow.json")
	var pv: PerspectiveView = _world._perspective
	_fails += _check(PerspectiveView.wants(spec) and pv.is_on() and PerspectiveView.active == pv, "it asks for the perspective view, and it's up")
	var mat: ShaderMaterial = pv._mat
	_fails += _check(mat != null and bool(mat.get_shader_parameter("has_hills")) and bool(mat.get_shader_parameter("has_clouds")), "hills and clouds hang round its horizon")
	var ground := _world._world_art.get_node_or_null("Ground") as GroundLayer
	_fails += _check(ground != null and ground._extra > 1000.0, "the ground carries on past the world's edge")
	var flutters := 0
	var windmills := 0
	var cards := 0
	var keep: TreeView = null
	for c in _world._scenery.get_children():
		if c is FlutterView:
			flutters += 1
		elif c is TreeView:
			var t := c as TreeView
			if t.angle_frames.size() == 8:
				windmills += 1
			if t.has_meta("card"):
				cards += 1
			if t.is_great:
				keep = t
	_fails += _check(flutters > 0, "butterflies stand in the scenery (%d)" % flutters)
	_fails += _check(windmills == 4, "four windmills, each drawn from 8 bearings")
	_fails += _check(cards >= 70, "fences and the fingerpost are cards (%d)" % cards)
	_fails += _check(keep != null and keep.tex != null, "the keep stands at the end of the road")
	# Which of a windmill's views you see turns with where you look from.
	_fails += _check(TreeView.angle_frame(8, PI, 0.0) == 0 and TreeView.angle_frame(8, PI, PI / 2.0) == 2 and TreeView.angle_frame(8, PI, PI) == 4, "a windmill shows its front, side and back as you go round it")
	# Taps land where they're drawn, near and far, at two headings.
	var worst := 0.0
	for yaw in [0.0, 2.1]:
		pv.proj.yaw = yaw
		for off in [Vector2(0, 0), Vector2(120, -300), Vector2(-300, -900), Vector2(40, 60)]:
			var w: Vector2 = _world._player.position + off.rotated(yaw)
			var s := PerspectiveView.to_screen(_world, w)
			var err := PerspectiveView.to_world(_world, Vector2(s.x, s.y)).distance_to(w)
			if err > 0.5:
				print("    tap miss: yaw %.2f off %s screen %s view %s zoom %s center %s" % [yaw, str(off), str(s), str(pv._view_size()), str(pv._zoom()), str(pv.proj.center)])
			worst = maxf(worst, err)
	pv.proj.yaw = pv.rig.yaw
	_fails += _check(worst < 0.5, "a tap lands where it's drawn (worst %.2f)" % worst)
	# The long road, something to look at on the way, and the way home.
	var keep_pos := WorldData.to_vec2(spec["landmarks"][0]["position"])
	_fails += _check(keep_pos.distance_to(WorldData.to_vec2(spec["player_spawn"])) > 2500.0, "the keep is a long road away")
	var looks := 0
	for e in _world._interactables:
		if String(e.get("label", "")) in ["a fingerpost", "the old keep", "a windmill"]:
			looks += 1
	_fails += _check(looks >= 4, "the fingerpost, the windmills and the keep can be examined (%d)" % looks)
	# The paddock's fence holds you in (and out) between its panels; its gates let you through.
	var solids: Array = _world._player._solids
	var bounds: Rect2 = _world._bounds_rect
	var blocked := _walk(solids, bounds, Vector2(500, 780), Vector2(500, 600))
	var gated := _walk(solids, bounds, Vector2(342, 160), Vector2(342, 400))
	_fails += _check(blocked.y > 700.0, "the paddock fence stops you between its panels (%s)" % str(blocked.round()))
	_fails += _check(gated.y > 300.0, "...and its gate lets you in (%s)" % str(gated.round()))
	# A fence panel the camera walks right past never flings itself across the screen.
	var panel: TreeView = null
	for c in _world._scenery.get_children():
		if c is TreeView and c.has_meta("card") and c.position.distance_to(Vector2(-70, 900)) < 30.0:
			panel = c
	# Walking up the road past it, step by step, every point of it stays put on screen from one step to the next
	# (while any of it is on screen): no end flung away as it passes the camera.
	var worst_jump := 0.0
	var steps_seen := 0
	var vanished := 0
	if panel != null:
		var saved := pv.proj.center
		pv.proj.yaw = 0.0
		var hw := panel.tex.get_width() * 0.5
		var half_h := pv._view_size().y * 0.5
		var last := []
		var half_w := pv._view_size().x * 0.5
		for i in 700:
			pv.proj.center = Vector2(-50, 1100 - i * 1.0)
			var xf := pv._card_xform(panel, panel.position, Vector3.ZERO, panel.position)
			var ends := [xf * Vector2(-hw, 0.0) - pv.proj.center, xf * Vector2(hw, 0.0) - pv.proj.center]
			# only while some of it is on screen (an end, or the bottom-to-top span of the panel)
			var on := false
			for e in ends:
				var v := e as Vector2
				if absf(v.x) <= half_w and v.y - panel.tex.get_height() * xf.y.y <= half_h and v.y >= -half_h:
					on = true
			if xf.x == Vector2.ZERO:
				# hidden: then no part of it nearer than the near depth's far side may still be in view
				for sgn in [-1.0, 1.0]:
					var e: Vector2 = panel.position + Vector2(-cos(float(panel.get_meta("card"))), -sin(float(panel.get_meta("card")))) * hw * sgn
					var pe := pv.proj.project(e)
					if pe.z > 0.0 and pe.z < 1.0 / PerspectiveView.CARD_NEAR and absf(pe.x) <= half_w and pe.y - panel.tex.get_height() * pe.z <= half_h:
						vanished += 1
				last = []
				continue
			if not on:
				last = []
				continue
			if not last.is_empty():
				worst_jump = maxf(worst_jump, maxf((ends[0] as Vector2).distance_to(last[0]), (ends[1] as Vector2).distance_to(last[1])))
			last = ends
			steps_seen += 1
		pv.proj.center = saved
		pv.proj.yaw = pv.rig.yaw
	_fails += _check(panel != null and steps_seen > 50 and steps_seen < 700 and worst_jump < 60.0, "walking past a fence panel, it never jumps across the screen (worst step %.1f px over %d steps)" % [worst_jump, steps_seen])
	_fails += _check(panel != null and vanished == 0, "...and it isn't hidden while any of it is still in view (%d)" % vanished)
	var router := root.get_node("/root/WorldRouter")
	_fails += _check(_world._return_world == router.HUB_ID and _world._return_portal == router.HUB_GATEWAY_ID, "the way home is the Vale's Gateway")


## Walk a body from `a` toward `b` through the world's real resolver; where it ends up.
func _walk(solids: Array, bounds: Rect2, a: Vector2, b: Vector2) -> Vector2:
	var p := a
	var dir := (b - a).normalized()
	for _i in int(a.distance_to(b) / 3.0) + 20:
		p += dir * 3.0
		p = Solids.resolve(p, 6.0, solids, bounds, 2.0)
	return p


func _toggle_checks() -> void:
	var pv: PerspectiveView = _world._perspective
	pv.set_on(false)
	var ground := _world._world_art.get_node_or_null("Ground") as GroundLayer
	var flutters := 0
	for c in _world._scenery.get_children():
		if c is FlutterView and not c.is_queued_for_deletion():
			flutters += 1
	_fails += _check(PerspectiveView.active == null and PerspectiveView.view_yaw == 0.0 and ground._extra == 0.0 and flutters == 0, "switched off: top-down, the ground back to the world, the butterflies gone")
	_fails += _check(_world._camera.limit_left > -100000 and _world._companion.follow_side == 0.0, "...the camera's limits and the companion's follow spot restored")
	pv.set_on(true)
	_fails += _check(PerspectiveView.active == pv, "and back on")


func _finish() -> bool:
	if _fails == 0:
		print("ALL FARMEADOW SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("FARMEADOW SMOKE FAILED: %d" % _fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> int:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	return 0 if cond else 1
