class_name FindDraw
extends RefCounted
## The small things Thimblewick's companion brings back through the fence (a pebble, an acorn's cup, a feather,
## a glass bead, a button and, the one that matters, a silver thimble), drawn procedurally so the same figure can
## stand on the ground (WorldArt's `find_*` / `thimble` types) and ride over the companion's head while it is
## carried (FetchFx). Pure drawing: `ci` is any CanvasItem inside its own _draw, `p` the item's feet, `k` a
## scale (1 on the ground, smaller in a mouth), `t` the clock for the thimble's slow glint.

const PEBBLE := Color(0.64, 0.60, 0.56)
const THREAD := Color(0.82, 0.14, 0.18)


static func draw(ci: CanvasItem, kind: String, p: Vector2, k: float, t: float) -> void:
	match kind:
		"pebble": _pebble(ci, p, k)
		"acorn": _acorn(ci, p, k)
		"feather": _feather(ci, p, k)
		"bead": _bead(ci, p, k)
		"button": _button(ci, p, k)
		"thimble": _thimble(ci, p, k, t)
		_: _pebble(ci, p, k)


## An item standing in for itself on a spool of red cotton: the thimble's keepsake at home.
static func draw_kept_thimble(ci: CanvasItem, p: Vector2, t: float) -> void:
	var wood := Color(0.78, 0.60, 0.38)
	ci.draw_circle(p + Vector2(0, 5), 9.0, Color(0.20, 0.14, 0.08, 0.18), true, -1.0, true)
	ci.draw_rect(Rect2(p.x - 8.0, p.y - 1.0, 16.0, 3.0), wood.darkened(0.12))
	ci.draw_rect(Rect2(p.x - 6.0, p.y - 6.0, 12.0, 5.0), THREAD)
	for i in 3:
		ci.draw_line(Vector2(p.x - 6.0, p.y - 5.0 + float(i) * 1.6), Vector2(p.x + 6.0, p.y - 4.0 + float(i) * 1.6), THREAD.darkened(0.25), 1.0)
	ci.draw_rect(Rect2(p.x - 8.0, p.y - 8.0, 16.0, 2.5), wood)
	_thimble(ci, p + Vector2(0, -8.0), 0.8, t)


static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := float(i) / 20.0 * TAU
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)


static func _shadow(ci: CanvasItem, p: Vector2, rx: float, k: float) -> void:
	_ellipse(ci, p + Vector2(0, 1.5 * k), rx * k, 2.2 * k, Color(0.12, 0.08, 0.04, 0.22))


static func _pebble(ci: CanvasItem, p: Vector2, k: float) -> void:
	_shadow(ci, p, 9.5, k)
	_ellipse(ci, p + Vector2(0, -5.0 * k), 9.0 * k, 6.2 * k, PEBBLE.darkened(0.22))
	_ellipse(ci, p + Vector2(-0.6, -6.0) * k, 8.2 * k, 5.4 * k, PEBBLE)
	_ellipse(ci, p + Vector2(-2.6, -8.0) * k, 4.2 * k, 2.2 * k, PEBBLE.lightened(0.28))
	ci.draw_line(p + Vector2(1.5, -8.5) * k, p + Vector2(4.5, -4.0) * k, PEBBLE.darkened(0.35), 1.0)
	ci.draw_circle(p + Vector2(-4.0, -5.0) * k, 0.7, PEBBLE.darkened(0.3))


static func _acorn(ci: CanvasItem, p: Vector2, k: float) -> void:
	var cup := Color(0.70, 0.48, 0.22)
	_shadow(ci, p, 9.0, k)
	_ellipse(ci, p + Vector2(0, -4.0 * k), 8.6 * k, 5.6 * k, cup.darkened(0.3))
	_ellipse(ci, p + Vector2(0, -5.6 * k), 8.6 * k, 4.6 * k, Color(0.22, 0.12, 0.06))              # the hollow
	_ellipse(ci, p + Vector2(0, -3.4 * k), 8.2 * k, 3.6 * k, cup)                                    # the near rim
	for i in range(-3, 4):
		ci.draw_line(p + Vector2(float(i) * 2.2, -1.2) * k, p + Vector2(float(i) * 2.0, -5.0) * k, cup.darkened(0.25), 1.0)
	ci.draw_line(p + Vector2(-6.0, -4.6) * k, p + Vector2(-2.0, -5.4) * k, cup.lightened(0.3), 1.0)


static func _feather(ci: CanvasItem, p: Vector2, k: float) -> void:
	var vane := Color(0.84, 0.84, 0.88)
	_shadow(ci, p + Vector2(0, 0), 13.0, k)
	var a := p + Vector2(-13.0, -2.0) * k
	var b := p + Vector2(13.0, -8.0) * k
	var mid := (a + b) * 0.5 + Vector2(0, -3.0) * k
	var pts := PackedVector2Array([a, mid + Vector2(0, -5.0) * k, b, mid + Vector2(0, 4.0) * k])
	ci.draw_colored_polygon(pts, vane)
	ci.draw_polyline(PackedVector2Array([a, mid, b]), Color(0.52, 0.52, 0.58), 1.4 * k, true)
	for i in 5:
		var u := 0.18 + float(i) * 0.16
		var q := a.lerp(b, u) + Vector2(0, -3.0 * sin(u * PI)) * k
		ci.draw_line(q, q + Vector2(1.5, -4.5) * k, vane.darkened(0.2), 1.0)
		ci.draw_line(q, q + Vector2(1.5, 3.5) * k, vane.darkened(0.2), 1.0)
	ci.draw_line(a + Vector2(-3.0, 1.0) * k, a, Color(0.92, 0.9, 0.84), 1.2 * k)


