class_name UseButton
extends Control
## The USE button (usable items, U-9 in docs/usable-items-design.md): a big round button alone in the
## bottom-right corner that uses whatever is selected on the item bar (the F key does the same). It shows
## the selected item's picture and, in a small pill to its left, what a tap would do ("Cast", "Chop",
## "Reel in"). When there's nothing to use it on right now it greys and the pill says what's missing
## ("Find water"), and a tap still explains (the director decides what to say).
##
## Pure presentation: FishingDirector sets the item (set_item), whether it's usable (set_ready), the words
## (set_verb) and whether a bite is on (set_alert, a pulse so you know to tap), and hears `used`.

signal used

const DIAMETER := 50.0
const MARGIN := Vector2(12, 12)
const LABEL_H := 18.0

var _button: Control
var _label: Control
var _key := ""
var _kind := ""
var _color := Color(0.8, 0.84, 0.88)
var _ready_now := false
var _alert := false
var _verb := ""
var _t := 0.0
## Kept out of sight regardless (the first-meeting search, when the companion column hides too).
var suppressed := false:
	set(value):
		suppressed = value
		visible = _key != "" and not suppressed


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button = Control.new()
	_button.name = "Use"
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.size = Vector2(DIAMETER, DIAMETER + 4.0)
	_button.draw.connect(_draw_button)
	_button.gui_input.connect(_on_button_input)
	add_child(_button)
	_label = Control.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.draw.connect(_draw_label)
	add_child(_label)
	visible = false
	_layout.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout()


func _layout() -> void:
	if _button == null:
		return
	_button.position = Vector2(size.x - MARGIN.x - DIAMETER, size.y - MARGIN.y - DIAMETER - 4.0)
	var font := UiFonts.grotesk(700)
	var w := 0.0
	if _verb != "" and font != null:
		w = font.get_string_size(_verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 18.0
	_label.visible = w > 0.0
	_label.size = Vector2(w, LABEL_H)
	_label.position = Vector2(_button.position.x - 6.0 - w, _button.position.y + DIAMETER * 0.5 - LABEL_H * 0.5)
	_label.queue_redraw()


## The selected item ("" key = nothing selected: the button hides).
func set_item(key: String, kind: String, color: Color) -> void:
	if key == _key and kind == _kind and color == _color:
		return
	_key = key
	_kind = kind
	_color = color
	visible = key != "" and not suppressed
	if _button != null:
		_button.queue_redraw()


## Whether using it now would do something (else it greys, and a tap explains).
func set_ready(ready_now: bool) -> void:
	if ready_now != _ready_now:
		_ready_now = ready_now
		if _button != null:
			_button.queue_redraw()
			_label.queue_redraw()


## The words beside the button: what a tap does now, or (while it isn't ready) what's missing.
## "" shows no words.
func set_verb(text: String) -> void:
	if text == _verb:
		return
	_verb = text
	_layout()


## A bite is on: the button pulses gold so you know it's time to tap.
func set_alert(on: bool) -> void:
	_alert = on
	if _button != null:
		_button.queue_redraw()


## The button's rect on screen.
func button_rect() -> Rect2:
	return Rect2(_button.position, Vector2(DIAMETER, DIAMETER)) if _button != null else Rect2()


func _process(delta: float) -> void:
	if not visible or not _alert:
		return
	_t += delta
	_button.queue_redraw()


func _on_button_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		used.emit()
		_button.accept_event()


func _draw_button() -> void:
	var c := Vector2(DIAMETER, DIAMETER) * 0.5
	var r := DIAMETER * 0.5
	var live := _ready_now or _alert
	if _alert:
		var pulse := 0.5 + 0.5 * sin(_t * 9.0)
		_button.draw_circle(c, r + 2.0 + 2.0 * pulse, Color(UiStyle.GEM_GOLD, 0.45 + 0.3 * pulse))
	if live:
		# Ready: a warm gold disc with an ink rim and a hard drop, the one primary thing on screen.
		_button.draw_circle(c + Vector2(0, 3), r, Color(UiStyle.INK, 0.85))
		_button.draw_circle(c, r, UiStyle.INK)
		_button.draw_circle(c, r - 2.5, UiStyle.GOLD)
	else:
		# Not now: a pale disc with a dashed rim, the picture faded.
		_button.draw_circle(c, r - 1.0, Color(UiStyle.HUD_BG, 0.8))
		var n := 18
		for i in n:
			var a := TAU * float(i) / float(n)
			_button.draw_arc(c, r - 1.5, a, a + TAU / float(n) * 0.55, 4, Color(UiStyle.LEGEND_TEXT, 0.9), 2.0, true)
	ItemIcon.draw(_button, _key, _kind, c, DIAMETER * 0.6, _color, 1.0 if live else 0.45)


func _draw_label() -> void:
	var font := UiFonts.grotesk(700)
	if font == null or _verb == "":
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiStyle.HUD_BG
	sb.set_corner_radius_all(int(LABEL_H * 0.5))
	sb.anti_aliasing = true
	_label.draw_style_box(sb, Rect2(Vector2.ZERO, _label.size))
	var ink := UiStyle.INK_SOFT if (_ready_now or _alert) else UiStyle.LEGEND_TEXT
	_label.draw_string(font, Vector2(9, LABEL_H - 5.0), _verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)


## The interactive Controls the joystick must leave alone.
func tap_targets() -> Array:
	return [_button]
