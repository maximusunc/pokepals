class_name WaterMask
extends RefCounted
## Where the water IS, as a small bitmap baked once (Stillglass's mirror lake): the world's pond outlines
## scanline-filled into a one-channel image over just the lake's own bounding box. Two readers share it:
##   * the CPU asks `is_water(p)` (and, with MirrorGeometry, "how far below this actor is the waterline?");
##   * the reflection shader samples the same image, as a texture, to clip every mirrored sprite to the
##     water (see assets/reflect.gdshader), so a reflection never spills onto land and the clip lines up
##     with the water that is actually drawn, because both come from the same rings.
## Pure data: no nodes, no rendering. Overlapping outlines union (a lake made of several ponds).

var cell := 2.0                   # world px per texel
var origin := Vector2.ZERO        # world position of texel (0, 0)'s corner
var width := 0
var height := 0
var _bytes := PackedByteArray()   # width * height, 255 = water


## Build over `rings` (Array of PackedVector2Array closed outlines in world px). `pad` px of dry margin are
## kept round the lake so a clamped texture sample outside the box always reads "land".
static func build(rings: Array, cell_px: float = 2.0, pad: float = 16.0) -> WaterMask:
	var m := WaterMask.new()
	m.cell = maxf(0.5, cell_px)
	var box := Rect2()
	var first := true
	for ring in rings:
		for p in (ring as PackedVector2Array):
			if first:
				box = Rect2(p, Vector2.ZERO)
				first = false
			else:
				box = box.expand(p)
	if first:
		return m   # no water at all: an empty mask
	box = box.grow(pad)
	m.origin = (box.position / m.cell).floor() * m.cell
	m.width = maxi(1, ceili((box.end.x - m.origin.x) / m.cell))
	m.height = maxi(1, ceili((box.end.y - m.origin.y) / m.cell))
	m._bytes.resize(m.width * m.height)
	m._bytes.fill(0)
	for ring in rings:
		m._fill_ring(ring)
	return m


func is_empty() -> bool:
	return width == 0 or height == 0


## The world rectangle the bitmap covers.
func rect() -> Rect2:
	return Rect2(origin, Vector2(width, height) * cell)


func is_water(p: Vector2) -> bool:
	if is_empty():
		return false
	var x := int(floor((p.x - origin.x) / cell))
	var y := int(floor((p.y - origin.y) / cell))
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	return _bytes[y * width + x] != 0


## The bitmap as an image (FORMAT_R8), for the shader to sample.
func to_image() -> Image:
	return Image.create_from_data(width, height, false, Image.FORMAT_R8, _bytes)


## Even-odd scanline fill of one closed outline: for each texel row, the x where the outline's edges cross
## the row's centre line, filled in pairs. Rows and edges are few (a lake is a few hundred rows of ~60-edge
## outlines), so this stays cheap enough to run at world load.
func _fill_ring(ring: PackedVector2Array) -> void:
	var n := ring.size()
	if n < 3:
		return
	var min_y := INF
	var max_y := -INF
	for p in ring:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	var row0 := maxi(0, int(floor((min_y - origin.y) / cell)))
	var row1 := mini(height - 1, int(ceil((max_y - origin.y) / cell)))
	for row in range(row0, row1 + 1):
		var wy := origin.y + (float(row) + 0.5) * cell
		var xs: Array = []
		for i in n:
			var a := ring[i]
			var b := ring[(i + 1) % n]
			if (a.y <= wy and b.y > wy) or (b.y <= wy and a.y > wy):
				xs.append(a.x + (wy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			var c0 := clampi(int(round((float(xs[k]) - origin.x) / cell)), 0, width)
			var c1 := clampi(int(round((float(xs[k + 1]) - origin.x) / cell)), 0, width)
			var base := row * width
			for c in range(c0, c1):
				_bytes[base + c] = 255
			k += 2