static func _bead(ci: CanvasItem, p: Vector2, k: float) -> void:
	var blue := Color(0.34, 0.58, 0.92)
	_shadow(ci, p, 8.0, k)
	ci.draw_circle(p + Vector2(0, -6.4 * k), 7.2 * k, blue.darkened(0.3), true, -1.0, true)
	ci.draw_circle(p + Vector2(0, -6.6 * k), 6.4 * k, blue, true, -1.0, true)
	ci.draw_circle(p + Vector2(1.2, -5.4) * k, 3.4 * k, Color(0.16, 0.30, 0.62), true, -1.0, true)   # the hole's shade
	ci.draw_circle(p + Vector2(0, -6.4 * k), 2.0 * k, Color(0.1, 0.16, 0.36), true, -1.0, true)       # the hole
	ci.draw_circle(p + Vector2(-2.8, -9.2) * k, 1.6 * k, Color(1, 1, 1, 0.9))
	ci.draw_circle(p + Vector2(-0.8, -3.0) * k, 0.8 * k, Color(0.8, 0.92, 1.0, 0.7))


static func _button(ci: CanvasItem, p: Vector2, k: float) -> void:
	var pearl := Color(0.94, 0.89, 0.84)
	_shadow(ci, p, 10.0, k)
	_ellipse(ci, p + Vector2(0, -3.4 * k), 9.4 * k, 6.4 * k, pearl.darkened(0.28))
	_ellipse(ci, p + Vector2(0, -5.0 * k), 9.4 * k, 6.4 * k, pearl)
	_ellipse(ci, p + Vector2(0, -5.0 * k), 6.8 * k, 4.4 * k, pearl.darkened(0.06))
	var holes := [Vector2(-2.6, -6.2), Vector2(2.6, -6.2), Vector2(-2.6, -3.8), Vector2(2.6, -3.8)]
	ci.draw_line(p + (holes[0] as Vector2) * k, p + (holes[3] as Vector2) * k, THREAD, 1.2 * k)
	ci.draw_line(p + (holes[1] as Vector2) * k, p + (holes[2] as Vector2) * k, THREAD, 1.2 * k)
	for h in holes:
		ci.draw_circle(p + (h as Vector2) * k, 1.0 * k, Color(0.16, 0.12, 0.12))
	ci.draw_arc(p + Vector2(-1.0, -6.0) * k, 7.0 * k, PI * 1.1, PI * 1.45, 6, Color(1, 1, 1, 0.8), 1.0, true)


static func _thimble(ci: CanvasItem, p: Vector2, k: float, t: float) -> void:
	var silver := Color(0.80, 0.84, 0.90)
	_shadow(ci, p, 9.0, k)
	# the body: a little taller than wide, flaring slightly at the brim, a rounded crown
	var body := PackedVector2Array([
		p + Vector2(-7.4, 0.0) * k, p + Vector2(-6.2, -11.0) * k, p + Vector2(-3.6, -15.2) * k, p + Vector2(3.6, -15.2) * k,
		p + Vector2(6.2, -11.0) * k, p + Vector2(7.4, 0.0) * k,
	])
	ci.draw_colored_polygon(body, silver.darkened(0.22))
	var lit := PackedVector2Array([
		p + Vector2(-7.4, 0.0) * k, p + Vector2(-6.2, -11.0) * k, p + Vector2(-3.6, -15.2) * k, p + Vector2(0.4, -15.2) * k,
		p + Vector2(-0.6, -0.5) * k,
	])
	ci.draw_colored_polygon(lit, silver)
	_ellipse(ci, p + Vector2(0, -15.2 * k), 3.8 * k, 1.7 * k, silver.lightened(0.22))   # the crown
	# the dimples, in rows
	for row in 3:
		var y := -4.0 - float(row) * 4.0
		var half := 6.4 - float(row) * 0.9
		for i in 4:
			var x := -half + (float(i) + 0.5 + (0.5 if row % 2 == 1 else 0.0)) * (half * 2.0 / 4.0)
			if absf(x) <= half:
				ci.draw_circle(p + Vector2(x, y) * k, 0.8 * k, silver.darkened(0.36))
	# the rim, worn bright
	ci.draw_rect(Rect2(p.x - 7.6 * k, p.y - 2.2 * k, 15.2 * k, 2.2 * k), silver.lightened(0.12))
	ci.draw_line(p + Vector2(-7.6, -2.2) * k, p + Vector2(7.6, -2.2) * k, Color(1, 1, 1, 0.75), 1.0)
	ci.draw_line(p + Vector2(-7.6, 0.0) * k, p + Vector2(7.6, 0.0) * k, silver.darkened(0.4), 1.0)
	# a slow glint travelling up the left of it, so it catches the eye
	var g := fposmod(t * 0.45, 1.6)
	if g < 1.0:
		ci.draw_circle(p + Vector2(-4.6 + g * 1.6, -2.0 - g * 12.0) * k, 1.2 * k, Color(1, 1, 1, 0.9 * (1.0 - g)))
