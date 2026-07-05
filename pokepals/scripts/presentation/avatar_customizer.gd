class_name AvatarCustomizer
extends Control
## The dressing-room overlay — one screen used in two modes:
##   • "create"   — the first-run pick (body type, skin, clothing, hair, accessory) before the
##                  world is playable; there's no cancel, defaults are already valid.
##   • "wardrobe" — reopened from the gear menu any time to restyle; Done applies, Cancel backs out.
##
## It edits a WORKING COPY of the player's PlayerAppearance (so a wardrobe cancel is lossless) and,
## on Done, emits the finished look as a plain dict — the exact shape that already flows over the
## wire and into the server save. It never touches the network or the live avatar itself; the world
## controller wires `confirmed`/`canceled` to refresh + broadcast + persist.
##
## Pure presentation, built in code so it drops into any scene. Reuses the real render path via
## AvatarPreview, so the portrait is a faithful mirror of what you'll be in the world.

signal confirmed(look: Dictionary)
signal canceled

const CREAM := Color(0.96, 0.94, 0.87)
const ACCENT := Color(0.29, 0.30, 0.33)
const TEXT_COLOR := Color(0.20, 0.20, 0.22)
const DIM := Color(0.08, 0.09, 0.11, 0.82)   # the scrim behind the panel
const EQUIPPED_FILL := Color(1.0, 0.97, 0.90)

var _catalog: CosmeticsCatalog
var _appearance: PlayerAppearance   # a working copy; the live one is untouched until Done
var _mode := "wardrobe"
var _active_slot := ""

var _preview: AvatarPreview
var _tabs: HBoxContainer
var _grid: HFlowContainer
var _colors: HBoxContainer
var _title: Label
var _built := false


## Seed the overlay. Pass the shared catalog, the appearance to start from (a working copy is
## taken), and the mode ("create" | "wardrobe"). Safe to call before or after entering the tree.
func setup(catalog: CosmeticsCatalog, appearance: PlayerAppearance, mode: String) -> void:
	_catalog = catalog
	_mode = mode
	_appearance = PlayerAppearance.from_dict(appearance.to_dict(), catalog)
	if not _built:
		_build_ui()
	_active_slot = _first_tab_slot()
	_title.text = "Create your look" if _mode == "create" else "Wardrobe"
	_preview.show_appearance(_appearance, _catalog)
	_rebuild_tabs()
	_rebuild_grid()
	_rebuild_colors()


## The working look right now — the caller can apply it directly (mirror of confirmed's payload).
func current_look() -> Dictionary:
	return _appearance.to_dict()


