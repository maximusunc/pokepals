class_name FacetGround
extends Node2D
## Glintwold's ground: a field of flat triangles, each one clean colour picked by how it faces a slowly turning
## light (assets/gw_facet.gdshader over one quad). A world asks for it with a "ground" entity whose render is
## "facet"; WorldArt then puts this node under everything in place of its own floor, paths and water (as it
## does GridGround for Ohmstead).
##
## This node hands the shader its inputs: the ramps and sizes from the art direction, the light's angle (a pure
## function of the shared clock, FacetLight), the clock for the water's glints, the last few FOOTSTEPS (the
## facet underfoot flashes and settles: this world's footprints), the regions' tints, and a small MASK baked
## once per world:
##
##   R = paths  (1 on the centre line, 0.5 at the ribbon's edge)
##   G = water  (over 0.5 in a pond or the river, falling to 0 a shore's width inland)
##   B = where across its body of water a point lies, 0 at the north (far) bank .. 1 at the south
##
## The shader reads the mask at each triangle's centroid, so a path is a ribbon of whole sand triangles and a
## pond is a sharp-edged zig-zag. The drawn shore follows the same organic outline as pond collision.
##
## Cost: one quad; two uniform writes a frame (the clock and the light), plus the shared visitor material's
## light. The footstep list is rewritten only when someone takes a step. Pure presentation.

const MAX_PULSES := 12
const MAX_REGIONS := 12
const MARGIN := 1100.0      # how far past the bounds the quad reaches (the sky is ours too)
const MAX_MASK := 640       # the mask's longest side, in texels

var _rect := Rect2()
var _mat: ShaderMaterial
var _cfg: Dictionary = {}
var _time := 0.0
var _walkers: Callable
var _spacing := 22.0
var _pulses: Array[Vector4] = []
var _next := 0
var _last: Dictionary = {}     # instance_id -> the feet's last step position
var _angle := FacetLight.DEFAULT_START

# the mask bake's flat channels
var _mw := 0
var _mh := 0
var _ox := 0.0
var _oy := 0.0
var _upt := 6.0
var _r := PackedFloat32Array()
var _g := PackedFloat32Array()
var _b := PackedFloat32Array()


## True if the art direction asks for the faceted ground.
static func wanted(style: ArtStyle) -> bool:
	return String(style.entity("ground").get("render", "")) == "facet"


