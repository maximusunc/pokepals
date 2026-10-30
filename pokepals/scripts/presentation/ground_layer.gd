class_name GroundLayer
extends Node2D
## The pixel-art ground (assets/ground.gdshader over tiles from tools/gen_ground.py). One rect over
## the world's bounds; the shader does the per-pixel work. This node's job is to hand it the inputs:
## the terrain tiles, the colour ramps and patch knobs from the art direction (the "ground" entity,
## which a world's art block can override), and a small MASK it bakes once per world:
##
##   R = paths  — the curved trails (PathShape), 1 on the centre line fading to 0 past the edge
##   G = shores — 1 inside a pond / the river, fading to 0 a little way inland (the sandy band)
##   B = shade  — soft pools under every tree, great tree and prop
##
## The mask is coarse (a texel per 2–4 world units) and linearly filtered; the shader adds the
## dither and jitter that turn its soft values into ragged pixel edges. Sits behind WorldArt
## (show_behind_parent) so ponds, props and everything else draw on top of it. Pure presentation.

const MAX_MASK := 1024        # the mask's longest side, in texels
const PATH_RADIUS := 9.0      # half the packed-earth width, in world units
const PATH_FALLOFF := 1.9     # the mask fades to 0 at PATH_RADIUS * this (the worn-grass rim lives there)
const SHORE_BAND := 18.0      # how far inland the sand reaches

var _rect := Rect2()
var _mask: Image = null
var _mask_upt := 2.0
# The bake works in three flat float channels (fast typed-array access, no per-pixel Image calls),
# packed into the Image once at the end. Kept for path_value lookups.
var _mw := 0
var _mh := 0
var _ox := 0.0
var _oy := 0.0
var _r := PackedFloat32Array()
var _g := PackedFloat32Array()
var _b := PackedFloat32Array()


## True if the art direction asks for the pixel ground and its tiles are present.
static func wanted(style: ArtStyle) -> bool:
	var cfg := style.entity("ground")
	return String(cfg.get("render", "")) == "pixel" and texture(cfg, "terrain") != null


