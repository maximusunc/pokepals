class_name PlayerView
extends Node2D
## The player avatar: reads input, moves smoothly, and draws a simple placeholder
## figure. Movement is presentation/input concern, kept light. It exposes
## `velocity` so the companion's brain can anticipate where the player is heading.
##
## Input is intentionally forgiving: arrow keys (ui_* actions), WASD (physical keys
## so it works on any layout), and an optional on-screen joystick for touch.

@export var speed := 118.0
@export var accel := 11.0
@export var joystick_path: NodePath

var velocity := Vector2.ZERO
var _joystick: Node = null
var _time := 0.0


func _ready() -> void:
	if joystick_path != NodePath(""):
		_joystick = get_node_or_null(joystick_path)


func _process(delta: float) -> void:
	_time += delta
	var dir := _input_direction()
	var desired := dir * speed
	# Exponential smoothing -> snappy but not robotic. (1 - e^(-k*dt)) is a
	# framerate-independent lerp weight.
	velocity = velocity.lerp(desired, 1.0 - exp(-accel * delta))
	position += velocity * delta
	queue_redraw()


func _input_direction() -> Vector2:
	var v := Vector2.ZERO
	v.x = Input.get_axis("ui_left", "ui_right")
	v.y = Input.get_axis("ui_up", "ui_down")
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		v.y += 1.0
	if _joystick != null:
		v += _joystick.direction
	return v.limit_length(1.0)


func _draw() -> void:
	var moving := velocity.length() > 8.0
	var step := absf(sin(_time * 11.0)) * 2.0 if moving else 0.0
	# soft shadow
	draw_circle(Vector2(0, 8), 9.0, Color(0, 0, 0, 0.18))
	# body
	draw_circle(Vector2(0, -4 - step), 10.0, Color(0.82, 0.49, 0.38))
	# head
	draw_circle(Vector2(0, -18 - step), 7.0, Color(0.96, 0.81, 0.67))
