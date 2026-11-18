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
const PAST_EDGE := 2600.0
const LANDMARK_REACH := 6000.0  # landmarks (TreeView.is_great) are drawn this far ahead, past the draw distance  # how far past the world's bounds the ground carries on (GroundLayer.extend)  # visibility layer bit value for the flat world (rendered only into the SubViewports)

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
var _static_shadows: GroundShadows
var _actor_shadows: GroundShadows
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
	# Contact shadows lie on the ground (GroundShadows), so they go in the flat layer too.
	_static_shadows = GroundShadows.new()
	_static_shadows.name = "GroundShadowsStatic"
	_art.add_child(_static_shadows)
	_actor_shadows = GroundShadows.new()
	_actor_shadows.name = "GroundShadowsActors"
	_art.add_child(_actor_shadows)
	_items_count = -1
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
	_mat.set_shader_parameter("land_haze", _color(sky.get("land_haze", [0.62, 0.70, 0.60])))
	_mat.set_shader_parameter("haze_from", float(sky.get("haze_from", 0.6)))
	_mat.set_shader_parameter("haze_max", float(sky.get("haze_max", 0.85)))
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
	proj.center = _player.position
	_camera.global_position = proj.center
	process_priority = 100
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
	for gs in [_static_shadows, _actor_shadows]:
		if is_instance_valid(gs):
			gs.queue_free()
	for item in _items:
		if is_instance_valid(item[0]) and int(item[1]) & F_SMALL:
			(item[0] as Node2D).visible = true
	for item in _items:
		if is_instance_valid(item[0]) and (item[0] is TreeView):
			(item[0] as Node2D).visible = true
	_items_count = -1
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
	_follow(delta)
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


## The view frames you, not wherever the camera node has eased to: its focus follows you a touch behind (the same
## ease as CameraRig's), snapping when you've jumped (an arrival), and the camera node is kept on it, since what
## the main view draws is laid out round the screen centre. Runs after CameraRig (process_priority).
const FOLLOW_SPEED := 4.5
const SNAP := 160.0


func _follow(delta: float) -> void:
	var target := _player.position
	if proj.center.distance_to(target) > SNAP:
		proj.center = target
	else:
		proj.center = proj.center.lerp(target, 1.0 - exp(-FOLLOW_SPEED * delta))
	_camera.global_position = proj.center


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
	_project_uprights()
	last_project_usec = Time.get_ticks_usec() - t0


# What each Scenery child is, worked out once (and again whenever children come or go), so the per-frame pass
# does no type checks or meta lookups: [node, flags]. It's the one loop over every upright thing each frame, so
# it's kept tight: the projection is inlined (ViewProjection.project's maths) and plain nodes skip the matrices.
const F_CARD := 1
const F_FADE := 2       # a tree or building: fades when it stands between the camera and you
const F_LANDMARK := 4   # drawn past the draw distance
const F_BASIS := 8      # has its own scale/rotation to keep
const F_SMALL := 16     # a bush or stump (the understory): culled to the wedge here, and dropped past SMALL_REACH
const SMALL_REACH := 700.0
const F_STATIC := 32    # never moves (trees, bushes, fences, buildings, portals): skipped while the camera is still
var _cam_key := PackedFloat32Array()
var _items: Array = []
var _items_count := -1


func _rebuild_items() -> void:
	_items.clear()
	for child in _scenery.get_children():
		var n := child as Node2D
		if n == null:
			continue
		var flags := 0
		if n.has_meta("card"):
			flags |= F_CARD
		if n is TreeView or n is BuildingView:
			flags |= F_FADE
		if n is TreeView and (n as TreeView).is_great:
			flags |= F_LANDMARK
		if n.has_meta("understory"):
			flags |= F_SMALL
		if n is TreeView or n is BuildingView or n is PortalView or n.has_meta("understory"):
			flags |= F_STATIC
		var b := n.transform
		if not (b.x.is_equal_approx(Vector2.RIGHT) and b.y.is_equal_approx(Vector2.DOWN)):
			flags |= F_BASIS
		_items.append([n, flags, _tall(n)])
	_items_count = _scenery.get_child_count()
	_refresh_shadows()


## Who casts a contact shadow on the ground: every tree, windmill, keep and haystack (not the flat cards), and
## every actor (you, your companion, friends, pals). Redone whenever Scenery's children come or go.
func _refresh_shadows() -> void:
	if not is_instance_valid(_static_shadows):
		return
	var spots: Array = []
	var actors: Array = []
	for item in _items:
		var n: Node2D = item[0]
		var flags: int = item[1]
		if n is TreeView and not (flags & F_CARD):
			var t := n as TreeView
			var tex: Texture2D = t.angle_frames[0] if not t.angle_frames.is_empty() else (t.canopy_tex if t.canopy_tex != null else t.tex)
			var w := tex.get_width() * t.tex_scale if tex != null else 48.0
			var r := clampf(w * 0.3, 6.0, 40.0 if t.is_great else 18.0)
			spots.append([n.position, r, float(item[2]) * 0.4])
		elif not (flags & F_STATIC) and not (n is FlutterView):
			actors.append([n, 6.0, 12.0])
	var shadow := Color(0.1, 0.12, 0.08)
	_static_shadows.setup_static(spots, shadow)
	_actor_shadows.setup_actors(actors, shadow)


