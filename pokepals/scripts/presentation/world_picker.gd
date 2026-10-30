class_name WorldPicker
extends Control
## The Gateway's world picker: a cozy, searchable list of every world you can travel to from the hub.
## Opened when you walk into the Vale's Gateway. A search box at the top; below it the worlds as cards
## (accent dot · name · one-line blurb · a live "N here"), shelved Featured / All worlds while browsing
## and as one list of matches while searching; tap a card to go.
##
## A thin PRESENTATION surface over WorldDirectory (the search state: request numbering, pages,
## shelving). It never talks to the network: it emits `fetch_requested` and the world controller relays
## that to Net.list_worlds, then hands the answer back through receive(). Choosing a world emits
## `world_chosen`; the controller does the actual travel. Built in code so it drops into any scene.
##
## It arrives and leaves SOFTLY: the world dims into a dusky wash of the gate's colour while the panel
## fades in and settles, and backing out plays that in reverse. Picking a world melts the panel away
## while the controller fades the screen to black for the trip. All of it is tweens on this node. The
## world is NOT paused under it (it's shared); the controller just stands your own steering down.

## Ask the server for a page of the directory (relayed to Net.list_worlds).
signal fetch_requested(query: String, req: int, offset: int)
## The player picked a world to travel to.
signal world_chosen(world_id: String, world_name: String)
## The player backed out (Stay here / Esc). The world resumes.
signal closed()

## How long typing must pause before the search is sent (so "riverbank" isn't nine requests).
const SEARCH_DEBOUNCE := 0.25
const PANEL_W := 380.0
const LIST_H := 190.0
## How far the panel drifts up into place as it appears, and the scale it settles from.
const SETTLE_RISE := 6.0
const SETTLE_SCALE := 0.96

## The arrival / back-out fade lengths in seconds (the smoke test sets these to 0 to skip the waits).
var fade_in_time := 0.35
var fade_out_time := 0.22
## The gate's colour; the backdrop is a deep, dusky wash of it rather than a flat dark. Set before adding.
var tint := Color(0.8, 0.74, 0.98)

var _dir := WorldDirectory.new()
var _search: LineEdit
var _list: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _debounce: Timer
var _backdrop: ColorRect
var _center: CenterContainer
var _chosen := false  # latched once a world is picked, so a double-tap can't fire two trips


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_render()
	_fade_in()
	# On a keyboard device, land straight in the search box; on touch, don't pop the on-screen keyboard
	# until the player actually taps the box.
	if not DisplayServer.is_touchscreen_available():
		_search.grab_focus()
	_send(_dir.begin_search(""))


## The server answered a directory request. Stale answers (a search since replaced) are ignored.
func receive(req: int, offset: int, worlds: Array, more: bool) -> void:
	if _dir.accept(req, offset, worlds, more):
		_render()


func _exit_tree() -> void:
	# The status line is parked out of the tree whenever there are cards; free it with the picker.
	if _status != null and not _status.is_inside_tree():
		_status.free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


