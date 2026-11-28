class_name CompanionRadial
extends Control
## The COMPANION COLUMN down the right edge: everything you ask of your companion, each one tap, kept
## off the busy bottom of the screen. From the top: the companion's portrait (the animal it's wearing
## right now), then its everyday actions as plain icons (Call, Pet, and Go look where there's somewhere
## to look), then, below a little divider and lit gold, a world's own trick where that world has one
## (Howl in Hollowsong, Go up in Loftreach). Tapping the portrait slides a row of the SHAPES it can take
## out to the left along the top edge; tap one to ask for it (the row closes), or tap the portrait or
## anywhere else to put it away. Tap only: no holds, no slides.
##
## (The class keeps its old name from when this was a chip that fanned actions out on two arcs.)
##
## Pure presentation: the controller pushes what's on offer (set_actions) and the portrait's picture
## (set_portrait); this node lays them out and reports what was tapped (`action_selected`).

signal action_selected(id: String)
signal opened  ## the shapes row slid out, so the controller can close the menu sheet

const MARGIN := 10.0
const WIDTH := 46.0
const PAD := 4.0
const PORTRAIT := 38.0
const ACTION := 34.0
const GAP := 4.0
const SHAPE := 38.0
## The actions that belong to every world, in the column's order; anything else offered (that isn't a
## shape) is a world's own trick and goes below the divider.
const CORE := ["call", "pet", "seek"]
const ICONS := { "call": "call", "pet": "pet", "seek": "look", "howl": "howl", "up": "up" }

var _catcher: Control
var _column: Control
var _portrait: HudTile
var _shapes: Control
var _actions: Array = []      # [{id, label}] offered (enabled only)
var _signature := ""
var _open := false
var _current_form := ""
var _sheets: Dictionary = {}  # species -> { tex, region } for the shape buttons


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # empty space falls through to the world

	# Tap-away for the shapes row (transparent; the world stays visible behind it).
	_catcher = Control.new()
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.visible = false
	_catcher.gui_input.connect(_on_catcher_input)
	add_child(_catcher)

	_column = Control.new()
	_column.mouse_filter = Control.MOUSE_FILTER_STOP  # its gaps don't leak through as world taps
	_column.draw.connect(_draw_column)
	add_child(_column)

	_portrait = HudTile.new()
	_portrait.look = "primary"
	_portrait.radius = PORTRAIT * 0.5
	_portrait.size = Vector2(PORTRAIT, PORTRAIT)
	_portrait.pressed.connect(_toggle)
	_column.add_child(_portrait)

	_shapes = Control.new()
	_shapes.mouse_filter = Control.MOUSE_FILTER_STOP
	_shapes.visible = false
	_shapes.draw.connect(_draw_shapes)
	add_child(_shapes)

	_layout.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout()


## The animal on the portrait: its sheet and the frame to show (null for none).
func set_portrait(tex: Texture2D, region: Rect2) -> void:
	if _portrait == null:
		return
	_portrait.set_sprite(tex, region, (PORTRAIT - 6.0) / maxf(region.size.y, 1.0))


## The shape it's wearing (highlighted in the shapes row) and, per species on offer, the picture of it:
## { species: { tex, region } }.
func set_shape_art(current: String, sheets: Dictionary) -> void:
	_current_form = current
	_sheets = sheets
	if _open:
		_build_shapes()


## What to offer right now. Each entry: { id, label, enabled }; disabled ones are left out ("Go look" is
## only there when there's somewhere to look). Ids "form:<species>" are the shapes.
func set_actions(actions: Array) -> void:
	var offered: Array = []
	var sig := ""
	for a in actions:
		if bool(a.get("enabled", true)):
			offered.append({ "id": String(a["id"]), "label": String(a["label"]) })
			sig += String(a["id"]) + "|"
	if sig == _signature:
		return
	_signature = sig
	_actions = offered
	_layout()


## The column's rect on screen (the use button keeps below it).
func chip_rect() -> Rect2:
	if _column == null:
		return Rect2(size - Vector2(56, 200), Vector2(WIDTH, 190))
	return Rect2(_column.position, _column.size)


func _layout() -> void:
	if _column == null:
		return
	for c in _column.get_children():
		if c != _portrait:
			c.queue_free()
	var core: Array = []
	var tricks: Array = []
	for a in _actions:
		var id := String(a["id"])
		if id.begins_with("form:"):
			continue
		if id in CORE:
			core.append(a)
		else:
			tricks.append(a)
	core.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return CORE.find(String(x["id"])) < CORE.find(String(y["id"])))
	var x_mid := WIDTH * 0.5
	_portrait.position = Vector2(x_mid - PORTRAIT * 0.5, PAD)
	var y := PAD + PORTRAIT + GAP + 2.0 + GAP  # the divider under the portrait
	for a in core:
		_action_button(String(a["id"]), String(a["label"]), Vector2(x_mid - ACTION * 0.5, y), false)
		y += ACTION + GAP
	if not tricks.is_empty():
		y += 2.0 + GAP  # a second divider
		for a in tricks:
			_action_button(String(a["id"]), String(a["label"]), Vector2(x_mid - ACTION * 0.5, y), true)
			y += ACTION + GAP
	_column.size = Vector2(WIDTH, y - GAP + PAD)
	_column.position = Vector2(size.x - MARGIN - WIDTH, MARGIN)
	_column.set_meta("dividers", [PAD + PORTRAIT + GAP + 1.0] + \
		([PAD + PORTRAIT + GAP * 2.0 + 2.0 + float(core.size()) * (ACTION + GAP) + 1.0] if not tricks.is_empty() else []))
	_column.queue_redraw()
	if _open:
		_build_shapes()