## shapes = {
##   paths: Array[PackedVector2Array]               (already curved, PathShape)
##   ponds: [{ center: Vector2, radius: float, seed: float }]
##   river: { rect: Rect2, top_seed: float, bot_seed: float } or {}
##   regions: [{ rect: Rect2, color: Color }], region_alpha: float
## }
func build(bounds: Rect2, style: ArtStyle, shapes: Dictionary) -> void:
	show_behind_parent = true
	_rect = bounds.grow(MARGIN)
	_cfg = style.entity("ground")
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/gw_facet.gdshader")
	for key in ["cell", "jitter", "relief", "hills", "hill_scale", "light_height", "contrast", "grain", "path_cut",
			"shore_cut", "water_relief", "lip_cut", "lip_dark", "band_wobble", "glint_share", "glint_period", "glint_alpha", "cliff",
			"sky_reach", "cloud_cell", "cloud_speed", "region_feather", "step_life", "step_amount", "ring_speed"]:
		if _cfg.has(key):
			_mat.set_shader_parameter(key, float(_cfg[key]))
	_mat.set_shader_parameter("jitter", clampf(float(_cfg.get("jitter", 0.3)), 0.0, 0.45))
	for key in ["cloud_color", "cloud_shade", "step_color"]:
		if _cfg.has(key):
			_mat.set_shader_parameter(key, WorldData.to_color(_cfg[key]))
	for slot in ["grass", "sand", "shore", "water", "stone", "sky"]:
		_set_ramp(slot, _cfg.get(slot, []))
	_mat.set_shader_parameter("bounds", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	_spacing = maxf(8.0, float(_cfg.get("step_spacing", 22.0)))
	_pulses.clear()
	for i in MAX_PULSES:
		_pulses.append(Vector4(0, 0, -1000.0, 0))
	_push_pulses()
	_set_regions(shapes.get("regions", []), float(shapes.get("region_alpha", 0.12)))
	var mask := _bake_mask(bounds, shapes)
	_mat.set_shader_parameter("mask", ImageTexture.create_from_image(mask))
	_mat.set_shader_parameter("mask_rect", Vector4(_ox, _oy, float(_mw) * _upt, float(_mh) * _upt))
	_turn_light()
	material = _mat
	queue_redraw()


## Whose footsteps flash: a Callable returning the actors present (the same one GlowTrail is handed).
func set_walkers(walkers: Callable) -> void:
	_walkers = walkers


## A step at `pos`, now: the facet under it flashes and a faint ring runs out.
func add_pulse(pos: Vector2) -> void:
	_pulses[_next] = Vector4(pos.x, pos.y, _time, 0.0)
	_next = (_next + 1) % MAX_PULSES
	_push_pulses()


## The light's angle right now (radians, toward the light, screen space). See FacetLight.
func light_angle() -> float:
	return _angle


## What the mask says at a world point: { path, water, band } (for tests and for anything that wants to match).
func mask_at(p: Vector2) -> Dictionary:
	if _r.is_empty():
		return { "path": 0.0, "water": 0.0, "band": 0.0 }
	var x := int((p.x - _ox) / _upt)
	var y := int((p.y - _oy) / _upt)
	if x < 0 or y < 0 or x >= _mw or y >= _mh:
		return { "path": 0.0, "water": 0.0, "band": 0.0 }
	var i := y * _mw + x
	return { "path": _r[i], "water": _g[i], "band": _b[i] }


func _set_ramp(slot: String, cols: Array) -> void:
	if cols.is_empty():
		return
	var out := PackedVector3Array()
	for c in cols.slice(0, 6):
		var col := WorldData.to_color(c)
		out.append(Vector3(col.r, col.g, col.b))
	var n := out.size()
	while out.size() < 6:
		out.append(out[n - 1])
	_mat.set_shader_parameter(slot, out)
	_mat.set_shader_parameter(slot + "_n", n)


func _set_regions(regions: Array, alpha: float) -> void:
	var rects: Array[Vector4] = []
	var tints: Array[Vector4] = []
	for r in regions:
		if rects.size() >= MAX_REGIONS:
			break
		var rr: Rect2 = r["rect"]
		var c: Color = r["color"]
		rects.append(Vector4(rr.position.x, rr.position.y, rr.size.x, rr.size.y))
		tints.append(Vector4(c.r, c.g, c.b, alpha))
	var n := rects.size()
	while rects.size() < MAX_REGIONS:
		rects.append(Vector4.ZERO)
		tints.append(Vector4.ZERO)
	_mat.set_shader_parameter("regions", rects)
	_mat.set_shader_parameter("region_tints", tints)
	_mat.set_shader_parameter("region_n", n)


func _push_pulses() -> void:
	if _mat != null:
		_mat.set_shader_parameter("pulses", _pulses)


func _turn_light() -> void:
	_angle = FacetLight.from_config(_cfg, _clock_ms())
	_mat.set_shader_parameter("light_angle", _angle)
	var actors := OtherworldLook.facet_material()
	if actors != null:
		actors.set_shader_parameter("light_angle", _angle)


## The shared clock (Net.server_unix_ms, so everyone sees the same light). Looked up by path, not by the
## autoload's name, so a --script run that compiles this before the autoloads exist still compiles it.
func _clock_ms() -> int:
	var net := get_node_or_null("/root/Net")
	if net != null and net.has_method("server_unix_ms"):
		return int(net.server_unix_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _process(delta: float) -> void:
	if _mat == null:
		return
	_time += delta
	_mat.set_shader_parameter("now", _time)
	_turn_light()
	if not _walkers.is_valid():
		return
	var seen := {}
	for w in _walkers.call():
		if not is_instance_valid(w):
			continue
		var n := w as Node2D
		if n == null or not n.is_visible_in_tree():
			continue
		var id := n.get_instance_id()
		seen[id] = true
		var feet := n.position + Vector2(0, 6)
		if not _last.has(id):
			_last[id] = feet
			continue
		var step: Vector2 = feet - _last[id]
		var len := step.length()
		if len < _spacing:
			continue
		_last[id] = feet
		if len > _spacing * 6.0:
			continue   # a world-hop arrival or a puppet's first packet, not a step
		add_pulse(feet)
	if _last.size() > seen.size():
		for id in _last.keys():
			if not seen.has(id):
				_last.erase(id)


func _draw() -> void:
	if _rect.has_area():
		draw_rect(_rect, Color.WHITE)


## ---- the mask ----------------------------------------------------------------------------------
## Baked once per world load, in plain loops over typed float arrays, then packed into one RGB8 image.

func _bake_mask(bounds: Rect2, shapes: Dictionary) -> Image:
	_upt = maxf(2.0, ceilf(maxf(bounds.size.x, bounds.size.y) / float(MAX_MASK)))
	_mw = maxi(1, int(ceilf(bounds.size.x / _upt)))
	_mh = maxi(1, int(ceilf(bounds.size.y / _upt)))
	_ox = bounds.position.x
	_oy = bounds.position.y
	# (packed arrays are values: each is sized in place, not through a loop variable)
	_r.resize(_mw * _mh)
	_g.resize(_mw * _mh)
	_b.resize(_mw * _mh)
	_r.fill(0.0)
	_g.fill(0.0)
	_b.fill(0.0)
	var path_r := float(_cfg.get("path_radius", 16.0))
	for pts in shapes.get("paths", []):
		_paint_path(pts, path_r)
	var shore := float(_cfg.get("shore_width", 22.0))
	var ponds: Array = shapes.get("ponds", [])
	var spans := _pond_spans(ponds)
	for i in ponds.size():
		_paint_pond(ponds[i], spans[i], shore)
	var river: Dictionary = shapes.get("river", {})
	if not river.is_empty():
		_paint_river(river, shore)
	var data := PackedByteArray()
	data.resize(_mw * _mh * 3)
	for i in _mw * _mh:
		data[i * 3] = int(_r[i] * 255.0)
		data[i * 3 + 1] = int(_g[i] * 255.0)
		data[i * 3 + 2] = int(_b[i] * 255.0)
	return Image.create_from_data(_mw, _mh, false, Image.FORMAT_RGB8, data)


## Each pond's north..south span for its bands. Ponds that overlap are one body of water, so they share one
## span (the whole lake holds one sky, with no seam where two ponds meet).
static func _pond_spans(ponds: Array) -> Array:
	var n := ponds.size()
	var group: Array[int] = []
	for i in n:
		group.append(i)
	for i in n:
		for j in range(i + 1, n):
			var a: Dictionary = ponds[i]
			var b: Dictionary = ponds[j]
			if (a["center"] as Vector2).distance_to(b["center"]) < (float(a["radius"]) + float(b["radius"])) * 1.15:
				var ga := group[i]
				var gb := group[j]
				for k in n:
					if group[k] == gb:
						group[k] = ga
	var lo := {}
	var hi := {}
	for i in n:
		var c: Vector2 = ponds[i]["center"]
		var r := float(ponds[i]["radius"]) * 1.15
		var g := group[i]
		lo[g] = minf(float(lo.get(g, INF)), c.y - r)
		hi[g] = maxf(float(hi.get(g, -INF)), c.y + r)
	var out: Array = []
	for i in n:
		out.append(Vector2(lo[group[i]], hi[group[i]]))
	return out


func _span(r: Rect2) -> Rect2i:
	var x0 := clampi(int(floorf((r.position.x - _ox) / _upt)), 0, _mw)
	var y0 := clampi(int(floorf((r.position.y - _oy) / _upt)), 0, _mh)
	var x1 := clampi(int(ceilf((r.end.x - _ox) / _upt)) + 1, 0, _mw)
	var y1 := clampi(int(ceilf((r.end.y - _oy) / _upt)) + 1, 0, _mh)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


func _paint_path(pts: PackedVector2Array, radius: float) -> void:
	var rr := radius * 2.0     # R falls from 1 on the line to 0.5 at `radius` to 0 at twice that
	var rr2 := rr * rr
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var abx := b.x - a.x
		var aby := b.y - a.y
		var l2 := maxf(abx * abx + aby * aby, 0.0001)
		var sp := _span(Rect2(a, Vector2.ZERO).expand(b).grow(rr))
		for y in range(sp.position.y, sp.end.y):
			var py := _oy + (float(y) + 0.5) * _upt
			var row := y * _mw
			for x in range(sp.position.x, sp.end.x):
				var px := _ox + (float(x) + 0.5) * _upt
				var t := clampf(((px - a.x) * abx + (py - a.y) * aby) / l2, 0.0, 1.0)
				var dx := px - (a.x + abx * t)
				var dy := py - (a.y + aby * t)
				var d2 := dx * dx + dy * dy
				if d2 < rr2:
					var v := 1.0 - sqrt(d2) / rr
					if v > _r[row + x]:
						_r[row + x] = v


func _paint_pond(pd: Dictionary, span: Vector2, shore: float) -> void:
	var c: Vector2 = pd["center"]
	var radius := float(pd["radius"])
	var seed := float(pd["seed"])
	var reach := radius * 1.25 + shore
	var height := maxf(1.0, span.y - span.x)
	var sp := _span(Rect2(c - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	for y in range(sp.position.y, sp.end.y):
		var py := _oy + (float(y) + 0.5) * _upt
		var oy := py - c.y
		var band := clampf((py - span.x) / height, 0.0, 1.0)
		var row := y * _mw
		for x in range(sp.position.x, sp.end.x):
			var ox := _ox + (float(x) + 0.5) * _upt - c.x
			var d := sqrt(ox * ox + oy * oy) - WorldArt.organic_radius(atan2(oy, ox), radius, seed)  # < 0 in the water
			if d < shore:
				var v := clampf(0.5 - d / (2.0 * shore), 0.0, 1.0)
				if v > _g[row + x]:
					_g[row + x] = v
				_b[row + x] = band


func _paint_river(river: Dictionary, shore: float) -> void:
	var rect: Rect2 = river["rect"]
	var top_seed := float(river["top_seed"])
	var bot_seed := float(river["bot_seed"])
	var sp := _span(rect.grow(shore + 12.0))
	for x in range(sp.position.x, sp.end.x):
		var px := _ox + (float(x) + 0.5) * _upt
		var top := rect.position.y + WorldArt.river_bank_offset(px, top_seed)
		var bot := rect.end.y + WorldArt.river_bank_offset(px, bot_seed)
		for y in range(sp.position.y, sp.end.y):
			var py := _oy + (float(y) + 0.5) * _upt
			var d := maxf(top - py, py - bot)
			if d < shore:
				var v := clampf(0.5 - d / (2.0 * shore), 0.0, 1.0)
				var i := y * _mw + x
				if v > _g[i]:
					_g[i] = v
				_b[i] = clampf((py - top) / maxf(1.0, bot - top), 0.0, 1.0)
