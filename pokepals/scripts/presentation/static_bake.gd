class_name StaticBake
extends RefCounted
## Draw a world's unmoving structure ONCE, into textures, instead of every frame. A souk is mostly
## walls, rooftops and stalls that never change, yet WorldArt used to repaint all of it 60 times a
## second: hundreds of separate shapes, each its own GPU draw call, plus the script time to issue
## them. Baked, the same picture costs one textured draw per piece and no script time at all.
##
## How: a SubViewport is an off-screen render target. We put a hidden copy of WorldArt inside one
## (in bake_only mode, drawing just the static parts), let the renderer draw it for a frame, read the
## result back as an image, and hand the live WorldArt the textures to draw instead. The world is cut
## into pieces no bigger than CHUNK, so even a big world stays within phones' texture size limits.
##
## Opt-in per world, through its art block: "static_bake": { "enabled": true, "types": [...] }. If
## baking can't happen (a headless test run, where nothing is really rendered), the live drawing
## simply carries on: the bake only ever replaces drawing, it never removes it first.

const CHUNK := 1024
# How far the baked region reaches past the world bounds: walls stand ~22 px tall above their
# footprint and props reach up from their ground point, so give the top more room.
const MARGIN_TOP := 160.0
const MARGIN := 24.0


static func run(host: WorldArt, data: Dictionary, style: ArtStyle, types: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return  # nothing is rendered headless; keep drawing live
	var region: Rect2 = host._bounds.grow_individual(MARGIN, MARGIN_TOP, MARGIN, MARGIN)
	var jobs: Array = []  # [rect, viewport]
	var y := region.position.y
	while y < region.end.y:
		var x := region.position.x
		while x < region.end.x:
			var rect := Rect2(x, y, minf(CHUNK, region.end.x - x), minf(CHUNK, region.end.y - y))
			var vp := SubViewport.new()
			vp.size = Vector2i(ceili(rect.size.x), ceili(rect.size.y))
			vp.transparent_bg = true
			vp.disable_3d = true
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
			var art := WorldArt.new()
			art.position = -rect.position
			vp.add_child(art)
			host.add_child(vp)
			art.render_bake(data, style, types)
			jobs.append([rect, vp])
			x += CHUNK
		y += CHUNK
	# Let the renderer draw them (UPDATE_ONCE renders on the next frame), then read them back.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var pieces: Array = []
	var ok := is_instance_valid(host)
	for job in jobs:
		var vp: SubViewport = job[1]
		if ok and is_instance_valid(vp):
			var img := vp.get_texture().get_image()
			if img == null or img.is_empty():
				ok = false
			else:
				pieces.append([job[0], ImageTexture.create_from_image(img)])
		if is_instance_valid(vp):
			vp.queue_free()
	if ok:
		host.adopt_bake(pieces, types)