func _action_button(id: String, label: String, at: Vector2, trick: bool) -> void:
	var b := HudTile.new()
	b.look = "gold" if trick else "ghost"
	b.icon = String(ICONS.get(id, ""))
	if b.icon == "":
		b.text = label.substr(0, 1)  # an action with no drawn icon yet still gets a tappable letter
	b.icon_size = 19.0
	b.radius = ACTION * 0.5
	b.glow = trick
	b.size = Vector2(ACTION, ACTION)
	b.position = at
	b.tooltip_text = label  # names the icon on a desktop (hover); nothing on screen otherwise
	b.pressed.connect(func() -> void:
		_close()
		action_selected.emit(id))
	_column.add_child(b)


func _draw_column() -> void:
	var sb := UiStyle.hud_box(int(WIDTH * 0.5))
	sb.anti_aliasing = true
	_column.draw_style_box(sb, Rect2(Vector2.ZERO, _column.size))
	for dy in _column.get_meta("dividers", []):
		_column.draw_line(Vector2(WIDTH * 0.5 - 12.0, dy), Vector2(WIDTH * 0.5 + 12.0, dy), UiStyle.DIVIDER, 2.0)


# ── the shapes row ──

func _toggle() -> void:
	if _open:
		_close()
	else:
		_open_row()


func _open_row() -> void:
	if _shape_ids().is_empty():
		return
	_open = true
	_catcher.visible = true
	_portrait.selected = true
	_build_shapes()
	_shapes.visible = true
	_shapes.modulate.a = 0.0
	var from := _shapes.position + Vector2(16, 0)
	var to := _shapes.position
	_shapes.position = from
	var tw := _shapes.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_shapes, "position", to, 0.16)
	tw.tween_property(_shapes, "modulate:a", 1.0, 0.14)
	opened.emit()


## Put the shapes row away if it's out (public so the controller can dismiss it when the menu opens).
func close() -> void:
	_close()


func _close() -> void:
	if not _open:
		return
	_open = false
	_catcher.visible = false
	_portrait.selected = false
	_shapes.visible = false
	for c in _shapes.get_children():
		c.queue_free()


func _shape_ids() -> Array:
	var out: Array = []
	for a in _actions:
		if String(a["id"]).begins_with("form:"):
			out.append(String(a["id"]))
	return out


func _build_shapes() -> void:
	for c in _shapes.get_children():
		c.queue_free()
	var ids := _shape_ids()
	var n := ids.size()
	var w := PAD * 2.0 + float(n) * SHAPE + float(maxi(n - 1, 0)) * GAP
	_shapes.size = Vector2(w, SHAPE + PAD * 2.0)
	_shapes.position = Vector2(_column.position.x - 8.0 - w, _column.position.y + _portrait.position.y + PORTRAIT * 0.5 - _shapes.size.y * 0.5)
	for i in n:
		var id: String = ids[i]
		var species := id.substr(5)
		var b := HudTile.new()
		b.look = "tile"
		b.radius = SHAPE * 0.5
		b.size = Vector2(SHAPE, SHAPE)
		b.position = Vector2(PAD + float(i) * (SHAPE + GAP), PAD)
		b.selected = species == _current_form
		b.tooltip_text = species.capitalize()
		var art: Dictionary = _sheets.get(species, {})
		if art.get("tex") is Texture2D:
			var region: Rect2 = art["region"]
			b.set_sprite(art["tex"], region, (SHAPE - 4.0) / maxf(region.size.y, 1.0))
		else:
			b.text = species.capitalize().substr(0, 3)
		b.pressed.connect(func() -> void:
			_close()
			action_selected.emit(id))
		_shapes.add_child(b)


func _draw_shapes() -> void:
	var sb := UiStyle.hud_box(int(_shapes.size.y * 0.5))
	sb.anti_aliasing = true
	_shapes.draw_style_box(sb, Rect2(Vector2.ZERO, _shapes.size))


func _on_catcher_input(event: InputEvent) -> void:
	var tap: bool = event is InputEventMouseButton and event.pressed
	var touch: bool = event is InputEventScreenTouch and event.pressed
	if tap or touch:
		_close()
		accept_event()


## The interactive Controls the joystick must exclude.
func tap_targets() -> Array:
	return [_column, _catcher]
