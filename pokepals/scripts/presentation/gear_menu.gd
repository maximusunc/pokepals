class_name GearMenu
extends Control
## The top-left corner and the MENU SHEET. The corner holds a round Menu button and, beside it, a little
## chip naming where you are ("The Vale · 2 here"). The Menu button slides a cream sheet in from the right
## edge with everything that isn't about the pet or the world: your name and friend code up top; the
## everyday things as big tiles (Bag, Wardrobe, Journal), then Friends, Sound and the Guide; Return to
## the Vale where a world offers it; and at the foot Leave, set apart in rust, beside a folded-away
## Developer row (New Companion, the inside view, the debug readout).
##
## (The class keeps its old name, GearMenu, from when this was a cog in the top-right corner.)
##
## Pure presentation: the controller pushes the items that apply right now (set_items, each already gated)
## and the corner's place (set_place), and listens for `item_selected`. This node owns opening and closing.

signal item_selected(id: String)
signal opened  ## the sheet slid open, so the controller can close the companion's shapes row

const MARGIN := 10.0
const BUTTON := 44.0
const CHIP_H := 28.0
const PAD := 12.0
const TILE_H := 58.0
const ROW_H := 34.0

## The six tiles, in order; the first three are the everyday ones and stand out.
const GRID_ORDER := ["bag", "wardrobe", "journal", "friends", "sound", "welcome"]
const PRIMARY := ["bag", "wardrobe", "journal"]
const DEV := ["new_companion", "perspective", "dbg"]
const ICONS := {
	"bag": "bag", "wardrobe": "wardrobe", "journal": "journal", "friends": "friends", "sound": "sound",
	"welcome": "guide", "leave": "leave", "return": "return",
}
const NAMES := { "welcome": "Guide", "leave": "Leave" }

var _menu_btn: HudTile
var _chip: Control
var _catcher: Control
var _sheet: Control
var _items: Array = []      # [{id, label}]
var _signature := ""
var _open := false
var _dev_open := false
var _place_name := ""
var _place_count := 0
var _profile_name := ""
var _profile_code := ""
var _portrait_tex: Texture2D
var _portrait_region := Rect2()
var _slide: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Tap-away: a dimmer over the world while the sheet is open; a tap on it closes the sheet.
	_catcher = Control.new()
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.visible = false
	_catcher.gui_input.connect(_on_catcher_input)
	_catcher.draw.connect(func() -> void: _catcher.draw_rect(Rect2(Vector2.ZERO, _catcher.size), Color(0.09, 0.11, 0.07, 0.42)))
	add_child(_catcher)

	_menu_btn = HudTile.new()
	_menu_btn.look = "round"
	_menu_btn.icon = "menu"
	_menu_btn.icon_size = 24.0
	_menu_btn.size = Vector2(BUTTON, BUTTON)
	_menu_btn.pressed.connect(_toggle)
	add_child(_menu_btn)

	_chip = Control.new()
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.draw.connect(_draw_chip)
	add_child(_chip)

	_sheet = Control.new()
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP  # taps on the sheet's empty space stay on the sheet
	_sheet.visible = false
	_sheet.draw.connect(_draw_sheet)
	add_child(_sheet)

	_layout.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout()


func _layout() -> void:
	_menu_btn.position = Vector2(MARGIN, MARGIN)
	_layout_chip()
	if _open:
		_build_sheet()
		_sheet.position.x = size.x - _sheet.size.x


## Where you are, for the corner chip: the world's name and how many people are here (you included).
## Cheap to call every frame: it only redraws on a change.
func set_place(world_name: String, count: int) -> void:
	if world_name == _place_name and count == _place_count:
		return
	_place_name = world_name
	_place_count = count
	_layout_chip()


## Your name and friend code, for the top of the sheet.
func set_profile(player_name: String, code: String) -> void:
	if player_name == _profile_name and code == _profile_code:
		return
	_profile_name = player_name
	_profile_code = code
	if _open:
		_build_sheet()


## The companion's picture beside your name (a frame of the animal it's wearing; null for none).
func set_portrait(tex: Texture2D, region: Rect2) -> void:
	if tex == _portrait_tex and region == _portrait_region:
		return
	_portrait_tex = tex
	_portrait_region = region
	if _open:
		_build_sheet()


