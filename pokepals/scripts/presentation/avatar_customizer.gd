class_name AvatarCustomizer
extends Control
## The dressing screen — the landscape "overlay dock" design. The world stays visible at the
## left (dimmed toward the panel) with the hero walking in place over a soft clearing; a cream
## wardrobe dock sits against the right edge. One screen, two modes:
##   • "create"   — the first-run pick before the world is playable; no cancel affordances.
##   • "wardrobe" — reopened from the gear menu any time; Equip look applies, back/✕ cancels.
##
## Two INDEPENDENT navigation axes inside the dock (switching one never resets the other):
##   • mode — Items ⇄ Dyes, a segmented toggle at the top.
##   • tab  — the category pills (Hair / Top / Legs / Shoes / Hat / Extra), shared by both.
## The content area is (mode × tab): an item grid with try-on thumbnails, or dye swatches for
## whatever color slot targets that tab (plus the universal Skin tone row).
##
## It edits a WORKING COPY of the player's PlayerAppearance (so a cancel is lossless) and, on
## Equip look, emits the finished look as a plain dict — the exact shape that already flows over
## the wire and into the server save. It never touches the network or the live avatar itself; the
## world controller wires `confirmed`/`canceled` to refresh + broadcast + persist.
##
## Pure presentation, built in code so it drops into any scene. Reuses the real render path via
## AvatarPreview (the hero) and AvatarCompositor (the try-on thumbnails), so everything shown is
## a faithful mirror of what you'll be in the world.

signal confirmed(look: Dictionary)
signal canceled

# ---- design tokens (the wireframe's palette, metrics at the game's 640×360 UI scale) ----
const INK := Color("2f2417")
const INK_STRONG := Color("33281b")
const MUTED := Color("9a8b76")
const MUTED_2 := Color("b7a98f")
const PANEL_TOP := Color("f8f2e5")
const PANEL_BOTTOM := Color("efe5d2")
const TAB_IDLE_BG := Color("fffdf7")
const TAB_IDLE_BORDER := Color("dccca6")
const TAB_IDLE_TEXT := Color("5a4a34")
const TAB_ON_BG := Color("2f2417")
const TAB_ON_TEXT := Color("f6efe0")
const TOGGLE_TRACK := Color("e7d9bd")
const TOGGLE_IDLE_TEXT := Color("7a6a52")
const GOLD := Color("dfa53e")
const DIVIDER := Color("e2d6bd")
const CELL_EQUIPPED := Color("fff6e6")
const CELL_OWNED := Color("efe6d3")
const CELL_LOCKED := Color("ddd1b8")
const SILHOUETTE := Color(0.11, 0.08, 0.06, 0.92)
const LEGEND_TEXT := Color("8a7c65")
const ACCENT_RUST := Color("b5603a")
const CREAM_TEXT := Color("f4ecda")
const BADGE_GOLD := Color("c2902f")
const GEM_GOLD := Color("f2c65a")

const DOCK_W := 240.0

## Rarity tiers (border + dot + legend), keyed by the catalog items' 'rarity' hint.
const RARITY_ORDER := ["common", "uncommon", "rare", "legendary"]
const RARITY_COLOR := {
	"common": Color("8a8175"),
	"uncommon": Color("4f7a4d"),
	"rare": Color("3f6da0"),
	"legendary": Color("c2902f"),
}

## Category pills in wireframe order; a tab appears only if the catalog stocks that slot.
## (The 'body' slot is deliberately absent — skin lives in the Dyes view's Skin tone row.)
const TAB_ORDER := [
	["hair", "Hair"], ["outfit", "Top"], ["legwear", "Legs"],
	["footwear", "Shoes"], ["headwear", "Hat"], ["accessory", "Extra"],
]

var _catalog: CosmeticsCatalog
var _appearance: PlayerAppearance   # a working copy; the live one is untouched until Equip look
var _mode := "wardrobe"
var _balance := 0
var _tab := ""            # active category (paper-doll slot id)
var _dye_mode := false    # Items ⇄ Dyes
var _built := false

# node refs (built once in _build_ui)
var _preview: AvatarPreview
var _hero: Control
var _clearing: TextureRect
var _screen_header: Control
var _back_btn: Button
var _close_btn: Button
var _coin_label: Label
var _toggle_items: Button
var _toggle_dyes: Button
var _tabs_box: HFlowContainer
var _content: VBoxContainer
var _equip_btn: Button


