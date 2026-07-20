class_name ExaminePrompt
extends Control
## The diegetic "Examine" prompt: a small cream bubble with a downward caret that floats just ABOVE
## the nearby world object and points at it, instead of a fixed on-screen button. It fades in only
## while the player is in range of something examinable and tracks the object as the camera pans, so
## the affordance reads as belonging to the world, not the HUD.
##
## The bubble just reads "Examine" — no object name. What the thing IS should come across from how it
## looks in the world, and the hint line names it once you actually examine it, so spelling it out on
## the prompt would only be noise.
##
## Pure presentation: the world controller tells it WHERE to point (a world position) and listens for
## `pressed`; it owns none of the interaction logic. Lives on a CanvasLayer (so it isn't scaled by the
## Camera2D), and projects the target world point to screen each frame via the viewport's canvas
## transform — the standard way to anchor HUD to a world position in Godot.

signal pressed

const BUBBLE_BG := UiStyle.HUD_BG
const BUBBLE_BORDER := UiStyle.HUD_BORDER
const BORDER_W := 2  # matches the HUD buttons' border weight
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
	_button.text = "Examine"  # constant — never names the object (see class docs)
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	UiStyle.hud_button(_button, 10, 600, 8, 10.0, 3.0)
	_button.pressed.connect(func() -> void: pressed.emit())
	add_child(_button)


## Point the prompt at a world object (the bubble text is the constant "Examine"). Fades in if it
## wasn't already showing.
func point_at(world_pos: Vector2) -> void:
	_target_world = world_pos
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
	draw_line(Vector2(-half, base_y), Vector2(0, 0), BUBBLE_BORDER, float(BORDER_W))
	draw_line(Vector2(half, base_y), Vector2(0, 0), BUBBLE_BORDER, float(BORDER_W))


## The interactive Controls the virtual joystick must exclude (so a tap here doesn't also move you).
func tap_targets() -> Array:
	return [_button]