## The items to offer right now, each already gated by the controller: { id, label }. Rebuilds the open
## sheet if the set changed.
func set_items(items: Array) -> void:
	var sig := ""
	var next: Array = []
	for it in items:
		next.append({ "id": String(it["id"]), "label": String(it["label"]) })
		sig += String(it["id"]) + ":" + String(it["label"]) + "|"
	if sig == _signature:
		return
	_signature = sig
	_items = next
	if _open:
		_build_sheet()


func _toggle() -> void:
	if _open:
		_close()
	else:
		_open_sheet()


func _open_sheet() -> void:
	_open = true
	_dev_open = false
	_catcher.visible = true
	_catcher.queue_redraw()
	_build_sheet()
	_sheet.visible = true
	_sheet.position.x = size.x
	_slide_to(size.x - _sheet.size.x)
	opened.emit()


## Close the sheet if it's open (public so the controller can dismiss it).
func close() -> void:
	_close()


func is_open() -> bool:
	return _open


func _close() -> void:
	if not _open:
		return
	_open = false
	_catcher.visible = false
	var tw := _slide_to(size.x)
	tw.tween_callback(func() -> void:
		if not _open:
			_sheet.visible = false
			_clear_sheet())


func _slide_to(x: float) -> Tween:
	if _slide != null and _slide.is_valid():
		_slide.kill()
	_slide = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide.tween_property(_sheet, "position:x", x, 0.18)
	return _slide


func _on_catcher_input(event: InputEvent) -> void:
	var tap: bool = event is InputEventMouseButton and event.pressed
	var touch: bool = event is InputEventScreenTouch and event.pressed
	if tap or touch:
		_close()
		accept_event()


# ── the corner chip ──

