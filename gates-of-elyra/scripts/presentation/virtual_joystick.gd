class_name VirtualJoystick
extends Control
## The walking thumbstick, at home in the BOTTOM-LEFT corner. At rest it's only a faint dashed ring, so
## it doesn't sit on the scenery. A press anywhere in the corner's reach (a generous circle round that
## resting spot) brings the stick to the thumb: its base centres where you pressed and dragging steers
## (clamped to max_radius). Let go and it settles back to its corner. A press ANYWHERE ELSE is left
## untouched, so it falls through to the world, which reads it as a companion order (see
## world_controller). It reports a normalized `direction` the player controller adds to its input.
##
## Touch only: on a plain desktop (no touchscreen) it hides itself and does nothing; the keyboard
## (WASD/arrows) walks there.

@export var max_radius := 70.0
@export var margin := 30.0        # gap from the bottom-left corner to the base's edge
@export var grab_pad := 22.0      # extra radius past the base that still counts as grabbing the stick
@export var reach := 60.0         # how much further out from the corner a press still brings the stick
@export var ghost_radius := 44.0  # the faint ring drawn at rest

var direction := Vector2.ZERO
## Off while a menu is up over the live world: the stick lets go and ignores presses (it reads input in
## _input, BEFORE the GUI, so without this it would still grab under a full-screen menu).
var enabled := true:
	set(value):
		enabled = value
		if not enabled and _active:
			_release()

## HUD controls a press must never be taken from (the item bar, an Examine bubble, an open menu's
## tap-away): a press over any visible one is left to the GUI.
var avoid: Array = []

var _use_mouse := false           # desktop (no touchscreen): the stick is hidden and inert
var _active := false
var _touch_index := -1
var _home := Vector2.ZERO         # the stick's resting spot in the corner (from _layout)
var _center := Vector2.ZERO       # the base's centre now: home at rest, under the thumb while held
var _knob := Vector2.ZERO


func _ready() -> void:
	_use_mouse = not DisplayServer.is_touchscreen_available()
	# Desktop walks with the keyboard: no stick drawn, and none grabbing clicks in the corner.
	if _use_mouse:
		visible = false
		enabled = false
	_layout.call_deferred()


## Reflow to the bottom-left corner whenever the (full-rect) control resizes — i.e. on window resize.
## Guarded like the other HUD chips: the first NOTIFICATION_RESIZED can arrive before _ready().
##
## Let go when the tree pauses. The lobby gate (a dropped connection) pauses the world, and a paused
## node gets no _input — so the finger lifting off the stick is never heard, and on unpause the stick
## would still be held, walking you in a straight line forever. Releasing on pause means you come back
## standing still; just press the stick again to walk. (Menus over the live world don't pause it —
## they switch `enabled` off instead.)
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout()
	elif what == NOTIFICATION_PAUSED and _active:
		_release()


func _layout() -> void:
	_home = Vector2(margin + max_radius, size.y - margin - max_radius)
	if not _active:
		_center = _home
		_knob = _center
	queue_redraw()


## True if a screen point is within the stick's grab region (the corner's reach). Gates both
## grabbing the knob and swallowing the emulated mouse twin of a touch, so a press on the stick
## never doubles as a companion command.
func contains_point(point: Vector2) -> bool:
	if point.distance_to(_home) > max_radius + grab_pad + reach:
		return false
	for c in avoid:
		if is_instance_valid(c) and (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().has_point(point):
			return false
	return true


func _input(event: InputEvent) -> void:
	if not enabled or _use_mouse:
		return
	_handle_touch(event)


func _handle_touch(event: InputEvent) -> void:
	# emulate_mouse_from_touch synthesizes a MOUSE twin of every touch, and handling the touch does
	# NOT mark the twin handled — left alone it sails on into the GUI stage (the world-tap catcher,
	# any HUD chip under the corner) and a stick press doubles as a tap behind the stick. Swallow
	# every left-press that lands in the grab region; the touch branch below is what steers.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and contains_point(event.position):
		get_viewport().set_input_as_handled()
		return
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


## Take ownership of this press: start steering and consume the event so it isn't also read as a
## companion order.
func _grab(at: Vector2) -> void:
	_active = true
	# The base comes to the thumb, kept far enough in that most of its ring stays on screen.
	var inset := max_radius * 0.6
	_center = Vector2(clampf(at.x, inset, maxf(inset, size.x - inset)), clampf(at.y, inset, maxf(inset, size.y - inset)))
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
	_center = _home
	_knob = _center
	queue_redraw()


func _draw() -> void:
	if _active:
		# Held: the base well and rim under the thumb, and the knob.
		draw_circle(_center, max_radius, Color(1, 1, 1, 0.08))
		draw_arc(_center, max_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.0, true)
		draw_circle(_knob, 24.0, Color(1, 1, 1, 0.7))
		return
	# At rest: a faint dashed ring and a soft knob, just enough to say "walk from here".
	var n := 22
	for i in n:
		var a := TAU * float(i) / float(n)
		draw_arc(_home, ghost_radius, a, a + TAU / float(n) * 0.5, 4, Color(1, 1, 1, 0.32), 2.0, true)
	draw_circle(_home, 17.0, Color(1, 1, 1, 0.18))
