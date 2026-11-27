class_name FlutterView
extends Node2D
## A butterfly for the perspective view. AmbientLife draws a world's butterflies flat over the whole top-down
## view, which has no meaning in perspective; there, PerspectiveView keeps a few of these instead. Each is an
## ordinary y-sorted child of Scenery standing on its ground point, so the projector stands it up, sizes it by
## distance and sorts it among the trees like anything else. It draws its shadow on the ground and itself a few
## pixels above it. Cosmetic and local, like AmbientLife's.

const HEIGHT := 9.0

var color := Color(0.98, 0.86, 0.4)
var _ang := 0.0
var _speed := 20.0
var _rest := 0.0
var _phase := 0.0
var _time := 0.0
var _rng: RandomNumberGenerator


func setup(rng: RandomNumberGenerator, c: Color) -> void:
	_rng = rng
	color = c
	_ang = rng.randf() * TAU
	_speed = rng.randf_range(16.0, 26.0)
	_phase = rng.randf() * TAU


func tick(delta: float) -> void:
	_time += delta
	if _rest > 0.0:
		_rest -= delta
	else:
		_ang += _rng.randfn(0.0, 3.2) * delta
		position += Vector2(cos(_ang), sin(_ang)) * _speed * delta
		if _rng.randf() < 0.12 * delta:
			_rest = _rng.randf_range(1.0, 3.0)  # settle on a flower for a moment
	queue_redraw()


func _draw() -> void:
	var resting := _rest > 0.0
	var lift := 2.0 if resting else HEIGHT + roundf(sin(_time * 7.0 + _phase) * 1.5)
	draw_rect(Rect2(Vector2(-1, 0), Vector2(3, 1)), Color(0, 0, 0, 0.16))
	var q := Vector2(0, -lift)
	var body := Color(0.18, 0.13, 0.12)
	var open := sin(_time * (5.0 if resting else 19.0) + _phase) > (0.6 if resting else 0.0)
	if open:
		draw_rect(Rect2(q + Vector2(-3, -1), Vector2(3, 2)), color)
		draw_rect(Rect2(q + Vector2(1, -1), Vector2(3, 2)), color)
		draw_rect(Rect2(q + Vector2(-2, 1), Vector2(2, 1)), color.darkened(0.2))
		draw_rect(Rect2(q + Vector2(1, 1), Vector2(2, 1)), color.darkened(0.2))
	else:
		draw_rect(Rect2(q + Vector2(-1, -3), Vector2(1, 3)), color)
		draw_rect(Rect2(q + Vector2(1, -3), Vector2(1, 3)), color)
	draw_rect(Rect2(q + Vector2(0, -1), Vector2(1, 3)), body)
