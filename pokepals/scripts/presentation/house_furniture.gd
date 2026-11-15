class_name HouseFurniture
extends Node2D
## One piece of furniture in YOUR HOUSE (home building; HouseView): a y-sorted node in the Scenery, feet at
## its position, so you walk in front of a chair below you and behind a table above. Drawn by hand in the
## game's oblique view (a top face, then the front face below it), `w` px wide. Shown only once the house is
## built, and only while you're inside (it fades in with the cutaway). Its collision is the house's
## `furniture_solids` (Solids), not here.
##
## Kinds: counter, stove, table, chair_n / chair_s / chair_e / chair_w, plant, lamp, fireplace (a crackling
## fire), bookshelf, armchair_e / armchair_w, coffee_table, couch, nightstand, bed, wardrobe.

var kind := ""
var w := 20.0
var house_view: HouseView
var animated := false

const WOOD := Color(0.56, 0.38, 0.24)
const WOOD_LIGHT := Color(0.70, 0.52, 0.34)
const INK := Color(0.20, 0.14, 0.10)

var _t := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	animated = kind in ["fireplace", "stove", "lamp"]
	set_process(animated)


func _process(delta: float) -> void:
	_t += delta


func _shadow(width: float, alpha := 0.18) -> void:
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, width * 0.55, Color(0, 0, 0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A box in the oblique view: front face `fh` tall at the feet, top face `td` deep above it.
func _box(x0: float, width: float, fh: float, td: float, top: Color, front: Color, lift := 0.0) -> void:
	draw_rect(Rect2(x0, -fh - lift, width, fh), front)
	draw_rect(Rect2(x0, -fh - td - lift, width, td), top)
	draw_rect(Rect2(x0, -fh - td - lift, width, 1.0), top.lightened(0.2))
	draw_rect(Rect2(x0, -fh - lift, width, 1.0), front.darkened(0.25))


func _draw() -> void:
	var hw := w * 0.5
	match kind:
		"counter":
			_shadow(w, 0.12)
			_box(-hw, w, 16.0, 7.0, Color(0.84, 0.80, 0.72), Color(0.62, 0.70, 0.66))
			var dx := -hw + 2.0
			while dx < hw - 10.0:   # cupboard doors with little knobs
				draw_rect(Rect2(dx, -14.0, 11.0, 12.0), Color(0.56, 0.64, 0.60))
				draw_rect(Rect2(dx + 8.0, -9.0, 1.0, 2.0), Color(0.86, 0.74, 0.40))
				dx += 13.0
			# the sink and its tap, a cutting board with bread, a bowl of fruit
			draw_rect(Rect2(-hw + 10.0, -22.0, 18.0, 5.0), Color(0.70, 0.74, 0.78))
			draw_rect(Rect2(-hw + 11.0, -21.0, 16.0, 3.0), Color(0.56, 0.64, 0.70))
			draw_line(Vector2(-hw + 19.0, -22.0), Vector2(-hw + 19.0, -27.0), Color(0.72, 0.72, 0.76), 1.5)
			draw_line(Vector2(-hw + 19.0, -27.0), Vector2(-hw + 22.0, -25.0), Color(0.72, 0.72, 0.76), 1.5)
			draw_rect(Rect2(-6.0, -22.0, 16.0, 4.0), Color(0.78, 0.60, 0.38))
			draw_circle(Vector2(1.0, -23.0), 3.0, Color(0.86, 0.66, 0.38))
			draw_circle(Vector2(hw - 14.0, -23.0), 4.0, Color(0.80, 0.80, 0.86))
			draw_circle(Vector2(hw - 16.0, -25.0), 2.0, Color(0.90, 0.30, 0.26))
			draw_circle(Vector2(hw - 12.0, -25.0), 2.0, Color(0.96, 0.78, 0.30))
			draw_circle(Vector2(hw - 14.0, -27.0), 2.0, Color(0.56, 0.74, 0.32))
		"stove":
			_shadow(w, 0.15)
			var iron := Color(0.24, 0.24, 0.26)
			_box(-hw, w, 18.0, 6.0, iron.lightened(0.12), iron)
			draw_rect(Rect2(-hw + 5.0, -15.0, w - 10.0, 10.0), iron.darkened(0.3))   # the oven door
			var glow := 0.6 + 0.4 * sin(_t * 5.0)
			draw_rect(Rect2(-hw + 8.0, -12.0, w - 16.0, 4.0), Color(1.0, 0.56, 0.22, 0.6 * glow))
			draw_rect(Rect2(-hw + 6.0, -17.0, w - 12.0, 1.0), Color(0.80, 0.70, 0.40))   # the brass rail
			# a pot with steam, and the stovepipe up the wall
			draw_rect(Rect2(-6.0, -30.0, 12.0, 7.0), Color(0.76, 0.46, 0.30))
			draw_rect(Rect2(-7.0, -31.0, 14.0, 2.0), Color(0.86, 0.56, 0.38))
			for k in 3:
				var ph := fposmod(_t * 0.6 + float(k) / 3.0, 1.0)
				draw_circle(Vector2(sin(ph * 6.0 + float(k)) * 2.0, -34.0 - ph * 14.0), 2.0 + ph * 2.0, Color(1, 1, 1, 0.35 * (1.0 - ph)))
			draw_rect(Rect2(hw - 8.0, -64.0 - 26.0, 4.0, 66.0), iron.lightened(0.05))
		"table":
			_shadow(w)
			var top := WOOD_LIGHT
			draw_rect(Rect2(-hw + 3.0, -12.0, 3.0, 12.0), WOOD.darkened(0.2))   # legs
			draw_rect(Rect2(hw - 6.0, -12.0, 3.0, 12.0), WOOD.darkened(0.2))
			draw_rect(Rect2(-hw, -26.0, w, 14.0), top)
			draw_rect(Rect2(-hw, -13.0, w, 3.0), WOOD)
			draw_rect(Rect2(-hw, -26.0, w, 1.0), top.lightened(0.2))
			draw_rect(Rect2(-8.0, -26.0, 16.0, 14.0), Color(0.94, 0.92, 0.86))   # a runner
			# a vase of flowers and two plates
			draw_rect(Rect2(-2.0, -27.0, 4.0, 6.0), Color(0.56, 0.70, 0.82))
			draw_circle(Vector2(-2.0, -30.0), 2.0, Color(0.96, 0.60, 0.60))
			draw_circle(Vector2(2.0, -31.0), 2.0, Color(0.98, 0.88, 0.48))
			draw_circle(Vector2(0.0, -33.0), 2.0, Color(0.80, 0.64, 0.92))
			draw_circle(Vector2(-hw + 9.0, -19.0), 3.5, Color(0.96, 0.96, 0.94))
			draw_circle(Vector2(hw - 9.0, -19.0), 3.5, Color(0.96, 0.96, 0.94))
		"chair_s", "chair_n", "chair_e", "chair_w":
			_shadow(14.0, 0.14)
			var seat := WOOD_LIGHT
			draw_rect(Rect2(-5.0, -7.0, 2.0, 7.0), WOOD.darkened(0.2))
			draw_rect(Rect2(3.0, -7.0, 2.0, 7.0), WOOD.darkened(0.2))
			if kind == "chair_s":
				draw_rect(Rect2(-6.0, -20.0, 12.0, 10.0), WOOD)                 # its back, behind the seat
				draw_rect(Rect2(-4.0, -18.0, 8.0, 2.0), WOOD_LIGHT)
				draw_rect(Rect2(-6.0, -11.0, 12.0, 5.0), seat)
				draw_rect(Rect2(-5.0, -11.0, 10.0, 3.0), Color(0.82, 0.40, 0.36))  # a cushion
			elif kind == "chair_n":
				draw_rect(Rect2(-6.0, -11.0, 12.0, 5.0), seat)
				draw_rect(Rect2(-6.0, -20.0, 12.0, 13.0), WOOD)                 # its back, toward you
				draw_rect(Rect2(-4.0, -18.0, 2.0, 9.0), WOOD_LIGHT)
				draw_rect(Rect2(2.0, -18.0, 2.0, 9.0), WOOD_LIGHT)
			else:
				var s := 1.0 if kind == "chair_e" else -1.0
				draw_rect(Rect2(-6.0, -11.0, 12.0, 5.0), seat)
				draw_rect(Rect2(-6.0 if s > 0.0 else 4.0, -22.0, 2.0, 16.0), WOOD)   # the back, on its far side
				draw_rect(Rect2(-5.0, -11.0, 10.0, 3.0), Color(0.82, 0.40, 0.36))
		"plant":
			_shadow(14.0, 0.14)
			draw_rect(Rect2(-5.0, -9.0, 10.0, 9.0), Color(0.74, 0.42, 0.30))
			draw_rect(Rect2(-6.0, -10.0, 12.0, 2.0), Color(0.82, 0.50, 0.36))
			for k in 6:
				var a := -PI * 0.5 + (float(k) - 2.5) * 0.42
				draw_line(Vector2(0, -10), Vector2(0, -10) + Vector2(cos(a), sin(a)) * 13.0, Color(0.34, 0.58, 0.32), 3.0)
			draw_circle(Vector2(0, -20), 4.0, Color(0.40, 0.66, 0.36))
		"lamp":
			_shadow(10.0, 0.12)
			var on := 0.85 + 0.15 * sin(_t * 1.3)
			SoftGlow.draw(self, Vector2(0, -2), 34.0, Color(1.0, 0.84, 0.52, 0.14 * on), 0.5)
			draw_rect(Rect2(-4.0, -2.0, 8.0, 2.0), Color(0.30, 0.26, 0.22))
			draw_rect(Rect2(-1.0, -32.0, 2.0, 30.0), Color(0.30, 0.26, 0.22))
			draw_colored_polygon(PackedVector2Array([Vector2(-8, -30), Vector2(8, -30), Vector2(5, -40), Vector2(-5, -40)]), Color(0.98, 0.86, 0.62))
			SoftGlow.draw(self, Vector2(0, -33), 12.0, Color(1.0, 0.90, 0.60, 0.4 * on), 0.6)
		"fireplace":
			_draw_fireplace()
		"bookshelf":
			_shadow(w, 0.14)
			var tall := 50.0
			draw_rect(Rect2(-hw, -tall, w, tall), WOOD)
			draw_rect(Rect2(-hw + 2.0, -tall + 2.0, w - 4.0, tall - 4.0), WOOD.darkened(0.35))
			var book_cols := [Color(0.72, 0.30, 0.28), Color(0.30, 0.46, 0.62), Color(0.86, 0.72, 0.36), Color(0.38, 0.56, 0.36), Color(0.56, 0.36, 0.56)]
			for shelf in 4:
				var sy := -tall + 2.0 + float(shelf + 1) * 11.5
				draw_rect(Rect2(-hw + 2.0, sy, w - 4.0, 2.0), WOOD)
				var bx := -hw + 3.0
				var k := shelf
				while bx < hw - 4.0:
					var bw := 2.0 + float((k * 7) % 3)
					var bh := 7.0 + float((k * 5) % 3)
					draw_rect(Rect2(bx, sy - bh, bw, bh), book_cols[k % book_cols.size()])
					bx += bw + 0.5
					k += 1
		"armchair_e", "armchair_w":
			_shadow(w)
			var s := 1.0 if kind == "armchair_e" else -1.0
			var fabric := Color(0.42, 0.56, 0.70) if s > 0.0 else Color(0.74, 0.54, 0.36)
			draw_rect(Rect2(-hw, -12.0, w, 12.0), fabric.darkened(0.15))          # the base
			draw_rect(Rect2(-hw, -16.0, w, 6.0), fabric)                         # the seat
			var bx := -hw if s > 0.0 else hw - 6.0
			draw_rect(Rect2(bx, -30.0, 6.0, 26.0), fabric.darkened(0.08))         # the back, on its far side
			draw_rect(Rect2(bx, -30.0, 6.0, 2.0), fabric.lightened(0.15))
			draw_rect(Rect2(-hw, -20.0, w, 4.0), fabric.lightened(0.1))           # the near armrest
			draw_rect(Rect2(-hw + 6.0, -15.0, 8.0, 4.0), Color(0.96, 0.90, 0.74)) # a cushion
		"coffee_table":
			_shadow(w, 0.12)
			draw_rect(Rect2(-hw + 2.0, -6.0, 2.0, 6.0), WOOD.darkened(0.2))
			draw_rect(Rect2(hw - 4.0, -6.0, 2.0, 6.0), WOOD.darkened(0.2))
			draw_rect(Rect2(-hw, -14.0, w, 9.0), WOOD_LIGHT)
			draw_rect(Rect2(-hw, -6.0, w, 2.0), WOOD)
			# a teapot and two cups
			draw_circle(Vector2(-3.0, -14.0), 3.5, Color(0.90, 0.92, 0.96))
			draw_rect(Rect2(0.0, -16.0, 3.0, 1.5), Color(0.90, 0.92, 0.96))
			draw_rect(Rect2(5.0, -13.0, 3.0, 3.0), Color(0.96, 0.84, 0.70))
			draw_rect(Rect2(-11.0, -11.0, 3.0, 3.0), Color(0.96, 0.84, 0.70))
		"couch":
			_shadow(w)
			var fabric := Color(0.48, 0.62, 0.44)
			draw_rect(Rect2(-hw + 6.0, -24.0, w - 12.0, 6.0), fabric.lightened(0.15))   # cushions, peeking over
			for k in 3:
				draw_rect(Rect2(-hw + 8.0 + float(k) * (w - 16.0) / 3.0, -25.0, (w - 16.0) / 3.0 - 1.0, 3.0), fabric.lightened(0.25))
			draw_rect(Rect2(-hw + 4.0, -20.0, w - 8.0, 20.0), fabric)                  # its back, toward you
			draw_rect(Rect2(-hw + 4.0, -20.0, w - 8.0, 2.0), fabric.lightened(0.12))
			draw_rect(Rect2(-hw, -18.0, 7.0, 18.0), fabric.darkened(0.12))              # the arms
			draw_rect(Rect2(hw - 7.0, -18.0, 7.0, 18.0), fabric.darkened(0.12))
			draw_rect(Rect2(-hw, -19.0, 7.0, 2.0), fabric.lightened(0.05))
			draw_rect(Rect2(hw - 7.0, -19.0, 7.0, 2.0), fabric.lightened(0.05))
			# a knitted throw over the back
			draw_rect(Rect2(hw * 0.2, -20.0, 18.0, 14.0), Color(0.92, 0.80, 0.54))
			for k in 4:
				draw_rect(Rect2(hw * 0.2 + float(k) * 4.0 + 1.0, -20.0, 2.0, 14.0), Color(0.86, 0.70, 0.44))
		"nightstand":
			_shadow(w, 0.12)
			_box(-hw, w, 12.0, 5.0, WOOD_LIGHT, WOOD)
			draw_rect(Rect2(-hw + 3.0, -10.0, w - 6.0, 4.0), WOOD.darkened(0.1))
			draw_rect(Rect2(-1.0, -9.0, 2.0, 1.0), Color(0.86, 0.74, 0.40))
			draw_rect(Rect2(-2.0, -22.0, 4.0, 5.0), Color(0.96, 0.94, 0.88))   # a candle
			draw_circle(Vector2(0, -24.0), 1.5, Color(1.0, 0.80, 0.40))
			SoftGlow.draw(self, Vector2(0, -24.0), 8.0, Color(1.0, 0.86, 0.50, 0.3), 0.6)
		"bed":
			_draw_bed()
		"wardrobe":
			_shadow(w, 0.14)
			var tall := 52.0
			draw_rect(Rect2(-hw, -tall, w, tall), WOOD)
			draw_rect(Rect2(-hw, -tall, w, 3.0), WOOD_LIGHT)
			draw_rect(Rect2(-hw + 2.0, -tall + 5.0, hw - 3.0, tall - 9.0), WOOD.lightened(0.08))
			draw_rect(Rect2(1.0, -tall + 5.0, hw - 3.0, tall - 9.0), WOOD.lightened(0.08))
			draw_rect(Rect2(-3.0, -tall * 0.5, 2.0, 3.0), Color(0.86, 0.74, 0.40))
			draw_rect(Rect2(1.0, -tall * 0.5, 2.0, 3.0), Color(0.86, 0.74, 0.40))
			draw_rect(Rect2(-hw, -3.0, w, 3.0), WOOD.darkened(0.25))


## The hearth: a stone chimney breast up the wall, a mantel, the firebox with its fire, and warm light.
func _draw_fireplace() -> void:
	var hw := w * 0.5
	var stone := Color(0.66, 0.62, 0.58)
	var wall_h := house_view.wall_h if house_view != null else 64.0
	var up := 20.0 + wall_h   # from the feet to the top of the back wall
	var flick := 0.8 + 0.2 * sin(_t * 9.0) * sin(_t * 5.3)
	SoftGlow.draw(self, Vector2(0, 2), 70.0, Color(1.0, 0.62, 0.30, 0.16 * flick), 0.4)
	# the chimney breast
	draw_rect(Rect2(-hw + 8.0, -up, w - 16.0, up - 20.0), stone.darkened(0.06))
	for k in int((up - 20.0) / 7.0):
		var y := -up + float(k) * 7.0
		draw_rect(Rect2(-hw + 8.0, y, w - 16.0, 1.0), stone.darkened(0.2))
		draw_rect(Rect2(-hw + 8.0 + (6.0 if k % 2 == 0 else 14.0), y, 1.0, 7.0), stone.darkened(0.2))
	# the hearth's body
	draw_rect(Rect2(-hw, -26.0, w, 26.0), stone)
	draw_rect(Rect2(-hw, -26.0, w, 2.0), stone.lightened(0.15))
	# the mantel, with candles and a little clock on it
	draw_rect(Rect2(-hw - 3.0, -31.0, w + 6.0, 5.0), Color(0.50, 0.34, 0.22))
	draw_rect(Rect2(-hw - 3.0, -31.0, w + 6.0, 1.0), Color(0.66, 0.48, 0.32))
	for cxp in [-hw + 5.0, hw - 7.0]:
		draw_rect(Rect2(cxp, -38.0, 2.0, 7.0), Color(0.96, 0.94, 0.88))
		draw_circle(Vector2(cxp + 1.0, -40.0), 1.5, Color(1.0, 0.80, 0.40, flick))
	# the firebox: dark, logs, and the fire
	var fb := Rect2(-hw + 8.0, -20.0, w - 16.0, 17.0)
	draw_rect(fb, Color(0.12, 0.08, 0.06))
	draw_rect(Rect2(fb.position.x + 2.0, -6.0, fb.size.x - 4.0, 3.0), Color(0.40, 0.26, 0.16))
	for k in 5:
		var fx := fb.position.x + 4.0 + float(k) * (fb.size.x - 8.0) / 4.0
		var fh := 6.0 + 5.0 * absf(sin(_t * (6.0 + float(k)) + float(k) * 1.7))
		draw_colored_polygon(PackedVector2Array([Vector2(fx - 3.0, -5.0), Vector2(fx + 3.0, -5.0), Vector2(fx, -5.0 - fh)]), Color(1.0, 0.56, 0.20))
		draw_colored_polygon(PackedVector2Array([Vector2(fx - 1.5, -5.0), Vector2(fx + 1.5, -5.0), Vector2(fx, -5.0 - fh * 0.6)]), Color(1.0, 0.88, 0.46))
	draw_rect(Rect2(-hw - 2.0, -3.0, w + 4.0, 3.0), stone.darkened(0.2))   # the hearthstone


## The bed: its headboard against the back wall, a quilt over it toward you, pillows at its head.
func _draw_bed() -> void:
	var hw := w * 0.5
	var length := 76.0
	draw_set_transform(Vector2(0, 0), 0.0, Vector2.ONE)
	draw_rect(Rect2(-hw + 2.0, -2.0, w, 4.0), Color(0, 0, 0, 0.14))
	# the headboard
	draw_rect(Rect2(-hw, -length - 18.0, w, 22.0), WOOD)
	draw_rect(Rect2(-hw, -length - 18.0, w, 3.0), WOOD_LIGHT)
	for k in 4:
		draw_rect(Rect2(-hw + 8.0 + float(k) * (w - 16.0) / 3.0 - 1.0, -length - 14.0, 2.0, 14.0), WOOD.darkened(0.2))
	# the mattress and the quilt
	draw_rect(Rect2(-hw, -length, w, length - 6.0), Color(0.96, 0.94, 0.90))
	var quilt := Color(0.88, 0.56, 0.48)
	var qtop := -length + 22.0
	draw_rect(Rect2(-hw, qtop, w, -qtop - 6.0), quilt)
	var y := qtop
	var row := 0
	while y < -8.0:
		var x := -hw + (0.0 if row % 2 == 0 else 8.0)
		while x < hw:
			draw_rect(Rect2(x, y, minf(8.0, hw - x), minf(8.0, -6.0 - y)), quilt.lightened(0.12))
			x += 16.0
		y += 8.0
		row += 1
	draw_rect(Rect2(-hw, qtop, w, 3.0), Color(0.98, 0.96, 0.92))       # the turned-down sheet
	# pillows
	draw_rect(Rect2(-hw + 5.0, -length + 4.0, hw - 8.0, 12.0), Color(1, 1, 1))
	draw_rect(Rect2(3.0, -length + 4.0, hw - 8.0, 12.0), Color(1, 1, 1))
	draw_rect(Rect2(-hw + 5.0, -length + 14.0, w - 10.0, 2.0), Color(0.86, 0.86, 0.88))
	# the foot of the bed, toward you
	draw_rect(Rect2(-hw, -8.0, w, 8.0), WOOD)
	draw_rect(Rect2(-hw, -8.0, w, 2.0), WOOD_LIGHT)
