class_name TideField
extends RefCounted
## EBBMERE's seabed: how high the sand stands at every point of the flats, as a small baked grid (the spec's
## `tide.field`: one byte per cell, elevation 0..1 as 0..255, base64). The water covers a point whenever
## the tide LEVEL (TideClock) is above its elevation, so ONE number per place says when it is wet, when it
## is dry and where the waterline is, with nothing simulated. Three readers share the grid:
##   * the CPU asks `elev_at` / `depth` (dig spots exposing, the companion sniffing, ripples under your feet);
##   * the tide shader samples the same grid as a texture (assets/eb_tide.gdshader), so the drawn water edge is
##     exactly where this says it is (`to_image`);
##   * the world generator walls the DEEP part (elevation under `deep_elev`: the open sea) with invisible
##     posts, so you stop at the drop-off you can see. Everything over that, however far the tide covers it, is
##     wadeable; no moving wall.
## Elevation is stored in 16 bits per cell (`bits`: 16, big-endian pairs; a field without it is the older one byte per
## cell): at one byte the gentle flats stair-stepped into square patches of the same value and the waterline
## followed the grid. The shader gets the grid as a half-float texture, so it is as fine as the CPU's.
## Sampling is bilinear on cell centres, the same as a linear-filtered texture, so CPU and GPU agree.
## Pure data: no nodes, no rendering.

var origin := Vector2.ZERO     # world position of the grid's top-left corner
var cell := 16.0               # world px per cell
var width := 0
var height := 0
var deep_elev := 0.26          # elevation under which the sea is too deep to wade
var _vals := PackedFloat32Array()   # width * height elevations, 0..1


static func from_spec(field: Dictionary, deep: float = 0.26) -> TideField:
	var f := TideField.new()
	f.deep_elev = deep
	if field.is_empty():
		return f
	f.origin = WorldData.to_vec2(field.get("origin", [0, 0]))
	f.cell = maxf(1.0, float(field.get("cell", 16.0)))
	f.width = int(field.get("w", 0))
	f.height = int(field.get("h", 0))
	var raw := Marshalls.base64_to_raw(String(field.get("data", "")))
	var bits := int(field.get("bits", 8))
	var n := f.width * f.height
	if (bits != 8 and bits != 16) or raw.size() != n * (bits / 8):
		f.width = 0
		f.height = 0
		return f
	f._vals.resize(n)
	if bits == 16:
		for i in n:
			f._vals[i] = float(raw[i * 2] * 256 + raw[i * 2 + 1]) / 65535.0
	else:
		for i in n:
			f._vals[i] = float(raw[i]) / 255.0
	return f


## A field built straight from bytes (tests).
static func from_bytes(origin_px: Vector2, cell_px: float, w: int, h: int, bytes: PackedByteArray, deep: float = 0.26) -> TideField:
	var f := TideField.new()
	f.origin = origin_px
	f.cell = cell_px
	f.width = w
	f.height = h
	f.deep_elev = deep
	f._vals.resize(bytes.size())
	for i in bytes.size():
		f._vals[i] = float(bytes[i]) / 255.0
	return f


func is_empty() -> bool:
	return width <= 0 or height <= 0


## The world rectangle the grid covers.
func rect() -> Rect2:
	return Rect2(origin, Vector2(width, height) * cell)


func _at(x: int, y: int) -> float:
	return _vals[clampi(y, 0, height - 1) * width + clampi(x, 0, width - 1)]


## Elevation at a world point, 0..1 (bilinear between cell centres; clamped at the grid's edge).
func elev_at(p: Vector2) -> float:
	if is_empty():
		return 1.0
	var fx := (p.x - origin.x) / cell - 0.5
	var fy := (p.y - origin.y) / cell - 0.5
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var top := lerpf(_at(x0, y0), _at(x0 + 1, y0), tx)
	var bottom := lerpf(_at(x0, y0 + 1), _at(x0 + 1, y0 + 1), tx)
	return lerpf(top, bottom, ty)


## How far under water a point is at `level` (negative = dry by that much).
func depth(p: Vector2, level: float) -> float:
	return level - elev_at(p)


## Open sea, too deep to wade (a fixed place, whatever the tide does).
func is_deep(p: Vector2) -> bool:
	return elev_at(p) < deep_elev


## Dry enough to show a dig spot's sign: the water is at least `margin` (elevation) below the sand there.
func is_exposed(p: Vector2, level: float, margin: float = 0.0) -> bool:
	return level < elev_at(p) - margin


## The part of the grid the water can ever reach (or wet): the rows down to the last one whose sand is under
## `level_max` + `margin` anywhere. Everything under that is always dry, so nothing needs drawing there.
func wet_extent(level_max: float, margin: float = 0.0) -> Rect2:
	if is_empty():
		return Rect2()
	var last := 0
	for j in height:
		for i in width:
			if _at(i, j) < level_max + margin:
				last = j
				break
	return Rect2(origin, Vector2(width, last + 1) * cell)


## The elevation grid as a one-channel half-float image, for the tide shader (filterable on every target).
func to_image() -> Image:
	var img := Image.create_from_data(width, height, false, Image.FORMAT_RF, _vals.to_byte_array())
	img.convert(Image.FORMAT_RH)
	return img


static func encode(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes)


## 16-bit big-endian encoding of elevations 0..1 (what the generator writes, with "bits": 16).
static func encode16(vals: Array) -> String:
	var b := PackedByteArray()
	b.resize(vals.size() * 2)
	for i in vals.size():
		var v := clampi(int(round(float(vals[i]) * 65535.0)), 0, 65535)
		b[i * 2] = v >> 8
		b[i * 2 + 1] = v & 0xFF
	return Marshalls.raw_to_base64(b)
