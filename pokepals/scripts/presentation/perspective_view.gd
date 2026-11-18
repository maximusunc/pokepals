class_name PerspectiveView
extends Node
## The perspective ("inside") view: an ordinary 2D world seen from just behind and above you, the ground running
## off to a horizon, everything standing up on it and shrinking with distance, the camera swinging round behind
## the way you walk. A world opts in with a `view` block in its spec ({"projection": "perspective", ...},
## deep-merged over data/view.json); any world can be looked at this way from the gear menu's dev item.
##
## The world itself is untouched: every position stays a plain 2D world position, so logic, collision, the
## server and every director carry on exactly as before. Only the DRAWING changes, in two parts:
##   * the flat layer (WorldArt: ground, paths, ponds, props, footprints) is rendered top-down into two
##     SubViewports that share this world's canvas, both cut along the view's heading (a sharp one for the near
##     ground, a wide one out to the draw distance), and a full-screen shader (assets/perspective_ground.gdshader)
##     looks at them in perspective, with the sky above;
##   * just before each frame is drawn, every direct child of Scenery (actors, trees, buildings, portals) has its
##     DRAWN transform overridden in the RenderingServer: moved to its projected spot and scaled by depth. Godot
##     y-sorts by that drawn transform, so nearer things still cover farther ones at any heading. Node.position
##     is never written, so nothing that reads it sees any difference.
## The camera is pure logic: ViewProjection (where things land) and ViewRig (how it turns and lingers).
##
## Godot notes: a SubViewport is an off-screen screen; giving it the main viewport's `world_2d` makes it look at
## the same canvas, and visibility layers + its `canvas_cull_mask` make it draw only the flat layer while the main
## view skips it. RenderingServer.frame_pre_draw fires after all scripts have run for the frame, just before
## drawing, so the transforms set there are what gets drawn.

const SHADER := preload("res://assets/perspective_ground.gdshader")
const DEFAULTS_PATH := "res://data/view.json"
const FLAT_LAYER := 2
const PAST_EDGE := 2600.0  # how far past the world's bounds the ground carries on (GroundLayer.extend)  # visibility layer bit value for the flat world (rendered only into the SubViewports)

## The view on screen right now, or null. Taps and on-screen prompts go through it (see to_world / to_screen).
static var active: PerspectiveView
## The view's heading, read by the sprite drawers (a sprite faces relative to the camera) and the player's input
## (the joystick moves you relative to the screen). 0 whenever no perspective view is on.
static var view_yaw := 0.0

var proj := ViewProjection.new()
var rig := ViewRig.new()
## Timings (usec) of the last frame's projection pass, for measuring.
var last_project_usec := 0

var _cfg: Dictionary = {}
var _world: Node2D
var _art: CanvasItem
var _scenery: Node2D
var _camera: Camera2D
var _player: Node2D
var _companion: Node2D
var _near: SubViewport
var _near_cam: Camera2D
var _far: SubViewport
var _far_cam: Camera2D
var _layer: CanvasLayer
var _mat: ShaderMaterial
var _hidden: Array[CanvasItem] = []
var _saved_camera := {}
var _on := false
var _life_cfg: Dictionary = {}
var _flutters: Array[FlutterView] = []
var _rng := RandomNumberGenerator.new()
var _day_tint: CanvasModulate
var _cloud_speed := 0.0
var _cloud_drift := 0.0


static func defaults() -> Dictionary:
	return WorldData.load_json(DEFAULTS_PATH)


## Does this world's spec ask to be seen in perspective?
static func wants(spec: Dictionary) -> bool:
	return String(spec.get("view", {}).get("projection", "")) == "perspective"


## `life` is the world's ambient_life art entity: its butterflies are kept here, standing up in the scenery.
func setup(world: Node2D, art: CanvasItem, scenery: Node2D, camera: Camera2D, player: Node2D, companion: Node2D, spec_view: Dictionary = {}, life: Dictionary = {}) -> void:
	_life_cfg = life
	_day_tint = world.get_node_or_null("DayTint") as CanvasModulate
	_world = world
	_art = art
	_scenery = scenery
	_camera = camera
	_player = player
	_companion = companion
	_cfg = ArtStyle.deep_merge(defaults(), spec_view)
	rig.configure(_cfg)
	proj.configure(_cfg.get("camera", {}))
	set_process(false)


func is_on() -> bool:
	return _on


func set_on(on: bool) -> void:
	if on == _on:
		return
	_on = on
	if on:
		_enable()
	else:
		_disable()


# ---------------------------------------------------------------------------------------------- screen <-> world

