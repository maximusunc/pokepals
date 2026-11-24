class_name Hotbar
extends Control
## The ITEM BAR at the bottom centre: the hotbar's 5 slots (usable items, U-9 in
## docs/usable-items-design.md) and, at its end, the BAG. One slot is SELECTED (a gold frame, its item's
## name in a little pill above the bar) and the use button in the bottom-right corner uses whatever is in
## it; tap another slot to switch, or press 1-5 (the numbers show on a desktop). Empty slots are quiet
## dashed outlines, so they don't read as buttons. Before you carry anything usable, only the bag shows.
##
## Pure presentation: FishingDirector pushes the slots (set_slots) and the selection (set_selected); this
## node draws them and reports a tapped slot (`slot_selected`) or the bag (`bag_pressed`). The bar's own
## rect stops taps, so tapping it never reaches the world as a companion order; the rest of this
## full-screen control lets taps through.

signal slot_selected(index: int)
signal bag_pressed

const SLOT := 32.0          # one slot's size
const GAP := 4.0            # between slots
const PAD := 5.0            # the tray's inner margin
const SEP := 14.0           # the room the divider before the bag takes
const BOTTOM_MARGIN := 8.0
const NAME_H := 16.0        # the selected item's name pill above the bar

var _bar: Control
var _slots: Array = []      # per slot: {} for empty, else { key, name, kind, color, quantity }
var _selected := 0
var _show_keys := true      # the 1-5 key hints (desktop only)
var _has_items := false
## Kept out of sight regardless (the first-meeting search, when the companion column hides too).
var suppressed := false:
	set(value):
		suppressed = value
		visible = not suppressed


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show_keys = not DisplayServer.is_touchscreen_available()
	_bar = Control.new()
	_bar.name = "Bar"
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.draw.connect(_draw_bar)
	_bar.gui_input.connect(_on_bar_input)
	add_child(_bar)
	visible = not suppressed
	_layout.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout()


## Whether the slots are showing (anything usable carried); the bag is there regardless.
func shows_slots() -> bool:
	return _has_items


func _slots_shown() -> int:
	return _slots.size() if _has_items else 0


func _layout() -> void:
	if _bar == null:
		return
	var n := _slots_shown()
	var w := PAD * 2.0 + SLOT
	if n > 0:
		w += float(n) * SLOT + float(n - 1) * GAP + SEP
	var h := SLOT + PAD * 2.0
	_bar.size = Vector2(w, h + NAME_H + 4.0)
	_bar.position = Vector2(round((size.x - w) * 0.5), size.y - h - BOTTOM_MARGIN - NAME_H - 4.0)
	_bar.queue_redraw()


## The bar's slots: each {} (empty) or { key, name, kind, color, quantity }.
func set_slots(slots: Array) -> void:
	_slots = slots.duplicate(true)
	var any := false
	for s in _slots:
		if s is Dictionary and not (s as Dictionary).is_empty():
			any = true
	_has_items = any
	_layout()


func set_selected(index: int) -> void:
	_selected = index
	if _bar != null:
		_bar.queue_redraw()


## The tray's rect on screen (without the name pill above it), for anything that must keep clear of it.
func bar_rect() -> Rect2:
	if _bar == null:
		return Rect2()
	return Rect2(_bar.position + Vector2(0, NAME_H + 4.0), Vector2(_bar.size.x, SLOT + PAD * 2.0))


func _tray_top() -> float:
	return NAME_H + 4.0


func _slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(PAD + float(i) * (SLOT + GAP), _tray_top() + PAD), Vector2(SLOT, SLOT))


func _bag_rect() -> Rect2:
	return Rect2(Vector2(_bar.size.x - PAD - SLOT, _tray_top() + PAD), Vector2(SLOT, SLOT))


func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var p: Vector2 = event.position
		if p.y < _tray_top():
			# Above the tray (the name pill's row): let it through to the world.
			return
		if _bag_rect().grow(GAP * 0.5).has_point(p):
			bag_pressed.emit()
		else:
			for i in _slots_shown():
				if _slot_rect(i).grow(GAP * 0.5).has_point(p):
					slot_selected.emit(i)
		_bar.accept_event()