## Seed the overlay. Pass the shared catalog, the appearance to start from (a working copy is
## taken), the mode ("create" | "wardrobe"), and the wallet balance for the coin badge.
func setup(catalog: CosmeticsCatalog, appearance: PlayerAppearance, mode: String, balance := 0) -> void:
	_catalog = catalog
	_mode = mode
	_balance = balance
	_appearance = PlayerAppearance.from_dict(appearance.to_dict(), catalog)
	if not _built:
		_build_ui()
	_tab = _first_tab()
	_dye_mode = false
	var cancelable := _mode != "create"
	_back_btn.visible = cancelable
	_close_btn.visible = cancelable
	_equip_btn.text = "Equip look" if cancelable else "Begin"
	_coin_label.text = _format_amount(_balance)
	_preview.show_appearance(_appearance, _catalog)
	_refresh_toggle()
	_rebuild_tabs()
	_rebuild_content()
	_layout.call_deferred()


## The working look right now — the caller can apply it directly (mirror of confirmed's payload).
func current_look() -> Dictionary:
	return _appearance.to_dict()


# ------------------------------------------------------------------ UI scaffold
func _build_ui() -> void:
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # swallow taps so the world beneath ignores them
	resized.connect(_layout)

	# The world stays visible; it just falls into shadow toward the dock.
	var dim := DimLayer.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_build_stage()
	_build_screen_header()
	_build_dock()


