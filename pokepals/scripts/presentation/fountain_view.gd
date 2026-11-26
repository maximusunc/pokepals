class_name FountainView
extends Node2D
## Lingerlong's wishing fountain: one y-sorted node in the Scenery layer at the middle of the basin, so you walk
## behind it on its far side and in front of it on its near side. It draws, back to front, the basin (smooth @2x
## art), soft rings on the basin's water, the upper bowls and stem, and then the moving water: a plume from the
## spout and the overflow falling from each bowl's rim into the one below, droplets running down every arc.
##
## Its art and its water's shape come from the art direction's "fountain" entity:
##   base, top          the basin, and the bowls + stem (drawn over it); both share the foot line
##   foot, top_foot     world px from each image's bottom edge up to its foot line (the baked floor reflection)
##   front              how far in front of the basin's middle its foot line is (the node sits at the middle)
##   water              the water's colour      jet_height   how high the plume rises over the spout
##   spout_y            the spout, in px above the foot line
##   bowls              [{ y, r }]: each bowl's rim height above the foot line and its half-width, top bowl last
##   basin              { y, rx, ry }: the basin's water, its middle's height above the foot line and its radii
## The basin's collision is the spec's (a fence capsule), and its words are a prop's; this only draws.
##
## Cost: a dozen polylines and dots a frame, and only while it is on screen (it hides itself otherwise).
## `swell(amount)` makes the jets rise for a moment (a wish tossed in).

const ARCS := 6
const DROPS := 3

var _base: Texture2D = null
var _top: Texture2D = null
var _foot := 13.0
var _top_foot := 21.0
var _front := 30.0
var _water := Color(0.78, 0.94, 0.98)
var _jet := 46.0
var _spout_y := 112.0
var _bowls: Array = []
var _basin := { "y": 26.0, "rx": 72.0, "ry": 22.0 }
var _time := 0.0
var _swell := 0.0


func setup(center: Vector2, style: ArtStyle) -> void:
	position = center
	name = "Fountain"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var cfg := style.entity("fountain")
	_base = _tex(String(cfg.get("base", "")))
	_top = _tex(String(cfg.get("top", "")))
	_foot = float(cfg.get("foot", _foot))
	_top_foot = float(cfg.get("top_foot", _top_foot))
	_front = float(cfg.get("front", _front))
	if cfg.has("water"):
		_water = WorldData.to_color(cfg["water"])
	_jet = float(cfg.get("jet_height", _jet))
	_spout_y = absf(float(cfg.get("spout_y", -_spout_y)))
	_bowls = cfg.get("bowls", [{ "y": 58.0, "r": 40.0 }, { "y": 94.0, "r": 20.0 }])
	var b: Dictionary = cfg.get("basin", {})
	for k in ["y", "rx", "ry"]:
		if b.has(k):
			_basin[k] = float(b[k])


static func _tex(path: String) -> Texture2D:
	return load(path) if path != "" and ResourceLoader.exists(path) else null


## The jets rise for a moment, by `amount` (about 1 for one wish; several in a row add up, to a limit).
func swell(amount := 1.0) -> void:
	_swell = clampf(_swell + amount, 0.0, 2.5)


func swelling() -> float:
	return _swell


func _process(delta: float) -> void:
	_time += delta
	if _swell > 0.0:
		_swell = maxf(0.0, _swell - delta * 0.6)
	var vis := ViewCull.visible_world_rect(self, 160.0)
	var on := not vis.has_area() or vis.has_point(position)
	if on != visible:
		visible = on
	if on:
		queue_redraw()


func _draw() -> void:
	var fy := _front   # the foot line, in this node's space
	if _base != null:
		var sz := _base.get_size() * 0.5
		draw_texture_rect(_base, Rect2(Vector2(-sz.x * 0.5, fy + _foot - sz.y), sz), false)
	else:
		_draw_plain_basin(fy)
	_draw_basin_rings(fy)
	if _top != null:
		var tz := _top.get_size() * 0.5
		draw_texture_rect(_top, Rect2(Vector2(-tz.x * 0.5, fy + _top_foot - tz.y), tz), false)
	else:
		_draw_plain_bowls(fy)
	_draw_water(fy)


