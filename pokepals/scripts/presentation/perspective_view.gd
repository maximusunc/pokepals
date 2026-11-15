class_name PerspectiveView
extends Node
## SPIKE (Horizon, the fake-3D world): look at an ordinary 2D world through a tilted perspective, with the
## ground running off to a horizon and upright things standing on it, scaled by distance. The world itself is
## untouched: every position stays a plain 2D world position, so logic, collision, the server and every
## director carry on exactly as before. Only the DRAWING changes, in two parts:
##   * the flat layer (WorldArt: ground, paths, ponds, props) is rendered top-down into a SubViewport that
##     shares this world's canvas, and a full-screen shader looks at that texture in perspective;
##   * just before the frame is drawn, every direct child of Scenery (actors, trees, buildings, portals) has
##     its DRAWN transform overridden in the RenderingServer: moved to its projected spot and scaled by depth.
##     Node.position is never touched, so nothing that reads it sees any difference.
## Throwaway: proving the trick and its cost decides whether Horizon is built for real.
##
## The projection, fixed-tilt, camera facing north. For a world point p, with C the ground point at the focus:
##   d = p - C;  z = z0 - d.y (distance from the eye);  s = z0 / z (scale; 1 at the focus)
##   screen offset (world units at the focus) = focus + (d.x * s, k * z0 * (s - 1))
## so near the focus the ground is foreshortened by k, and the horizon (s -> 0) sits k * z0 above it.

const SHADER := preload("res://assets/perspective_ground.gdshader")
const FLAT_LAYER := 2  # visibility layer bit value for the flat world (rendered only into the SubViewport)

# The "over the shoulder" camera (chosen over a higher drone-like one and a near-the-ground one).
@export var k := 0.35
@export var z0 := 260.0
@export var focus := Vector2(0, 90)
@export var s_far := 0.22
@export var s_near_cull := 0.05
@export var flat_tex_size := Vector2i(2048, 1024)

var _world: Node2D
var _art: CanvasItem
var _scenery: Node2D
var _camera: Camera2D
var _sub: SubViewport
var _sub_cam: Camera2D
var _layer: CanvasLayer
var _rect: ColorRect
var _mat: ShaderMaterial
var _hidden: Array[CanvasItem] = []
var _on := false
## Timings (usec) of the last frame's projection pass, for measuring.
var last_project_usec := 0


func setup(world: Node2D, art: CanvasItem, scenery: Node2D, camera: Camera2D) -> void:
	_world = world
	_art = art
	_scenery = scenery
	_camera = camera


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


func _enable() -> void:
	var vp := _world.get_viewport()
	_sub = SubViewport.new()
	_sub.name = "PerspectiveFlat"
	_sub.size = flat_tex_size
	_sub.world_2d = vp.world_2d
	_sub.canvas_cull_mask = FLAT_LAYER
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.disable_3d = true
	_sub.transparent_bg = true  # past the world's edge reads as haze, not the clear colour
	_sub.snap_2d_transforms_to_pixel = true
	add_child(_sub)
	_sub_cam = Camera2D.new()
	_sub.add_child(_sub_cam)
	_sub_cam.make_current()
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
	_mat.set_shader_parameter("flat_tex", _sub.get_texture())
	_rect.material = _mat
	_layer.add_child(_rect)
	# Things floating over the whole world that this spike doesn't project yet.
	for n in ["AmbientLife", "Garlands", "SteamPuffs"]:
		var ci := _world.get_node_or_null(n) as CanvasItem
		if ci != null and ci.visible:
			ci.visible = false
			_hidden.append(ci)
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
	for c in _scenery.get_children():
		if c is Node2D:
			RenderingServer.canvas_item_set_transform((c as Node2D).get_canvas_item(), (c as Node2D).transform)
	_sub.queue_free()
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


## Where world point p lands, as an offset from the screen centre in world units at the focus (multiply by the
## camera zoom for canvas units), and its scale. z = s <= 0 means behind the eye.
func project(p: Vector2, c: Vector2) -> Vector3:
	var d := p - c
	var z := z0 - d.y
	if z <= 1.0:
		return Vector3(0, 0, 0)
	var s := z0 / z
	return Vector3(focus.x + d.x * s, focus.y + k * z0 * (s - 1.0), s)


func _ground_rect(c: Vector2, view: Vector2) -> Rect2:
	# The visible ground: from the bottom of the screen to the draw distance, widest at the far edge.
	var half := view * 0.5
	var s_near := 1.0 + (half.y - focus.y) / (k * z0)
	var near_y := z0 - z0 / s_near
	var far_y := z0 - z0 / s_far
	var far_half_w := half.x / s_far
	var r := Rect2(c + Vector2(-far_half_w, far_y), Vector2(2.0 * far_half_w, near_y - far_y))
	return r


func _project() -> void:
	if not is_instance_valid(_scenery) or not _scenery.is_inside_tree():
		return
	var t0 := Time.get_ticks_usec()
	var zoom := _camera.zoom.x
	var view := _world.get_viewport_rect().size / zoom
	var c := _camera.get_screen_center_position()
	var gr := _ground_rect(c, view)
	ViewCull.override_rect = gr
	# The flat texture covers the visible ground at one uniform scale.
	var zs := minf(float(flat_tex_size.x) / gr.size.x, float(flat_tex_size.y) / gr.size.y)
	var covered := Vector2(flat_tex_size) / zs
	var fc := gr.get_center()
	_sub_cam.position = fc
	_sub_cam.zoom = Vector2(zs, zs)
	_mat.set_shader_parameter("view_size", _world.get_viewport_rect().size)
	_mat.set_shader_parameter("cam_center", c)
	_mat.set_shader_parameter("zoom", zoom)
	_mat.set_shader_parameter("focus", focus)
	_mat.set_shader_parameter("k", k)
	_mat.set_shader_parameter("z0", z0)
	_mat.set_shader_parameter("flat_center", fc)
	_mat.set_shader_parameter("flat_size", covered)
	_mat.set_shader_parameter("s_far", s_far)
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
