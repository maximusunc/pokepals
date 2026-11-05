class_name WelcomePanel
extends CozySheet
## The WELCOME: a few short pages that tell a newcomer what Kithbound is and what to do first. A
## brand-new player sees it right after the connection gate and before choosing their look (the world
## controller opens it from PresenceDirector.needs_creation, then the wardrobe on `finished`); anyone
## can read it again from the gear menu.
##
## The words live in data/welcome.json, so they can be edited without touching code; this script only
## lays them out. Pure presentation.

## The reader reached the end and pressed the last button (not emitted when dismissed early).
signal finished()

const DATA_PATH := "res://data/welcome.json"
const PAGE_MIN_HEIGHT := 150.0  # keeps the card from jumping in size as the pages change

## True for the first-run welcome: it can't be waved away (it leads into choosing your look), and the
## last button reads "finish_first_run". False when reopened from the gear menu.
var first_run := false

var _data: Dictionary = {}
var _pages: Array = []
var _index := 0
var _page: VBoxContainer
var _dots: HBoxContainer
var _back: Button
var _next: Button


func _build() -> void:
	width = 320.0
	modal = first_run
	_data = WelcomePanel.load_data()
	_pages = _data.get("pages", [])
	var fox := TrottingFox.new(1)
	fox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(fox)
	_page = VBoxContainer.new()
	_page.custom_minimum_size = Vector2(0, PAGE_MIN_HEIGHT)
	_page.add_theme_constant_override("separation", 6)
	body.add_child(_page)
	_dots = HBoxContainer.new()
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.add_theme_constant_override("separation", 5)
	body.add_child(_dots)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	_back = CozySheet.pill("Back", _go_back, false, 10)
	_next = CozySheet.pill("Next", _go_next, true, 10)
	buttons.add_child(_back)
	buttons.add_child(_next)
	body.add_child(buttons)
	_show_page(0)


## The welcome's words, from data/welcome.json. An empty dictionary if the file is missing or broken
## (the panel then shows a single fallback line rather than nothing).
static func load_data() -> Dictionary:
	var text := FileAccess.get_file_as_string(DATA_PATH)
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if parsed is Dictionary:
		return parsed
	push_warning("WelcomePanel: couldn't read %s" % DATA_PATH)
	return {}


func _show_page(i: int) -> void:
	_index = clampi(i, 0, maxi(0, _pages.size() - 1))
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	var page: Dictionary = _pages[_index] if _index < _pages.size() else { "heading": "Welcome to Kithbound." }
	if String(page.get("eyebrow", "")) != "":
		var eb := UiStyle.pixel_label(String(page["eyebrow"]).to_upper(), 7, UiStyle.ACCENT_RUST, 1)
		eb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_page.add_child(eb)
	var h := UiStyle.label(String(page.get("heading", "")), 13, UiStyle.INK_STRONG, 700)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(h)
	for para in page.get("body", []):
		var l := note(String(para), _page, UiStyle.INK_SOFT)
		l.add_theme_font_size_override("font_size", 10)
	if String(page.get("tip", "")) != "":
		note(String(page["tip"]), _page)
	_refresh_controls()


func _refresh_controls() -> void:
	for c in _dots.get_children():
		_dots.remove_child(c)
		c.queue_free()
	if _pages.size() > 1:
		for i in _pages.size():
			var dot := Panel.new()
			dot.custom_minimum_size = Vector2(6, 6)
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiStyle.INK if i == _index else UiStyle.PILL_BORDER
			sb.set_corner_radius_all(999)
			dot.add_theme_stylebox_override("panel", sb)
			_dots.add_child(dot)
	_back.visible = _index > 0
	if _is_last():
		var key := "finish_first_run" if first_run else "finish_again"
		_next.text = String(_data.get(key, "Choose your look" if first_run else "Close"))
	else:
		_next.text = "Next"


func _is_last() -> bool:
	return _index >= _pages.size() - 1


func _go_next() -> void:
	if _closed:
		return  # already fading out; a second press mustn't finish twice
	if _is_last():
		finished.emit()
		close()
	else:
		_show_page(_index + 1)


func _go_back() -> void:
	if _index > 0:
		_show_page(_index - 1)


## Keyboard paging: Enter/Space or → for Next, ← for Back. Claimed here so they don't also reach the
## world underneath (where Enter would Examine). Esc still closes a non-first-run welcome (CozySheet).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_go_next()
		return
	if event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_go_back()
		return
	super._unhandled_input(event)
