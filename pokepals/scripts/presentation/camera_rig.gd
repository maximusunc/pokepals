class_name CameraRig
extends Camera2D
## A camera that centers on the player and eases to follow, so the view stays
## steady and readable while you wander. The companion is free to roam in and out of
## frame around you — keeping the shot locked to the player (rather than splitting it
## between the two) is what makes the player feel like the anchor of the world and
## the companion's comings and goings legible as motion.
##
## It also leads slightly in the direction you're moving (look-ahead), so you see a
## little more of where you're heading than where you've been — a gentle pull that
## invites you onward into the world. On start it eases out of a brief zoomed-in
## reveal, a small "here you are" breath.
##
## companion_weight pulls the framing a little toward the companion (0 = locked to
## the player, 1 = midpoint). Default 0: centered on the player.

@export var player_path: NodePath
@export var companion_path: NodePath
@export var follow_speed := 4.5
@export var companion_weight := 0.0  # 0 = lock to player, 1 = midpoint
@export var look_ahead := 0.34       # how far to lead in the move direction (× speed)
@export var look_ahead_max := 88.0   # cap the lead so the player never leaves frame
@export var intro_zoom := 1.16       # start a touch closer, then ease out to reveal the world

var _player: Node2D
var _companion: Node2D
var _lead := Vector2.ZERO  # smoothed look-ahead offset


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_companion = get_node_or_null(companion_path)
	if _player != null:
		global_position = _player.global_position
	# Opening reveal: begin slightly zoomed in and ease out to normal, so the world
	# seems to open up around the player as the scene settles. A Tween is Godot's
	# fire-and-forget animator — it interpolates a property over time on its own.
	if intro_zoom != 1.0:
		zoom = Vector2(intro_zoom, intro_zoom)
		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "zoom", Vector2.ONE, 2.4)


## Keep the camera inside the world so we never show the void past the edges.
func set_bounds(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.position.x + rect.size.x)
	limit_bottom = int(rect.position.y + rect.size.y)


func _process(delta: float) -> void:
	if _player == null:
		return

	# Lead the framing toward where the player is heading. We read the player's
	# velocity loosely (via get) so the camera stays decoupled from the player class.
	var vel := Vector2.ZERO
	var v: Variant = _player.get("velocity")
	if v is Vector2:
		vel = v
	var desired_lead := (vel * look_ahead).limit_length(look_ahead_max)
	_lead = _lead.lerp(desired_lead, 1.0 - exp(-3.0 * delta))

	var anchor := _player.global_position
	if _companion != null:
		anchor = _player.global_position.lerp(_companion.global_position, companion_weight)
	var target := anchor + _lead
	global_position = global_position.lerp(target, 1.0 - exp(-follow_speed * delta))