## How far up from its feet a thing reaches, for telling when it has gone wholly below the screen.
static func _tall(n: Node2D) -> float:
	if n is TreeView:
		var t := n as TreeView
		var tex: Texture2D = t.angle_frames[0] if not t.angle_frames.is_empty() else (t.canopy_tex if t.canopy_tex != null else t.tex)
		return (tex.get_height() * t.tex_scale if tex != null else 90.0) + 10.0
	if n is Sprite2D and (n as Sprite2D).texture != null:
		return (n as Sprite2D).texture.get_height() + 6.0
	return 72.0


func _project_uprights() -> void:
	if _scenery.get_child_count() != _items_count:
		_rebuild_items()
	var origin_ok := _scenery.global_transform == Transform2D.IDENTITY
	var to_local := _scenery.global_transform.affine_inverse()
	var me := proj.project(_player.position) if _player != null else Vector3.ZERO
	# ViewProjection.project, unrolled: a = along the heading from the camera's foot, b = across it.
	var fwd := proj.forward()
	var foot := proj.center - fwd * proj.back
	var fx := fwd.x
	var fy := fwd.y
	var cp := cos(proj.pitch)
	var sp := sin(proj.pitch)
	var h := proj.height
	var f := proj.focal()
	var hsp := h * sp
	var hcp := h * cp
	var shift := proj.shift
	var cx := proj.center.x
	var cy := proj.center.y
	var a_far := proj.back + proj.far
	var a_land := proj.back + LANDMARK_REACH
	var a_small := proj.back + SMALL_REACH
	var slope := (_view_size().x * 0.5 / _zoom()) / f * 1.08
	var half_h := _view_size().y * 0.5 / _zoom() + 4.0
	# The camera exactly where it was last frame: nothing that never moves needs projecting again.
	var key := PackedFloat32Array([cx, cy, proj.yaw, h, proj.back, proj.pitch, shift, _zoom(), _items_count, me.x, me.y])
	var still := key == _cam_key
	_cam_key = key
	for item in _items:
		var flags: int = item[1]
		if still and flags & F_STATIC:
			continue
		var n: Node2D = item[0]
		if not is_instance_valid(n):
			continue
		if not n.visible and not (flags & F_SMALL):
			continue
		var wp := n.position if origin_ok else _scenery.global_transform * n.position
		var rx := wp.x - foot.x
		var ry := wp.y - foot.y
		var a := rx * fx + ry * fy
		if flags & F_SMALL:
			var seen := a > 4.0 and a < a_small and absf(rx * -fy + ry * fx) < a * slope + SIDE_MARGIN
			if seen != n.visible:
				n.visible = seen
			if not seen:
				continue
		var z := a * cp + hsp
		var xf: Transform2D
		if flags & F_CARD and a <= a_far:
			# a flat panel works out its own near clipping (it may be half past the camera and half still in view)
			RenderingServer.canvas_item_set_transform(n.get_canvas_item(), _card_xform(n, wp, Vector3.ZERO, n.position))
			continue
		if z <= 1.0 or a > (a_land if flags & F_LANDMARK else a_far):
			xf = Transform2D(Vector2.ZERO, Vector2.ZERO, n.position)  # past the draw distance, or behind the eye
		else:
			var b := rx * -fy + ry * fx  # along R = F turned a quarter clockwise
			var s := f / z
			var oy := shift + f * (hcp - a * sp) / z
			if oy - float(item[2]) * s > half_h or s > NEAR_HIDE:
				# wholly below the bottom of the screen (it's passing beside or under the camera): nothing to draw
				RenderingServer.canvas_item_set_transform(n.get_canvas_item(), Transform2D(Vector2.ZERO, Vector2.ZERO, n.position))
				continue
			var at := Vector2(cx + f * b / z, cy + oy)
			if not origin_ok:
				at = to_local * at
			if flags & F_CARD:
				xf = _card_xform(n, wp, Vector3(at.x, at.y, s), at)
			elif flags & F_BASIS:
				var basis := n.transform
				basis.origin = Vector2.ZERO
				xf = Transform2D(Vector2(s, 0.0), Vector2(0.0, s), at) * basis
			else:
				xf = Transform2D(Vector2(s, 0.0), Vector2(0.0, s), at)
			if flags & F_FADE and s > me.z:
				_fade_if_in_the_way(n, Vector3(at.x - cx, at.y - cy, s), me)
			elif flags & F_FADE and n.self_modulate.a < 1.0:
				_fade_if_in_the_way(n, Vector3(at.x - cx, at.y - cy, s), me)
		RenderingServer.canvas_item_set_transform(n.get_canvas_item(), xf)