func _layout_chip() -> void:
	if _chip == null:
		return
	var font := UiFonts.grotesk(700)
	var w := 0.0
	if _place_name != "" and font != null:
		w = 30.0 + font.get_string_size(_place_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0
		if _place_count > 1:
			w += UiFonts.grotesk(500).get_string_size(_here_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 4.0
	_chip.visible = w > 0.0
	_chip.position = Vector2(MARGIN + BUTTON + 6.0, MARGIN + (BUTTON - CHIP_H) * 0.5)
	_chip.size = Vector2(w, CHIP_H)
	_chip.queue_redraw()


func _here_text() -> String:
	return "· %d here" % _place_count


func _draw_chip() -> void:
	var r := Rect2(Vector2.ZERO, _chip.size)
	var sb := UiStyle.hud_box(int(CHIP_H * 0.5))
	sb.anti_aliasing = true
	_chip.draw_style_box(sb, r)
	HudIcons.draw(_chip, "compass", Vector2(16, CHIP_H * 0.5 - 1.0), 15.0, UiStyle.INK_SOFT)
	var bold := UiFonts.grotesk(700)
	if bold == null:
		return
	var base := CHIP_H * 0.5 + 3.0
	_chip.draw_string(bold, Vector2(28, base), _place_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiStyle.INK_SOFT)
	if _place_count > 1:
		var x := 28.0 + bold.get_string_size(_place_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 4.0
		_chip.draw_string(UiFonts.grotesk(500), Vector2(x, base), _here_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiStyle.LABEL_BROWN)


# ── the sheet ──

func _clear_sheet() -> void:
	for c in _sheet.get_children():
		c.queue_free()


func _has(id: String) -> bool:
	for it in _items:
		if String(it["id"]) == id:
			return true
	return false


func _label_of(id: String) -> String:
	if NAMES.has(id):
		return String(NAMES[id])
	for it in _items:
		if String(it["id"]) == id:
			return String(it["label"])
	return id.capitalize()


func _build_sheet() -> void:
	_clear_sheet()
	var w := clampf(size.x * 0.42, 260.0, 330.0)
	_sheet.size = Vector2(w, size.y)
	var inner := w - PAD * 2.0
	var y := PAD

	# Who you are, with your companion's picture, and the close button.
	var portrait := HudTile.new()
	portrait.look = "quiet"
	portrait.radius = 17.0
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.size = Vector2(34, 34)
	portrait.position = Vector2(PAD, y)
	if _portrait_tex != null:
		portrait.set_sprite(_portrait_tex, _portrait_region, 30.0 / maxf(_portrait_region.size.y, 1.0))
	_sheet.add_child(portrait)
	var who := UiStyle.label(_profile_name if _profile_name != "" else "You", 13, UiStyle.INK_STRONG, 700)
	who.position = Vector2(PAD + 42, y)
	who.clip_text = true
	who.size = Vector2(inner - 42 - 40, 18)
	_sheet.add_child(who)
	if _profile_code != "":
		var code := UiStyle.label("Friend code %s" % _profile_code, 10, UiStyle.LABEL_BROWN, 500)
		code.position = Vector2(PAD + 42, y + 17)
		_sheet.add_child(code)
	var close_btn := _tile("ghost", "close", "", Vector2(PAD + inner - 34, y), Vector2(34, 34))
	close_btn.icon_size = 16.0
	close_btn.radius = 17.0
	close_btn.pressed.connect(_close)
	y += 34 + 12

	if _dev_open:
		# The folded-away tools, as plain rows in the tiles' place.
		for id in DEV:
			if not _has(id):
				continue
			var row := _tile("quiet", "", _label_of(id), Vector2(PAD, y), Vector2(inner, ROW_H))
			row.font_size = 11
			row.pressed.connect(_pick.bind(id))
			y += ROW_H + 6
	else:
		var gap := 6.0
		var tw := (inner - gap * 2.0) / 3.0
		var k := 0
		for id in GRID_ORDER:
			if not _has(id):
				continue
			var at := Vector2(PAD + float(k % 3) * (tw + gap), y + float(k / 3) * (TILE_H + gap))
			var tile := _tile("primary" if id in PRIMARY else "quiet", String(ICONS.get(id, "")), _label_of(id), at, Vector2(tw, TILE_H))
			tile.icon_size = 20.0
			tile.font_size = 11
			tile.pressed.connect(_pick.bind(id))
			k += 1
		if k > 0:
			y += float((k + 2) / 3) * (TILE_H + gap) + 2.0
		if _has("return"):
			var ret := _tile("quiet", "return", _label_of("return"), Vector2(PAD, y), Vector2(inner, ROW_H))
			ret.icon_size = 16.0
			ret.pressed.connect(_pick.bind("return"))
			y += ROW_H + 6

	# The foot: the Developer fold, and Leave set apart.
	var foot_y := size.y - PAD - ROW_H - 2.0
	var leave_w := 0.0
	if _has("leave"):
		leave_w = 86.0
		var leave := _tile("danger", "leave", _label_of("leave"), Vector2(PAD + inner - leave_w, foot_y), Vector2(leave_w, ROW_H))
		leave.icon_size = 15.0
		leave.pressed.connect(_pick.bind("leave"))
	var any_dev := false
	for id in DEV:
		any_dev = any_dev or _has(id)
	if any_dev:
		var dev_w := inner - (leave_w + 8.0 if leave_w > 0.0 else 0.0)
		var dev := _tile("ghost", "dev", "Back" if _dev_open else "Developer", Vector2(PAD, foot_y), Vector2(dev_w, ROW_H))
		dev.icon_size = 15.0
		dev.font_size = 11
		dev.pressed.connect(func() -> void:
			_dev_open = not _dev_open
			_build_sheet())
	_sheet.queue_redraw()


func _tile(look: String, icon: String, label: String, at: Vector2, sz: Vector2) -> HudTile:
	var t := HudTile.new()
	t.look = look
	t.icon = icon
	t.text = label
	t.position = at
	t.size = sz
	_sheet.add_child(t)
	return t


func _pick(id: String) -> void:
	item_selected.emit(id)
	_close()


func _draw_sheet() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiStyle.PANEL_TOP
	sb.corner_radius_top_left = 16
	sb.corner_radius_bottom_left = 16
	sb.border_width_left = 3
	sb.border_color = UiStyle.HUD_BORDER
	sb.anti_aliasing = true
	_sheet.draw_style_box(sb, Rect2(Vector2.ZERO, _sheet.size))


## The interactive Controls the joystick must exclude (the catcher covers the open sheet too).
func tap_targets() -> Array:
	return [_menu_btn, _catcher]


## The corner's rect on screen (the button and the chip), for anything that must keep clear of it.
func corner_rect() -> Rect2:
	var r := Rect2(_menu_btn.position, _menu_btn.size)
	if _chip.visible:
		r = r.merge(Rect2(_chip.position, _chip.size))
	return r