## The left "stage": a soft dirt clearing with the hero walking in place, nameplate below.
func _build_stage() -> void:
	_clearing = TextureRect.new()
	_clearing.texture = _make_clearing_texture()
	_clearing.stretch_mode = TextureRect.STRETCH_SCALE
	_clearing.size = Vector2(165, 112)
	_clearing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clearing)

	_hero = Control.new()
	_hero.size = Vector2(120, 96)
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero)

	# Live portrait through the real render path; pixel_scale 3 → 96px tall, feet at y=72.
	_preview = AvatarPreview.new()
	_preview.pixel_scale = 3.0
	_preview.position = Vector2.ZERO
	_preview.size = Vector2(120, 96)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.add_child(_preview)

	# Nameplate pill, centred just under the feet (a point-anchor that grows both ways).
	var pill_anchor := Control.new()
	pill_anchor.position = Vector2(60, 74)
	_hero.add_child(pill_anchor)
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(20.0 / 255.0, 15.0 / 255.0, 10.0 / 255.0, 0.72)
	sb.set_border_width_all(1)
	sb.border_color = Color(1.0, 240.0 / 255.0, 215.0 / 255.0, 0.28)
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 4
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pill.add_theme_stylebox_override("panel", sb)
	pill_anchor.add_child(pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	pill.add_child(row)
	var badge := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = BADGE_GOLD
	bsb.set_corner_radius_all(4)
	bsb.content_margin_left = 3
	bsb.content_margin_right = 3
	bsb.content_margin_top = 1
	bsb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", bsb)
	badge.add_child(_pixel_label("YOU", 6, Color("241813")))
	row.add_child(badge)
	row.add_child(_label("Wanderer", 9, CREAM_TEXT, 600))
	# Centre the pill on the anchor point (a 0-size parent) and keep it centred as it sizes.
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH


## Top-left screen header: back chevron, the WARDROBE title, and the coin badge.
func _build_screen_header() -> void:
	_screen_header = HBoxContainer.new()
	_screen_header.position = Vector2(12, 10)
	_screen_header.add_theme_constant_override("separation", 8)
	add_child(_screen_header)

	_back_btn = Button.new()
	_back_btn.text = "‹"
	_back_btn.focus_mode = Control.FOCUS_NONE
	_back_btn.custom_minimum_size = Vector2(26, 26)
	_back_btn.add_theme_font_size_override("font_size", 13)
	var f := UiFonts.grotesk(700)
	if f != null:
		_back_btn.add_theme_font_override("font", f)
	_set_button_colors(_back_btn, Color("3a2c1c"))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(246.0 / 255.0, 240.0 / 255.0, 228.0 / 255.0, 0.9)
	bsb.set_border_width_all(2)
	bsb.border_width_bottom = 4   # the chunky hard drop
	bsb.border_color = Color(20.0 / 255.0, 14.0 / 255.0, 8.0 / 255.0, 0.5)
	bsb.set_corner_radius_all(7)
	_set_button_boxes(_back_btn, bsb)
	_back_btn.pressed.connect(func() -> void: canceled.emit())
	_screen_header.add_child(_back_btn)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_screen_header.add_child(col)

	var title := _pixel_label("WARDROBE", 9, Color.WHITE, 1)
	title.add_theme_color_override("font_shadow_color", Color(20.0 / 255.0, 14.0 / 255.0, 8.0 / 255.0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 1)
	col.add_child(title)

	var pill := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(20.0 / 255.0, 15.0 / 255.0, 10.0 / 255.0, 0.6)
	psb.set_border_width_all(1)
	psb.border_color = Color(1.0, 240.0 / 255.0, 215.0 / 255.0, 0.25)
	psb.set_corner_radius_all(999)
	psb.content_margin_left = 6
	psb.content_margin_right = 6
	psb.content_margin_top = 2
	psb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", psb)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(pill)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 3)
	pill.add_child(prow)
	var gem := GemIcon.new()
	gem.custom_minimum_size = Vector2(8, 8)
	prow.add_child(gem)
	_coin_label = _label("0", 8, CREAM_TEXT, 600)
	prow.add_child(_coin_label)


## The right dock: header (title/close, mode toggle, tabs), content, Equip-look footer.
func _build_dock() -> void:
	var dock := DockPanel.new()
	dock.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	dock.offset_left = -DOCK_W
	dock.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dock)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	dock.add_child(col)

	# --- dock header ---
	var head := MarginContainer.new()
	_set_margins(head, 12, 9, 12, 8)
	col.add_child(head)
	var head_col := VBoxContainer.new()
	head_col.add_theme_constant_override("separation", 8)
	head.add_child(head_col)

	var title_row := HBoxContainer.new()
	head_col.add_child(title_row)
	title_row.add_child(_pixel_label("CUSTOMIZE", 8, ACCENT_RUST, 1))
	title_row.add_child(_spacer())
	_close_btn = Button.new()
	_close_btn.text = "×"
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.custom_minimum_size = Vector2(20, 20)
	_close_btn.add_theme_font_size_override("font_size", 10)
	var cf := UiFonts.grotesk(700)
	if cf != null:
		_close_btn.add_theme_font_override("font", cf)
	_set_button_colors(_close_btn, TOGGLE_IDLE_TEXT)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color.WHITE
	csb.set_border_width_all(2)
	csb.border_color = Color("d8c9a8")
	csb.set_corner_radius_all(6)
	_set_button_boxes(_close_btn, csb)
	_close_btn.pressed.connect(func() -> void: canceled.emit())
	title_row.add_child(_close_btn)

	# Mode toggle — Items ⇄ Dyes. Its own axis; never touches the selected tab.
	var track := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = TOGGLE_TRACK
	tsb.set_corner_radius_all(8)
	tsb.set_content_margin_all(2)
	track.add_theme_stylebox_override("panel", tsb)
	head_col.add_child(track)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 3)
	track.add_child(trow)
	_toggle_items = _make_button("Items", func() -> void: _set_dye_mode(false))
	_toggle_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(_toggle_items)
	_toggle_dyes = _make_button("Dyes", func() -> void: _set_dye_mode(true))
	_toggle_dyes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(_toggle_dyes)

	# Category pills — shared by BOTH modes.
	_tabs_box = HFlowContainer.new()
	_tabs_box.add_theme_constant_override("h_separation", 4)
	_tabs_box.add_theme_constant_override("v_separation", 4)
	head_col.add_child(_tabs_box)

	col.add_child(_divider())

	# --- content: (mode × tab) ---
	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 0)
	col.add_child(_content)

	# --- footer ---
	col.add_child(_divider())
	var foot := MarginContainer.new()
	_set_margins(foot, 12, 8, 12, 10)
	col.add_child(foot)
	_equip_btn = _make_button("Equip look", func() -> void: confirmed.emit(_appearance.to_dict()))
	_equip_btn.add_theme_font_size_override("font_size", 10)
	var ef := UiFonts.grotesk(700)
	if ef != null:
		_equip_btn.add_theme_font_override("font", ef)
	_set_button_colors(_equip_btn, INK)
	var esb := StyleBoxFlat.new()
	esb.bg_color = GOLD
	esb.set_border_width_all(2)
	esb.border_width_bottom = 5   # 2px border + the hard 3px drop, in one chunky ink base
	esb.border_color = INK
	esb.set_corner_radius_all(8)
	esb.content_margin_top = 7
	esb.content_margin_bottom = 7
	_set_button_boxes(_equip_btn, esb)
	foot.add_child(_equip_btn)


