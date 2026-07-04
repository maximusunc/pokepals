class_name GearMenu
extends Control
## The top-right gear and its drop-down list of system / meta actions — the things that aren't about
## the pet or the world (start a new companion, return to the Vale, leave the game, toggle the dev
## overlay). They live under the gear, out of the way, so the corners stay quiet while you wander.
##
## Pure presentation: the controller pushes the currently-applicable items via set_items() (each
## already gated on session/bond/world state) and listens for `item_selected`. This node owns the
## open/close toggle and the gear's little drawn icon.

signal item_selected(id: String)
signal opened  ## fired when the list drops open, so the controller can close the companion radial

const CREAM := Color(0.96, 0.94, 0.87)
const ACCENT := Color(0.55, 0.48, 0.78)  # system purple (matches the mockup legend)
const TEXT_COLOR := Color(0.16, 0.15, 0.20)
const GEAR_SIZE := 42.0
const GEAR_MARGIN := Vector2(14, 12)

var _gear: Button
var _catcher: Control
var _list: VBoxContainer
var _items: Array = []      # [{id, label}]
var _signature := ""
var _open := false
var _pressed_look := false  # dims the drawn gear disc while the button is held


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_catcher = Control.new()
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.visible = false
	_catcher.gui_input.connect(_on_catcher_input)
	add_child(_catcher)

	# The drop-down list, revealed on open. Default top-left anchors — positioned manually in
	# _build_list so its right edge lines up under the gear.
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.visible = false
	add_child(_list)

	# The gear button — a transparent, round hit-target. Its whole look (the cream disc AND the gear
	# glyph) is drawn in _draw() BELOW the button: a child button with an opaque stylebox would paint
	# over the parent's icon, so we keep the button see-through and draw the visuals ourselves.
	_gear = Button.new()
	_gear.focus_mode = Control.FOCUS_NONE
	_gear.custom_minimum_size = Vector2(GEAR_SIZE, GEAR_SIZE)
	var empty := StyleBoxEmpty.new()
	_gear.add_theme_stylebox_override("normal", empty)
	_gear.add_theme_stylebox_override("hover", empty)
	_gear.add_theme_stylebox_override("pressed", empty)
	_gear.add_theme_stylebox_override("focus", empty)
	_gear.pressed.connect(_toggle)
	_gear.button_down.connect(func() -> void: _pressed_look = true; queue_redraw())
	_gear.button_up.connect(func() -> void: _pressed_look = false; queue_redraw())
	add_child(_gear)

	_layout.call_deferred()


## Reposition the gear (and any open list) when the root's size changes — i.e. on window resize.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _pill_style(dim := 1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CREAM.r * dim, CREAM.g * dim, CREAM.b * dim, 0.98)
	sb.border_color = ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(11)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


func _layout() -> void:
	_gear.size = Vector2(GEAR_SIZE, GEAR_SIZE)
	_gear.position = Vector2(size.x - GEAR_SIZE - GEAR_MARGIN.x, GEAR_MARGIN.y)
	if _open:
		_place_list()
	queue_redraw()


## Hang the list just below the gear, its right edge aligned to the gear's right edge.
func _place_list() -> void:
	var lw := _list.get_combined_minimum_size().x
	var gear_right := _gear.position.x + GEAR_SIZE
	_list.position = Vector2(gear_right - lw, _gear.position.y + GEAR_SIZE + 8)


## The items to offer right now, each already gated by the controller: { id, label }. Rebuilds the
## open list if the set changed.
func set_items(items: Array) -> void:
	var sig := ""
	var next: Array = []
	for it in items:
		next.append({ "id": String(it["id"]), "label": String(it["label"]) })
		sig += String(it["id"]) + ":" + String(it["label"]) + "|"
	if sig == _signature:
		return
	_signature = sig
	_items = next
	if _open:
		_build_list()


func _toggle() -> void:
	if _open:
		_close()
	else:
		_open = true
		_catcher.visible = true
		_build_list()
		opened.emit()


## Close the list if it's open (public so the controller can dismiss it when the radial opens).
func close() -> void:
	_close()


func _close() -> void:
	if not _open:
		return
	_open = false
	_catcher.visible = false
	_list.visible = false
	for c in _list.get_children():
		c.queue_free()


func _build_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for it in _items:
		var id := String(it["id"])
		var btn := Button.new()
		btn.text = String(it["label"])
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", TEXT_COLOR)
		btn.add_theme_color_override("font_hover_color", TEXT_COLOR)
		btn.add_theme_color_override("font_pressed_color", TEXT_COLOR)
		btn.add_theme_stylebox_override("normal", _pill_style())
		btn.add_theme_stylebox_override("hover", _pill_style(0.96))
		btn.add_theme_stylebox_override("pressed", _pill_style(0.9))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(func() -> void:
			item_selected.emit(id)
			_close())
		_list.add_child(btn)
	_list.visible = true
	_place_list()
	# A gentle drop-in.
	_list.modulate.a = 0.0
	var tw := _list.create_tween()
	tw.tween_property(_list, "modulate:a", 1.0, 0.14)


func _on_catcher_input(event: InputEvent) -> void:
	var tap: bool = event is InputEventMouseButton and event.pressed
	var touch: bool = event is InputEventScreenTouch and event.pressed
	if tap or touch:
		_close()
		accept_event()


func _draw() -> void:
	# The gear's whole look, drawn beneath the transparent hit-target: a cream disc with a purple
	# outline, then a small gear glyph in the system-purple accent.
	var c := _gear.position + _gear.size * 0.5
	var r := GEAR_SIZE * 0.5
	var dim := 0.9 if _pressed_look else 1.0
	draw_circle(c, r, Color(CREAM.r * dim, CREAM.g * dim, CREAM.b * dim, 0.98))
	draw_arc(c, r - 1.0, 0.0, TAU, 40, ACCENT, 2.0)
	var outer := GEAR_SIZE * 0.28
	var inner := GEAR_SIZE * 0.13
	# Teeth: short spokes around the ring.
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (outer * 0.7), c + dir * (outer + 3.0), ACCENT, 3.0)
	draw_arc(c, outer, 0.0, TAU, 24, ACCENT, 3.0)
	draw_arc(c, inner, 0.0, TAU, 16, ACCENT, 2.5)


## The interactive Controls the joystick must exclude (the catcher covers the open list too).
func tap_targets() -> Array:
	return [_gear, _catcher]
