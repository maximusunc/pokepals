class_name VirtualJoystick
extends Control
## A minimal on-screen thumbstick for touch devices. It stays invisible until a
## finger touches the screen, then appears under that finger and reports a
## normalized `direction` the player controller adds to its input. Harmless on
## desktop (no touch events, stays hidden) — present so the slice is playable on
## mobile from the start.

@export var max_radius := 70.0

var direction := Vector2.ZERO

var _active := false
var _touch_index := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not _active:
			_active = true
			_touch_index = event.index
			_center = event.position
			_knob = event.position
			visible = true
			queue_redraw()
		elif not event.pressed and event.index == _touch_index:
			_reset()
	elif event is InputEventScreenDrag and _active and event.index == _touch_index:
		var offset: Vector2 = event.position - _center
		if offset.length() > max_radius:
			offset = offset.normalized() * max_radius
		_knob = _center + offset
		direction = offset / max_radius
		queue_redraw()


func _reset() -> void:
	_active = false
	_touch_index = -1
	direction = Vector2.ZERO
	visible = false
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	draw_circle(_center, max_radius, Color(1, 1, 1, 0.10))
	draw_circle(_knob, 24.0, Color(1, 1, 1, 0.22))
