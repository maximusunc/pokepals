class_name OffcutDraw
extends RefCounted
## THE OFFCUT (Glintwold's secret): the last face of the Unfinished, the one that had to come away so the rest
## could close. A small chip of pale rose stone with one face cut perfectly flat, that catches the light from
## every side at once. Drawn in one place so the same figure lies on the Turning Floor (WorldArt's `offcut`),
## drops out of the stone as it closes (HeartstoneView), stands at home on a little stand (`kept_offcut`) and
## shows in the bag and the curio cabinet (ItemIcon). Uses assets/gw_offcut@2x.png when it exists (half size,
## linear filtering), else a flat-shaded chip of its own. `ci` is any CanvasItem inside its own _draw, `p` the
## chip's feet, `k` a scale, `t` a clock for the slow glint.

const ART := "res://assets/gw_offcut@2x.png"
const KEPT_ART := "res://assets/gw_offcut_kept@2x.png"
const FACES := [Color(1.0, 0.914, 0.933), Color(0.980, 0.816, 0.863), Color(0.914, 0.663, 0.753), Color(0.718, 0.478, 0.620)]
const SHADOW := Color(0.227, 0.290, 0.420, 0.18)

static var _tex_cache := {}


static func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


## The chip lying on the ground (or in the air, falling), with a slow glint running over its flat face.
static func draw_chip(ci: CanvasItem, p: Vector2, k: float, t: float) -> void:
	var tex := _tex(ART)
	if tex != null:
		var sz := tex.get_size() * 0.5 * k
		ci.draw_texture_rect(tex, Rect2(p + Vector2(-sz.x * 0.5, -sz.y + 2.0 * k), sz), false)
		_glint(ci, p + Vector2(0, -sz.y * 0.55), k, t)
		return
	ci.draw_colored_polygon(_oct(p + Vector2(0, 1.0 * k), 7.0 * k, 2.4 * k), SHADOW)
	SoftGlow.draw(ci, p + Vector2(0, -4.0 * k), 12.0 * k, Color(1.0, 0.92, 0.95, 0.28))
	# a little wedge of stone: one big flat face toward the light, three smaller ones round it
	var top := p + Vector2(-1.0, -11.0) * k
	var l := p + Vector2(-7.0, -4.0) * k
	var r := p + Vector2(6.5, -5.5) * k
	var bl := p + Vector2(-4.5, 0.0) * k
	var br := p + Vector2(4.0, 0.5) * k
	var mid := p + Vector2(0.5, -4.0) * k
	ci.draw_colored_polygon(PackedVector2Array([top, l, mid]), FACES[0])       # the cut face, catching the light
	ci.draw_colored_polygon(PackedVector2Array([top, mid, r]), FACES[2])
	ci.draw_colored_polygon(PackedVector2Array([l, bl, br, mid]), FACES[1])
	ci.draw_colored_polygon(PackedVector2Array([mid, br, r]), FACES[3])
	_glint(ci, (top + l + mid) / 3.0, k, t)


## Every few seconds a white star runs over the cut face, catching the light.
static func _glint(ci: CanvasItem, c: Vector2, k: float, t: float) -> void:
	var g := fmod(t * 0.45, 2.6)
	if g > 0.7:
		return
	var a := sin(g / 0.7 * PI)
	var arm := 4.5 * k * a
	var col := Color(1, 1, 1, 0.95 * a)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -arm), c + Vector2(0.8 * k, 0), c + Vector2(0, arm), c + Vector2(-0.8 * k, 0)]), col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-arm, 0), c + Vector2(0, -0.8 * k), c + Vector2(arm, 0), c + Vector2(0, 0.8 * k)]), col)


## Its keepsake at home: the chip held up on a little faceted stand of pale stone, flat face to the room.
static func draw_kept(ci: CanvasItem, p: Vector2, t: float) -> void:
	var tex := _tex(KEPT_ART)
	if tex != null:
		var sz := tex.get_size() * 0.5
		ci.draw_texture_rect(tex, Rect2(p + Vector2(-sz.x * 0.5, -sz.y + 2.0), sz), false)
		_glint(ci, p + Vector2(0, -sz.y * 0.7), 0.8, t)
		return
	ci.draw_colored_polygon(_oct(p + Vector2(0, 4), 10.0, 3.4), SHADOW)
	# the stand: a squat six-sided block, lit top, two side faces
	var stone := [Color(0.847, 0.831, 0.886), Color(0.725, 0.706, 0.780), Color(0.600, 0.576, 0.678)]
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-8, -4), p + Vector2(0, -7), p + Vector2(8, -4), p + Vector2(0, -1)]), stone[0])
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-8, -4), p + Vector2(0, -1), p + Vector2(0, 5), p + Vector2(-8, 2)]), stone[1])
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -1), p + Vector2(8, -4), p + Vector2(8, 2), p + Vector2(0, 5)]), stone[2])
	draw_chip(ci, p + Vector2(0, -4), 0.85, t)


## A flat octagon (Glintwold's shadows are hard-edged, no blur).
static func _oct(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 8:
		var a := float(i) / 8.0 * TAU + PI / 8.0
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out