## Position the world-side pieces (hero, clearing) — anything not driven by anchors.
func _layout() -> void:
	if not _built:
		return
	var world_w := maxf(size.x - DOCK_W, 120.0)
	# The wireframe centres the hero at 26% / 52% of the screen; keep it inside the world side.
	var cx := clampf(size.x * 0.26, 66.0, world_w - 70.0)
	var feet_y := size.y * 0.52 + 48.0   # sprite centre at 52% → feet half a sprite lower
	_hero.position = Vector2(cx - 60.0, feet_y - 72.0)
	_clearing.position = Vector2(cx - _clearing.size.x * 0.5, feet_y - 48.0 - _clearing.size.y * 0.5)


# ------------------------------------------------------------------ state
func _set_dye_mode(dyes: bool) -> void:
	if _dye_mode == dyes:
		return
	_dye_mode = dyes
	_refresh_toggle()
	_rebuild_content()


func _set_tab(slot: String) -> void:
	if _tab == slot:
		return
	_tab = slot
	_refresh_tabs()
	_rebuild_content()


func _after_change() -> void:
	_preview.show_appearance(_appearance, _catalog)
	_rebuild_content()


## The tabs actually available: the preferred wireframe order filtered by catalog stock, then
## any other stocked slot (except the dye-only body) appended, so new slots appear unprompted.
func _tabs() -> Array:
	var out: Array = []
	var known: Array = []
	for pair in TAB_ORDER:
		known.append(pair[0])
		if not _catalog.items_in_slot(pair[0]).is_empty():
			out.append(pair)
	for slot in _catalog.slots_by_z():
		if slot == "body" or slot in known:
			continue
		if not _catalog.items_in_slot(slot).is_empty():
			out.append([slot, String(slot).capitalize()])
	return out


func _first_tab() -> String:
	var tabs := _tabs()
	return String(tabs[0][0]) if not tabs.is_empty() else ""


func _tab_label(slot: String) -> String:
	for pair in _tabs():
		if String(pair[0]) == slot:
			return String(pair[1])
	return slot.capitalize()


# ------------------------------------------------------------------ header widgets
func _refresh_toggle() -> void:
	_style_seg(_toggle_items, not _dye_mode)
	_style_seg(_toggle_dyes, _dye_mode)


func _rebuild_tabs() -> void:
	for c in _tabs_box.get_children():
		c.queue_free()
	for pair in _tabs():
		var slot := String(pair[0])
		var b := _make_button(String(pair[1]), func() -> void: _set_tab(slot))
		b.set_meta("slot", slot)
		b.add_theme_font_size_override("font_size", 9)
		var f := UiFonts.grotesk(600)
		if f != null:
			b.add_theme_font_override("font", f)
		_style_tab(b, slot == _tab)
		_tabs_box.add_child(b)


func _refresh_tabs() -> void:
	for b in _tabs_box.get_children():
		_style_tab(b, String(b.get_meta("slot")) == _tab)


# ------------------------------------------------------------------ content
func _rebuild_content() -> void:
	for c in _content.get_children():
		c.queue_free()
	if _tab == "":
		return
	if _dye_mode:
		_build_dyes_view()
	else:
		_build_items_view()


