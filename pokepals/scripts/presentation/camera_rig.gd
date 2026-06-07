class_name CameraRig
extends Camera2D
## A camera that frames the player AND the companion together. It eases toward a
## point weighted mostly to the player but pulled a little toward the companion, so
## the pair stays comfortably in shot without the camera feeling twitchy.

@export var player_path: NodePath
@export var companion_path: NodePath
@export var follow_speed := 4.5
@export var companion_weight := 0.32  # 0 = lock to player, 1 = midpoint

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