func _draw_basin_rings(fy: float) -> void:
	var c := Vector2(0, fy - float(_basin["y"]))
	var rx := float(_basin["rx"])
	var ry := float(_basin["ry"])
	for i in 3:
		var k := fposmod(_time * 0.32 + float(i) / 3.0, 1.0)
		var a := (1.0 - k) * 0.38
		draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
		draw_arc(Vector2.ZERO, rx * (0.35 + 0.55 * k), 0.0, TAU, 40, Color(1, 1, 1, a), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_water(fy: float) -> void:
	var lift := 1.0 + _swell * 0.7
	var spout := Vector2(0, fy - _spout_y)
	var col := Color(_water.r, _water.g, _water.b, 0.78)
	var bright := Color(1, 1, 1, 0.85)
	# the plume: up from the spout and back down into the top bowl, a soft column with droplets
	var h := _jet * lift
	var top := spout - Vector2(0, h)
	draw_line(spout, top, Color(col.r, col.g, col.b, 0.42), 4.0, true)
	draw_line(spout, top + Vector2(0, 4), bright, 1.2, true)
	for k in DROPS * 2:
		var t := fposmod(_time * 0.9 + float(k) / float(DROPS * 2), 1.0)
		var side := -1.0 if k % 2 == 0 else 1.0
		var p := top + Vector2(side * (2.0 + 14.0 * t), h * 0.15 * t + (h * 0.85 + 6.0) * t * t)
		draw_circle(p, 1.3, Color(1, 1, 1, 0.8 * (1.0 - t)), true, -1.0, true)
	# each bowl overflows into the one below it (the bottom bowl into the basin), in arcs round its rim
	var levels: Array = []
	for b in _bowls:
		levels.append({ "y": float(b["y"]), "r": float(b["r"]) })
	levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["y"] > b["y"])   # top bowl first
	for li in levels.size():
		var from: Dictionary = levels[li]
		var into_y := float(levels[li + 1]["y"]) if li + 1 < levels.size() else float(_basin["y"]) - 4.0
		var into_r := float(levels[li + 1]["r"]) if li + 1 < levels.size() else float(_basin["rx"]) * 0.7
		_draw_overflow(fy, float(from["y"]), float(from["r"]), into_y, into_r, lift, col, bright)


## A ring of ARCS arcs from a rim (height `y_from`, half-width `r_from`) falling into the level below.
func _draw_overflow(fy: float, y_from: float, r_from: float, y_to: float, r_to: float, lift: float, col: Color, bright: Color) -> void:
	var drop := (y_from - y_to)
	for i in ARCS:
		var ang := (float(i) + 0.5) / float(ARCS) * PI   # the front half of the rim (the back is hidden by the bowl)
		var dx := cos(ang)
		var start := Vector2(dx * r_from, fy - y_from + sin(ang) * r_from * 0.28)
		var reach := maxf(r_to * 0.9, r_from + 6.0) * (0.92 + 0.08 * lift)
		var end := Vector2(dx * reach, fy - y_to + sin(ang) * minf(r_to, reach) * 0.28)
		var pts := PackedVector2Array()
		for s in 7:
			var t := float(s) / 6.0
			var p := start.lerp(end, t)
			p.y = lerpf(start.y, end.y, t * t) - sin(t * PI) * 5.0 * lift
			pts.append(p)
		draw_polyline(pts, col, 1.6, true)
		var t2 := fposmod(_time * 0.8 + float(i) * 0.37, 1.0)
		var dp := start.lerp(end, t2)
		dp.y = lerpf(start.y, end.y, t2 * t2) - sin(t2 * PI) * 5.0 * lift
		draw_circle(dp, 1.1, bright, true, -1.0, true)
		if drop > 0.0:
			var sp := fposmod(_time * 1.6 + float(i) * 0.53, 1.0)
			draw_arc(end, 1.5 + 4.0 * sp, PI, TAU, 8, Color(1, 1, 1, 0.5 * (1.0 - sp)), 1.0, true)


func _draw_plain_basin(fy: float) -> void:
	var c := Vector2(0, fy - float(_basin["y"]))
	var rx := float(_basin["rx"]) + 10.0
	var ry := float(_basin["ry"]) + 6.0
	draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
	draw_circle(Vector2.ZERO, rx, Color(0.965, 0.937, 0.902))
	draw_circle(Vector2.ZERO, rx - 8.0, _water)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_plain_bowls(fy: float) -> void:
	draw_rect(Rect2(-5, fy - _spout_y, 10, _spout_y - float(_basin["y"])), Color(0.965, 0.937, 0.902))
	for b in _bowls:
		var r := float(b["r"])
		draw_set_transform(Vector2(0, fy - float(b["y"])), 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, r, Color(0.965, 0.937, 0.902))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
