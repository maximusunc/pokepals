class_name PerspectiveView
extends Node
## SPIKE (Horizon, the fake-3D world): look at an ordinary 2D world through a tilted perspective, with the
## ground running off to a horizon and upright things standing on it, scaled by distance. The world itself is
## untouched: every position stays a plain 2D world position, so logic, collision, the server and every
## director carry on exactly as before. Only the DRAWING changes, in two parts:
##   * the flat layer (WorldArt: ground, paths, ponds, props) is rendered top-down into two SubViewports that
##     share this world's canvas (a sharp one for the near ground, a wide one out to the horizon), and a
##     full-screen shader looks at those textures in perspective;
##   * just before the frame is drawn, every direct child of Scenery (actors, trees, buildings, portals) has
##     its DRAWN transform overridden in the RenderingServer: moved to its projected spot and scaled by depth.
##     Node.position is never touched, so nothing that reads it sees any difference.
## Throwaway: proving the trick and its cost decides whether Horizon is built for real.
##
## Two cameras, cycled from the gear menu (or P):
##   SHOULDER: fixed, facing north, over the shoulder.
##   INSIDE:   lower, nearer eye level; it swings lazily round behind you as you walk, the joystick moves you
##             relative to the screen, your companion walks beside you, and standing still for a few seconds
##             lets the camera drift down lower still (lingering).
##
## The projection. The camera faces F = (0,-1) rotated by `yaw` (0 = north, +PI/2 = east). For a world point
## p, with C the ground point at the focus:
##   d = (p - C).rotated(-yaw)   (into the view's frame: -y is "away from the camera")
##   z = z0 - d.y (distance from the eye);  s = z0 / z (scale; 1 at the focus)
##   screen offset (world units at the focus) = focus + (d.x * s, k * z0 * (s - 1))
## so near the focus the ground is foreshortened by k, and the horizon (s -> 0) sits k * z0 above it.

enum Mode { OFF, SHOULDER, INSIDE }

const SHADER := preload("res://assets/perspective_ground.gdshader")
const FLAT_LAYER := 2  # visibility layer bit value for the flat world (rendered only into the SubViewports)

## The view's turn, read by the sprite drawers (so a sprite faces relative to the camera) and the player's
## input (so the joystick moves you relative to the screen). 0 whenever the perspective view is off.
static var view_yaw := 0.0

# SHOULDER: the "over the shoulder" camera (chosen over a higher drone-like one and a near-the-ground one).
@export var shoulder := { "k": 0.35, "z0": 260.0, "focus_y": 90.0, "s_far": 0.22 }
# INSIDE: lower, with a nearer eye; and where lingering takes it.
@export var inside := { "k": 0.24, "z0": 220.0, "focus_y": 105.0, "s_far": 0.15 }
@export var inside_linger := { "k": 0.17, "z0": 210.0, "focus_y": 75.0, "s_far": 0.12 }
@export var swing_rate := 0.8       # how quickly the INSIDE camera comes round behind you (per second, at full speed)
@export var swing_sideways := 0.25  # ...as a share of that when walking straight across the screen (so holding a side doesn't spin you round)
@export var swing_max_deg := 115.0  # walking back toward the camera (more than this off its facing) doesn't swing it
@export var linger_after := 2.5     # seconds standing still before the camera starts to settle lower
@export var linger_down_rate := 0.45
@export var linger_up_rate := 2.5
@export var companion_side_deg := 70.0  # INSIDE: the companion's follow spot, turned from behind you toward your side
@export var near_s := 0.5            # the sharp near texture covers the ground from the bottom of the screen to here
@export var near_tex_size := Vector2i(1024, 512)
@export var far_tex_size := Vector2i(2048, 1024)

var k := 0.35
var z0 := 260.0
var focus := Vector2(0, 90)
var s_far := 0.22

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
var _rect: ColorRect
var _mat: ShaderMaterial
var _hidden: Array[CanvasItem] = []
var _mode := Mode.OFF
var _yaw := 0.0
var _still := 0.0
var _linger := 0.0
var _limits := []
## Timings (usec) of the last frame's projection pass, for measuring.
var last_project_usec := 0


func setup(world: Node2D, art: CanvasItem, scenery: Node2D, camera: Camera2D, player: Node2D = null, companion: Node2D = null) -> void:
	_world = world
	_art = art
	_scenery = scenery
	_camera = camera
	_player = player
	_companion = companion
	set_process(false)


func is_on() -> bool:
	return _mode != Mode.OFF


func mode() -> int:
	return _mode


## The label for the gear menu's item: what a tap switches TO.
func next_label() -> String:
	match _mode:
		Mode.OFF: return "Shoulder view (test)"
		Mode.SHOULDER: return "Inside view (test)"
	return "Top-down view (test)"


