class_name LarkFlight
extends Node2D
## Farmeadow's painted skylark, come alive: it starts exactly where the painted one is on the farmyard (its ground
## point on the ray through it, lifted to its height, as big as it's painted), shrinks to a real bird's size as it
## flies, and flutters down to land at your feet, then `landed`. There it stays, a little carved wooden lark
## standing in the grass, until it's picked up (the world's flat prop drawing would be a smear at this low angle). A child of Scenery, so the perspective view stands
## it up, sizes it by distance and sorts it like anything else. Drawn procedurally, wings beating.

signal landed

const SECS := 2.6
const SMALL := 16.0  # a real lark's wingspan, in world units

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _lift := 0.0
var _span := 60.0
var _t := 0.0
var _perched := false
const WOOD := Color(0.70, 0.54, 0.38)


func start(ground: Vector2, lift: float, span: float, land: Vector2) -> void:
	_from = ground
	_to = land
	_lift = lift
	_span = span
	position = ground


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / SECS, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	position = _from.lerp(_to, e)
	queue_redraw()
	if k >= 1.0 and not _perched:
		_perched = true
		set_process(false)
		landed.emit()


func _draw() -> void:
	if _perched:
		_draw_carved()
		return
	var k := clampf(_t / SECS, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var height := lerpf(_lift, 0.0, e) + sin(k * PI) * 18.0
	var span := lerpf(_span, SMALL, minf(1.0, e * 1.4))
	var flap := sin(_t * (14.0 + 10.0 * k)) * (1.0 - k * 0.6)
	var c := Vector2(0, -height)
	# painted brown in the air, turning to pale carved wood as it comes down
	var body := Color(0.41, 0.30, 0.21).lerp(WOOD, smoothstep(0.7, 1.0, k))
	var dark := Color(0.27, 0.20, 0.15).lerp(WOOD.darkened(0.35), smoothstep(0.7, 1.0, k))
	var u := span / 60.0
	# shadow on the ground beneath it
	draw_circle(Vector2.ZERO, 4.0 * u + 2.0, Color(0, 0, 0, 0.18 * e))
	for side in [-1.0, 1.0]:
		var tip := c + Vector2(side * 28.0 * u, (-26.0 * flap - 4.0) * u)
		var root_a := c + Vector2(side * 2.0 * u, -2.0 * u)
		var root_b := c + Vector2(side * 9.0 * u, 1.0 * u)
		draw_colored_polygon(PackedVector2Array([root_a, tip, root_b]), body)
		draw_line(root_a, tip, dark, maxf(1.0, u))
	draw_set_transform(c, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 11.0 * u, body)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(c + Vector2(10.0 * u, -3.0 * u), 4.0 * u, body)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-10.0 * u, 0), c + Vector2(-20.0 * u, -4.0 * u), c + Vector2(-20.0 * u, 5.0 * u)]), dark)


## Landed: a little carved lark standing in the grass, wings up, on a scrap of shadow.
func _draw_carved() -> void:
	var dark := WOOD.darkened(0.35)
	var c := Vector2(0, -6)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-1, -5, 2, 5), dark)   # its little stand
	for side in [-1.0, 1.0]:
		var tip := c + Vector2(side * 9.0, -10.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(side * 1.0, -2.0), tip, c + Vector2(side * 4.0, 1.0)]), WOOD)
		draw_line(c + Vector2(side * 1.0, -2.0), tip, dark, 1.0)
	draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, 5.5, WOOD)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(c + Vector2(4.5, -2.5), 2.6, WOOD)
	draw_line(c + Vector2(-5.0, 0.0), c + Vector2(-9.0, -2.0), dark, 1.5)
	draw_rect(Rect2(c + Vector2(5.0, -3.5), Vector2(1, 1)), Color(0.12, 0.08, 0.06))
	draw_line(c + Vector2(7.0, -2.5), c + Vector2(9.0, -2.0), dark, 1.0)
