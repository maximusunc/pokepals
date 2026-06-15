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

var _interactables: Array = []  # [ { pos: Vector2, label: String } ]
var _examine_shown := false  # whether the touch Examine button is currently faded in


func _ready() -> void:
	var data := WorldData.load_json(WORLD_PATH)

	_player.position = WorldData.to_vec2(data["player_spawn"])
	_companion.position = WorldData.to_vec2(data["companion_spawn"])
	_companion.setup(_player)

	_world_art.render_world(data)

	var bmin := WorldData.to_vec2(data["bounds"]["min"])
	var bmax := WorldData.to_vec2(data["bounds"]["max"])
	_camera.set_bounds(Rect2(bmin, bmax - bmin))

	for it in data.get("interactables", []):
		_interactables.append({ "pos": WorldData.to_vec2(it["position"]), "label": String(it.get("label", "something")) })

	# Let the companion know where the props are, so it can wander to them on its own.
	var poi: Array = []
	for entry in _interactables:
		poi.append(entry["pos"])
	_companion.set_points_of_interest(poi)

	# Touch: tapping the on-screen button examines. Wire it up and keep its taps
	# from also spinning up the movement thumbstick underneath it.
	_examine_button.pressed.connect(_try_interact)
	_joystick.add_exclusion(_examine_button)

	_hint.text = "Wander with arrows / WASD or drag.  Space or tap Examine to look closer."


func _process(_delta: float) -> void:
	# Surface a gentle prompt — and the touch Examine button — when standing near
	# something to examine.
	var nearest := _nearest_interactable()
	if nearest >= 0:
		_hint.text = "Examine %s" % _interactables[nearest]["label"]
		_set_examine_visible(true)
	else:
		_set_examine_visible(false)
		if _hint.text.begins_with("Examine "):
			_hint.text = ""


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_try_interact()


func _try_interact() -> void:
	var index := _nearest_interactable()
	if index < 0:
		return
	var spot: Vector2 = _interactables[index]["pos"]
	_world_art.pulse_interactable(index)
	_companion.notify_interaction(spot)
	_hint.text = "You examine %s. Your companion perks up." % _interactables[index]["label"]


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
