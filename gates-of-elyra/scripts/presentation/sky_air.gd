class_name SkyAir
extends Node2D
## What hangs in the air of a sky-island world, drawn ABOVE the scenery, the actors and everything else on the
## ground (a child of SkyLayer with a high z_index): the windmill's turning sails, kites on their long lines, and
## the PICTURE in the high clouds, which only shows when your companion has flown high enough to see it
## (SkyDirector feeds `set_picture`). Cheap by construction: a few dozen sprites and lines, each skipped when
## the camera cannot see it, and the picture draws nothing at all while it is invisible.

var _sky: Dictionary = {}
var _layer: SkyLayer = null
var _windmills: Array = []
var _kites: Array = []
var _puffs: Array = []
var _hi_tex: Array = []
var _picture := 0.0
var _picture_alpha := 0.95
var _time := 0.0
var _glow := 0.0                # a gentle brightening of the picture while the bird looks right at it


func _ready() -> void:
	z_index = 20
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func build(sky: Dictionary, layer: SkyLayer) -> void:
	_sky = sky
	_layer = layer
	_windmills = sky.get("windmills", [])
	_kites = sky.get("kites", [])
	var pic: Dictionary = sky.get("picture", {})
	_puffs = pic.get("puffs", [])
	_picture_alpha = float(pic.get("alpha", 0.95))
	_hi_tex.clear()
	for n in (sky.get("hiclouds", {}) as Dictionary).get("textures", []):
		var path := "res://assets/sprites/%s.png" % String(n)
		if ResourceLoader.exists(path):
			_hi_tex.append(ResourceLoader.load(path))
	queue_redraw()


## 0 .. 1: how much of the picture in the high clouds shows (SkyView.picture_at).
func set_picture(v: float) -> void:
	_picture = clampf(v, 0.0, 1.0)


func picture() -> float:
	return _picture


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var vis := ViewCull.visible_world_rect(self, 140.0)
	var cull := vis.has_area()
	for w in _windmills:
		_draw_sails(w, vis, cull)
	for k in _kites:
		_draw_kite(k, vis, cull)
	if _picture > 0.01 and not _hi_tex.is_empty():
		_draw_picture(vis, cull)


func _draw_sails(w: Dictionary, vis: Rect2, cull: bool) -> void:
	var hub := WorldData.to_vec2(w["hub"])
	var blade := float(w.get("blade", 54.0))
	if cull and not vis.grow(blade).has_point(hub):
		return
	var spin := _time * float(w.get("speed", 0.5)) * TAU * 0.35
	for i in 4:
		var ang := spin + float(i) * PI * 0.5
		var dir := Vector2(cos(ang), sin(ang))
		var side := dir.orthogonal()
		var inner := hub + dir * 7.0
		var outer := hub + dir * blade
		# the stock, then the lattice sail on its trailing side
		draw_line(hub, outer, Color(0.34, 0.24, 0.16), 2.0)
		var sail := PackedVector2Array([inner + side * 1.0, outer + side * 1.0, outer + side * 13.0, inner + side * 11.0])
		draw_colored_polygon(sail, Color(0.97, 0.94, 0.84, 0.96))
		draw_polyline(PackedVector2Array([inner + side * 1.0, outer + side * 1.0, outer + side * 13.0, inner + side * 11.0, inner + side * 1.0]), Color(0.36, 0.26, 0.18), 1.0)
		for k in 1:
			draw_line(hub + dir * (blade * 0.5) + side * 1.0, hub + dir * (blade * 0.5) + side * 12.0, Color(0.5, 0.4, 0.3, 0.8), 1.0)
	draw_circle(hub, 3.0, Color(0.30, 0.32, 0.38))
	draw_circle(hub + Vector2(-0.8, -0.8), 1.2, Color(0.7, 0.74, 0.82))


func _draw_kite(k: Dictionary, vis: Rect2, cull: bool) -> void:
	var anchor := WorldData.to_vec2(k["anchor"])
	var length := float(k.get("len", 160.0))
	var ph := float(k.get("phase", 0.0))
	var t := _time * 0.9 + ph
	# up and to the right, the way everything here leans, with the wind's swing and bob
	var tip := anchor + Vector2(length * (0.60 + 0.06 * sin(t * 0.7)), -length * (0.80 + 0.05 * sin(t * 0.9 + 1.0)))
	if cull and not vis.grow(60.0).intersects(Rect2(anchor, Vector2.ZERO).expand(tip).grow(30.0)):
		return
	var col := WorldData.to_color(k.get("color", [0.96, 0.36, 0.3]))
	var size := float(k.get("size", 14.0))
	# the line: a sagging curve down to the stake
	var pts := PackedVector2Array()
	for i in 9:
		var f := float(i) / 8.0
		var p := anchor.lerp(tip, f)
		p += Vector2(sin(t + f * 3.0) * 4.0 * f, 14.0 * sin(PI * f) * (1.0 - f))
		pts.append(p)
	draw_polyline(pts, Color(1, 1, 1, 0.55), 1.0, true)
	var tilt := 0.35 + 0.18 * sin(t * 1.3)
	var up := Vector2(sin(tilt), -cos(tilt))
	var right := up.orthogonal()
	var diamond := PackedVector2Array([tip + up * size * 1.25, tip + right * size * 0.8, tip - up * size * 0.95, tip - right * size * 0.8])
	draw_colored_polygon(diamond, col)
	var dark := PackedVector2Array([tip + up * size * 1.25, tip - up * size * 0.95, tip - right * size * 0.8])
	draw_colored_polygon(dark, col.darkened(0.22))
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), col.darkened(0.45), 1.0, true)
	draw_line(tip + up * size * 1.25, tip - up * size * 0.95, Color(1, 1, 1, 0.5), 1.0)
	draw_line(tip - right * size * 0.8, tip + right * size * 0.8, Color(1, 1, 1, 0.5), 1.0)
	# the tail: little bows on a wavy string
	var base := tip - up * size * 0.95
	var prev := base
	for i in 1 + int(size / 3.5):
		var f := float(i)
		var q := base + Vector2(sin(t * 1.6 - f * 0.9) * 6.0, f * 6.5)
		draw_line(prev, q, Color(1, 1, 1, 0.6), 1.0)
		draw_rect(Rect2(q + Vector2(-2.0, -1.0), Vector2(4.0, 2.0)), col.lightened(0.15 * f))
		prev = q


func _draw_picture(vis: Rect2, cull: bool) -> void:
	var a := _picture * _picture_alpha
	for p in _puffs:
		var pos := Vector2(float(p[0]), float(p[1]))
		var tex: Texture2D = _hi_tex[int(p[2]) % _hi_tex.size()]
		var sc := float(p[3]) * 1.35
		var size := tex.get_size() * sc
		var bob := Vector2(sin(_time * 0.5 + pos.x * 0.01) * 3.0, cos(_time * 0.4 + pos.y * 0.01) * 2.0)
		var r := Rect2(pos - size * 0.5 + bob, size)
		if cull and not vis.intersects(r):
			continue
		# a soft halo so the picture reads against any island or cloud beneath it
		SoftGlow.draw(self, pos + bob, size.x * 0.55, Color(1, 1, 1, 0.16 * a), 0.55)
		draw_texture_rect(tex, r, false, Color(1, 1, 1, a))
