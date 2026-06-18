class_name CompanionView
extends Node2D
## The companion's BODY — the presentation side of the logic/presentation split.
## Each frame it builds a context, asks CompanionBrain what it wants, and then
## brings that intent to life: eases toward the desired point, turns its eyes
## toward whatever it's attending to (the cheap-but-huge "it's looking at me/that"
## effect), bobs and hops, and pops when it notices something.
##
## It never decides behavior itself — that's the brain's job. It only renders the
## brain's intent.

@export var config_path := "res://data/companion.json"

const SELF_SAVE_PATH := "user://companion_self.json"
const AUTOSAVE_INTERVAL := 15.0

var velocity := Vector2.ZERO

var _brain: CompanionBrain
var _cfg: Dictionary
var _player: PlayerView
var _events: Array = []
var _points_of_interest: Array = []
var _world_id := ""
var _regions: Array = []
var _time := 0.0
var _autosave_accum := 0.0

var _look_dir := Vector2.DOWN
var _eye_offset := Vector2.ZERO
var _bob := 0.0
var _hop_squash := 0.0   # 0..1, decays; squashes the body on a "hop"
var _perk := 0.0         # 0..1, decays; pops the body on "perk"
var _body_color := Color(0.56, 0.62, 0.86)


## Called by the world to hand the companion its player to follow.
func setup(player: PlayerView) -> void:
	_player = player


## Called by the world to tell the companion where the standing props are, so it
## can choose to wander over and investigate them on its own.
func set_points_of_interest(points: Array) -> void:
	_points_of_interest = points


## Called by the world to hand over its id and named regions, so the companion can resolve
## which area it's in (for the bond of reaching a new place). regions: [{ id, min, max }].
func set_world_areas(world_id: String, regions: Array) -> void:
	_world_id = world_id
	_regions = regions


## Called by the world when the player interacts with something — the brain may
## decide to grow curious about it. The stable prop `id` lets the companion tell one
## thing from another (habituation/memory); the neutral `tags` let it appraise how it
## feels about the thing (see CompanionAppraisal).
func notify_interaction(world_position: Vector2, id: String = "", tags: Array = []) -> void:
	_events.append({ "type": "interaction", "position": world_position, "id": id, "tags": tags })


func _ready() -> void:
	_cfg = WorldData.load_json(config_path)
	# Carry the companion across sessions: load its saved self if there is one, so
	# it returns as the same partner the player has been shaping.
	var saved: Dictionary = SaveStore.load_json(SELF_SAVE_PATH)
	var existing_self: CompanionSelf = null
	if not saved.is_empty():
		existing_self = CompanionSelf.from_dict(saved, _cfg)
	else:
		# A brand-new companion: gently randomize its traits so this playthrough's
		# partner has its own slight leanings (a touch more wander-, prop-, or
		# follow-inclined) rather than always the exact same temperament.
		existing_self = CompanionSelf.make_random(_cfg, RandomNumberGenerator.new())
	_brain = CompanionBrain.new(_cfg, 0, existing_self)


func _process(delta: float) -> void:
	_time += delta
	if _player == null:
		return

	var context := {
		"companion_pos": position,
		"player_pos": _player.position,
		"player_velocity": _player.velocity,
		"delta": delta,
		"events": _events,
		"time": _time,
		"points_of_interest": _points_of_interest,
		"current_area": WorldAreas.resolve(position, _world_id, _regions),
	}
	_events = []

	var intent := _brain.update(context)
	_apply_movement(intent, delta)
	_apply_attention(intent, delta)
	_apply_reactions(intent["reactions"])
	_decay_animation(delta)
	queue_redraw()

	# Periodic autosave so a long session (or a mobile app being backgrounded)
	# never loses much of who the companion is becoming.
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_INTERVAL:
		_autosave_accum = 0.0
		_save_self()


## Whether the bond has reached its maximum — used by the world to reveal the
## "start over" affordance only once there's a fully bonded companion to reset.
func is_fully_bonded() -> bool:
	if _brain == null:
		return false
	var max_bond := float(_cfg.get("bond", {}).get("max", 1.0))
	return _brain.get_self().bond >= max_bond