# ---- ITEMS: header (name + owned count + equipped), rarity legend, 5-up try-on grid ----
func _build_items_view() -> void:
	var ids := _catalog.items_in_slot(_tab)
	var owned_n := 0
	for id in ids:
		if _appearance.is_owned(String(id)):
			owned_n += 1
	var equipped_id := String(_appearance.equipped.get(_tab, ""))

	var head := MarginContainer.new()
	_set_margins(head, 12, 9, 12, 4)
	_content.add_child(head)
	var head_col := VBoxContainer.new()
	head_col.add_theme_constant_override("separation", 1)
	head.add_child(head_col)

	var row1 := HBoxContainer.new()
	row1.add_child(_label(_tab_label(_tab), 11, INK_STRONG, 700))
	row1.add_child(_spacer())
	row1.add_child(_label("%d/%d owned" % [owned_n, ids.size()], 8, MUTED, 600))
	head_col.add_child(row1)

	var eq_name := "None"
	var eq_color: Color = RARITY_COLOR["common"]
	if equipped_id != "":
		eq_name = String(_catalog.item(equipped_id).get("name", equipped_id))
		eq_color = _rarity_color(equipped_id)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	row2.add_child(_label(eq_name, 9, eq_color, 600))
	row2.add_child(_label("equipped", 8, MUTED_2))
	head_col.add_child(row2)

	var legend_wrap := MarginContainer.new()
	_set_margins(legend_wrap, 12, 0, 12, 7)
	_content.add_child(legend_wrap)
	legend_wrap.add_child(_rarity_legend())

	var grid_wrap := MarginContainer.new()
	_set_margins(grid_wrap, 10, 0, 10, 9)
	grid_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(grid_wrap)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_wrap.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	# A non-required slot can be worn empty — "None" leads the grid as an unequip card.
	if not _catalog.slot_required(_tab):
		grid.add_child(_item_cell("", equipped_id == ""))
	for id in ids:
		grid.add_child(_item_cell(String(id), String(id) == equipped_id))


## One grid cell: a try-on thumbnail (the whole avatar wearing this item) framed in its rarity
## color. Owned items equip on tap; locked ones show a dark silhouette + padlock, inert.
func _item_cell(item_id: String, equipped: bool) -> Control:
	var owned := item_id == "" or _appearance.is_owned(item_id)
	var rarity := _rarity_color(item_id) if item_id != "" else RARITY_COLOR["common"] as Color
	var display_name := "None" if item_id == "" else String(_catalog.item(item_id).get("name", item_id))

	var cell := Button.new()
	cell.focus_mode = Control.FOCUS_NONE
	cell.tooltip_text = display_name
	cell.custom_minimum_size = Vector2(0, 44)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = CELL_EQUIPPED if equipped else (CELL_OWNED if owned else CELL_LOCKED)
	sb.set_border_width_all(3 if equipped else 2)
	sb.border_color = rarity
	sb.set_corner_radius_all(7)
	sb.set_content_margin_all(2)
	_set_button_boxes(cell, sb)
	cell.add_theme_stylebox_override("disabled", sb)
	if owned:
		var slot := _tab
		cell.pressed.connect(func() -> void: _pick_item(slot, item_id))
	else:
		cell.disabled = true

	var thumb := Thumb.new(_thumb_layers(item_id))
	thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
	thumb.offset_left = 2
	thumb.offset_top = 2
	thumb.offset_right = -2
	thumb.offset_bottom = -2
	if not owned:
		thumb.modulate = SILHOUETTE
	cell.add_child(thumb)

	var dot := RarityDot.new()
	dot.color = rarity
	dot.position = Vector2(3, 3)
	dot.size = Vector2(6, 6)
	cell.add_child(dot)

	if not owned:
		var lock := LockBadge.new()
		lock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		lock.position = Vector2(-12, 3)
		lock.size = Vector2(9, 10)
		cell.add_child(lock)
	return cell


## The try-on layers for a thumbnail: the CURRENT working look with just this one slot swapped
## (or bared, for the None card). Locked items still preview — the copy may "own" anything.
func _thumb_layers(item_id: String) -> Array:
	var work := PlayerAppearance.from_dict(_appearance.to_dict(), _catalog)
	if item_id == "":
		work.unequip(_catalog, _tab)
	else:
		work.owned[item_id] = true
		work.equip(_catalog, item_id)
	return AvatarCompositor.load_layers(work.resolved_layers(_catalog))


func _pick_item(slot: String, item_id: String) -> void:
	var changed := false
	if item_id == "":
		changed = _appearance.unequip(_catalog, slot)
	else:
		changed = _appearance.equip(_catalog, item_id)
	if changed:
		_after_change()