## The world point under a screen position (viewport coordinates, as an input event gives them): the ground seen
## there in perspective, or the canvas inverse when no perspective view is up. A tap on the sky gives the far
## ground straight ahead of it.
static func to_world(ci: CanvasItem, screen_pos: Vector2) -> Vector2:
	if active != null:
		return active._screen_to_world(screen_pos)
	return ci.get_viewport().get_canvas_transform().affine_inverse() * screen_pos


## Where a world point appears on screen (viewport coordinates) and how big things there are drawn (1 = native).
static func to_screen(ci: CanvasItem, world_pos: Vector2) -> Vector3:
	if active != null:
		return active._world_to_screen(world_pos)
	var p := ci.get_viewport().get_canvas_transform() * world_pos
	return Vector3(p.x, p.y, 1.0)


## A world point in a node's own drawing space, as it's DRAWN: for something carried by an upright thing (the
## rod in your hand drawing its line out to the bobber on the water), the point where the world point appears,
## relative to how the carrier is drawn (projected and scaled). Plain to_local() when no perspective view is up.
static func local_of(ci: Node2D, world_pos: Vector2) -> Vector2:
	if active == null:
		return ci.to_local(world_pos)
	return active._local_of(ci, world_pos)


func _local_of(ci: Node2D, world_pos: Vector2) -> Vector2:
	var a: Node = ci
	while a != null and a.get_parent() != _scenery:
		a = a.get_parent()
	var carrier := a as Node2D
	if carrier == null:
		return ci.to_local(world_pos)
	var pa := proj.project(_scenery.global_transform * carrier.position)
	var pw := proj.project(world_pos)
	if pa.z <= 0.0 or pw.z <= 0.0:
		return ci.to_local(world_pos)
	var basis := carrier.transform
	basis.origin = Vector2.ZERO
	var in_carrier := basis.affine_inverse() * ((Vector2(pw.x, pw.y) - Vector2(pa.x, pa.y)) / pa.z)
	return (ci.global_transform.affine_inverse() * carrier.global_transform) * in_carrier


func _view_size() -> Vector2:
	return _world.get_viewport_rect().size


func _zoom() -> float:
	return _camera.zoom.x


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var off := (screen_pos - _view_size() * 0.5) / _zoom()
	var g: Variant = proj.unproject(off)
	if g == null:
		g = proj.unproject(Vector2(off.x, proj.horizon_y() + 1.0))
	return g if g != null else proj.center


func _world_to_screen(world_pos: Vector2) -> Vector3:
	var p := proj.project(world_pos)
	var s := _view_size() * 0.5 + Vector2(p.x, p.y) * _zoom()
	return Vector3(s.x, s.y, p.z * _zoom())


# ------------------------------------------------------------------------------------------------- on / off

func _new_flat(size: Vector2i) -> Array:
	var sub := SubViewport.new()
	sub.size = size
	sub.world_2d = _world.get_viewport().world_2d
	sub.canvas_cull_mask = FLAT_LAYER
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.disable_3d = true
	sub.transparent_bg = true  # past the world's edge reads as plain ground, not the clear colour
	sub.snap_2d_transforms_to_pixel = true
	add_child(sub)
	var cam := Camera2D.new()
	cam.ignore_rotation = false  # the texture is cut along the view's heading, so its texels line up with the screen
	sub.add_child(cam)
	cam.make_current()
	return [sub, cam]