## One of the ground entity's images (its "terrain" tiles or "details" atlas), or null if it isn't there.
## (Not SpriteSlot.resolve: that only answers for render "sprite", and the ground's render is "pixel".)
static func texture(cfg: Dictionary, key: String) -> Texture2D:
	var path := String(cfg.get(key, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


## Build the mask + material. shapes = {
##   paths: Array[PackedVector2Array]            (already curved)
##   ponds: [{ center: Vector2, radius: float, seed: float }]   (WorldArt.organic_radius outlines)
##   river: { rect: Rect2, top_seed: float, bot_seed: float } or {}
##   shade: [{ pos: Vector2, r: float }]
## }
func build(bounds: Rect2, style: ArtStyle, shapes: Dictionary) -> void:
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect = bounds
	var cfg := style.entity("ground")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/ground.gdshader")
	var tex: Texture2D = texture(cfg, "terrain")
	mat.set_shader_parameter("terrain", tex)
	mat.set_shader_parameter("tile", float(cfg.get("tile", 128)))
	mat.set_shader_parameter("bounds", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	mat.set_shader_parameter("ramps", _ramps(cfg.get("ramps", {})))
	var acc := PackedVector3Array()
	for c in cfg.get("accents", [[0.95, 0.62, 0.72], [0.98, 0.92, 0.55], [0.95, 0.95, 0.92], [0.72, 0.64, 0.96]]):
		var col := WorldData.to_color(c)
		acc.append(Vector3(col.r, col.g, col.b))
	while acc.size() < 4:
		acc.append(acc[0] if not acc.is_empty() else Vector3.ONE)
	mat.set_shader_parameter("accents", acc)
	var patches: Dictionary = cfg.get("patches", {})
	for k in ["lush", "meadow", "dirt"]:
		var pc: Dictionary = patches.get(k, {})
		if not pc.is_empty():
			mat.set_shader_parameter(k, Vector2(float(pc.get("scale", 0.005)), float(pc.get("threshold", 0.7))))
	mat.set_shader_parameter("seed", fposmod(bounds.position.x * 0.37 + bounds.size.y * 0.11, 97.0))
	_mask = _bake_mask(bounds, shapes)
	mat.set_shader_parameter("mask", ImageTexture.create_from_image(_mask))
	material = mat
	queue_redraw()


## How "on a path" a world point is (the mask's R: 1 on a trail's centre line, 0 well clear of it), so
## WorldArt can keep litter off the trails and fray pebbles along their shoulders.
func path_value(p: Vector2) -> float:
	if _r.is_empty():
		return 0.0
	var x := int((p.x - _ox) / _mask_upt)
	var y := int((p.y - _oy) / _mask_upt)
	if x < 0 or y < 0 or x >= _mw or y >= _mh:
		return 0.0
	return _r[y * _mw + x]


func _draw() -> void:
	if _rect.has_area():
		draw_rect(_rect, Color.WHITE)


const SLOTS := ["grass", "lush", "meadow", "dirt", "sand", "path", "worn"]

## The 7 ramp slots x 4 shades, flattened for the shader. A missing slot borrows the grass ramp, so a
## partial override still draws.
static func _ramps(cfg: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var grass: Array = cfg.get("grass", [[0.28, 0.43, 0.26], [0.35, 0.51, 0.30], [0.39, 0.56, 0.32], [0.53, 0.68, 0.39]])
	for slot in SLOTS:
		var ramp: Array = cfg.get(slot, grass)
		for i in 4:
			var col := WorldData.to_color(ramp[mini(i, ramp.size() - 1)])
			out.append(Vector3(col.r, col.g, col.b))
	return out


## ---- the mask ----------------------------------------------------------------------------------
## Baked once per world load, so it's written for speed: plain loops over typed float arrays with the
## geometry inlined (no per-pixel function calls or Image reads), then one pack into an RGB8 image.

func _bake_mask(bounds: Rect2, shapes: Dictionary) -> Image:
	var upt := maxf(2.0, ceilf(maxf(bounds.size.x, bounds.size.y) / float(MAX_MASK)))  # world units per texel
	_mask_upt = upt
	_mw = maxi(1, int(ceilf(bounds.size.x / upt)))
	_mh = maxi(1, int(ceilf(bounds.size.y / upt)))
	_ox = bounds.position.x
	_oy = bounds.position.y
	_r = PackedFloat32Array()
	_g = PackedFloat32Array()
	_b = PackedFloat32Array()
	_r.resize(_mw * _mh)
	_g.resize(_mw * _mh)
	_b.resize(_mw * _mh)
	_r.fill(0.0)
	_g.fill(0.0)
	_b.fill(0.0)
	for pts in shapes.get("paths", []):
		_paint_path(pts)
	for pd in shapes.get("ponds", []):
		_paint_pond(pd)
	var river: Dictionary = shapes.get("river", {})
	if not river.is_empty():
		_paint_river(river)
	for s in shapes.get("shade", []):
		_paint_shade(s["pos"], float(s["r"]))
	var data := PackedByteArray()
	data.resize(_mw * _mh * 3)
	for i in _mw * _mh:
		data[i * 3] = int(_r[i] * 255.0)
		data[i * 3 + 1] = int(_g[i] * 255.0)
		data[i * 3 + 2] = int(_b[i] * 255.0)
	return Image.create_from_data(_mw, _mh, false, Image.FORMAT_RGB8, data)


## The texel range [x0, x1) x [y0, y1) covering a world rect, clamped to the mask.
func _span(r: Rect2) -> Rect2i:
	var x0 := clampi(int(floorf((r.position.x - _ox) / _mask_upt)), 0, _mw)
	var y0 := clampi(int(floorf((r.position.y - _oy) / _mask_upt)), 0, _mh)
	var x1 := clampi(int(ceilf((r.end.x - _ox) / _mask_upt)) + 1, 0, _mw)
	var y1 := clampi(int(ceilf((r.end.y - _oy) / _mask_upt)) + 1, 0, _mh)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


func _paint_path(pts: PackedVector2Array) -> void:
	var u := _mask_upt
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		# a slow swell and pinch in the trail's width, so it isn't a constant-width ribbon
		var rr := PATH_RADIUS * PATH_FALLOFF * (1.0 + 0.18 * sin(a.x * 0.019 + a.y * 0.013))
		var rr2 := rr * rr
		var abx := b.x - a.x
		var aby := b.y - a.y
		var l2 := maxf(abx * abx + aby * aby, 0.0001)
		var sp := _span(Rect2(a, Vector2.ZERO).expand(b).grow(rr))
		for y in range(sp.position.y, sp.end.y):
			var py := _oy + (float(y) + 0.5) * u
			var row := y * _mw
			for x in range(sp.position.x, sp.end.x):
				var px := _ox + (float(x) + 0.5) * u
				var t := clampf(((px - a.x) * abx + (py - a.y) * aby) / l2, 0.0, 1.0)
				var dx := px - (a.x + abx * t)
				var dy := py - (a.y + aby * t)
				var d2 := dx * dx + dy * dy
				if d2 < rr2:
					var v := 1.0 - sqrt(d2) / rr
					if v > _r[row + x]:
						_r[row + x] = v


func _paint_pond(pd: Dictionary) -> void:
	var c: Vector2 = pd["center"]
	var radius := float(pd["radius"])
	var seed := float(pd["seed"])
	var reach := radius * 1.25 + SHORE_BAND
	var u := _mask_upt
	var sp := _span(Rect2(c - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	for y in range(sp.position.y, sp.end.y):
		var oy := _oy + (float(y) + 0.5) * u - c.y
		var row := y * _mw
		for x in range(sp.position.x, sp.end.x):
			var ox := _ox + (float(x) + 0.5) * u - c.x
			var d := sqrt(ox * ox + oy * oy) - WorldArt.organic_radius(atan2(oy, ox), radius, seed)  # < 0 in the water
			if d < SHORE_BAND:
				var v := clampf(1.0 - d / SHORE_BAND, 0.0, 1.0)
				if v > _g[row + x]:
					_g[row + x] = v


func _paint_river(river: Dictionary) -> void:
	var rect: Rect2 = river["rect"]
	var top_seed := float(river["top_seed"])
	var bot_seed := float(river["bot_seed"])
	var u := _mask_upt
	var sp := _span(rect.grow(SHORE_BAND + 12.0))
	for x in range(sp.position.x, sp.end.x):
		var px := _ox + (float(x) + 0.5) * u
		if px < rect.position.x - SHORE_BAND or px > rect.end.x + SHORE_BAND:
			continue
		var top := rect.position.y + WorldArt.river_bank_offset(px, top_seed)
		var bot := rect.end.y + WorldArt.river_bank_offset(px, bot_seed)
		for y in range(sp.position.y, sp.end.y):
			var py := _oy + (float(y) + 0.5) * u
			var d := maxf(top - py, py - bot)  # < 0 between the banks
			if d < SHORE_BAND:
				var v := clampf(1.0 - d / SHORE_BAND, 0.0, 1.0)
				var i := y * _mw + x
				if v > _g[i]:
					_g[i] = v


## A soft pool of shade, nudged down-right of its source (the light comes from the upper-left).
func _paint_shade(pos: Vector2, r: float) -> void:
	var c := pos + Vector2(r * 0.18, r * 0.12)
	var u := _mask_upt
	var sp := _span(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
	for y in range(sp.position.y, sp.end.y):
		var qy := (_oy + (float(y) + 0.5) * u - c.y) * 1.6  # a flattened ellipse, like a cast shadow
		var row := y * _mw
		for x in range(sp.position.x, sp.end.x):
			var qx := _ox + (float(x) + 0.5) * u - c.x
			var d2 := (qx * qx + qy * qy) / (r * r)
			if d2 < 1.0:
				var v := 1.0 - d2
				if v > _b[row + x]:
					_b[row + x] = v