func _rarity_color(item_id: String) -> Color:
	var tier := String(_catalog.item(item_id).get("rarity", "common"))
	return RARITY_COLOR.get(tier, RARITY_COLOR["common"])


func _rarity_legend() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 3)
	for tier in RARITY_ORDER:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 3)
		var dot := RarityDot.new()
		dot.color = RARITY_COLOR[tier]
		dot.custom_minimum_size = Vector2(6, 6)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(dot)
		item.add_child(_label(String(tier).capitalize(), 8, LEGEND_TEXT))
		row.add_child(item)
	return row


# ---- DYES: swatches for whatever color slot targets this tab, plus the Skin tone row ----
func _build_dyes_view() -> void:
	var head := MarginContainer.new()
	_set_margins(head, 12, 9, 12, 6)
	_content.add_child(head)
	var head_col := VBoxContainer.new()
	head_col.add_theme_constant_override("separation", 1)
	head.add_child(head_col)
	head_col.add_child(_label(_tab_label(_tab) + " dye", 11, INK_STRONG, 700))
	head_col.add_child(_label("Tap a shade to recolor this piece", 8, MUTED_2))

	var body_wrap := MarginContainer.new()
	_set_margins(body_wrap, 12, 2, 12, 10)
	body_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(body_wrap)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_wrap.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var cs := _color_slot_for(_tab)
	if cs.is_empty():
		# This piece keeps its authored colors (e.g. the inked glasses) — say so, gently.
		var empty := VBoxContainer.new()
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.add_theme_constant_override("separation", 6)
		var brush := BrushIcon.new()
		brush.custom_minimum_size = Vector2(20, 20)
		brush.self_modulate = Color(1, 1, 1, 0.5)
		brush.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		empty.add_child(brush)
		var msg := _label("This piece has fixed colors and can't be dyed.", 9, Color("a89877"))
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD
		msg.custom_minimum_size = Vector2(150, 0)
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(msg)
		var pad := MarginContainer.new()
		_set_margins(pad, 9, 15, 9, 15)
		pad.add_child(empty)
		body.add_child(pad)
	else:
		body.add_child(_swatch_row(cs))

	# Skin tone — universal (it recolors *you*, not a garment), so it's always down here.
	var skin := _color_slot_for("body")
	if not skin.is_empty():
		body.add_child(_vspace(13))
		body.add_child(DashedLine.new())
		body.add_child(_vspace(10))
		body.add_child(_label("Skin tone", 9, Color("7c6e5b"), 600))
		body.add_child(_vspace(7))
		body.add_child(_swatch_row(skin))


## The color (palette) slot whose recolor targets this paper-doll slot, or {} if none does.
func _color_slot_for(slot: String) -> Dictionary:
	for cs in _catalog.color_slots():
		if String(cs.get("applies_to", "")) == slot:
			return cs
	return {}


func _swatch_row(cs: Dictionary) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	var slot_id := String(cs["id"])
	var current := String(_appearance.colors.get(slot_id, cs.get("default", "")))
	for ramp in cs.get("ramps", []):
		var rgb := _catalog.ramp_color(slot_id, String(ramp))
		if rgb.size() < 3:
			continue
		var sw := DyeSwatch.new()
		sw.color = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
		sw.active = String(ramp) == current
		var ramp_name := String(ramp)
		sw.picked.connect(func() -> void: _pick_dye(slot_id, ramp_name))
		row.add_child(sw)
	return row


func _pick_dye(slot_id: String, ramp: String) -> void:
	if _appearance.set_color(_catalog, slot_id, ramp):
		_after_change()


# ------------------------------------------------------------------ little widgets
func _label(text: String, sz: int, color: Color, weight := 400) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", color)
	var f := UiFonts.grotesk(weight)
	if f != null:
		l.add_theme_font_override("font", f)
	return l


