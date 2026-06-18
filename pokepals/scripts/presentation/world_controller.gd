extends Node2D
## Wires the slice together: loads the world, places the player and companion,
## hands the companion its player to follow, frames the camera, and routes cozy
## interactions. When the player examines a nearby prop, the prop glows and the
## companion is told about it — so it can notice and wander over. The controller
## decides *that* an interaction happened; the companion's brain decides how to feel
## about it.

const WORLD_PATH := "res://data/world.json"
const INTERACT_RANGE := 60.0

@onready var _world_art: WorldArt = $WorldArt
@onready var _player: PlayerView = $Player
@onready var _companion: CompanionView = $Companion
@onready var _camera: CameraRig = $Camera2D
@onready var _hint: Label = $UI/HintLabel
@onready var _joystick: VirtualJoystick = $UI/Joystick
@onready var _examine_button: Button = $UI/ExamineButton
@onready var _reset_button: Button = $UI/ResetButton
@onready var _debug: DebugOverlay = $DebugOverlay
@onready var _debug_button: Button = $UI/DebugButton
@onready var _day_tint: CanvasModulate = $DayTint
@onready var _vignette: ColorRect = $Vignette/Rect
@onready var _pollen: CPUParticles2D = $Camera2D/Pollen

var _interactables: Array = []  # [ { pos: Vector2, label: String } ]
var _examine_shown := false  # whether the touch Examine button is currently faded in
var _reset_shown := false  # whether the "new companion" button is currently faded in
var _intro_tween: Tween  # fades the opening "how to move" hint away after a few seconds


func _ready() -> void:
	var data := WorldData.load_json(WORLD_PATH)

	_player.position = WorldData.to_vec2(data["player_spawn"])
	_companion.position = WorldData.to_vec2(data["companion_spawn"])
	_companion.setup(_player)

	_world_art.render_world(data)
	_apply_atmosphere(data.get("atmosphere", {}))

	var bmin := WorldData.to_vec2(data["bounds"]["min"])
	var bmax := WorldData.to_vec2(data["bounds"]["max"])
	_camera.set_bounds(Rect2(bmin, bmax - bmin))

	for i in data.get("interactables", []).size():
		var it: Dictionary = data["interactables"][i]
		# A stable id for the companion's habituation/memory: prefer an explicit "id",
		# else fall back to "type" or the index, so existing worlds still get stable keys.
		var prop_id := String(it.get("id", it.get("type", "prop_%d" % i)))
		_interactables.append({
			"pos": WorldData.to_vec2(it["position"]),
			"label": String(it.get("label", "something")),
			"id": prop_id,
			"tags": it.get("tags", []),
		})

	# Let the companion know where the props are, so it can wander to them on its own.
	var poi: Array = []
	for entry in _interactables:
		poi.append(entry["pos"])
	_companion.set_points_of_interest(poi)

	# Hand the companion the world's id and named regions, so it can feel the bond of
	# reaching a new area (resolved from its own position; see WorldAreas / CompanionSelf).
	var regions: Array = []
	for r in data.get("regions", []):
		regions.append({ "id": String(r.get("id", "region")), "min": WorldData.to_vec2(r["min"]), "max": WorldData.to_vec2(r["max"]) })
	_companion.set_world_areas(String(data.get("world_id", "")), regions)

	# Touch: tapping the on-screen button examines. Wire it up and keep its taps
	# from also spinning up the movement thumbstick underneath it.
	_examine_button.pressed.connect(_try_interact)
	_joystick.add_exclusion(_examine_button)

	# Top-right "start over" button: only revealed once fully bonded (see _process).
	_reset_button.pressed.connect(_on_reset_pressed)
	_joystick.add_exclusion(_reset_button)

	# Dev-only companion/bond readout. On by default; the DBG button (and F3 on
	# desktop) toggles it. Exclude its taps from the movement thumbstick underneath.
	_debug.setup(_companion, _player)
	_debug_button.pressed.connect(_debug.toggle)
	_joystick.add_exclusion(_debug_button)

	# Opening instruction, then let it quietly fade so the world isn't framed by UI
	# text while you wander. Any real prompt (Examine ...) cancels the fade and shows.
	_hint.text = "Wander with arrows / WASD or drag.  Space or tap Examine to look closer."
	_hint.modulate.a = 1.0
	_intro_tween = create_tween()
	_intro_tween.tween_interval(5.0)
	_intro_tween.tween_property(_hint, "modulate:a", 0.0, 1.4)


