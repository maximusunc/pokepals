class_name HudIcons
extends RefCounted
## The HUD's little line icons (menu, bag, call, pet, ...), drawn with a few strokes rather than
## from image files, so they stay crisp at any size and take the colour of whatever they sit on.
## Each is laid out on a 24x24 grid (the same grid the redesign mockups used) and scaled to `size`.
##
## Pure presentation: draw(ci, id, center, size, color) onto any CanvasItem, inside its _draw.
## An unknown id draws nothing.

const GRID := 24.0


## `bg` is the colour the icon sits on; the moon uses it to cut its crescent.
static func draw(ci: CanvasItem, id: String, c: Vector2, size: float, color: Color, weight := 2.0, bg := Color(0, 0, 0, 0)) -> void:
	var k := size / GRID
	var w := maxf(1.0, weight * k)
	var o := c - Vector2(12, 12) * k  # the grid's top-left on the canvas
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	match id:
		"menu":
			for y in [7.0, 12.0, 17.0]:
				ci.draw_line(P.call(5, y), P.call(19, y), color, w, true)
		"close":
			ci.draw_line(P.call(6, 6), P.call(18, 18), color, w, true)
			ci.draw_line(P.call(18, 6), P.call(6, 18), color, w, true)
		"chevron":
			_poly(ci, [P.call(9, 6), P.call(15, 12), P.call(9, 18)], color, w)
		"compass":
			ci.draw_arc(P.call(12, 12), 9.0 * k, 0.0, TAU, 32, color, w, true)
			_poly(ci, [P.call(15.5, 8.5), P.call(13.5, 13.5), P.call(8.5, 15.5), P.call(10.5, 10.5), P.call(15.5, 8.5)], color, w)
		"bag":
			# A satchel: a rounded body, the flap folding down to a clasp, and a handle on top.
			_poly(ci, [P.call(5, 10), P.call(5, 18.5), P.call(6.5, 20), P.call(17.5, 20), P.call(19, 18.5), P.call(19, 10), P.call(5, 10)], color, w)
			_poly(ci, [P.call(5, 10), P.call(12, 14.5), P.call(19, 10)], color, w)
			ci.draw_circle(P.call(12, 15.2), w * 0.9, color)
			ci.draw_arc(P.call(12, 10), 3.6 * k, PI, TAU, 12, color, w, true)
		"wardrobe":
			_poly(ci, [P.call(9, 4), P.call(4, 7), P.call(6, 11), P.call(8, 10), P.call(8, 20), P.call(16, 20),
				P.call(16, 10), P.call(18, 11), P.call(20, 7), P.call(15, 4)], color, w)
			ci.draw_arc(P.call(12, 4), 3.0 * k, 0.0, PI, 10, color, w, true)
		"journal":
			_poly(ci, [P.call(7, 3), P.call(18, 3), P.call(18, 21), P.call(7, 21), P.call(5, 19), P.call(5, 5), P.call(7, 3)], color, w)
			ci.draw_line(P.call(9, 8), P.call(15, 8), color, w, true)
			ci.draw_line(P.call(9, 11.5), P.call(14, 11.5), color, w, true)
		"friends":
			ci.draw_arc(P.call(9, 8), 3.0 * k, 0.0, TAU, 16, color, w, true)
			ci.draw_arc(P.call(9, 20), 6.0 * k, PI, TAU, 16, color, w, true)
			ci.draw_arc(P.call(17, 9), 2.5 * k, 0.0, TAU, 14, color, w, true)
			ci.draw_arc(P.call(16.5, 19.5), 4.5 * k, PI * 1.45, TAU, 12, color, w, true)
		"sound":
			_poly(ci, [P.call(4, 10), P.call(8, 10), P.call(13, 6), P.call(13, 18), P.call(8, 14), P.call(4, 14), P.call(4, 10)], color, w)
			ci.draw_arc(P.call(13, 12), 4.0 * k, -0.85, 0.85, 10, color, w, true)
			ci.draw_arc(P.call(13, 12), 7.5 * k, -0.85, 0.85, 14, color, w, true)
		"guide":
			ci.draw_arc(P.call(12, 12), 9.0 * k, 0.0, TAU, 32, color, w, true)
			ci.draw_arc(P.call(12, 9.5), 2.6 * k, PI, TAU + 0.9, 14, color, w, true)
			ci.draw_line(P.call(13.6, 11.6), P.call(12, 13.6), color, w, true)
			ci.draw_circle(P.call(12, 17), w * 0.75, color)
		"leave":
			_poly(ci, [P.call(13, 4), P.call(6, 4), P.call(6, 20), P.call(13, 20)], color, w)
			ci.draw_line(P.call(11, 12), P.call(20, 12), color, w, true)
			_poly(ci, [P.call(17, 9), P.call(20, 12), P.call(17, 15)], color, w)
		"return":
			# Home: a little house outline.
			_poly(ci, [P.call(4, 11), P.call(12, 4), P.call(20, 11)], color, w)
			_poly(ci, [P.call(6.5, 9.5), P.call(6.5, 20), P.call(17.5, 20), P.call(17.5, 9.5)], color, w)
			_poly(ci, [P.call(10.5, 20), P.call(10.5, 15), P.call(13.5, 15), P.call(13.5, 20)], color, w)
		"dev":
			# A wrench.
			ci.draw_arc(P.call(15, 9), 4.0 * k, PI * 0.95, PI * 2.55, 14, color, w, true)
			ci.draw_line(P.call(12.2, 11.8), P.call(5, 19), color, w * 1.2, true)
		"call":
			ci.draw_line(P.call(20, 12), P.call(6, 12), color, w, true)
			_poly(ci, [P.call(10, 7), P.call(5, 12), P.call(10, 17)], color, w)
		"pet":
			var pts := PackedVector2Array()
			for i in 32:
				var tt := TAU * float(i) / 32.0
				var x := 16.0 * pow(sin(tt), 3)
				var y := 13.0 * cos(tt) - 5.0 * cos(2.0 * tt) - 2.0 * cos(3.0 * tt) - cos(4.0 * tt)
				pts.append(P.call(12.0 + x * 0.55, 11.5 - y * 0.55))
			ci.draw_colored_polygon(pts, color)
		"look":
			# An eye: two shallow arcs make the almond, a ring the iris.
			ci.draw_arc(P.call(12, 20), 12.8 * k, PI * 1.215, PI * 1.785, 16, color, w, true)
			ci.draw_arc(P.call(12, 4), 12.8 * k, PI * 0.215, PI * 0.785, 16, color, w, true)
			ci.draw_circle(P.call(12, 12), 2.8 * k, color)
		"howl":
			# A crescent moon: a full disc with a second disc, in the colour behind it, taken out of it.
			ci.draw_circle(P.call(12, 12), 8.0 * k, color)
			if bg.a > 0.0:
				ci.draw_circle(P.call(15.5, 9.0), 6.6 * k, bg)
		"up":
			ci.draw_line(P.call(12, 20), P.call(12, 5), color, w, true)
			_poly(ci, [P.call(7, 10), P.call(12, 5), P.call(17, 10)], color, w)


static func _poly(ci: CanvasItem, pts: Array, color: Color, w: float) -> void:
	ci.draw_polyline(PackedVector2Array(pts), color, w, true)
