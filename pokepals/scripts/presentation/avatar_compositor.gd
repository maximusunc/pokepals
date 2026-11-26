class_name AvatarCompositor
extends RefCounted
## Draws a PAPER-DOLL avatar: a stack of directional, animated sprite layers composited
## back-to-front, each one blitted by the same per-frame logic SpriteActor already uses
## (it picks the right row for facing and column for the walk phase, anchored bottom-centre
## so every layer's feet land on the same ground). This is the presentation counterpart to
## PlayerAppearance: PlayerAppearance decides the ORDERED LIST of layers (pure data);
## AvatarCompositor turns each layer's 'sheet' into a Texture2D and draws them in order.
##
## A single base body layer drawn through here is byte-for-byte the old single-sheet player
## render — the compositor is the seam that lets hats/hair/outfits stack on top later without
## touching movement, collision, or the procedural fallback.
##
## Pure presentation; a layer whose sheet doesn't exist is silently dropped (SpriteSlot's
## discipline), so items can be declared in the catalog before their art is drawn.

## look_id -> keep last N recolored textures in VRAM. Bounded so switching skin/hair in the
## wardrobe (or many friends' looks) doesn't leak — a small cap is plenty for a few avatars.
static var _recolor_cache: Dictionary = {}   # "sheet|ramp" -> ImageTexture
static var _recolor_order: Array[String] = []
const RECOLOR_CACHE_MAX := 64
static var _sheet_cache: Dictionary = {}     # sheet path -> Texture2D (null: no art)
const SHEET_CACHE_MAX := 256
const OUTLINE_CUT := 0.18   # luminance below this stays the authored dark outline


## Turn the pure data layers from PlayerAppearance.resolved_layers() into DRAWABLE layers:
## load each 'sheet' to a Texture2D, keep the order, drop any whose texture is missing. Do
## this once when the loadout changes (not every frame) — Godot caches loads, but the array
## is what _draw iterates. Each returned entry is { tex, cfg, palette }, where cfg IS the
## item definition (it already carries frame/fps/walk_frames/idle_frame/dirs for SpriteActor).
##
## DYE layers (a body or hair sheet authored in grayscale) carry a 'palette_color' [r,g,b]:
## we recolor the sheet once (mapping luminance onto that swatch — dark outline preserved,
## mid/light -> shadow/highlight) and cache the result by (sheet, ramp), so skin tone and
## hair color actually show. Non-dye layers draw at their native colors, unchanged.
static func load_layers(resolved: Array) -> Array:
	var out: Array = []
	for layer in resolved:
		var tex := _sheet(String(layer.get("sheet", "")))
		if tex == null:
			continue
		var path := String(layer.get("sheet", ""))
		var pc: Array = layer.get("palette_color", [])
		if pc.size() >= 3:
			tex = _recolored(tex, path, String(layer.get("palette", "")), pc)
		out.append({ "tex": tex, "cfg": layer, "palette": String(layer.get("palette", "")) })
	return out


## A wardrobe sheet by path, or null when it has no art. Held here once loaded: a dyed layer keeps only its
## recolored copy, so without this its source sheet would be freed and read from disk again for every avatar
## that wears it (a crowd arriving would load the same few sheets hundreds of times).
static func _sheet(path: String) -> Texture2D:
	if path == "":
		return null
	if _sheet_cache.has(path):
		return _sheet_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = ResourceLoader.load(path) as Texture2D
	if _sheet_cache.size() >= SHEET_CACHE_MAX:
		_sheet_cache.clear()
	_sheet_cache[path] = tex
	return tex


## Fetch (or bake + cache) a recolored copy of a grayscale sheet for the given ramp swatch.
## The math mirrors palette_swap.gdshader: outline pixels (very dark) are preserved, and the
## rest is remapped from a shadow (base*0.72) to a highlight (base->white 0.28) by luminance.
static func _recolored(src: Texture2D, path: String, ramp: String, rgb: Array) -> Texture2D:
	var key := path + "|" + ramp
	if _recolor_cache.has(key):
		_recolor_order.erase(key)
		_recolor_order.append(key)
		return _recolor_cache[key]

	var img := src.get_image()
	if img == null:
		return src
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	var base := Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	var shadow := base * 0.72
	var highlight := base.lerp(Color.WHITE, 0.28)
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var p := img.get_pixel(x, y)
			if p.a < 0.01:
				continue
			var lum := p.r * 0.299 + p.g * 0.587 + p.b * 0.114
			if lum < OUTLINE_CUT:
				continue  # keep the dark outline as authored
			var t := smoothstep(OUTLINE_CUT, 0.95, lum)
			var c := shadow.lerp(highlight, t)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, p.a))

	var out := ImageTexture.create_from_image(img)
	_recolor_cache[key] = out
	_recolor_order.append(key)
	while _recolor_order.size() > RECOLOR_CACHE_MAX:
		_recolor_cache.erase(_recolor_order.pop_front())
	return out


## Whether there's anything to composite (at least one layer's art resolved). When false,
## the caller should fall back to its procedural look (VectorActor).
static func has_drawable(loaded: Array) -> bool:
	return not loaded.is_empty()


## Draw the loaded layers back-to-front. params (facing, speed, time) are shared by every
## layer so the whole avatar faces and walks as one. Any recolor was already baked into each
## layer's texture by load_layers (dye layers), so drawing is a plain per-layer blit.
static func draw(ci: CanvasItem, loaded: Array, params: Dictionary) -> void:
	if ci.has_meta("brick_cell") and not loaded.is_empty():
		_draw_bricks(ci, loaded, params)
		return
	for layer in loaded:
		SpriteActor.draw(ci, layer["tex"], params, layer["cfg"])


## A brick world (Clickton): the layers are flattened into ONE picture and rebuilt out of bricks as one
## figure (BrickLook.for_stack), so the outfit doesn't become several brick figures stacked on top of each
## other. Only layers laid out like the first (same sheet size and frame) can be flattened; any other is
## drawn over the top, bricked on its own.
static func _draw_bricks(ci: CanvasItem, loaded: Array, params: Dictionary) -> void:
	var base: Dictionary = loaded[0]
	var size: Vector2 = (base["tex"] as Texture2D).get_size()
	var frame: Array = base["cfg"].get("frame", [32, 32])
	var stack: Array = []
	var rest: Array = []
	for layer in loaded:
		if (layer["tex"] as Texture2D).get_size() == size and layer["cfg"].get("frame", [32, 32]) == frame:
			stack.append(layer["tex"])
		else:
			rest.append(layer)
	SpriteActor.draw(ci, BrickLook.for_stack(ci, stack, frame), params, base["cfg"], true)
	for layer in rest:
		SpriteActor.draw(ci, layer["tex"], params, layer["cfg"])
