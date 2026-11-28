class_name ReflectionPuppet
extends Node2D
## One mirrored actor on Stillglass's lake: a node that draws a player (the worn wardrobe layers) or an
## animal (a pal sheet: your companion's, a friend's, or the odd one the lake shows instead) the way that
## actor draws itself, but UPSIDE DOWN: the node is flipped (scale.y = -1) about the waterline, so the same
## drawing code (AvatarCompositor / PalSprite) that draws the real actor draws its image, no copy of the
## art and no render target. Its ShaderMaterial (assets/reflect.gdshader) clips it to the water, silvers it
## and ripples it. Presentation only; ReflectionLayer places and feeds it every frame.

var _kind := ""            # "player" | "pal" | ""
var _pose: Dictionary = {}
var _mat: ShaderMaterial


func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	scale = Vector2(1.0, -1.0)


func set_shader_material(m: ShaderMaterial) -> void:
	_mat = m
	material = m


func material_ref() -> ShaderMaterial:
	return _mat


## Feed the pose to draw (the actor's `reflection_pose()`), and which kind of drawing it is.
func set_pose(kind: String, pose: Dictionary) -> void:
	_kind = kind
	_pose = pose
	queue_redraw()


## Put the image's feet at `foot_y` (where the mirrored feet land, world y) under x. The node is flipped, so
## its local +8 (the sprites' feet) maps to 8 px ABOVE its origin on screen.
func place(x: float, foot_y: float) -> void:
	position = Vector2(x, foot_y + 8.0)


func _draw() -> void:
	if _pose.is_empty():
		return
	if _kind == "player":
		var layers: Array = _pose.get("layers", [])
		if not layers.is_empty():
			AvatarCompositor.draw(self, layers, { "facing": _pose.get("facing", Vector2.DOWN), "speed": _pose.get("speed", 0.0), "time": _pose.get("time", 0.0) })
	elif _kind == "pal" and _pose.get("tex") != null:
		PalSprite.draw(self, _pose["tex"], { "look": _pose.get("look", Vector2.DOWN), "speed": _pose.get("speed", 0.0), "time": _pose.get("time", 0.0) },
			_pose.get("sheet", {}))
