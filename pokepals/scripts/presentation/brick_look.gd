class_name BrickLook
extends RefCounted
## Rebuilds a character sheet out of BRICKS (Clickton, the city made of bricks). A world whose actor_look
## carries a `brick` block marks every player and companion node with a `brick_cell` meta
## (OtherworldLook.apply); the sheet drawers (SpriteActor, PalSprite, CompanionSprite) then draw
## `for_actor(ci, tex)` instead of the raw sheet. Whatever they wear, however they're dyed, whatever animal
## the companion has shifted into, the picture is cut into square CELLS (4 texels: it divides every 32 px
## frame, so the grid sits still on the figure as its walk cycle plays) and each cell that is mostly filled
## becomes ONE brick: the average colour underneath, pulled toward the nearest stock brick colour, shaded
## like a real brick (a lit top-left edge, a shaded bottom-right seam, a stud standing on its face).
## The silhouette steps in whole bricks: you are a little brick figure.
##
## It is done once per sheet, on the CPU, and cached (a few ms for a sheet), rather than in a shader, so it
## looks identical on every renderer. Pure presentation.

const STOCK: Array[Color] = [
	Color(0.769, 0.157, 0.106), Color(0.051, 0.412, 0.671), Color(0.961, 0.804, 0.188), Color(0.157, 0.498, 0.275),
	Color(0.855, 0.522, 0.251), Color(0.949, 0.953, 0.953), Color(0.106, 0.165, 0.204), Color(0.639, 0.635, 0.647),
	Color(0.388, 0.373, 0.384), Color(0.843, 0.773, 0.600), Color(0.412, 0.251, 0.157), Color(1.000, 0.596, 0.863),
	Color(0.655, 0.514, 0.784), Color(0.071, 0.616, 0.616), Color(0.800, 0.557, 0.412), Color(0.643, 0.741, 0.278),
	Color(0.455, 0.722, 0.871), Color(0.482, 0.180, 0.184), Color(0.545, 0.373, 0.255), Color(0.918, 0.718, 0.553)]
const CACHE_MAX := 96

static var _cache := {}


## `tex` as this actor should draw it: the brick version if the node is marked, else the sheet itself.
static func for_actor(ci: CanvasItem, tex: Texture2D) -> Texture2D:
	if tex == null or not ci.has_meta("brick_cell"):
		return tex
	return brickify(tex, int(ci.get_meta("brick_cell")), float(ci.get_meta("brick_quantize", 0.6)))


static func brickify(tex: Texture2D, cell: int = 4, quantize: float = 0.6) -> Texture2D:
	var key := "%d|%d" % [tex.get_instance_id(), cell]
	if _cache.has(key):
		return _cache[key]
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)   # starts fully transparent
	var cy := 0
	while cy < h:
		var cx := 0
		while cx < w:
			_brick(img, out, cx, cy, cell, quantize, w, h)
			cx += cell
		cy += cell
	var result := ImageTexture.create_from_image(out)
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[key] = result
	return result


static func _brick(img: Image, out: Image, cx: int, cy: int, cell: int, quantize: float, w: int, h: int) -> void:
	var lo := 1
	var hi := cell - 2
	var sum := Vector3.ZERO
	var n := 0
	for pt in [Vector2i(lo, lo), Vector2i(hi, lo), Vector2i(lo, hi), Vector2i(hi, hi)]:
		var x := mini(cx + pt.x, w - 1)
		var y := mini(cy + pt.y, h - 1)
		var p := img.get_pixel(x, y)
		if p.a >= 0.5:
			sum += Vector3(p.r, p.g, p.b)
			n += 1
	if n < 2:
		return
	var avg := Color(sum.x / n, sum.y / n, sum.z / n)
	var best := STOCK[0]
	var bd := 10.0
	for s in STOCK:
		var d := Vector3(s.r - avg.r, s.g - avg.g, s.b - avg.b)
		var dd := d.dot(d)
		if dd < bd:
			bd = dd
			best = s
	var c := avg.lerp(best, quantize)
	var last := cell - 1
	for y in cell:
		for x in cell:
			if cx + x >= w or cy + y >= h:
				continue
			var shade := 1.08                           # the stud's face
			if x >= last or y >= last:
				shade = 0.74                            # the seam along the bottom and right
			elif x < 1 or y < 1:
				shade = 1.13                            # the lit top-left edge
			elif x < 2 and y < 2:
				shade = 1.30                            # the stud's highlight
			elif x >= last - 1 and y >= last - 1:
				shade = 0.88                            # the stud's shadow side
			out.set_pixel(cx + x, cy + y, Color(clampf(c.r * shade, 0.0, 1.0), clampf(c.g * shade, 0.0, 1.0), clampf(c.b * shade, 0.0, 1.0), 1.0))
