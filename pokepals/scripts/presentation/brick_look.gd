class_name BrickLook
extends RefCounted
## Rebuilds a character sheet out of BRICKS (Clickton, the city made of bricks). A world whose actor_look
## carries a `brick` block marks every player and companion node with a `brick_cell` meta
## (OtherworldLook.apply); the sheet drawers (SpriteActor, PalSprite, CompanionSprite, and AvatarCompositor
## for a whole paper-doll avatar) then draw the brick version of the sheet instead of the raw one.
##
## The picture is cut into small square bricks (`cell` texels, 2 by default) and each brick that is mostly
## filled takes ONE colour. It's built to stay STEADY while the figure animates, so the bricks don't churn:
##   * the brick grid rides the figure: each frame's rows are anchored to its topmost filled row, so the
##     walk cycle's one-texel bob carries every brick along with it rather than re-cutting the body;
##   * colour is decided per SOURCE colour, not per average: every distinct colour in the sheet is nudged
##     toward the nearest stock brick colour once (by hue first, so a garment's shades stay one family),
##     and a brick takes the colour most of its texels have, so it never blends into a muddy in-between;
##   * the sheet's dark outline isn't a brick of its own: on the rim it's dropped (the rebuilt figure is
##     rimmed by darkening its own edge bricks instead), inside it takes the neighbouring bricks' colour,
##     and small dark details wholly inside the figure (eyes, a mouth, glasses) are kept as a PRINT on the bricks;
##   * every brick carries a lit stud texel in its top-left corner.
## A paper-doll avatar is flattened into one picture first (for_stack), so its layers become one figure
## of bricks rather than several brick figures stacked on top of each other.
##
## Done once per sheet on the CPU and cached, rather than in a shader, so it looks identical on every
## renderer. Pure presentation.

const STOCK: Array[Color] = [
	Color(0.769, 0.157, 0.106), Color(0.051, 0.412, 0.671), Color(0.961, 0.804, 0.188), Color(0.157, 0.498, 0.275),
	Color(0.855, 0.522, 0.251), Color(0.949, 0.953, 0.953), Color(0.106, 0.165, 0.204), Color(0.639, 0.635, 0.647),
	Color(0.388, 0.373, 0.384), Color(0.843, 0.773, 0.600), Color(0.412, 0.251, 0.157), Color(1.000, 0.596, 0.863),
	Color(0.655, 0.514, 0.784), Color(0.071, 0.616, 0.616), Color(0.800, 0.557, 0.412), Color(0.643, 0.741, 0.278),
	Color(0.455, 0.722, 0.871), Color(0.482, 0.180, 0.184), Color(0.545, 0.373, 0.255), Color(0.918, 0.718, 0.553)]
const CACHE_MAX := 96
const INK_LUM := 30.0           # luminance (0-255) under which a near-grey texel is the sheet's dark outline
const INK_CHROMA := 12          # ...and how far from grey it may be (a dark but coloured body isn't outline)
const PRINT_MAX := 40           # an interior run of outline this small or smaller (eyes, a mouth, glasses) is printed on
const STUD := 1.12              # the lit stud texel in each brick's top-left corner
const SEAM := 0.80              # bricks of 3+ texels also get a shaded seam along the bottom and right
const RIM := 0.42               # the silhouette's edge texels, darkened into an outline
const EMPTY := -2               # brick grid: no brick here
const ALL_INK := -1             # brick grid: a brick that is all outline (resolved before drawing)
const PRINT_RGB := 0x1c1a1c     # PRINT as 0xRRGGBB

static var _cache := {}


## `tex` as this actor should draw it: the brick version if the node is marked, else the sheet itself.
## `frame` is the sheet's frame size ([w, h], as the art cfg gives it): the grid is anchored per frame.
static func for_actor(ci: CanvasItem, tex: Texture2D, frame: Array = [32, 32]) -> Texture2D:
	if tex == null or not ci.has_meta("brick_cell"):
		return tex
	return brickify(tex, int(ci.get_meta("brick_cell")), float(ci.get_meta("brick_quantize", 0.3)), _frame_size(frame))


