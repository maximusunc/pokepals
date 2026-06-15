class_name CameraRig
extends Camera2D
## A camera that centers on the player and eases to follow, so the view stays
## steady and readable while you wander. The companion is free to roam in and out of
## frame around you — keeping the shot locked to the player (rather than splitting it
## between the two) is what makes the player feel like the anchor of the world and
## the companion's comings and goings legible as motion.
##
## companion_weight pulls the framing a little toward the companion (0 = locked to
## the player, 1 = midpoint). Default 0: centered on the player.

@export var player_path: NodePath
@export var companion_path: NodePath
@export var follow_speed := 4.5
@export var companion_weight := 0.0  # 0 = lock to player, 1 = midpoint

var _player: Node2D
var _companion: Node2D


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_companion = get_node_or_null(companion_path)
	if _player != null:
		global_position = _player.global_position


## Keep the camera inside the world so we never show the void past the edges.
func set_bounds(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.position.x + rect.size.x)
	limit_bottom = int(rect.position.y + rect.size.y)


func _process(delta: float) -> void:
	if _player == null:
		return
	var target := _player.global_position
	if _companion != null:
		target = _player.global_position.lerp(_companion.global_position, companion_weight)
	global_position = global_position.lerp(target, 1.0 - exp(-follow_speed * delta))
