class_name VirtualJoystick
extends Control
## A DEDICATED thumbstick fixed in the BOTTOM-LEFT corner — the walking control. Unlike a floating
## stick, it lives in one place: a press that lands within its base region grabs the knob and the
## pointer drags it (clamped to max_radius) to steer; a press ANYWHERE ELSE is left untouched, so it
## falls through to the world, which reads it as a companion order (see world_controller). It reports
## a normalized `direction` the player controller adds to its input, and is always visible so the
## control is discoverable.
##
## Input source: on a touchscreen it tracks touches; on a plain desktop (no touchscreen) it tracks the
## mouse instead — chosen once so the two never mix (which would double-grab under Godot's
## emulate_mouse_from_touch). Desktop keyboard (WASD/arrows) still walks regardless.

@export var max_radius := 70.0
@export var margin := 30.0        # gap from the bottom-left corner to the base's edge
@export var grab_pad := 22.0      # extra radius past the base that still counts as grabbing the stick

var direction := Vector2.ZERO

var _use_mouse := false           # desktop (no touchscreen) drives the stick with the mouse
var _active := false
var _touch_index := -1
var _center := Vector2.ZERO       # base center in screen coords (from _layout)
var _knob := Vector2.ZERO


func _ready() -> void:
	_use_mouse = not DisplayServer.is_touchscreen_available()
	_layout.call_deferred()


## Reflow to the bottom-left corner whenever the (full-rect) control resizes — i.e. on window resize.
## Guarded like the other HUD chips: the first NOTIFICATION_RESIZED can arrive before _ready().
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout()


func _layout() -> void:
	_center = Vector2(margin + max_radius, size.y - margin - max_radius)
	if not _active:
		_knob = _center
	queue_redraw()


## True if a screen point is within the stick's grab region (base + a little pad). The world-order
## handler defers to this so a press on the stick never doubles as a companion command.
func contains_point(point: Vector2) -> bool:
	return point.distance_to(_center) <= max_radius + grab_pad


func _input(event: InputEvent) -> void:
	if _use_mouse:
		_handle_mouse(event)
	else:
		_handle_touch(event)


func _handle_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not _active:
			if not contains_point(event.position):
				return
			_touch_index = event.index
			_grab(event.position)
		elif not event.pressed and event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag and _active and event.index == _touch_index:
		_move(event.position)


func _handle_mouse(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _active:
			if not contains_point(event.position):
				return
			_grab(event.position)
		elif not event.pressed and _active:
			_release()
	elif event is InputEventMouseMotion and _active:
		_move(event.position)


## Take ownership of this press: start steering and consume the event so it isn't also read as a
## companion order.
func _grab(at: Vector2) -> void:
	_active = true
	_move(at)
	get_viewport().set_input_as_handled()


func _move(at: Vector2) -> void:
	var offset: Vector2 = at - _center
	if offset.length() > max_radius:
		offset = offset.normalized() * max_radius
	_knob = _center + offset
	direction = offset / max_radius
	queue_redraw()


func _release() -> void:
	_active = false
	_touch_index = -1
	direction = Vector2.ZERO
	_knob = _center
	queue_redraw()


func _draw() -> void:
	# Base well + a rim, then the knob. Brighter while actively steering.
	var base_a := 0.16 if _active else 0.10
	draw_circle(_center, max_radius, Color(1, 1, 1, 0.06))
	draw_arc(_center, max_radius, 0.0, TAU, 48, Color(1, 1, 1, base_a), 2.0, true)
	draw_circle(_knob, 26.0, Color(1, 1, 1, 0.22 if _active else 0.16))
