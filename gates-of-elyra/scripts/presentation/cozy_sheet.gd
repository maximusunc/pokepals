class_name CozySheet
extends Control
## The shared shape of the small social windows (friends, the journal, a player's card, an invite):
## a dusky backdrop over the world and one cream card in the middle, in the same voice as the Gateway
## picker. Subclasses fill `body` in `_build()`. Tapping the backdrop or pressing Esc closes it, unless
## `modal` is set (an invite waiting for an answer).
##
## A Control built in code, so it drops into the world's UI layer anywhere. "Full rect" anchors make it
## cover the whole screen, which is also what stops taps reaching the world underneath while it's up.

signal closed()

## How long after opening the sheet ignores every tap. On a phone, the browser sends its own
## "compatibility" mouse click a moment after the finger lifts, so the very tap that opened a sheet
## arrives a second time once it's on screen. Without this it lands on the backdrop (closing the sheet
## at once) or on whatever button happens to sit under the finger.
const OPEN_GRACE := 0.45

var width := 340.0
var modal := false

var body: VBoxContainer
var _closed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.08, 0.06, 0.1, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box(12, 12.0))
	center.add_child(panel)
	body = VBoxContainer.new()
	body.custom_minimum_size = Vector2(minf(width, get_viewport_rect().size.x - 32.0), 0)
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)
	_build()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	# A transparent shield on top for the first moment: it swallows the opening tap's echo, then goes.
	var shield := Control.new()
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shield)
	get_tree().create_timer(OPEN_GRACE, true).timeout.connect(shield.queue_free)


## Fill `body`. Overridden by each sheet.
func _build() -> void:
	pass


func close() -> void:
	if _closed:
		return
	_closed = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())


func _unhandled_input(event: InputEvent) -> void:
	if not modal and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_backdrop_input(event: InputEvent) -> void:
	if modal:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		close()


# --- small builders the sheets share ---------------------------------------------------------

func eyebrow(text: String) -> void:
	var l := UiStyle.pixel_label(text.to_upper(), 7, UiStyle.ACCENT_RUST, 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(l)


func heading(text: String) -> Label:
	var l := UiStyle.label(text, 13, UiStyle.INK_STRONG, 700)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)
	return l


func note(text: String, parent: Control = null, color := UiStyle.MUTED) -> Label:
	var l := UiStyle.label(text, 9, color, 500)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(parent if parent != null else body).add_child(l)
	return l


func section(text: String, parent: Control = null) -> void:
	var l := UiStyle.pixel_label(text.to_upper(), 6, UiStyle.LABEL_BROWN, 1)
	(parent if parent != null else body).add_child(l)


static func pill(text: String, on_press: Callable, gold := false, size := 9) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if gold:
		UiStyle.gold_button(b, size)
	else:
		UiStyle.pill_button(b, size)
	b.pressed.connect(on_press)
	return b


## A text field in the same cream pill style as the Gateway's search box.
static func field(placeholder: String) -> LineEdit:
	var f := LineEdit.new()
	f.placeholder_text = placeholder
	UiStyle.set_font(f, 500, 10)
	f.add_theme_color_override("font_color", UiStyle.INK_STRONG)
	f.add_theme_color_override("font_placeholder_color", UiStyle.MUTED_2)
	f.add_theme_color_override("caret_color", UiStyle.INK)
	var box := StyleBoxFlat.new()
	box.bg_color = UiStyle.PILL_BG
	box.set_border_width_all(2)
	box.border_color = UiStyle.PILL_BORDER
	box.set_corner_radius_all(8)
	box.content_margin_left = 10
	box.content_margin_right = 8
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	f.add_theme_stylebox_override("normal", box)
	var focused := box.duplicate() as StyleBoxFlat
	focused.border_color = UiStyle.GOLD
	f.add_theme_stylebox_override("focus", focused)
	return f


## A row: a label that takes the room, then buttons on the right.
func row(text: String, buttons: Array, parent: Control, sub := "") -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 5)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	var name_label := UiStyle.label(text, 10, UiStyle.INK_STRONG, 700)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	words.add_child(name_label)
	if sub != "":
		words.add_child(UiStyle.label(sub, 8, UiStyle.MUTED, 500))
	r.add_child(words)
	for b in buttons:
		(b as Button).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(b)
	parent.add_child(r)
	return r
