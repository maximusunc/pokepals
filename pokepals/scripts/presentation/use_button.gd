class_name UseButton
extends Control
## The USE button (usable items, U-9 in docs/usable-items-design.md): a round button on the right, just left
## of the companion chip, that uses whatever is selected on the hotbar (the F key does the same). It shows the
## selected item's picture; when there's nothing to use it on right now (a rod with no water in reach) it
## DIMS, and a tap then explains rather than doing nothing (the director decides what to say).
##
## Pure presentation: FishingDirector sets the item (set_item), whether it's usable (set_ready) and whether a
## bite is on (set_alert, a pulse so you know to tap), and hears `used`. It keeps beside the companion chip by
## reading the radial's chip rect each frame (it can move when the window resizes).

signal used

const DIAMETER := 38.0
const GAP := 8.0            # from the companion chip

var _radial: CompanionRadial
var _button: Control
var _key := ""
var _kind := ""
var _color := Color(0.8, 0.84, 0.88)
var _ready_now := false
var _alert := false
var _t := 0.0
## Kept out of sight regardless (the first-meeting search, when the companion radial hides too).
var suppressed := false:
	set(value):
		suppressed = value
		visible = _key != "" and not suppressed


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button = Control.new()
	_button.name = "Use"
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.size = Vector2(DIAMETER, DIAMETER)
	_button.draw.connect(_draw_button)
	_button.gui_input.connect(_on_button_input)
	add_child(_button)
	visible = false


## The companion radial, whose chip this button sits beside.
func attach_to(radial: CompanionRadial) -> void:
	_radial = radial


## The selected item ("" key = nothing selected: the button hides).
func set_item(key: String, kind: String, color: Color) -> void:
	_key = key
	_kind = kind
	_color = color
	visible = key != "" and not suppressed
	if _button != null:
		_button.queue_redraw()


## Whether using it now would do something (else it dims, and a tap explains).
func set_ready(ready_now: bool) -> void:
	if ready_now != _ready_now:
		_ready_now = ready_now
		if _button != null:
			_button.queue_redraw()


## A bite is on: the button pulses gold so you know it's time to tap.
func set_alert(on: bool) -> void:
	_alert = on


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var chip := _radial.chip_rect() if _radial != null else Rect2(size - Vector2(110, 40), Vector2(96, 26))
	_button.position = Vector2(chip.position.x - GAP - DIAMETER, chip.end.y - DIAMETER)
	if _alert:
		_button.queue_redraw()


func _on_button_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		used.emit()
		_button.accept_event()


func _draw_button() -> void:
	var c := Vector2(DIAMETER, DIAMETER) * 0.5
	var r := DIAMETER * 0.5
	var bg := UiStyle.HUD_BG
	var rim := UiStyle.HUD_BORDER
	if _alert:
		var pulse := 0.5 + 0.5 * sin(_t * 9.0)
		_button.draw_circle(c, r + 2.0 + 2.0 * pulse, Color(UiStyle.GEM_GOLD, 0.45 + 0.3 * pulse))
		rim = UiStyle.GOLD
	_button.draw_circle(c + Vector2(0, 2), r, Color(rim, 0.9))  # the hard bottom drop
	_button.draw_circle(c, r - 1.0, bg)
	_button.draw_arc(c, r - 1.0, 0.0, TAU, 40, rim, 2.0, true)
	var alpha := 1.0 if (_ready_now or _alert) else 0.38
	ItemIcon.draw(_button, _key, _kind, c, DIAMETER * 0.62, _color, alpha)