func _enable() -> void:
	var vp := _world.get_viewport()
	var n := _new_flat(_vec2i(_cfg.get("near_tex", [1024, 512])))
	_near = n[0]
	_near_cam = n[1]
	var f := _new_flat(_vec2i(_cfg.get("far_tex", [1024, 512])))
	_far = f[0]
	_far_cam = f[1]
	# The world node draws nothing itself but is a parent of both halves, so it is in both layers.
	_world.visibility_layer = 1 | FLAT_LAYER
	_set_layer(_art, FLAT_LAYER)
	vp.set_canvas_cull_mask_bit(1, false)
	_layer = CanvasLayer.new()
	_layer.layer = -1
	add_child(_layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("near_tex", _near.get_texture())
	_mat.set_shader_parameter("far_tex", _far.get_texture())
	var sky: Dictionary = _cfg.get("sky", {})
	_mat.set_shader_parameter("sky_top", _color(sky.get("top", [0.45, 0.66, 0.9])))
	_mat.set_shader_parameter("sky_low", _color(sky.get("low", [0.86, 0.9, 0.92])))
	_mat.set_shader_parameter("beyond", _color(sky.get("beyond", [0.27, 0.44, 0.21])))
	var backdrop: Dictionary = _cfg.get("backdrop", {})
	for key in ["hills", "clouds"]:
		var path := String(backdrop.get(key, ""))
		var tex: Texture2D = load(path) if path != "" and ResourceLoader.exists(path) else null
		_mat.set_shader_parameter("has_" + key, tex != null)
		if tex != null:
			_mat.set_shader_parameter(key, tex)
	_cloud_speed = float(backdrop.get("cloud_drift", 0.0))
	rect.material = _mat
	_layer.add_child(rect)
	# Things that float over the whole world in top-down space and have no perspective form (yet).
	for nm in ["AmbientLife", "Garlands", "SteamPuffs"]:
		var ci := _world.get_node_or_null(nm) as CanvasItem
		if ci != null and ci.visible:
			ci.visible = false
			_hidden.append(ci)
	# The camera: no world limits (they'd push you off the focus at an edge) and no look-ahead (ahead is up).
	_saved_camera = {
		"limits": [_camera.limit_left, _camera.limit_top, _camera.limit_right, _camera.limit_bottom],
		"look_ahead": _camera.get("look_ahead"),
	}
	_camera.limit_left = -10000000
	_camera.limit_top = -10000000
	_camera.limit_right = 10000000
	_camera.limit_bottom = 10000000
	if "look_ahead" in _camera:
		_camera.set("look_ahead", 0.0)
	if _companion != null and "follow_side" in _companion:
		_companion.follow_side = deg_to_rad(float(_cfg.get("companion_side_deg", 70.0)))
	rig.yaw = 0.0
	rig.linger = 0.0
	rig.still = 0.0
	var ground := _art.get_node_or_null("Ground") as GroundLayer
	if ground != null:
		ground.extend(PAST_EDGE)
	_spawn_life()
	active = self
	set_process(true)
	RenderingServer.frame_pre_draw.connect(_project)


func _disable() -> void:
	RenderingServer.frame_pre_draw.disconnect(_project)
	set_process(false)
	if active == self:
		active = null
	view_yaw = 0.0
	ViewCull.override_rect = Rect2()
	_world.get_viewport().set_canvas_cull_mask_bit(1, true)
	_world.visibility_layer = 1
	_set_layer(_art, 1)
	for ci in _hidden:
		ci.visible = true
	_hidden.clear()
	var lim: Array = _saved_camera["limits"]
	_camera.limit_left = lim[0]
	_camera.limit_top = lim[1]
	_camera.limit_right = lim[2]
	_camera.limit_bottom = lim[3]
	if _saved_camera["look_ahead"] != null:
		_camera.set("look_ahead", _saved_camera["look_ahead"])
	if _companion != null and "follow_side" in _companion:
		_companion.follow_side = 0.0
	for c in _scenery.get_children():
		if c is Node2D:
			RenderingServer.canvas_item_set_transform((c as Node2D).get_canvas_item(), (c as Node2D).transform)
	var ground := _art.get_node_or_null("Ground") as GroundLayer
	if ground != null:
		ground.extend(0.0)
	_unfade_all()
	for fl in _flutters:
		fl.queue_free()
	_flutters.clear()
	_near.queue_free()
	_far.queue_free()
	_layer.queue_free()


## A CanvasItem draws in a viewport only if it AND all its parents share a layer with the viewport's cull
## mask, so the whole flat subtree moves together (its children were added after WorldArt, on layer 1).
func _set_layer(n: Node, layer: int) -> void:
	if n is CanvasItem:
		(n as CanvasItem).visibility_layer = layer
	for c in n.get_children():
		if not c is SubViewport:
			_set_layer(c, layer)


func _exit_tree() -> void:
	if _on:
		RenderingServer.frame_pre_draw.disconnect(_project)
		ViewCull.override_rect = Rect2()
		view_yaw = 0.0
		if active == self:
			active = null


# ------------------------------------------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if _player == null:
		return
	var v: Variant = _player.get("velocity")
	rig.step(v if v is Vector2 else Vector2.ZERO, delta)
	view_yaw = rig.yaw
	proj.yaw = rig.yaw
	proj.blend(_cfg.get("camera", {}), _cfg.get("linger_camera", _cfg.get("camera", {})), _smooth(rig.linger))
	_tick_life(delta)
	_cloud_drift = fposmod(_cloud_drift + _cloud_speed * delta, 1.0)


# Butterflies about the ground just ahead of you (AmbientLife's, which have no perspective form, are hidden).
const LIFE_AHEAD := 150.0
const LIFE_RADIUS := 260.0


func _spawn_life() -> void:
	var bf: Dictionary = _life_cfg.get("butterflies", {})
	var colors: Array = bf.get("colors", [[0.98, 0.86, 0.4]])
	_rng.seed = 0x5EEDF1
	for i in int(bf.get("count", 0)):
		var fl := FlutterView.new()
		fl.setup(_rng, WorldData.to_color(colors[i % colors.size()]))
		fl.position = _life_spot()
		_scenery.add_child(fl)
		_flutters.append(fl)


func _life_spot() -> Vector2:
	var mid := _player.position + proj.forward() * LIFE_AHEAD
	return mid + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * LIFE_RADIUS


func _tick_life(delta: float) -> void:
	if _flutters.is_empty():
		return
	var mid := _player.position + proj.forward() * LIFE_AHEAD
	for fl in _flutters:
		if fl.position.distance_to(mid) > LIFE_RADIUS * 1.3:
			fl.position = _life_spot()
		fl.tick(delta)


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Lay a flat texture's camera over a band of ground (a rect in the view's frame) and say what it covers.
func _fit(sub_cam: Camera2D, tex: Vector2i, band: Rect2) -> Array:
	var zs := minf(float(tex.x) / band.size.x, float(tex.y) / band.size.y)
	var covered := Vector2(tex) / zs
	var mid := band.get_center()
	sub_cam.position = proj.center + mid.rotated(proj.yaw)
	sub_cam.rotation = proj.yaw
	sub_cam.zoom = Vector2(zs, zs)
	return [mid, covered]


