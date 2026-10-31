class_name CompanionRadial
extends Control
## The bottom-right companion "chip" and its fan-out action arc. The chip is always there in the
## fixed corner (with a small dot that warms as the bond grows); tapping it fans the companion's
## actions out from the corner on two arcs: what it can do close in, the shapes it can take further
## out, spaced so no two buttons touch. Because the chip is anchored, the arcs are always in the
## same place no matter where the companion has wandered — the actions come to a spot you know,
## rather than chasing a roaming pet around the screen.
##
## Pure presentation: the controller pushes the currently-available actions via set_actions() and the
## live bond via set_bond(); this node only lays them out and reports which one the player tapped
## (`action_selected`). It owns the open/close toggle itself — one less thing for the controller to track.

signal action_selected(id: String)
signal opened  ## fired when the arc fans open, so the controller can close the gear menu

const CHIP_MARGIN := Vector2(14, 14)  # gap from the bottom-right corner
## The two arcs: companion actions on the inner one, the shapes it can take on the outer one. Each
## starts at its base radius and only grows if its buttons can't fit along it without touching.
const INNER_RADIUS := 92.0
const RING_GAP := 14.0       # the least room between the inner and outer arcs
const BUTTON_GAP := 10.0     # the least room between any two buttons (a fat-finger margin)
const ARC_FROM := 178.0      # the arcs sweep from nearly straight left of the chip…
const ARC_TO := 84.0         # …to just past straight up
const SLICE_STAGGER := 0.035

var _chip: Button
var _dot: Panel
var _catcher: Control
var _slots: Control
var _actions: Array = []      # [{id, label}] currently offered (enabled only)
var _signature := ""          # to skip rebuilding the arc when the offered set is unchanged
var _open := false
var _bond := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # empty space falls through to the joystick

	# Full-screen tap-away catcher, shown only while the arc is open. While visible it also blankets
	# the joystick (registered as an exclusion), so the world doesn't pan under an open menu.
	_catcher = Control.new()
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.visible = false
	_catcher.gui_input.connect(_on_catcher_input)
	add_child(_catcher)

	# Holds the fanned action buttons (built on open, freed on close).
	_slots = Control.new()
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_slots)

	# The chip itself — always present, top-most. Positioned manually at the bottom-right corner from
	# the root's size (see _layout); with default top-left anchors, `position` is plain pixel coords,
	# which sidesteps the corner-anchor/offset confusion.
	_chip = Button.new()
	_chip.text = "Companion"
	UiStyle.hud_button(_chip, 11, 600, 999, 13.0, 6.0)
	# Leave room on the right for the bond dot (same on every state so the text doesn't jump on press).
	for state in ["normal", "hover", "pressed"]:
		(_chip.get_theme_stylebox(state) as StyleBoxFlat).content_margin_right = 30
	_chip.pressed.connect(_toggle)
	add_child(_chip)

	# The bond dot: a small circle at the chip's right edge that warms with the bond.
	_dot = Panel.new()
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.custom_minimum_size = Vector2(10, 10)
	_dot.size = Vector2(10, 10)
	_dot.add_theme_stylebox_override("panel", _dot_style(_bond))
	_chip.add_child(_dot)

	_layout.call_deferred()


## Reflow the chip (and any open arc) whenever the root's size changes — i.e. on window resize.
## Guarded on is_node_ready(): a Control gets its first NOTIFICATION_RESIZED as its rect resolves,
## which happens BEFORE _ready() builds _chip/_dot — so an unguarded _layout() would deref a null
## _chip. The initial layout is handled by the _layout.call_deferred() in _ready(); this only needs
## to catch later, post-ready resizes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout()