## A single read surface for the debug overlay: the brain's last decision merged
## with the persistent self's state and a couple of presentation facts. Read-only —
## the overlay only displays this; it never writes back. Empty before the brain exists.
func debug_state() -> Dictionary:
	if _brain == null:
		return {}
	var d := _brain.debug_state().duplicate(true)
	var self_state := _brain.get_self().debug_state(_cfg)
	for key in self_state:
		d[key] = self_state[key]
	# The mood-overlaid trait values, so the overlay can show how the current mood is
	# bending behavior versus the underlying (raw) traits.
	d["effective"] = CompanionTraits.effective_snapshot(_brain.get_self(), _cfg, ["energy", "clinginess"])
	d["companion_pos"] = position
	d["speed"] = velocity.length()
	return d


## Start a whole new companion: wipe the save and spawn a freshly randomized partner
## so the bond arc can be played again from zero without reinstalling. Replacing the
## brain outright also clears every drive's internal timers, so it truly begins anew.
func reset() -> void:
	SaveStore.delete_save(SELF_SAVE_PATH)
	var fresh := CompanionSelf.make_random(_cfg, RandomNumberGenerator.new())
	_brain = CompanionBrain.new(_cfg, 0, fresh)
	_autosave_accum = 0.0


## Persist who the companion has become. Cheap and idempotent.
func _save_self() -> void:
	if _brain == null:
		return
	SaveStore.save_json(SELF_SAVE_PATH, _brain.get_self().to_dict())


## Save on the ways a session can end: window close, app backgrounded on mobile,
## or this node leaving the tree (scene change / quit).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_save_self()


func _apply_movement(intent: Dictionary, delta: float) -> void:
	var target: Vector2 = intent["move_target"]
	var speed: float = intent["desired_speed"]
	var to_target := target - position
	var desired_velocity := Vector2.ZERO
	if to_target.length() > 2.0 and speed > 0.0:
		desired_velocity = to_target.normalized() * speed
	velocity = velocity.lerp(desired_velocity, 1.0 - exp(-float(_cfg["accel"]) * delta))
	position += velocity * delta


func _apply_attention(intent: Dictionary, delta: float) -> void:
	var to_look := (intent["look_at"] as Vector2) - position
	if to_look.length() > 1.0:
		_look_dir = _look_dir.lerp(to_look.normalized(), 1.0 - exp(-6.0 * delta))
	_eye_offset = _look_dir.normalized() * 2.4


func _apply_reactions(reactions: Array) -> void:
	for r in reactions:
		match r:
			"hop":
				_hop_squash = 1.0
			"perk":
				_perk = 1.0


func _decay_animation(delta: float) -> void:
	_bob = sin(_time * 3.0)
	_hop_squash = maxf(0.0, _hop_squash - delta * 2.5)
	_perk = maxf(0.0, _perk - delta * 2.0)


func _draw() -> void:
	var moving := velocity.length() > 6.0
	var body_y: float
	if moving:
		body_y = -absf(sin(_time * 12.0)) * 3.0  # little running hop
	else:
		body_y = _bob * 1.4                       # gentle breathing bob
	var scale := 1.0 + 0.16 * _perk - 0.12 * _hop_squash
	var body_pos := Vector2(0, body_y - 2.0)
	var radius := 9.0 * scale

	# soft shadow (stays put on the ground)
	draw_circle(Vector2(0, 7), 7.5, Color(0, 0, 0, 0.18))
	# body
	draw_circle(body_pos, radius, _body_color)
	# two little ears
	draw_circle(body_pos + Vector2(-5, -7), 3.0, _body_color)
	draw_circle(body_pos + Vector2(5, -7), 3.0, _body_color)
	# eyes, shifted toward whatever it's attending to
	var eye_color := Color(0.12, 0.12, 0.16)
	draw_circle(body_pos + Vector2(-3, -1) + _eye_offset, 1.9, eye_color)
	draw_circle(body_pos + Vector2(3, -1) + _eye_offset, 1.9, eye_color)
