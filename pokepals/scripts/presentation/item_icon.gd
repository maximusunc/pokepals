class_name ItemIcon
## Little procedural pictures of items, for the hotbar, the use button and a catch popping up. Drawn with a
## CanvasItem's own draw calls, so there's no art to ship for them yet: a rod, a fish, a boot, a bit of
## sea-glass. `key` is the item's key from the server (Server.Fishing: "rod", "minnow", "old_boot", ...);
## `kind` is its category ("tool", "fish", "rare_fish", "material").

const INK := Color(0.16, 0.12, 0.10)


## Draw the icon for `key` centred at `c`, about `size` pixels across.
static func draw(ci: CanvasItem, key: String, kind: String, c: Vector2, size: float, tint := Color(0.8, 0.84, 0.88), alpha := 1.0) -> void:
	var s := size / 24.0
	if key == "rod":
		_draw_rod(ci, c, s, alpha)
	elif key == "old_boot":
		_draw_boot(ci, c, s, tint, alpha)
	elif key == "sea_glass":
		_draw_glass(ci, c, s, tint, alpha)
	elif kind == "fish" or kind == "rare_fish":
		draw_fish(ci, c, s * 1.1, tint, kind == "rare_fish", alpha)
	else:
		ci.draw_circle(c, 6.0 * s, Color(tint, alpha))


## A fishing rod laid corner to corner: a cane, a little reel, a line down to a hook.
static func _draw_rod(ci: CanvasItem, c: Vector2, s: float, alpha: float) -> void:
	var butt := c + Vector2(-8, 9) * s
	var tip := c + Vector2(9, -9) * s
	ci.draw_line(butt, tip, Color(0.46, 0.32, 0.18, alpha), 2.6 * s, true)
	ci.draw_line(butt, butt.lerp(tip, 0.28), Color(0.30, 0.20, 0.12, alpha), 3.2 * s, true)
	ci.draw_circle(butt.lerp(tip, 0.2) + Vector2(2, 2) * s, 2.4 * s, Color(0.72, 0.74, 0.78, alpha))
	ci.draw_line(tip, tip + Vector2(0, 12) * s, Color(0.94, 0.94, 0.90, 0.85 * alpha), 0.8 * s, true)
	ci.draw_arc(tip + Vector2(-1.6, 12) * s, 1.6 * s, 0.0, PI, 6, Color(0.80, 0.80, 0.84, alpha), 1.0 * s, true)


## A fish, side on, nose to the right. A rare one gets a soft glow and a sparkle.
static func draw_fish(ci: CanvasItem, c: Vector2, s: float, tint: Color, rare := false, alpha := 1.0) -> void:
	if rare:
		ci.draw_circle(c, 10.0 * s, Color(1.0, 0.95, 0.70, 0.22 * alpha))
	var body := PackedVector2Array()
	for k in 16:
		var a := TAU * float(k) / 16.0
		body.append(c + Vector2(cos(a) * 7.0, sin(a) * 3.6) * s)
	var tail := PackedVector2Array([c + Vector2(-5.5, 0) * s, c + Vector2(-10.5, -4.2) * s, c + Vector2(-10.5, 4.2) * s])
	ci.draw_colored_polygon(tail, Color(tint.darkened(0.15), alpha))
	ci.draw_colored_polygon(body, Color(tint, alpha))
	ci.draw_line(c + Vector2(-2, -3.2) * s, c + Vector2(2, -3.4) * s, Color(tint.lightened(0.3), alpha), 1.0 * s, true)
	ci.draw_circle(c + Vector2(4.2, -0.8) * s, 0.9 * s, Color(INK, alpha))
	if rare:
		var sp := c + Vector2(6, -6) * s
		ci.draw_line(sp + Vector2(-2.5, 0) * s, sp + Vector2(2.5, 0) * s, Color(1, 1, 0.9, alpha), 1.0 * s)
		ci.draw_line(sp + Vector2(0, -2.5) * s, sp + Vector2(0, 2.5) * s, Color(1, 1, 0.9, alpha), 1.0 * s)


static func _draw_boot(ci: CanvasItem, c: Vector2, s: float, tint: Color, alpha: float) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-5, -8) * s, c + Vector2(1, -8) * s, c + Vector2(1, 2) * s, c + Vector2(8, 3) * s,
		c + Vector2(8, 8) * s, c + Vector2(-5, 8) * s])
	ci.draw_colored_polygon(pts, Color(tint, alpha))
	ci.draw_line(c + Vector2(-5, 8) * s, c + Vector2(8, 8) * s, Color(tint.darkened(0.4), alpha), 1.6 * s)
	ci.draw_line(c + Vector2(-5, -6) * s, c + Vector2(1, -6) * s, Color(tint.lightened(0.2), alpha), 1.0 * s)


static func _draw_glass(ci: CanvasItem, c: Vector2, s: float, tint: Color, alpha: float) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-6, -2) * s, c + Vector2(-1, -7) * s, c + Vector2(6, -4) * s, c + Vector2(5, 4) * s,
		c + Vector2(-2, 6) * s])
	ci.draw_colored_polygon(pts, Color(tint, 0.85 * alpha))
	ci.draw_line(c + Vector2(-3, -3) * s, c + Vector2(1, -5) * s, Color(1, 1, 1, 0.7 * alpha), 1.2 * s)