## Top-down -> shoulder -> inside -> top-down.
func cycle() -> void:
	set_mode((_mode + 1) % 3)


func set_on(on: bool) -> void:
	set_mode(Mode.SHOULDER if on else Mode.OFF)


func set_mode(m: int) -> void:
	if m == _mode:
		return
	var was_on := _mode != Mode.OFF
	_mode = m
	if m != Mode.OFF and not was_on:
		_enable()
	elif m == Mode.OFF and was_on:
		_disable()
	_yaw = 0.0
	view_yaw = 0.0
	_still = 0.0
	_linger = 0.0
	_apply_params()
	if _companion != null and "follow_side" in _companion:
		_companion.follow_side = deg_to_rad(companion_side_deg) if m == Mode.INSIDE else 0.0
	set_process(m == Mode.INSIDE)


func _apply_params() -> void:
	var a: Dictionary = inside if _mode == Mode.INSIDE else shoulder
	var b: Dictionary = inside_linger if _mode == Mode.INSIDE else shoulder
	var t := _linger
	k = lerpf(float(a["k"]), float(b["k"]), t)
	z0 = lerpf(float(a["z0"]), float(b["z0"]), t)
	focus = Vector2(0, lerpf(float(a["focus_y"]), float(b["focus_y"]), t))
	s_far = lerpf(float(a["s_far"]), float(b["s_far"]), t)


func _new_flat(size: Vector2i) -> Array:
	var sub := SubViewport.new()
	sub.size = size
	sub.world_2d = _world.get_viewport().world_2d
	sub.canvas_cull_mask = FLAT_LAYER
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.disable_3d = true
	sub.transparent_bg = true  # past the world's edge reads as haze, not the clear colour
	sub.snap_2d_transforms_to_pixel = true
	add_child(sub)
	var cam := Camera2D.new()
	cam.ignore_rotation = false  # the texture is cut along the view's turn, so its texels line up with the screen
	sub.add_child(cam)
	cam.make_current()
	return [sub, cam]


func _enable() -> void:
	var vp := _world.get_viewport()
	var n := _new_flat(near_tex_size)
	_near = n[0]
	_near_cam = n[1]
	var f := _new_flat(far_tex_size)
	_far = f[0]
	_far_cam = f[1]
	# The world node draws nothing itself but is a parent of both halves, so it is in both layers.
	_world.visibility_layer = 1 | FLAT_LAYER
	_set_layer(_art, FLAT_LAYER)
	vp.set_canvas_cull_mask_bit(1, false)
	_layer = CanvasLayer.new()
	_layer.layer = -1
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("near_tex", _near.get_texture())
	_mat.set_shader_parameter("far_tex", _far.get_texture())
	_rect.material = _mat
	_layer.add_child(_rect)
	# Things floating over the whole world that this spike doesn't project yet.
	for nm in ["AmbientLife", "Garlands", "SteamPuffs"]:
		var ci := _world.get_node_or_null(nm) as CanvasItem
		if ci != null and ci.visible:
			ci.visible = false
			_hidden.append(ci)
	# The camera's world limits stop it at the edge, which in perspective just pushes you off the focus.
	_limits = [_camera.limit_left, _camera.limit_top, _camera.limit_right, _camera.limit_bottom]
	_camera.limit_left = -10000000
	_camera.limit_top = -10000000
	_camera.limit_right = 10000000
	_camera.limit_bottom = 10000000
	RenderingServer.frame_pre_draw.connect(_project)


func _disable() -> void:
	RenderingServer.frame_pre_draw.disconnect(_project)
	ViewCull.override_rect = Rect2()
	_world.get_viewport().set_canvas_cull_mask_bit(1, true)
	_world.visibility_layer = 1
	_set_layer(_art, 1)
	for ci in _hidden:
		ci.visible = true
	_hidden.clear()
	_camera.limit_left = _limits[0]
	_camera.limit_top = _limits[1]
	_camera.limit_right = _limits[2]
	_camera.limit_bottom = _limits[3]
	for c in _scenery.get_children():
		if c is Node2D:
			RenderingServer.canvas_item_set_transform((c as Node2D).get_canvas_item(), (c as Node2D).transform)
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
	if _mode != Mode.OFF:
		RenderingServer.frame_pre_draw.disconnect(_project)
		ViewCull.override_rect = Rect2()
		view_yaw = 0.0