## A whole paper-doll stack (same-sized sheets, back to front) flattened into one picture and rebuilt out
## of bricks as one figure. Cached by the stack, so it's built once per outfit.
static func for_stack(ci: CanvasItem, texs: Array, frame: Array = [32, 32]) -> Texture2D:
	if texs.is_empty():
		return null
	var cell := int(ci.get_meta("brick_cell", 2))
	var quantize := float(ci.get_meta("brick_quantize", 0.3))
	var key := "S"
	for t in texs:
		key += "|%d" % (t as Texture2D).get_instance_id()
	key += "|%d|%.3f" % [cell, quantize]
	if _cache.has(key):
		return _cache[key]
	var base := _rgba((texs[0] as Texture2D).get_image())
	if base == null:
		return texs[0]
	var flat := Image.create(base.get_width(), base.get_height(), false, Image.FORMAT_RGBA8)
	var rect := Rect2i(Vector2i.ZERO, flat.get_size())
	for t in texs:
		var img := _rgba((t as Texture2D).get_image())
		if img != null:
			flat.blend_rect(img, rect, Vector2i.ZERO)   # alpha "over", back to front
	return _store(key, ImageTexture.create_from_image(_build(flat, cell, quantize, _frame_size(frame))))


static func brickify(tex: Texture2D, cell: int = 2, quantize: float = 0.3, frame := Vector2i(32, 32)) -> Texture2D:
	var key := "%d|%d|%.3f|%d|%d" % [tex.get_instance_id(), cell, quantize, frame.x, frame.y]
	if _cache.has(key):
		return _cache[key]
	var img := _rgba(tex.get_image())
	if img == null:
		return tex
	return _store(key, ImageTexture.create_from_image(_build(img, cell, quantize, frame)))


static func _store(key: String, tex: Texture2D) -> Texture2D:
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[key] = tex
	return tex


static func _rgba(img: Image) -> Image:
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func _frame_size(frame: Array) -> Vector2i:
	if frame.size() < 2:
		return Vector2i(32, 32)
	return Vector2i(maxi(1, int(frame[0])), maxi(1, int(frame[1])))


## The whole sheet, frame by frame. Works on raw bytes (much faster than get/set_pixel, which matters on the
## web build): `opaque`/`ink` flag each texel, `col` holds its snapped colour as 0xRRGGBB.
static func _build(src: Image, cell: int, quantize: float, frame: Vector2i) -> Image:
	cell = maxi(1, cell)
	var w := src.get_width()
	var h := src.get_height()
	var n := w * h
	var d := src.get_data()
	var opaque := PackedByteArray()
	opaque.resize(n)
	var ink := PackedByteArray()
	ink.resize(n)
	var col := PackedInt32Array()
	col.resize(n)
	var snapped := {}
	for i in n:
		if d[i * 4 + 3] < 128:
			continue
		opaque[i] = 1
		var r: int = d[i * 4]
		var g: int = d[i * 4 + 1]
		var b: int = d[i * 4 + 2]
		if r * 0.299 + g * 0.587 + b * 0.114 < INK_LUM and maxi(r, maxi(g, b)) - mini(r, mini(g, b)) < INK_CHROMA:
			ink[i] = 1
			continue
		var k := (r << 16) | (g << 8) | b
		if not snapped.has(k):
			snapped[k] = _snap(k, quantize)
		col[i] = snapped[k]
	var out := PackedByteArray()
	out.resize(n * 4)   # all zero: fully transparent
	var fy := 0
	while fy < h:
		var fx := 0
		while fx < w:
			_frame(opaque, ink, col, out, w, fx, fy, mini(frame.x, w - fx), mini(frame.y, h - fy), cell)
			fx += frame.x
		fy += frame.y
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)


## One source colour (0xRRGGBB) nudged `quantize` of the way toward its stock brick colour. The match is by
## hue and saturation first, lightness only a little, so a garment's shadow and highlight land on the same
## brick colour; the stock colour then keeps a gentle share of the original shade.
static func _snap(k: int, quantize: float) -> int:
	var c := Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)
	var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	var best := 0
	var bd := INF
	for i in STOCK.size():
		var s := STOCK[i]
		var sl := s.r * 0.299 + s.g * 0.587 + s.b * 0.114
		var dr := (s.r - sl) - (c.r - l)
		var dg := (s.g - sl) - (c.g - l)
		var db := (s.b - sl) - (c.b - l)
		var dd := dr * dr + dg * dg + db * db + 0.35 * (sl - l) * (sl - l)
		if dd < bd:
			bd = dd
			best = i
	var st := STOCK[best]
	var stl := maxf(st.r * 0.299 + st.g * 0.587 + st.b * 0.114, 0.001)
	var f := clampf(pow(l / stl, 0.6), 0.82, 1.12)
	var target := Color(clampf(st.r * f, 0.0, 1.0), clampf(st.g * f, 0.0, 1.0), clampf(st.b * f, 0.0, 1.0))
	var o := c.lerp(target, quantize)
	return (clampi(roundi(o.r * 255.0), 0, 255) << 16) | (clampi(roundi(o.g * 255.0), 0, 255) << 8) | clampi(roundi(o.b * 255.0), 0, 255)


