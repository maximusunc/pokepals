class_name WelcomePanel
extends CozySheet
## The newcomer's CARDS: a few short, warm pages that tell someone what Kithbound is and what to do
## next. Each is one named card from data/welcome.json, and a panel plays any sequence of them:
##   * "welcome"  right after the connection gate, for a brand-new player, with a live portrait of
##                their starting look; its button leads into the wardrobe
##   * "find"     as the search for their companion begins
##   * "explore"  after bonding, once the Gateway has appeared
##   * all three  again from the gear menu's Welcome (a reread: no wardrobe, no search)
## The world controller decides when each plays; this script only lays the words out. Pure
## presentation.

## The reader pressed the last card's button (not emitted when a reread is waved away early).
signal finished()

const DATA_PATH := "res://data/welcome.json"
const PAGE_MIN_HEIGHT := 190.0  # keeps the card from jumping in size between pages

## Which cards to play, in order (keys of "cards" in data/welcome.json).
var card_ids: Array = []
## The last card's button label. "" uses that card's own "button".
var final_button := ""
## For a card with show_avatar: the player's look, and the catalog it resolves against.
var avatar: PlayerAppearance = null
var catalog: CosmeticsCatalog = null

var _cards: Array = []
var _index := 0
var _page: VBoxContainer
var _dots: HBoxContainer
var _back: Button
var _next: Button


func _build() -> void:
	width = 320.0
	var data := WelcomePanel.load_data()
	var all: Dictionary = data.get("cards", {})
	for id in card_ids:
		if all.has(id):
			_cards.append(all[id])
	if _cards.is_empty():
		_cards.append({ "heading": "Welcome to Kithbound." })
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


## The cards' words, from data/welcome.json. An empty dictionary if the file is missing or broken
## (a panel then shows a single fallback line rather than nothing).
static func load_data() -> Dictionary:
	var text := FileAccess.get_file_as_string(DATA_PATH)
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if parsed is Dictionary:
		return parsed
	push_warning("WelcomePanel: couldn't read %s" % DATA_PATH)
	return {}


func _show_page(i: int) -> void:
	_index = clampi(i, 0, _cards.size() - 1)
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	var card: Dictionary = _cards[_index]
	# The welcome shows YOU ("this is you"); the other cards keep the loading screen's little fox.
	if bool(card.get("show_avatar", false)) and avatar != null and catalog != null:
		var portrait := AvatarPreview.new()
		portrait.pixel_scale = 2.0
		portrait.custom_minimum_size = Vector2(80, 84)  # feet sit 8px*scale below centre
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page.add_child(portrait)
		portrait.show_appearance(avatar, catalog)
	else:
		var fox := TrottingFox.new(1)
		fox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_page.add_child(fox)
	if String(card.get("eyebrow", "")) != "":
		var eb := UiStyle.pixel_label(String(card["eyebrow"]).to_upper(), 7, UiStyle.ACCENT_RUST, 1)
		eb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_page.add_child(eb)
	var h := UiStyle.label(String(card.get("heading", "")), 13, UiStyle.INK_STRONG, 700)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(h)
	for para in card.get("body", []):
		var l := note(String(para), _page, UiStyle.INK_SOFT)
		l.add_theme_font_size_override("font_size", 10)
	if String(card.get("tip", "")) != "":
		note(String(card["tip"]), _page)
	_refresh_controls()


func _refresh_controls() -> void:
	for c in _dots.get_children():
		_dots.remove_child(c)
		c.queue_free()
	if _cards.size() > 1:
		for i in _cards.size():
			var dot := Panel.new()
			dot.custom_minimum_size = Vector2(6, 6)
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiStyle.INK if i == _index else UiStyle.PILL_BORDER
			sb.set_corner_radius_all(999)
			dot.add_theme_stylebox_override("panel", sb)
			_dots.add_child(dot)
	_back.visible = _index > 0
	if _is_last():
		var own := String((_cards[_index] as Dictionary).get("button", "Close"))
		_next.text = final_button if final_button != "" else own
	else:
		_next.text = "Next"


func _is_last() -> bool:
	return _index >= _cards.size() - 1


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
## world underneath (where Enter would Examine). Esc still closes a non-modal panel (CozySheet).
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
