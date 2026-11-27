class_name TideGauge
extends Node2D
## EBBMERE's tide pole: a weathered post standing by the landing that always shows where the tide is, so the
## state of the water is readable at a glance (the lesson of every playtest: every state visible). The origin
## is the post's foot, so it stands in the y-sorted Scenery and you walk behind it. A little blue float rides up
## and down it with the water, pointing the way the tide is moving; a gold notch marks the level that counts as
## LOWEST tide (the sand-dollar's level), and the notch glows while the tide is under it. Purely presentation:
## the TideDirector hands it the level and the clock's state.

const HEIGHT := 58.0

var _lo := 0.30
var _hi := 0.78
var _yield := 0.345
var _level := 0.5
var _rising := false
var _low := false
var _time := 0.0


func configure(tide: Dictionary) -> void:
	_lo = float(tide.get("level_low", 0.30))
	_hi = float(tide.get("level_high", 0.78))
	_yield = float(tide.get("yield_level", 0.345))


func set_state(level: float, rising: bool, low: bool) -> void:
	_level = level
	_rising = rising
	_low = low
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _low:
		queue_redraw()


func _y_of(level: float) -> float:
	return -4.0 - clampf((level - _lo) / maxf(0.001, _hi - _lo), 0.0, 1.0) * (HEIGHT - 12.0)


func _draw() -> void:
	# ground shadow
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 8.0, Color(0.2, 0.16, 0.12, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the post, lit on its left
	draw_rect(Rect2(-3, -HEIGHT, 6, HEIGHT), Color(0.52, 0.45, 0.37))
	draw_rect(Rect2(-3, -HEIGHT, 2, HEIGHT), Color(0.78, 0.70, 0.58))
	draw_rect(Rect2(1, -HEIGHT, 2, HEIGHT), Color(0.36, 0.30, 0.25))
	draw_rect(Rect2(-4, -HEIGHT - 2, 8, 3), Color(0.60, 0.52, 0.42))
	# notches: a tick every tenth of the range
	for i in 11:
		var y := _y_of(_lo + (_hi - _lo) * float(i) / 10.0)
		draw_line(Vector2(-6 if i % 5 == 0 else -5, y), Vector2(-3, y), Color(0.22, 0.18, 0.14), 1.0)
	# the lowest-tide notch, gold, glowing while the water is under it
	var gy := _y_of(_yield)
	var glow := 0.55 + 0.45 * sin(_time * 4.0) if _low else 0.0
	draw_rect(Rect2(3, gy - 1, 6, 2), Color(0.98, 0.82, 0.32, 0.85 + 0.15 * glow))
	if _low:
		draw_circle(Vector2(7, gy), 5.0, Color(1.0, 0.88, 0.40, 0.25 * glow))
	# the float, with an arrow for which way the water is going
	var fy := _y_of(_level)
	draw_rect(Rect2(-7, fy - 2, 14, 4), Color(0.30, 0.56, 0.72))
	draw_rect(Rect2(-7, fy - 2, 14, 1), Color(0.70, 0.90, 0.96))
	var s := -1.0 if _rising else 1.0
	draw_colored_polygon(PackedVector2Array([Vector2(10, fy + s * 3.0), Vector2(14, fy - s * 2.0), Vector2(6, fy - s * 2.0)]), Color(0.30, 0.56, 0.72))