# ------------------------------------------------------------------ UI scaffold
func _build_ui() -> void:
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # swallow taps so the world beneath ignores them

	var scrim := ColorRect.new()
	scrim.color = DIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", CREAM)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	# Live portrait.
	_preview = AvatarPreview.new()
	_preview.custom_minimum_size = Vector2(0, 200)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_preview)

	# Category tabs.
	var tabs_scroll := ScrollContainer.new()
	tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(tabs_scroll)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	tabs_scroll.add_child(_tabs)

	# Owned items for the active tab.
	var grid_scroll := ScrollContainer.new()
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(grid_scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	grid_scroll.add_child(_grid)

	# Color swatches (skin tone / hair color) for the active tab, when one applies.
	_colors = HBoxContainer.new()
	_colors.add_theme_constant_override("separation", 6)
	col.add_child(_colors)

	# Actions.
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	col.add_child(actions)
	if _mode == "wardrobe":
		actions.add_child(_make_button("Cancel", func() -> void: canceled.emit()))
	var done_label := "Begin" if _mode == "create" else "Done"
	actions.add_child(_make_button(done_label, func() -> void: confirmed.emit(_appearance.to_dict())))


# ------------------------------------------------------------------ tabs
func _rebuild_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	for slot in _tab_slots():
		var b := _make_button(_slot_label(slot), func() -> void: _set_active_slot(slot))
		if slot == _active_slot:
			_mark_pressed(b)
		_tabs.add_child(b)


func _set_active_slot(slot: String) -> void:
	_active_slot = slot
	_rebuild_tabs()
	_rebuild_grid()
	_rebuild_colors()


# ------------------------------------------------------------------ item grid
func _rebuild_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	# A non-required slot can be worn empty — offer a "None" card that unequips it.
	if not _catalog.slot_required(_active_slot):
		var bare := String(_appearance.equipped.get(_active_slot, "")) == ""
		var none_card := _make_button("None", func() -> void: _unequip(_active_slot))
		if bare:
			_mark_pressed(none_card)
		_grid.add_child(none_card)
	for id in _catalog.items_in_slot(_active_slot):
		if not _appearance.is_owned(id):
			continue   # only owned items are wearable here (locked/shop items come later)
		var item_name := String(_catalog.item(id).get("name", id))
		var card := _make_button(item_name, func() -> void: _equip(id))
		if String(_appearance.equipped.get(_active_slot, "")) == id:
			_mark_pressed(card)
		_grid.add_child(card)


func _equip(id: String) -> void:
	if _appearance.equip(_catalog, id):
		_after_change()


func _unequip(slot: String) -> void:
	if _appearance.unequip(_catalog, slot):
		_after_change()


# ------------------------------------------------------------------ colors
func _rebuild_colors() -> void:
	for c in _colors.get_children():
		c.queue_free()
	var cs := _color_slot_for(_active_slot)
	if cs.is_empty():
		_colors.visible = false
		return
	_colors.visible = true
	var slot_id := String(cs["id"])
	var current := String(_appearance.colors.get(slot_id, cs.get("default", "")))
	for ramp in cs.get("ramps", []):
		var rgb := _catalog.ramp_color(slot_id, String(ramp))
		_colors.add_child(_make_swatch(slot_id, String(ramp), rgb, String(ramp) == current))


func _make_swatch(slot_id: String, ramp: String, rgb: Array, is_current: bool) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(34, 34)
	b.focus_mode = Control.FOCUS_NONE
	var fill := Color(float(rgb[0]), float(rgb[1]), float(rgb[2])) if rgb.size() >= 3 else CREAM
	var border := CREAM if is_current else ACCENT
	var w := 4 if is_current else 2
	var style := PixelPanelStyle.make(fill, border, w, 0, 0)
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style)
	b.add_theme_stylebox_override("pressed", style)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: _set_color(slot_id, ramp))
	return b


func _set_color(slot_id: String, ramp: String) -> void:
	if _appearance.set_color(_catalog, slot_id, ramp):
		_after_change()


# ------------------------------------------------------------------ shared
func _after_change() -> void:
	_preview.show_appearance(_appearance, _catalog)
	_rebuild_grid()
	_rebuild_colors()


## Slots that get a tab: those with at least one owned item (so an empty slot like 'held' hides).
func _tab_slots() -> Array:
	var out: Array = []
	for slot in _catalog.slots_by_z():
		for id in _catalog.items_in_slot(slot):
			if _appearance.is_owned(id):
				out.append(slot)
				break
	return out


func _first_tab_slot() -> String:
	var slots := _tab_slots()
	return String(slots[0]) if not slots.is_empty() else "body"


## The color slot (if any) whose recolor targets this paper-doll slot — e.g. skin_tone -> body.
func _color_slot_for(slot: String) -> Dictionary:
	for cs in _catalog.color_slots():
		if String(cs.get("applies_to", "")) == slot:
			return cs
	return {}


func _slot_label(slot: String) -> String:
	match slot:
		"body": return "Build"
		"outfit": return "Clothing"
		"footwear": return "Shoes"
		"accessory": return "Extras"
		"headwear": return "Hats"
		_: return slot.capitalize()


# ------------------------------------------------------------------ little widgets
func _make_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", TEXT_COLOR)
	b.add_theme_color_override("font_hover_color", TEXT_COLOR)
	b.add_theme_color_override("font_pressed_color", TEXT_COLOR)
	b.add_theme_stylebox_override("normal", PixelPanelStyle.make(CREAM, ACCENT, 3))
	b.add_theme_stylebox_override("hover", PixelPanelStyle.make(CREAM.darkened(0.04), ACCENT, 3))
	b.add_theme_stylebox_override("pressed", PixelPanelStyle.make(EQUIPPED_FILL, ACCENT, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(on_press)
	return b


## Highlight a button as the current selection (equipped item / active tab).
func _mark_pressed(b: Button) -> void:
	b.add_theme_stylebox_override("normal", PixelPanelStyle.make(EQUIPPED_FILL, CREAM, 3))