static func _frame(opaque: PackedByteArray, ink: PackedByteArray, col: PackedInt32Array, out: PackedByteArray,
		w: int, fx: int, fy: int, fw: int, fh: int, cell: int) -> void:
	# The figure's bounds in this frame (native find/rfind per row, so an empty margin costs next to nothing);
	# everything below works only inside them.
	var top := -1
	var bottom := -1
	var left := fw
	var right := -1
	for y in fh:
		var row := (fy + y) * w + fx
		var a := opaque.find(1, row)
		if a < 0 or a >= row + fw:
			continue
		var b := opaque.rfind(1, row + fw - 1)
		if top < 0:
			top = y
		bottom = y
		left = mini(left, a - row)
		right = maxi(right, b - row)
	if top < 0:
		return
	# Anchor the brick rows to the figure's top, so a bob moves the bricks rather than re-cutting them.
	var oy := top % cell
	var gy0 := oy - cell if oy > 0 else 0
	var ncols := (fw + cell - 1) / cell
	var nrows := (fh - gy0 + cell - 1) / cell
	var r0 := (top - gy0) / cell
	var r1 := (bottom - gy0) / cell
	var c0 := left / cell
	var c1 := right / cell

	# 1. Each mostly-filled brick takes the colour most of its texels have. The grid holds EMPTY, ALL_INK
	#    (a brick that is all outline) or the colour.
	var grid := PackedInt32Array()
	grid.resize(ncols * nrows)
	grid.fill(EMPTY)
	var cand := PackedInt32Array()
	cand.resize(cell * cell)
	var cand_n := PackedInt32Array()
	cand_n.resize(cell * cell)
	for r in range(r0, r1 + 1):
		var cy := gy0 + r * cell
		var y0 := maxi(cy, 0)
		var y1 := mini(cy + cell, fh)
		for c in range(c0, c1 + 1):
			var cx := c * cell
			var x1 := mini(cx + cell, fw)
			var filled := 0
			var nc := 0
			var best := ALL_INK
			var best_n := 0
			for y in range(y0, y1):
				var row := (fy + y) * w + fx
				for x in range(cx, x1):
					var i := row + x
					if opaque[i] == 0:
						continue
					filled += 1
					if ink[i] == 1:
						continue
					var k := col[i]
					var j := 0
					while j < nc and cand[j] != k:
						j += 1
					if j == nc:
						cand[nc] = k
						cand_n[nc] = 0
						nc += 1
					cand_n[j] += 1
					if cand_n[j] > best_n:
						best_n = cand_n[j]
						best = k
			if filled * 2 >= (y1 - y0) * (x1 - cx):
				grid[r * ncols + c] = best

	# 2. All-outline bricks: on the rim (beside an empty brick) they go; inside they take the neighbours' colour.
	var changed := true
	while changed:
		changed = false
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				var gi := r * ncols + c
				if grid[gi] != ALL_INK:
					continue
				var nb := PackedInt32Array([
					grid[gi - ncols] if r > 0 else EMPTY, grid[gi + ncols] if r < nrows - 1 else EMPTY,
					grid[gi - 1] if c > 0 else EMPTY, grid[gi + 1] if c < ncols - 1 else EMPTY])
				if nb.has(EMPTY):
					grid[gi] = EMPTY
					changed = true
					continue
				var best := ALL_INK
				var best_n := 0
				for a in 4:
					if nb[a] < 0:
						continue
					var cnt := nb.count(nb[a])
					if cnt > best_n:
						best_n = cnt
						best = nb[a]
				if best >= 0:
					grid[gi] = best
					changed = true
	# (an all-outline pocket with no coloured neighbour at all is left empty)

	# 3. Printed details: small specks of outline wholly inside the figure (eyes, a mouth).
	var printed := _prints(opaque, ink, w, fx, fy, fw, fh, Rect2i(left, top, right - left + 1, bottom - top + 1))

	# 4. Write the bricks out, brick by brick: each one's stud (and seam, for big bricks), a darkened rim where
	#    it borders empty space (so the silhouette reads as outlined on any ground), and the prints.
	for r in range(r0, r1 + 1):
		var cy := gy0 + r * cell
		for c in range(c0, c1 + 1):
			var gi := r * ncols + c
			var colour := grid[gi]
			if colour < 0:
				continue
			var cx := c * cell
			# Which sides of this brick face empty space (or the frame's edge)?
			var open_l := c == 0 or grid[gi - 1] < 0
			var open_r := c == ncols - 1 or cx + cell >= fw or grid[gi + 1] < 0
			var open_u := r == 0 or cy <= 0 or grid[gi - ncols] < 0
			var open_d := r == nrows - 1 or cy + cell >= fh or grid[gi + ncols] < 0
			var cr := (colour >> 16) & 255
			var cg := (colour >> 8) & 255
			var cb := colour & 255
			for ly in cell:
				var y := cy + ly
				if y < 0 or y >= fh:
					continue
				var row := (fy + y) * w + fx
				for lx in cell:
					var x := cx + lx
					if x >= fw:
						break
					var f := 1.0
					if cell >= 3 and (lx == cell - 1 or ly == cell - 1):
						f = SEAM
					elif lx == 0 and ly == 0:
						f = STUD
					if (open_l and lx == 0) or (open_r and (lx == cell - 1 or x == fw - 1)) \
							or (open_u and (ly == 0 or y == 0)) or (open_d and (ly == cell - 1 or y == fh - 1)):
						f = RIM
					var o := (row + x) * 4
					if printed[y * fw + x] == 1:
						out[o] = (PRINT_RGB >> 16) & 255
						out[o + 1] = (PRINT_RGB >> 8) & 255
						out[o + 2] = PRINT_RGB & 255
					else:
						out[o] = mini(int(cr * f), 255)
						out[o + 1] = mini(int(cg * f), 255)
						out[o + 2] = mini(int(cb * f), 255)
					out[o + 3] = 255


