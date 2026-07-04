class_name ExaminePrompt
extends Control
## The diegetic "Examine <thing>" prompt: a small cream bubble with a downward caret that
## floats just ABOVE the nearby world object and points at it, instead of a fixed on-screen
## button. It fades in only while the player is in range of something examinable and tracks the
## object as the camera pans, so the affordance reads as belonging to the world, not the HUD.
##
## Pure presentation: the world controller tells it WHAT to point at (a world position + label)
## and listens for `pressed`; it owns none of the interaction logic. Lives on a CanvasLayer (so it
## isn't scaled by the Camera2D), and projects the target world point to screen each frame via the
## viewport's canvas transform — the standard way to anchor HUD to a world position in Godot.

signal pressed

const BUBBLE_BG := Color(0.96, 0.94, 0.87)
const BUBBLE_BORDER := Color(0.30, 0.50, 0.34)  # world-object green (matches the mockup legend)
const TEXT_COLOR := Color(0.17, 0.20, 0.16)
const CARET_H := 9.0
const OBJECT_LIFT := 26.0  # px above the object's world point where the caret tip sits

var _button: Button
var _target_world := Vector2.ZERO
var _active := false
var _fade: Tween


func _ready() -> void:
	# The root is a passive anchor — only the bubble Button takes taps.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false

	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.add_theme_font_size_override("font_size", 20)
	_button.add_theme_color_override("font_color", TEXT_COLOR)
	_button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	_button.add_theme_color_override("font_pressed_color", TEXT_COLOR)
	var sb := _bubble_style()
	_button.add_theme_stylebox_override("normal", sb)
	_button.add_theme_stylebox_override("hover", sb)
	_button.add_theme_stylebox_override("pressed", _bubble_style(0.90))
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_button.pressed.connect(func() -> void: pressed.emit())
	add_child(_button)


## A rounded cream bubble with a green outline. `dim` scales the fill for the pressed look.
func _bubble_style(dim := 1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BUBBLE_BG.r * dim, BUBBLE_BG.g * dim, BUBBLE_BG.b * dim, 0.98)
	sb.border_color = BUBBLE_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## Point the prompt at a world object. Sets the label and fades in if it wasn't already showing.
func point_at(world_pos: Vector2, label: String) -> void:
	_target_world = world_pos
	var text := "Examine %s" % label
	if _button.text != text:
		_button.text = text
	if not _active:
		_active = true
		visible = true
		_start_fade(1.0)


## Fade the prompt out (and stop tracking once hidden).
func hide_prompt() -> void:
	if not _active:
		return
	_active = false
	_start_fade(0.0)


func _start_fade(to_alpha: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", to_alpha, 0.18)
	if to_alpha == 0.0:
		_fade.tween_callback(func() -> void: visible = false)


func _process(_delta: float) -> void:
	if not visible:
		return
	# Project the object's world point to screen. A CanvasLayer Control isn't moved by the camera,
	# so we apply the viewport's canvas transform ourselves — this stays correct through the camera's
	# pan and its opening zoom. The caret tip sits OBJECT_LIFT px above the object.
	var xform := get_viewport().get_canvas_transform()
	var tip := xform * _target_world - Vector2(0, OBJECT_LIFT)
	var bsz := _button.get_combined_minimum_size()
	_button.size = bsz
	# Center the bubble over the tip, lifted by its height + the caret so the caret points down at it.
	_button.position = Vector2(-bsz.x * 0.5, -bsz.y - CARET_H)
	position = tip
	queue_redraw()


func _draw() -> void:
	# A small downward caret from the bubble's bottom-center to the tip (our origin, at 0,0).
	if not visible:
		return
	var half := 7.0
	var base_y := -CARET_H
	var pts := PackedVector2Array([
		Vector2(-half, base_y), Vector2(half, base_y), Vector2(0, 0),
	])
	draw_colored_polygon(pts, BUBBLE_BG)
	# Two edges of the caret in the border color, leaving the base open into the bubble.
	draw_line(Vector2(-half, base_y), Vector2(0, 0), BUBBLE_BORDER, 2.0)
	draw_line(Vector2(half, base_y), Vector2(0, 0), BUBBLE_BORDER, 2.0)


## The interactive Controls the virtual joystick must exclude (so a tap here doesn't also move you).
func tap_targets() -> Array:
	return [_button]
