class_name EmoteGlyphs
extends RefCounted
## Tiny procedural emote glyphs drawn in the same flat-vector language as the actors —
## no font assets, no sprite sheets, no locale dependency. These are the rare, earned
## little symbols that float up over the companion at a meaningful beat (a deepening bond),
## the diegetic way the player reads "something just happened between us."
##
## Pure presentation: handed a canvas, a kind, a position and a fade/scale, it draws. It
## decides nothing about WHEN to appear — CompanionView spawns and animates them.

const HEART_COLOR := Color(0.95, 0.45, 0.57)
const SPARKLE_COLOR := Color(1.0, 0.93, 0.62)
const ALERT_COLOR := Color(1.0, 0.85, 0.35)


## Draw one glyph centered at `pos` (in the canvas item's local space), faded by `alpha`
## (0..1) and sized by `scale` (1.0 = base). Unknown kinds draw nothing.
static func draw(ci: CanvasItem, kind: String, pos: Vector2, alpha: float, scale: float) -> void:
	match kind:
		"love":
			_draw_heart(ci, pos, scale, Color(HEART_COLOR.r, HEART_COLOR.g, HEART_COLOR.b, alpha))
		"delight":
			_draw_sparkle(ci, pos, scale, Color(SPARKLE_COLOR.r, SPARKLE_COLOR.g, SPARKLE_COLOR.b, alpha))
		"alert":
			_draw_exclamation(ci, pos, scale, Color(ALERT_COLOR.r, ALERT_COLOR.g, ALERT_COLOR.b, alpha))


# A heart from two lobe circles over a downward triangle — reads clearly even at a few px.
static func _draw_heart(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var r := 2.4 * s
	ci.draw_circle(c + Vector2(-r * 0.62, -r * 0.30), r, col)
	ci.draw_circle(c + Vector2(r * 0.62, -r * 0.30), r, col)
	var pts := PackedVector2Array([
		c + Vector2(-r * 1.5, 0.0),
		c + Vector2(r * 1.5, 0.0),
		c + Vector2(0.0, r * 1.95),
	])
	ci.draw_colored_polygon(pts, col)


# A four-point sparkle from two crossed slim diamonds (kept for the optional "delight" beat).
static func _draw_sparkle(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var r := 3.0 * s
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0.0, -r), c + Vector2(r * 0.28, 0.0), c + Vector2(0.0, r), c + Vector2(-r * 0.28, 0.0),
	]), col)
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r, 0.0), c + Vector2(0.0, r * 0.28), c + Vector2(r, 0.0), c + Vector2(0.0, -r * 0.28),
	]), col)


# An exclamation mark — a tapered upright bar over a round dot — the unmistakable "I'm onto
# something!" tell that floats over the companion while it points at a hidden salamander. The bar
# is slightly wider at the top so it reads as a "!" and not just a dash even at a few pixels.
static func _draw_exclamation(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var h := 5.2 * s   # bar height
	var w := 1.5 * s   # bar half-width at the top
	var top := c + Vector2(0.0, -h)
	ci.draw_colored_polygon(PackedVector2Array([
		top + Vector2(-w, 0.0), top + Vector2(w, 0.0),
		c + Vector2(w * 0.45, 0.0), c + Vector2(-w * 0.45, 0.0),
	]), col)
	ci.draw_circle(c + Vector2(0.0, 1.7 * s), 1.25 * s, col)