## INSIDE: swing the view round behind the way you're walking (lazily, and not when you walk back toward the
## camera), and settle lower while you stand still.
func _process(delta: float) -> void:
	if _player == null:
		return
	var v: Variant = _player.get("velocity")
	var vel: Vector2 = v if v is Vector2 else Vector2.ZERO
	var speed := vel.length()
	if speed > 20.0:
		var target := atan2(vel.x, -vel.y)
		var diff := angle_difference(_yaw, target)
		if absf(diff) < deg_to_rad(swing_max_deg):
			var pace := clampf(speed / 90.0, 0.0, 1.0)
			var w := swing_sideways + (1.0 - swing_sideways) * maxf(0.0, cos(diff))
			_yaw += diff * (1.0 - exp(-swing_rate * pace * w * delta))
		_still = 0.0
	else:
		_still += delta
	view_yaw = _yaw
	var want := 1.0 if _still > linger_after else 0.0
	var rate := linger_down_rate if want > _linger else linger_up_rate
	_linger = move_toward(_linger, want, rate * delta)
	_apply_params()


## Where world point p lands, as an offset from the screen centre in world units at the focus (multiply by the
## camera zoom for canvas units), and its scale. z = s <= 0 means behind the eye.
func project(p: Vector2, c: Vector2) -> Vector3:
	var d := (p - c).rotated(-_yaw)
	var z := z0 - d.y
	if z <= 1.0:
		return Vector3(0, 0, 0)
	var s := z0 / z
	return Vector3(focus.x + d.x * s, focus.y + k * z0 * (s - 1.0), s)


## The ground between scales s_a (nearer) and s_b (farther), as a rect in the VIEW's frame around C.
func _band(half: Vector2, s_a: float, s_b: float) -> Rect2:
	var near_y := z0 - z0 / s_a
	var far_y := z0 - z0 / s_b
	var far_half_w := half.x / s_b
	return Rect2(Vector2(-far_half_w, far_y), Vector2(2.0 * far_half_w, near_y - far_y))


func _fit(sub_cam: Camera2D, tex: Vector2i, band: Rect2, c: Vector2) -> Array:
	var zs := minf(float(tex.x) / band.size.x, float(tex.y) / band.size.y)
	var covered := Vector2(tex) / zs
	var center := band.get_center()
	sub_cam.position = c + center.rotated(_yaw)
	sub_cam.rotation = _yaw
	sub_cam.zoom = Vector2(zs, zs)
	return [center, covered]


func _project() -> void:
	if not is_instance_valid(_scenery) or not _scenery.is_inside_tree():
		return
	var t0 := Time.get_ticks_usec()
	var zoom := _camera.zoom.x
	var view := _world.get_viewport_rect().size / zoom
	var c := _camera.get_screen_center_position()
	var half := view * 0.5
	var s_bottom := 1.0 + (half.y - focus.y) / (k * z0)
	var whole := _band(half, s_bottom, s_far)
	# Culling: the bounding box of the visible ground, turned back into the world.
	var bb := Rect2(c + whole.position.rotated(_yaw), Vector2.ZERO)
	bb = bb.expand(c + Vector2(whole.end.x, whole.position.y).rotated(_yaw))
	bb = bb.expand(c + Vector2(whole.position.x, whole.end.y).rotated(_yaw))
	bb = bb.expand(c + whole.end.rotated(_yaw))
	ViewCull.override_rect = bb
	var nf := _fit(_near_cam, near_tex_size, _band(half, s_bottom, maxf(near_s, s_far)), c)
	var ff := _fit(_far_cam, far_tex_size, whole, c)
	_mat.set_shader_parameter("view_size", _world.get_viewport_rect().size)
	_mat.set_shader_parameter("zoom", zoom)
	_mat.set_shader_parameter("focus", focus)
	_mat.set_shader_parameter("k", k)
	_mat.set_shader_parameter("z0", z0)
	_mat.set_shader_parameter("near_center", nf[0])
	_mat.set_shader_parameter("near_size", nf[1])
	_mat.set_shader_parameter("far_center", ff[0])
	_mat.set_shader_parameter("far_size", ff[1])
	_mat.set_shader_parameter("s_far", s_far)
	_mat.set_shader_parameter("s_haze", lerpf(s_far, 1.0, 0.33))
	# Upright things: overriding only the drawn transform, relative to Scenery (at the world origin).
	var inv := _scenery.global_transform.affine_inverse()
	for child in _scenery.get_children():
		var n := child as Node2D
		if n == null or not n.visible:
			continue
		var pr := project(_scenery.global_transform * n.position, c)
		var xf: Transform2D
		if pr.z < s_far * 0.9:
			xf = Transform2D(0.0, Vector2.ZERO, 0.0, n.position)  # past the draw distance, or behind the eye
		else:
			var q := c + Vector2(pr.x, pr.y)
			var basis := n.transform
			basis.origin = Vector2.ZERO
			xf = Transform2D(0.0, Vector2(pr.z, pr.z), 0.0, inv * q) * basis
		RenderingServer.canvas_item_set_transform(n.get_canvas_item(), xf)
	last_project_usec = Time.get_ticks_usec() - t0