# --- building -----------------------------------------------------------------------------

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	var dusk := tint.darkened(0.72)
	_backdrop.color = Color(dusk.r, dusk.g, dusk.b, 0.62)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	# A CenterContainer keeps the panel centred however the window is sized.
	_center = CenterContainer.new()
	var center := _center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box(12, 12.0))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(PANEL_W, 0)
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var eyebrow := UiStyle.pixel_label("THE GREAT GATE", 7, UiStyle.ACCENT_RUST, 1)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(eyebrow)
	var title := UiStyle.label("Where to?", 13, UiStyle.INK_STRONG, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_search = LineEdit.new()
	_search.placeholder_text = "Search worlds…"
	_search.clear_button_enabled = true
	UiStyle.set_font(_search, 500, 10)
	_search.add_theme_color_override("font_color", UiStyle.INK_STRONG)
	_search.add_theme_color_override("font_placeholder_color", UiStyle.MUTED_2)
	_search.add_theme_color_override("caret_color", UiStyle.INK)
	var field := StyleBoxFlat.new()
	field.bg_color = UiStyle.PILL_BG
	field.set_border_width_all(2)
	field.border_color = UiStyle.PILL_BORDER
	field.set_corner_radius_all(8)
	field.content_margin_left = 10
	field.content_margin_right = 8
	field.content_margin_top = 4
	field.content_margin_bottom = 4
	_search.add_theme_stylebox_override("normal", field)
	var focused := field.duplicate() as StyleBoxFlat
	focused.border_color = UiStyle.GOLD
	_search.add_theme_stylebox_override("focus", focused)
	_search.text_changed.connect(_on_search_changed)
	box.add_child(_search)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, LIST_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	_scroll.add_child(_list)

	_status = UiStyle.label("", 9, UiStyle.MUTED, 500)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var stay := Button.new()
	stay.text = "Stay in the Vale"
	UiStyle.pill_button(stay, 10)
	stay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stay.pressed.connect(_close)
	box.add_child(stay)

	# A one-shot Timer restarted on every keystroke: the search only fires once typing settles.
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = SEARCH_DEBOUNCE
	_debounce.timeout.connect(func() -> void: _send(_dir.begin_search(_search.text)))
	add_child(_debounce)


## Redraw the list from the directory state: shelves of cards, a status line when there are none,
## and a "Show more" pill when the server has another page.
func _render() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		if child != _status:
			child.queue_free()
	var status := _dir.status_text()
	if status != "":
		_status.text = status
		_list.add_child(_status)
	for section in _dir.sections():
		var heading := UiStyle.pixel_label(String(section["title"]).to_upper(), 6, UiStyle.LABEL_BROWN, 1)
		_list.add_child(heading)
		for w in section["worlds"]:
			_list.add_child(_card(w))
	if _dir.has_more():
		var more := Button.new()
		more.text = "Loading…" if _dir.is_loading() else "Show more"
		more.disabled = _dir.is_loading()
		UiStyle.pill_button(more, 9)
		more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		more.pressed.connect(func() -> void: _send(_dir.begin_more()))
		_list.add_child(more)


## One world as a tappable card. The whole card is the Button (a big touch target); everything drawn
## inside it ignores the mouse so a tap anywhere on it lands on the button.
func _card(w: Dictionary) -> Button:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(0, 40)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiStyle.PILL_BG
	sb.set_border_width_all(2)
	sb.border_width_bottom = 3
	sb.border_color = UiStyle.PILL_BORDER
	sb.set_corner_radius_all(8)
	var pressed := sb.duplicate() as StyleBoxFlat
	pressed.bg_color = UiStyle.PILL_BG.darkened(0.06)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.border_color = UiStyle.GOLD
	UiStyle.set_button_boxes(card, sb, pressed)
	card.add_theme_stylebox_override("hover", hover)
	card.pressed.connect(_on_card_pressed.bind(String(w["world_id"]), String(w["name"])))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -8
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = _accent(w["accent"])
	dsb.set_corner_radius_all(999)
	dsb.set_border_width_all(1)
	dsb.border_color = Color(0, 0, 0, 0.25)
	dot.add_theme_stylebox_override("panel", dsb)
	row.add_child(dot)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var name_label := UiStyle.label(String(w["name"]), 10, UiStyle.INK_STRONG, 700)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(name_label)
	if String(w["blurb"]) != "":
		var blurb := UiStyle.label(String(w["blurb"]), 8, UiStyle.MUTED, 500)
		blurb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		blurb.clip_text = true
		blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(blurb)

	# The live head-count: a warm pill when someone's there, a quiet word when no one is.
	var players := int(w["players"])
	var here := UiStyle.label(WorldDirectory.presence_text(players), 8, UiStyle.INK if players > 0 else UiStyle.MUTED_2, 700)
	here.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	here.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if players > 0:
		var pill := StyleBoxFlat.new()
		pill.bg_color = UiStyle.GEM_GOLD
		pill.set_corner_radius_all(999)
		pill.content_margin_left = 6
		pill.content_margin_right = 6
		pill.content_margin_top = 1
		pill.content_margin_bottom = 1
		here.add_theme_stylebox_override("normal", pill)
	row.add_child(here)
	return card


# --- events -------------------------------------------------------------------------------

func _on_search_changed(_text: String) -> void:
	_debounce.start()


func _on_card_pressed(world_id: String, world_name: String) -> void:
	if _chosen:
		return
	_chosen = true
	world_chosen.emit(world_id, world_name)
	# The panel melts away while the controller fades the screen to black for the trip; the dusky
	# backdrop stays, so the world never flashes back into view on the way out.
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_center, "modulate:a", 0.0, 0.3)


func _close() -> void:
	if _chosen:
		return
	_chosen = true
	_fade_out(closed.emit)


# --- the soft arrival / departure ----------------------------------------------------------

## Start hidden, then (once the container has laid the panel out, so its centre is known) dim the world
## in and let the panel fade up, drifting a few pixels into place as it settles to full size.
func _fade_in() -> void:
	_backdrop.modulate.a = 0.0
	_center.modulate.a = 0.0
	if fade_in_time <= 0.0:
		_backdrop.modulate.a = 1.0
		_center.modulate.a = 1.0
		return
	# Containers size their children at the end of the frame, so wait one before reading the size.
	await get_tree().process_frame
	if not is_inside_tree() or _chosen:
		return
	_center.pivot_offset = _center.size * 0.5  # scale around the middle of the screen, not the corner
	_center.scale = Vector2.ONE * SETTLE_SCALE
	_center.position.y = SETTLE_RISE
	# set_parallel: every property below animates at once. EASE_OUT: quick at first, gently landing.
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_backdrop, "modulate:a", 1.0, fade_in_time)
	tw.tween_property(_center, "modulate:a", 1.0, fade_in_time)
	tw.tween_property(_center, "scale", Vector2.ONE, fade_in_time)
	tw.tween_property(_center, "position:y", 0.0, fade_in_time)


## The arrival in reverse (a touch quicker), then `then` — the world resumes once the panel is gone.
func _fade_out(then: Callable) -> void:
	if fade_out_time <= 0.0:
		then.call()
		return
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_backdrop, "modulate:a", 0.0, fade_out_time)
	tw.tween_property(_center, "modulate:a", 0.0, fade_out_time)
	tw.tween_property(_center, "scale", Vector2.ONE * SETTLE_SCALE, fade_out_time)
	tw.tween_property(_center, "position:y", SETTLE_RISE, fade_out_time)
	tw.chain().tween_callback(then)  # chain(): run after the parallel group finishes


func _send(req: int) -> void:
	if req < 0:
		return
	_render()
	fetch_requested.emit(_dir.query(), req, _dir.next_offset())


static func _accent(accent: Variant) -> Color:
	if accent is Array and (accent as Array).size() >= 3:
		return Color(float(accent[0]), float(accent[1]), float(accent[2]))
	return Color(0.74, 0.66, 0.96)