## Show a hint at full opacity, cancelling the opening fade if it's still running, so
## prompts (and the reset message) are always readable even after the intro faded out.
func _show_hint(text: String) -> void:
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	_hint.text = text
	_hint.modulate.a = 1.0


## Push the world's presentation-only mood knobs into the scene nodes that render
## them: the global warm color-wash (CanvasModulate), the screen-edge vignette, and
## the drifting pollen. All data-driven from world.json's "atmosphere" block, with
## defaults so a world without the block still looks right.
func _apply_atmosphere(atmo: Dictionary) -> void:
	if atmo.has("day_tint"):
		_day_tint.color = WorldData.to_color(atmo["day_tint"])

	var vig: Dictionary = atmo.get("vignette", {})
	var mat := _vignette.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("strength", float(vig.get("strength", 0.34)))
		mat.set_shader_parameter("tint", WorldData.to_color(vig.get("color", [0.06, 0.05, 0.10])))

	var pol: Dictionary = atmo.get("pollen", {})
	_pollen.amount = maxi(1, int(pol.get("amount", 34)))
	var pc := WorldData.to_color(pol.get("color", [1.0, 0.96, 0.74]))
	pc.a = 0.45
	_pollen.color = pc


func _process(_delta: float) -> void:
	# Surface a gentle prompt — and the touch Examine button — when standing near
	# something to examine.
	var nearest := _nearest_interactable()
	if nearest >= 0:
		_show_hint("Examine %s" % _interactables[nearest]["label"])
		_set_examine_visible(true)
	else:
		_set_examine_visible(false)
		if _hint.text.begins_with("Examine "):
			_hint.text = ""

	# Reveal the "new companion" button only once the bond is full.
	_set_reset_visible(_companion.is_fully_bonded())


## Gently fade the touch Examine button in or out as the player nears a prop, so
## it signals "something's here" without cluttering the screen while wandering.
func _set_examine_visible(show_button: bool) -> void:
	if show_button == _examine_shown:
		return
	_examine_shown = show_button
	if show_button:
		_examine_button.visible = true
	var tween := create_tween()
	tween.tween_property(_examine_button, "modulate:a", 1.0 if show_button else 0.0, 0.18)
	if not show_button:
		tween.tween_callback(func() -> void: _examine_button.visible = false)


## Gently fade the "new companion" button in once fully bonded, out otherwise —
## mirrors the Examine button's fade so the screen stays uncluttered until it matters.
func _set_reset_visible(show_button: bool) -> void:
	if show_button == _reset_shown:
		return
	_reset_shown = show_button
	if show_button:
		_reset_button.visible = true
	var tween := create_tween()
	tween.tween_property(_reset_button, "modulate:a", 1.0 if show_button else 0.0, 0.18)
	if not show_button:
		tween.tween_callback(func() -> void: _reset_button.visible = false)


## Start a fresh companion (immediate, no confirm — the button only appears once you
## have a fully bonded companion to start over from). It hides itself again until the
## new companion bonds.
func _on_reset_pressed() -> void:
	_companion.reset()
	_set_reset_visible(false)
	_show_hint("A new companion blinks into the world beside you.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_try_interact()


func _try_interact() -> void:
	var index := _nearest_interactable()
	if index < 0:
		return
	var spot: Vector2 = _interactables[index]["pos"]
	_world_art.pulse_interactable(index)
	_companion.notify_interaction(spot, _interactables[index]["id"], _interactables[index]["tags"])
	_show_hint("You examine %s. Your companion perks up." % _interactables[index]["label"])


## Index of the closest interactable within range, or -1 if none.
func _nearest_interactable() -> int:
	var best := -1
	var best_dist := INTERACT_RANGE
	for i in _interactables.size():
		var d := _player.position.distance_to(_interactables[i]["pos"])
		if d <= best_dist:
			best = i
			best_dist = d
	return best