func _pixel_label(text: String, sz: int, color: Color, spacing := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", color)
	var f := UiFonts.pixel(false, spacing)
	if f != null:
		l.add_theme_font_override("font", f)
	return l


func _make_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(on_press)
	return b


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _vspace(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _divider() -> Control:
	var c := ColorRect.new()
	c.color = DIVIDER
	c.custom_minimum_size = Vector2(0, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _set_margins(m: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)


func _set_button_boxes(b: Button, sb: StyleBox) -> void:
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, sb)


func _set_button_colors(b: Button, color: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(state, color)


func _style_seg(b: Button, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TAB_ON_BG if on else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(6)
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_set_button_boxes(b, sb)
	b.add_theme_font_size_override("font_size", 10)
	var f := UiFonts.grotesk(700)
	if f != null:
		b.add_theme_font_override("font", f)
	_set_button_colors(b, TAB_ON_TEXT if on else TOGGLE_IDLE_TEXT)


func _style_tab(b: Button, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TAB_ON_BG if on else TAB_IDLE_BG
	sb.set_corner_radius_all(999)
	sb.set_border_width_all(2)
	sb.border_color = TAB_ON_BG if on else TAB_IDLE_BORDER
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_set_button_boxes(b, sb)
	_set_button_colors(b, TAB_ON_TEXT if on else TAB_IDLE_TEXT)


## Thousands-separated coin amount ("1240" -> "1,240").
static func _format_amount(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The soft radial "clearing" the hero stands on (an ellipse via non-uniform stretch).
static func _make_clearing_texture() -> Texture2D:
	var g := Gradient.new()
	var dirt := Color(196.0 / 255.0, 166.0 / 255.0, 110.0 / 255.0)
	g.set_color(0, Color(dirt, 0.55))
	g.set_color(1, Color(dirt, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 128
	t.height = 128
	return t


# ------------------------------------------------------------------ inner draw pieces
## The world-side shadow: a horizontal wash that deepens toward the dock (the wireframe's
## three-stop gradient), drawn as vertex-colored bands so there's no texture to manage.
class DimLayer extends Control:
	const TINT := Color(24.0 / 255.0, 16.0 / 255.0, 10.0 / 255.0)

	func _init() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		_band(0.0, 0.34, 0.20, 0.05)
		_band(0.34, 0.62, 0.05, 0.34)
		_band(0.62, 1.0, 0.34, 0.34)

	func _band(x0: float, x1: float, a0: float, a1: float) -> void:
		var p0 := x0 * size.x
		var p1 := x1 * size.x
		var pts := PackedVector2Array([Vector2(p0, 0), Vector2(p1, 0), Vector2(p1, size.y), Vector2(p0, size.y)])
		var c0 := Color(TINT, a0)
		var c1 := Color(TINT, a1)
		draw_polygon(pts, PackedColorArray([c0, c1, c1, c0]))


## The dock chrome: rounded-left cream panel with a soft vertical gradient, an ink left
## border traced around the corners, and a shadow bleeding into the world.
class DockPanel extends Control:
	const RADIUS := 15.0
	const SEGS := 8
	const SHADOW := Color(20.0 / 255.0, 14.0 / 255.0, 8.0 / 255.0, 0.35)

	func _init() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := RADIUS
		# shadow into the world
		var sp := PackedVector2Array([Vector2(-16, 0), Vector2(0, 0), Vector2(0, h), Vector2(-16, h)])
		draw_polygon(sp, PackedColorArray([Color(SHADOW, 0.0), SHADOW, SHADOW, Color(SHADOW, 0.0)]))
		# panel body (vertex colors give the vertical gradient)
		var pts := PackedVector2Array()
		for i in SEGS + 1:   # top-left corner arc: 180° → 270°
			var a := PI + float(i) / SEGS * (PI / 2.0)
			pts.append(Vector2(r + cos(a) * r, r + sin(a) * r))
		pts.append(Vector2(w, 0))
		pts.append(Vector2(w, h))
		for i in SEGS + 1:   # bottom-left corner arc: 90° → 180°
			var a := PI / 2.0 + float(i) / SEGS * (PI / 2.0)
			pts.append(Vector2(r + cos(a) * r, h - r + sin(a) * r))
		var cols := PackedColorArray()
		for p in pts:
			cols.append(AvatarCustomizer.PANEL_TOP.lerp(AvatarCustomizer.PANEL_BOTTOM, clampf(p.y / h, 0.0, 1.0)))
		draw_polygon(pts, cols)
		# ink left border, curving with the corners
		var edge := PackedVector2Array()
		for i in SEGS + 1:   # 270° → 180° (top corner, from the top edge down to the left edge)
			var a := PI * 1.5 - float(i) / SEGS * (PI / 2.0)
			edge.append(Vector2(r + cos(a) * r, r + sin(a) * r))
		for i in SEGS + 1:   # 180° → 90° (left edge around to the bottom edge)
			var a := PI - float(i) / SEGS * (PI / 2.0)
			edge.append(Vector2(r + cos(a) * r, h - r + sin(a) * r))
		draw_polyline(edge, AvatarCustomizer.INK, 2.0, true)


## A static try-on portrait: the avatar drawn through the real compositor at the idle pose,
## integer-scaled and centred — the thumbnail equivalent of AvatarPreview without the walk.
class Thumb extends Control:
	var layers: Array = []

	func _init(p_layers: Array) -> void:
		layers = p_layers
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		resized.connect(queue_redraw)

	func _draw() -> void:
		if layers.is_empty():
			return
		var s := maxf(1.0, floorf(minf(size.x, size.y) / 32.0))
		var origin := Vector2(size.x * 0.5, size.y * 0.5 + 16.0 * s)   # sprite feet sit at the origin
		draw_set_transform(origin, 0.0, Vector2(s, s))
		AvatarCompositor.draw(self, layers, { "facing": Vector2.DOWN, "speed": 0.0, "time": 0.0 })
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A rarity marker: filled dot with a soft white ring (legend + cell corners).
class RarityDot extends Control:
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r - 0.5, color)
		draw_arc(c, r - 0.5, 0, TAU, 16, Color(1, 1, 1, 0.6), 1.0)


## The little padlock on cells you don't own yet.
class LockBadge extends Control:
	const BODY := Color("efe7d6")
	const RING := Color("241813")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_arc(Vector2(4.5, 4.0), 2.2, PI, TAU, 10, RING, 2.6)
		draw_arc(Vector2(4.5, 4.0), 2.2, PI, TAU, 10, BODY, 1.2)
		draw_rect(Rect2(0.5, 4.0, 8.0, 6.0), RING)
		draw_rect(Rect2(1.5, 5.0, 6.0, 4.0), BODY)


## A dye swatch: a color disc; the active one gets the ink ring + inner white keyline.
class DyeSwatch extends Control:
	signal picked
	var color := Color.WHITE
	var active := false

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			picked.emit()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		if active:
			draw_circle(c, r - 2.0, color)
			draw_arc(c, r - 2.5, 0, TAU, 24, Color.WHITE, 2.0)
			draw_arc(c, r - 0.8, 0, TAU, 24, AvatarCustomizer.INK, 1.8)
		else:
			draw_circle(c, r - 1.0, color)
			draw_arc(c, r - 1.2, 0, TAU, 24, Color(0, 0, 0, 0.22), 1.0)


## A dashed rule (the Skin-tone separator).
class DashedLine extends Control:
	var color := Color("e2d6bd")

	func _init() -> void:
		custom_minimum_size = Vector2(0, 1)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var x := 0.0
		while x < size.x:
			draw_rect(Rect2(x, 0, minf(4.0, size.x - x), 1.0), color)
			x += 8.0


## The gem in the coin badge — a filled diamond inside a diamond outline (the ◈ glyph, drawn
## by hand so it never depends on font coverage).
class GemIcon extends Control:
	var color := Color("f2c65a")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 0.5
		var outer := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)])
		draw_polyline(outer, color, 1.0)
		var r2 := r * 0.45
		var inner := PackedVector2Array([c + Vector2(0, -r2), c + Vector2(r2, 0), c + Vector2(0, r2), c + Vector2(-r2, 0)])
		draw_polygon(inner, PackedColorArray([color]))


## A tiny paintbrush for the "can't be dyed" empty state (again hand-drawn, no emoji font).
class BrushIcon extends Control:
	var color := Color("a89877")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_line(Vector2(15, 3), Vector2(9, 9), color, 2.0)                     # handle
		draw_line(Vector2(9, 9), Vector2(6.5, 11.5), color.darkened(0.15), 3.0)  # ferrule
		var tip := PackedVector2Array([Vector2(6, 10), Vector2(8, 12), Vector2(3, 17)])
		draw_polygon(tip, PackedColorArray([color]))                             # bristles
