class_name Hotbar
extends Control
## The HOTBAR (usable items, U-9 in docs/usable-items-design.md): a small row of 5 slots at the bottom centre
## of the screen, like Minecraft's, holding the items you use often. One slot is SELECTED (a gold frame) and
## the use button beside the companion chip uses whatever is in it; tap another slot to switch, or press
## 1-5. It stays out of sight until there's something on it.
##
## Pure presentation: FishingDirector pushes the slots (set_slots) and the selection (set_selected); this node
## draws them and reports a tapped slot (`slot_selected`). The bar's own rect stops taps, so tapping a slot
## never reaches the world as a companion order; the rest of this full-screen control lets taps through.

signal slot_selected(index: int)

const SLOT := 26.0          # one slot's size
const GAP := 4.0            # between slots
const BOTTOM_MARGIN := 10.0

var _bar: Control
var _slots: Array = []      # per slot: {} for empty, else { key, kind, color, quantity }
var _selected := 0
var _show_keys := true      # the 1-5 key hints (desktop only)
var _has_items := false
## Kept out of sight regardless (the first-meeting search, when the companion radial hides too).
var suppressed := false:
	set(value):
		suppressed = value
		visible = _has_items and not suppressed


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show_keys = not DisplayServer.is_touchscreen_available()
	_bar = Control.new()
	_bar.name = "Bar"
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.draw.connect(_draw_bar)
	_bar.gui_input.connect(_on_bar_input)
	add_child(_bar)
	visible = false
	_layout.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout()


func _layout() -> void:
	if _bar == null:
		return
	var n := maxi(_slots.size(), 1)
	var w := float(n) * SLOT + float(n - 1) * GAP
	_bar.size = Vector2(w, SLOT)
	_bar.position = Vector2((size.x - w) * 0.5, size.y - SLOT - BOTTOM_MARGIN)
	_bar.queue_redraw()


## The bar's slots: each {} (empty) or { key, kind, color, quantity }. The bar shows only while at least one
## slot holds something.
func set_slots(slots: Array) -> void:
	_slots = slots.duplicate(true)
	var any := false
	for s in _slots:
		if s is Dictionary and not (s as Dictionary).is_empty():
			any = true
	_has_items = any
	visible = _has_items and not suppressed
	_layout()


func set_selected(index: int) -> void:
	_selected = index
	if _bar != null:
		_bar.queue_redraw()


## The bar's rect on screen, for anything that must keep clear of it.
func bar_rect() -> Rect2:
	return Rect2(_bar.position, _bar.size) if _bar != null else Rect2()


func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var i := int(floor(event.position.x / (SLOT + GAP)))
		if i >= 0 and i < _slots.size():
			slot_selected.emit(i)
		_bar.accept_event()


func _draw_bar() -> void:
	var font := get_theme_default_font()
	for i in _slots.size():
		var r := Rect2(Vector2(float(i) * (SLOT + GAP), 0.0), Vector2(SLOT, SLOT))
		var sel := i == _selected
		var box := UiStyle.hud_box(7, false)
		if sel:
			box.border_color = UiStyle.GOLD
			box.set_border_width_all(2)
			box.border_width_bottom = 3
		_bar.draw_style_box(box, r)
		var s: Variant = _slots[i]
		if s is Dictionary and not (s as Dictionary).is_empty():
			var d: Dictionary = s
			ItemIcon.draw(_bar, String(d.get("key", "")), String(d.get("kind", "")), r.get_center() + Vector2(0, -1),
				SLOT * 0.72, d.get("color", Color(0.8, 0.84, 0.88)))
		if _show_keys and font != null:
			_bar.draw_string(font, r.position + Vector2(3, 9), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
				Color(UiStyle.INK_SOFT, 0.55))