## A flat thing standing up (a fence panel, a signpost): its two ends are projected, so it narrows and slants
## with the angle it's seen at, the same as the ground under it, and a run of panels joins up end to end. Seen
## from behind it comes out mirrored. Its height scales with its middle.
func _card_xform(n: Node2D, world_pos: Vector2, pr: Vector3, at: Vector2) -> Transform2D:
	var facing := float(n.get_meta("card"))
	var along := Vector2(-cos(facing), -sin(facing))  # its drawing's +x, from the front: east for a south-facing card
	var hw := 16.0
	if n is TreeView and (n as TreeView).tex != null:
		hw = (n as TreeView).tex.get_width() * (n as TreeView).tex_scale * 0.5
	# Near the camera part of a panel can come right up to the eye, where projecting it would fling it across the
	# screen. So nothing nearer than a near depth is projected: each end is pulled in along the panel to it, and if
	# even the middle is that near, the panel is anchored at the nearest point that isn't (toward its far end), so
	# it slides on off the screen rather than vanishing. The slant is taken from what's left (an affine stand-in
	# for the true perspective). Only a panel wholly that near isn't drawn.
	var z_min := proj.focal() * CARD_NEAR
	var e0: Vector2 = world_pos - along * hw
	var e1: Vector2 = world_pos + along * hw
	var z0 := _depth(e0)
	var z1 := _depth(e1)
	var z_mid := _depth(world_pos)
	var anchor := world_pos
	if z_mid < z_min:
		var far_end := e1 if z1 > z0 else e0
		var z_far := maxf(z0, z1)
		if z_far <= z_min:
			return Transform2D(Vector2.ZERO, Vector2.ZERO, at)
		anchor = world_pos + (far_end - world_pos) * ((z_min - z_mid) / (z_far - z_mid))
	var z_anchor := maxf(z_mid, z_min)
	if z0 < z_min:
		e0 = anchor + (e0 - anchor) * ((z_anchor - z_min) / maxf(z_anchor - z0, 1e-4))
	if z1 < z_min:
		e1 = anchor + (e1 - anchor) * ((z_anchor - z_min) / maxf(z_anchor - z1, 1e-4))
	var pa := proj.project(e0)
	var pb := proj.project(e1)
	var pc := proj.project(anchor)
	var span := (e1 - e0).dot(along)
	if pa.z <= 0.0 or pb.z <= 0.0 or pc.z <= 0.0 or span < 0.5:
		return Transform2D(Vector2.ZERO, Vector2.ZERO, at)
	var x_axis := (Vector2(pb.x, pb.y) - Vector2(pa.x, pa.y)) / span
	# The drawing's middle (local 0) goes where the anchor's own place along the panel says.
	var origin := proj.center + Vector2(pc.x, pc.y) - x_axis * (anchor - world_pos).dot(along)
	return Transform2D(x_axis, Vector2(0.0, pc.z), origin)


const NEAR_HIDE := 30.0  # (only right at the lens; anything still on screen is drawn)
const CARD_NEAR := 0.12  # nearest a card's end is projected from, as a share of the focal length (scale ~8)


## How far in front of the eye a ground point is, along the line of sight (ViewProjection's z).
func _depth(p: Vector2) -> float:
	var a := (p - (proj.center - proj.forward() * proj.back)).dot(proj.forward())
	return a * cos(proj.pitch) + proj.height * sin(proj.pitch)


## Scenery's grove, in a perspective world: a tree is shown only inside the wedge of ground the view can see
## (a landmark out to LANDMARK_REACH), and swayed (redrawn) every frame only while near; a distant one sways
## every few frames, where nobody can tell. Hiding drops it out of the y-sort and the projection pass too.
const SWAY_NEAR := 520.0
const SIDE_MARGIN := 90.0
var _tick := 0


func tick_trees(trees: Array, t: float) -> void:
	_tick += 1
	var fwd := proj.forward()
	var right := proj.right()
	var foot := proj.center - fwd * proj.back
	var slope := (_view_size().x * 0.5 / _zoom()) / proj.focal() * 1.08
	var reach := proj.back + proj.far
	var i := 0
	for tree in trees:
		i += 1
		var rel: Vector2 = tree.position - foot
		var a := rel.dot(fwd)
		var lim := proj.back + LANDMARK_REACH if tree.is_great else reach
		var vis := a > 4.0 and a < lim and absf(rel.dot(right)) < a * slope + SIDE_MARGIN
		if vis != tree.visible:
			tree.visible = vis
		if vis and (a < proj.back + SWAY_NEAR or (_tick + i) % 4 == 0):
			tree.set_time(t)


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