func _draw_bar() -> void:
	var tray := Rect2(Vector2(0, _tray_top()), Vector2(_bar.size.x, SLOT + PAD * 2.0))
	var sb := UiStyle.hud_box(12)
	sb.anti_aliasing = true
	_bar.draw_style_box(sb, tray)
	var font := get_theme_default_font()
	for i in _slots_shown():
		var r := _slot_rect(i)
		var sel := i == _selected
		var s: Variant = _slots[i]
		var filled: bool = s is Dictionary and not (s as Dictionary).is_empty()
		if filled or sel:
			var box := StyleBoxFlat.new()
			box.bg_color = Color("ffe7be") if sel else UiStyle.PILL_BG
			box.border_color = UiStyle.GOLD if sel else UiStyle.PILL_BORDER
			box.set_border_width_all(2 if not sel else 3)
			box.set_corner_radius_all(8)
			box.anti_aliasing = true
			_bar.draw_style_box(box, r)
		else:
			_dashed_round_rect(r.grow(-1.0), Color(UiStyle.PILL_BORDER, 0.9))
		if filled:
			var d: Dictionary = s
			ItemIcon.draw(_bar, String(d.get("key", "")), String(d.get("kind", "")), r.get_center() + Vector2(0, -1),
				SLOT * 0.7, d.get("color", Color(0.8, 0.84, 0.88)))
		if _show_keys and font != null:
			_bar.draw_string(font, r.position + Vector2(4, 10), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
				Color(UiStyle.INK_SOFT, 0.5))
	if _slots_shown() > 0:
		var dx := _bag_rect().position.x - SEP * 0.5 + GAP * 0.5 - 2.0
		_bar.draw_line(Vector2(dx, tray.position.y + 10.0), Vector2(dx, tray.end.y - 12.0), UiStyle.DIVIDER, 2.0)
	# The bag: an ink tile with a cream backpack.
	var bag := _bag_rect()
	var bb := StyleBoxFlat.new()
	bb.bg_color = UiStyle.INK
	bb.set_corner_radius_all(8)
	bb.anti_aliasing = true
	_bar.draw_style_box(bb, bag)
	HudIcons.draw(_bar, "bag", bag.get_center(), 21.0, UiStyle.PAPER)
	# The selected item's name, in a small dark pill above its slot's bar.
	var label_text := _selected_name()
	if label_text != "":
		var bold := UiFonts.grotesk(600)
		if bold != null:
			var tw := bold.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var pill := Rect2(Vector2((_bar.size.x - tw) * 0.5 - 8.0, 0.0), Vector2(tw + 16.0, NAME_H))
			var pb := StyleBoxFlat.new()
			pb.bg_color = UiStyle.DARK_PILL_BG
			pb.set_corner_radius_all(int(NAME_H * 0.5))
			pb.anti_aliasing = true
			_bar.draw_style_box(pb, pill)
			_bar.draw_string(bold, Vector2(pill.position.x + 8.0, NAME_H - 4.5), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiStyle.PAPER)


func _selected_name() -> String:
	if not _has_items or _selected < 0 or _selected >= _slots.size():
		return ""
	var s: Variant = _slots[_selected]
	if not (s is Dictionary):
		return ""
	return String((s as Dictionary).get("name", ""))


func _dashed_round_rect(r: Rect2, color: Color) -> void:
	# Dashes along the four straight edges (the corners stay open), enough to read as "a place for one".
	var dash := 4.0
	var gap := 3.0
	var inset := 5.0
	var edges := [
		[r.position + Vector2(inset, 0), r.position + Vector2(r.size.x - inset, 0)],
		[r.position + Vector2(inset, r.size.y), r.position + Vector2(r.size.x - inset, r.size.y)],
		[r.position + Vector2(0, inset), r.position + Vector2(0, r.size.y - inset)],
		[r.position + Vector2(r.size.x, inset), r.position + Vector2(r.size.x, r.size.y - inset)],
	]
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var t := 0.0
		while t < length:
			_bar.draw_line(a + dir * t, a + dir * minf(t + dash, length), color, 1.5)
			t += dash + gap


## The interactive Controls the joystick must leave alone.
func tap_targets() -> Array:
	return [_bar]
