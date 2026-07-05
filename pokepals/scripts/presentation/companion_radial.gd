class_name CompanionRadial
extends Control
## The bottom-right companion "chip" and its fan-out action arc. The chip is always there in the
## fixed corner (with a small dot that warms as the bond grows); tapping it fans a quarter-arc of
## companion actions inward from the corner. Because the chip is anchored, the arc is always in the
## same place no matter where the companion has wandered — the actions come to a spot you know,
## rather than chasing a roaming pet around the screen.
##
## Pure presentation: the controller pushes the currently-available actions via set_actions() and the
## live bond via set_bond(); this node only lays them out and reports which one the player tapped
## (`action_selected`). It owns the open/close toggle itself — one less thing for the controller to track.

signal action_selected(id: String)
signal opened  ## fired when the arc fans open, so the controller can close the gear menu

const CHIP_MARGIN := Vector2(14, 14)  # gap from the bottom-right corner
const ARC_RADIUS := 100.0
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


## Lay the offered actions along a quarter-arc sweeping up-and-left from the chip, each button
## popping out from the chip with a short staggered tween so it reads as a fan, not a snap.
func _build_slices() -> void:
	for c in _slots.get_children():
		c.queue_free()
	# Chip center in screen space. _slots is a full-rect container at the origin, so a child's
	# `position` is already screen coordinates.
	var chip_sz := _chip.get_combined_minimum_size()
	var origin := Vector2(size.x - CHIP_MARGIN.x - chip_sz.x * 0.5, size.y - CHIP_MARGIN.y - chip_sz.y * 0.5)
	var n := _actions.size()
	for i in n:
		var a: Dictionary = _actions[i]
		var btn := _make_slice(String(a["id"]), String(a["label"]))
		_slots.add_child(btn)
		var bsz := btn.get_combined_minimum_size()
		btn.size = bsz
		btn.pivot_offset = bsz * 0.5  # scale from the button's center for a clean pop
		# Angle from ~176° (nearly straight left) to ~96° (nearly straight up); y is down, so
		# -sin lifts the button upward. Single item sits mid-arc.
		var t := 0.5 if n == 1 else float(i) / float(n - 1)
		var ang := deg_to_rad(lerpf(176.0, 96.0, t))
		var target := origin + Vector2(cos(ang), -sin(ang)) * ARC_RADIUS - bsz * 0.5
		btn.position = origin - bsz * 0.5
		btn.modulate.a = 0.0
		btn.scale = Vector2(0.7, 0.7)
		var tw := btn.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var delay := i * SLICE_STAGGER
		tw.tween_property(btn, "position", target, 0.2).set_delay(delay)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.2).set_delay(delay)
		tw.tween_property(btn, "modulate:a", 1.0, 0.16).set_delay(delay)


func _make_slice(id: String, label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	UiStyle.hud_button(btn, 11, 600, 999, 13.0, 6.0)
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