## The bond dot's fill: a muted grey-brown when fresh, warming to a soft glow when fully bonded.
## A round pip with the HUD's soft ink rim, matching the pill it sits in.
func _dot_style(bond: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var cool := Color(0.62, 0.57, 0.52)
	var warm := Color(0.96, 0.52, 0.36)
	sb.bg_color = cool.lerp(warm, clampf(bond, 0.0, 1.0))
	sb.border_color = UiStyle.HUD_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(999)
	return sb


func _layout() -> void:
	var sz := _chip.get_combined_minimum_size()
	_chip.size = sz
	_chip.position = Vector2(size.x - sz.x - CHIP_MARGIN.x, size.y - sz.y - CHIP_MARGIN.y)
	# Park the dot at the chip's right edge, vertically centered.
	_dot.position = Vector2(sz.x - 22, (sz.y - _dot.size.y) * 0.5)
	if _open:
		_build_slices()


## The controller's live bond reading (0..1), for the chip dot.
func set_bond(bond: float) -> void:
	if is_equal_approx(bond, _bond):
		return
	_bond = bond
	if _dot != null:
		_dot.add_theme_stylebox_override("panel", _dot_style(_bond))


## The actions to offer right now. Each entry: { id, label, enabled }. Disabled ones are dropped
## (contextual actions like "Go look" simply aren't in the list when unavailable). If the offered set
## changed while the arc is open, it re-fans; if closed, the next open picks up the new set.
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
	if _open:
		_build_slices()


func _toggle() -> void:
	if _open:
		_close()
	else:
		_open_arc()


func _open_arc() -> void:
	_open = true
	_catcher.visible = true
	_build_slices()
	opened.emit()


## Close the arc if it's open (public so the controller can dismiss it when the gear menu opens).
func close() -> void:
	_close()


func _close() -> void:
	if not _open:
		return
	_open = false
	_catcher.visible = false
	for c in _slots.get_children():
		c.queue_free()


## Fan the offered actions out from the chip on two arcs: what the companion can DO (Pet, Call, Go look)
## close in, and the SHAPES it can take further out. Positions come from arc_layout (no two buttons
## touch), and each button pops out from the chip with a short staggered tween so it reads as a fan.
func _build_slices() -> void:
	for c in _slots.get_children():
		c.queue_free()
	# Chip center in screen space. _slots is a full-rect container at the origin, so a child's
	# `position` is already screen coordinates.
	var chip_sz := _chip.get_combined_minimum_size()
	var origin := Vector2(size.x - CHIP_MARGIN.x - chip_sz.x * 0.5, size.y - CHIP_MARGIN.y - chip_sz.y * 0.5)
	var rings: Array = [[], []]  # buttons per ring: [actions, shapes]
	for a in _actions:
		var btn := _make_slice(String(a["id"]), String(a["label"]))
		_slots.add_child(btn)
		btn.size = btn.get_combined_minimum_size()
		rings[1 if String(a["id"]).begins_with("form:") else 0].append(btn)
	if (rings[0] as Array).is_empty():
		rings.pop_front()
	var sizes: Array = rings.map(func(ring: Array) -> Array: return ring.map(func(b: Button) -> Vector2: return b.size))
	var chip_rect := Rect2(Vector2(size.x - CHIP_MARGIN.x - chip_sz.x, size.y - CHIP_MARGIN.y - chip_sz.y), chip_sz)
	var placed := CompanionRadial.arc_layout(origin, sizes, chip_rect)
	var k := 0
	for r in rings.size():
		for i in (rings[r] as Array).size():
			var btn: Button = rings[r][i]
			var bsz := btn.size
			btn.pivot_offset = bsz * 0.5  # scale from the button's center for a clean pop
			btn.position = origin - bsz * 0.5
			btn.modulate.a = 0.0
			btn.scale = Vector2(0.7, 0.7)
			var tw := btn.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			var delay := k * SLICE_STAGGER
			tw.tween_property(btn, "position", placed[r][i], 0.2).set_delay(delay)
			tw.tween_property(btn, "scale", Vector2.ONE, 0.2).set_delay(delay)
			tw.tween_property(btn, "modulate:a", 1.0, 0.16).set_delay(delay)
			k += 1


## Where each button goes (its top-left), ring by ring. `sizes` is one Array of button sizes per ring,
## innermost first; `chip` is the chip's rect, kept clear too. Pure (sizes in, positions out), so it's
## unit-tested. Each button is walked along its arc from ARC_FROM toward ARC_TO until it clears every
## button already placed by BUTTON_GAP; if a ring runs out of arc, its radius grows and it's laid again.
## So nothing ever overlaps, however many shapes the companion can take.
static func arc_layout(origin: Vector2, sizes: Array, chip: Rect2) -> Array:
	var out: Array = []
	var placed: Array = [chip]  # rects to keep clear of, grown as buttons are laid
	var radius := INNER_RADIUS
	for ring in sizes:
		var fit := false
		var positions: Array = []
		var rects: Array = []
		while not fit:
			positions = []
			rects = []
			fit = true
			var ang := ARC_FROM
			for sz in ring:
				var spot := _clear_spot(origin, radius, sz, ang, placed + rects)
				if spot.is_empty():
					fit = false
					radius += 6.0
					break
				ang = float(spot["angle"])
				positions.append(spot["pos"])
				rects.append(Rect2(spot["pos"], sz))
		out.append(positions)
		placed += rects
		# The next ring starts just beyond this one's farthest-reaching button.
		var reach := radius
		for rc in rects:
			reach = maxf(reach, ((rc as Rect2).get_center() - origin).length() + maxf((rc as Rect2).size.x, (rc as Rect2).size.y) * 0.5)
		radius = reach + RING_GAP
	return out


## The first angle from `from` toward ARC_TO where a button of size `sz` on the arc of `radius` clears
## every rect in `avoid` by BUTTON_GAP: { angle, pos }, or {} if it runs out of arc.
static func _clear_spot(origin: Vector2, radius: float, sz: Vector2, from: float, avoid: Array) -> Dictionary:
	var ang := from
	while ang >= ARC_TO:
		var center := origin + Vector2(cos(deg_to_rad(ang)), -sin(deg_to_rad(ang))) * radius
		var rect := Rect2(center - sz * 0.5, sz)
		var clear := true
		for o in avoid:
			if (o as Rect2).grow(BUTTON_GAP).intersects(rect):
				clear = false
				break
		if clear:
			return { "angle": ang, "pos": rect.position }
		ang -= 1.0
	return {}


func _make_slice(id: String, label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	UiStyle.hud_button(btn, 11, 600, 999, 14.0, 8.0)
	btn.pressed.connect(func() -> void:
		action_selected.emit(id)
		_close())
	return btn


func _on_catcher_input(event: InputEvent) -> void:
	var tap: bool = event is InputEventMouseButton and event.pressed
	var touch: bool = event is InputEventScreenTouch and event.pressed
	if tap or touch:
		_close()
		accept_event()


## The interactive Controls the joystick must exclude. The catcher (full-screen while open) covers the
## fanned slices too, so we only register the two persistent ones.
func tap_targets() -> Array:
	return [_chip, _catcher]
