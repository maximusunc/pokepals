class_name PaintBake
extends RefCounted
## Draw something that never changes ONCE, into a texture, instead of every frame (the same idea as StaticBake,
## for one picture rather than a whole world). Many little `draw_*` calls cost script time each time they're
## issued and many draw calls to render; baked, the same picture is one textured quad.
##
## How: a SubViewport is an off-screen render target. A throwaway node inside it calls `draw_fn(canvas_item)`
## (with `rect`'s top-left at the viewport's origin), the renderer draws it once (UPDATE_ONCE), and we read the
## result back as an image and hand `done` an ImageTexture. A transparent viewport stores its pixels with their
## alpha premultiplied, so draw the texture with `premult_material()` where it has soft edges.
##
## If nothing is really rendered (a headless test run) `done` is never called: the caller keeps drawing live,
## exactly as it would have. The bake only ever replaces drawing, it never removes it first.


static func bake(host: Node, rect: Rect2, draw_fn: Callable, done: Callable) -> void:
	if DisplayServer.get_name() == "headless" or rect.size.x < 1.0 or rect.size.y < 1.0 or not host.is_inside_tree():
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(ceili(rect.size.x), ceili(rect.size.y))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var painter := _Painter.new()
	painter.fn = draw_fn
	painter.position = -rect.position
	vp.add_child(painter)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(host) or not is_instance_valid(vp):
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return
	done.call(ImageTexture.create_from_image(img))


## The material a baked texture with soft or see-through edges is drawn with (see above).
static func premult_material() -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	return mat


class _Painter extends Node2D:
	var fn: Callable

	func _draw() -> void:
		fn.call(self)