## Flags (1 per frame texel) the outline texels that form small specks (PRINT_MAX or fewer, 4-connected) with
## every texel round them filled: eyes, a mouth, a nose; never the outline round the figure or a long inner line.
## Each flood gives up as soon as its speck grows too big or touches the outside, so the long outline round
## the figure costs a few steps per texel rather than a full flood each time.
static func _prints(opaque: PackedByteArray, ink: PackedByteArray, w: int, fx: int, fy: int, fw: int, fh: int,
		box: Rect2i) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(fw * fh)
	var blob := PackedInt32Array()
	for y in range(maxi(box.position.y, 1), mini(box.end.y, fh - 1)):
		for x in range(maxi(box.position.x, 1), mini(box.end.x, fw - 1)):
			var li := y * fw + x
			if result[li] == 1 or ink[(fy + y) * w + fx + x] == 0:
				continue
			blob.clear()
			blob.append(li)
			var at := 0
			var ok := true
			while ok and at < blob.size():
				var p := blob[at]
				at += 1
				var px := p % fw
				var py := p / fw
				if px == 0 or py == 0 or px == fw - 1 or py == fh - 1:
					ok = false
					break
				var up := (fy + py - 1) * w + fx + px
				var mid := up + w
				var dn := mid + w
				if opaque[up - 1] == 0 or opaque[up] == 0 or opaque[up + 1] == 0 or opaque[mid - 1] == 0 \
						or opaque[mid + 1] == 0 or opaque[dn - 1] == 0 or opaque[dn] == 0 or opaque[dn + 1] == 0:
					ok = false
					break
				if ink[mid - 1] == 1 and not blob.has(p - 1):
					blob.append(p - 1)
				if ink[mid + 1] == 1 and not blob.has(p + 1):
					blob.append(p + 1)
				if ink[up] == 1 and not blob.has(p - fw):
					blob.append(p - fw)
				if ink[dn] == 1 and not blob.has(p + fw):
					blob.append(p + fw)
				if blob.size() > PRINT_MAX:
					ok = false
			if ok:
				for p in blob:
					result[p] = 1
	return result