func _project() -> void:
	if not is_instance_valid(_scenery) or not _scenery.is_inside_tree():
		return
	var t0 := Time.get_ticks_usec()
	var zoom := _zoom()
	var view := _view_size() / zoom
	proj.center = _camera.get_screen_center_position()
	ViewCull.override_rect = proj.visible_bounds(view)
	var a_near := proj.near_ground(view)
	var a_focus := proj.back
	var nf := _fit(_near_cam, _near.size, proj.band(view, a_near, a_focus + float(_cfg.get("near_reach", 220.0))))
	var ff := _fit(_far_cam, _far.size, proj.band(view, a_near, a_focus + proj.far))
	_mat.set_shader_parameter("view_size", _view_size())
	_mat.set_shader_parameter("zoom", zoom)
	_mat.set_shader_parameter("cam", Vector4(proj.height, proj.back, proj.pitch, proj.shift))
	_mat.set_shader_parameter("far", proj.far)
	_mat.set_shader_parameter("near_center", nf[0])
	_mat.set_shader_parameter("near_size", nf[1])
	_mat.set_shader_parameter("far_center", ff[0])
	_mat.set_shader_parameter("far_size", ff[1])
	_mat.set_shader_parameter("yaw", proj.yaw)
	_mat.set_shader_parameter("cloud_drift", _cloud_drift)
	if _day_tint != null:
		_mat.set_shader_parameter("tint", _day_tint.color)
	# Upright things: only the DRAWN transform changes, relative to Scenery (which sits at the world origin).
	var to_local := _scenery.global_transform.affine_inverse()
	var me := proj.project(_player.position) if _player != null else Vector3.ZERO
	for child in _scenery.get_children():
		var n := child as Node2D
		if n == null or not n.visible:
			continue
		var world_pos := _scenery.global_transform * n.position
		var pr := proj.project(world_pos)
		var xf: Transform2D
		if pr.z <= 0.0 or proj.ahead_of_focus(world_pos) > proj.far:
			xf = Transform2D(0.0, Vector2.ZERO, 0.0, n.position)  # past the draw distance, or behind the eye
		else:
			var basis := n.transform
			basis.origin = Vector2.ZERO
			if n.has_meta("card"):
				# a flat thing, narrowed by the angle it's seen at (edge-on is a sliver; from behind it's mirrored)
				var c := cos(angle_difference(float(n.get_meta("card")) - PI, proj.yaw))
				basis = basis * Transform2D(0.0, Vector2(c if absf(c) > 0.12 else 0.12 * signf(c + 1e-6), 1.0), 0.0, Vector2.ZERO)
			xf = Transform2D(0.0, Vector2(pr.z, pr.z), 0.0, to_local * (proj.center + Vector2(pr.x, pr.y))) * basis
			if n is TreeView or n is BuildingView:
				_fade_if_in_the_way(n, pr, me)
		RenderingServer.canvas_item_set_transform(n.get_canvas_item(), xf)
	last_project_usec = Time.get_ticks_usec() - t0


# A tree or building standing between the camera and you fades, so it never hides you.
const FADED := 0.35
var _faded := {}


func _fade_if_in_the_way(n: CanvasItem, pr: Vector3, me: Vector3) -> void:
	var in_way := me.z > 0.0 and pr.z > me.z and absf(pr.x - me.x) < 34.0 * pr.z and pr.y - 70.0 * pr.z < me.y
	var want := FADED if in_way else 1.0
	var a := n.self_modulate.a
	if is_equal_approx(a, want):
		if not in_way:
			_faded.erase(n)
		return
	n.self_modulate.a = move_toward(a, want, 0.08)
	_faded[n] = true


func _unfade_all() -> void:
	for n in _faded:
		if is_instance_valid(n):
			(n as CanvasItem).self_modulate.a = 1.0
	_faded.clear()


static func _vec2i(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


static func _color(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))
