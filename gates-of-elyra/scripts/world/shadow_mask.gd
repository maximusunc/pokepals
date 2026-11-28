class_name ShadowMask
extends RefCounted
## A silhouette as a small grid of opaque / empty cells, for judging whether one shadow has the SHAPE of
## another (Lanternfold's mural: does this animal's shadow fill the gap the bird left?). Pure: a mask is
## handed a flat alpha array (the presentation reads it off a sprite frame) and answers questions.
##
## The grid is in the sprite's own cell pixels; (ox, oy) is where the sprite's origin (its feet-line anchor)
## sits in the grid, so a mask can be placed the way the sprite is drawn. `iou` compares two masks at their
## own scales after lining up their CENTRES, which makes it a measure of shape and size alone (where the
## shadow lands is a separate question, ShadowCast's).

var w := 0
var h := 0
var ox := 0.0
var oy := 0.0
var _bits := PackedByteArray()
var _bbox := Rect2i()
var _centre := Vector2.ZERO


## alpha: w*h bytes, row by row; a cell is solid when its alpha is at least `cut`.
static func from_alpha(width: int, height: int, alpha: PackedByteArray, origin_x: float, origin_y: float, cut: int = 40) -> ShadowMask:
	var m := ShadowMask.new()
	m.w = width
	m.h = height
	m.ox = origin_x
	m.oy = origin_y
	m._bits.resize(width * height)
	var x0 := width
	var y0 := height
	var x1 := -1
	var y1 := -1
	for y in height:
		for x in width:
			var on := alpha[y * width + x] >= cut
			m._bits[y * width + x] = 1 if on else 0
			if on:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 >= 0:
		m._bbox = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
		m._centre = Vector2(float(x0 + x1 + 1) * 0.5, float(y0 + y1 + 1) * 0.5)
	return m


## A solid rectangle (tests, and a stand-in shape).
static func solid_rect(width: int, height: int, rx: int, ry: int, rw: int, rh: int, origin_x: float = 0.0, origin_y: float = 0.0) -> ShadowMask:
	var a := PackedByteArray()
	a.resize(width * height)
	for y in range(ry, ry + rh):
		for x in range(rx, rx + rw):
			a[y * width + x] = 255
	return from_alpha(width, height, a, origin_x, origin_y)


func is_empty() -> bool:
	return _bbox.size == Vector2i.ZERO


## The solid cells' bounding box, in cell pixels.
func bbox() -> Rect2i:
	return _bbox


## The middle of that box, in cell pixels.
func centre() -> Vector2:
	return _centre


func solid_at(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return _bits[y * w + x] == 1


## How alike two shadows are in shape and size, 0..1: the overlap of their solid areas over their union, with
## `a` drawn at scale `sa` and `b` at scale `sb` and the two lined up centre to centre. 1 = the same
## silhouette at the same size; a bigger or smaller copy, or a different shape, scores less. `mirror_b`
## flips b left to right first (an animal facing the other way).
static func iou(a: ShadowMask, sa: float, b: ShadowMask, sb: float, mirror_b: bool = false) -> float:
	if a == null or b == null or a.is_empty() or b.is_empty() or sa <= 0.0 or sb <= 0.0:
		return 0.0
	var ha := Vector2(a._bbox.size) * sa * 0.5
	var hb := Vector2(b._bbox.size) * sb * 0.5
	var half := Vector2(maxf(ha.x, hb.x), maxf(ha.y, hb.y)) + Vector2.ONE
	# about one sample per screen pixel, at most 64 a side
	var step := maxf(1.0, maxf(half.x, half.y) * 2.0 / 64.0)
	var inter := 0
	var union := 0
	var y := -half.y + step * 0.5   # sample cell centres, so the grid is symmetric about the centre
	while y < half.y:
		var x := -half.x + step * 0.5
		while x < half.x:
			var ia := a.solid_at(int(floorf(a._centre.x + x / sa)), int(floorf(a._centre.y + y / sa)))
			var bx := (-x if mirror_b else x) / sb
			var ib := b.solid_at(int(floorf(b._centre.x + bx)), int(floorf(b._centre.y + y / sb)))
			if ia and ib:
				inter += 1
			if ia or ib:
				union += 1
			x += step
		y += step
	return float(inter) / float(union) if union > 0 else 0.0
