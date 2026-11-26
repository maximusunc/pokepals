class_name ArchView
extends BuildingView
## One free-standing marble ARCH (Lingerlong): a BuildingView (the y-sorted, walk-behind mass the brick city uses)
## drawn from smooth @2x art instead of tiles. You walk through its doorway: its collision is only its two legs (the
## spec's `solid_rects`, see Solids.build), and because its node sits at the foot of its footprint you are drawn
## behind it on its far side and in front of it on its near side, like a tree.
##
## Chosen by a spec's `"view": "arch"` (Scenery.add_buildings). Its art is the art direction's "arch" entity:
##   frame          the arch itself (transparent where the doorway is)
##   pictures       { name: path }: a picture filling only the doorway, drawn UNDER the frame (a door that opens on
##                  somewhere else). A spec's `"picture": "<name>"` picks one (the Late Arch's evening, the
##                  terrace's afternoon).
##   foot           world px from the image's bottom edge up to the foot line (the art bakes a floor reflection there)
##
## For what comes later (the Late Arch opening): `set_picture`, `picture_alpha`, and `set_between(fn)`, a drawing
## hook called between the picture and the frame (fn(ci: CanvasItem), in this node's space, origin at the feet).
## `doorway_rect()` is the opening, in the same space. Find one by id with Scenery.building(id).
## Pure presentation: the legs' collision is built from the same spec by Solids.

const DOOR_W := 52.0
const DOOR_H := 84.0

var picture_alpha := 1.0
var _frame: Texture2D = null
var _picture: Texture2D = null
var _pictures := {}
var _foot := 8.0
var _between: Callable = Callable()


func setup(s: Dictionary, style: ArtStyle) -> void:
	super.setup(s, style)
	var cfg := style.entity("arch")
	_frame = _tex(String(cfg.get("frame", "")))
	_foot = float(cfg.get("foot", 8.0))
	var pics: Dictionary = cfg.get("pictures", {})
	for k in pics:
		_pictures[String(k)] = String(pics[k])
	set_picture(String(s.get("picture", "")))
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_animated = false
	name = "Arch_%s" % String(s.get("id", "arch"))


static func _tex(path: String) -> Texture2D:
	return load(path) if path != "" and ResourceLoader.exists(path) else null


## Show the doorway picture `name` (one of the art entity's pictures), or none ("").
func set_picture(pic_name: String) -> void:
	_picture = _tex(String(_pictures.get(pic_name, ""))) if pic_name != "" else null
	queue_redraw()


func has_picture() -> bool:
	return _picture != null


## Draw `fn(ci)` between the doorway picture and the frame every frame while it is set (an invalid Callable clears
## it). The arch redraws itself every frame only while a hook is set.
func set_between(fn: Callable) -> void:
	_between = fn
	_animated = fn.is_valid()
	queue_redraw()


## The doorway, in this node's space (origin at the feet).
func doorway_rect() -> Rect2:
	return Rect2(-DOOR_W * 0.5, -DOOR_H, DOOR_W, DOOR_H)


## An arch never fades for someone behind it: you can see them through the doorway, and its legs are slim.
func occludes(_p: Vector2) -> bool:
	return false


func _draw() -> void:
	if _picture != null and picture_alpha > 0.0:
		_blit(_picture, Color(1, 1, 1, picture_alpha))
	if _between.is_valid():
		_between.call(self)
	if _frame != null:
		_blit(_frame, Color.WHITE)
	else:
		_draw_plain()


func _blit(t: Texture2D, mod: Color) -> void:
	var sz := t.get_size() * 0.5
	draw_texture_rect(t, Rect2(Vector2(-sz.x * 0.5, _foot - sz.y), sz), false, mod)


## No art yet: a plain marble arch in the house palette, so the world still reads.
func _draw_plain() -> void:
	var marble := Color(0.965, 0.937, 0.902)
	var shade := Color(0.725, 0.655, 0.839)
	var leg := (hw * 2.0 - DOOR_W) * 0.5
	for x in [-hw, DOOR_W * 0.5]:
		draw_rect(Rect2(x, -DOOR_H, leg, DOOR_H), marble)
		draw_rect(Rect2(x + leg - 3.0, -DOOR_H, 3.0, DOOR_H), shade)
	draw_rect(Rect2(-hw, -DOOR_H - 30.0, hw * 2.0, 30.0), marble)
	draw_rect(Rect2(-hw, -DOOR_H - 4.0, hw * 2.0, 4.0), shade)
