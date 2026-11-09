class_name TideLayer
extends Node2D
## EBBMERE's sea: the one node that draws the tide. A child of WorldArt (above the ground, props and litter,
## under every character and tree in the y-sorted Scenery), it is ONE rectangle with ONE shader
## (assets/eb_tide.gdshader) that reads the world's baked seabed (TideField) and the current tide level and
## works out, per fragment, whether it is sea, shallows, foam, wet gloss or dry sand. Nothing is rebuilt per
## frame and no render target is used: the director hands it a level once a frame (a uniform) and that is the
## whole cost, plus a handful of small ripples where you and your companion wade. The rectangle covers only
## the part of the flats the water can ever reach, so draw cost follows what is on screen.
## Config: the world's `tide` block (`look` colours and bands).

const SHADER := preload("res://assets/eb_tide.gdshader")
const RIPPLE_LIFE := 1.2
const RIPPLE_EVERY := 0.30

var _field: TideField
var _mat: ShaderMaterial
var _extent := Rect2()
var _level := 0.5
var _time := 0.0
var _walkers: Callable
var _ripples: Array = []          # { pos, age }
var _prev := {}                   # instance id -> last position (for the wading ripples)
var _wade_t := {}                 # instance id -> seconds to the next ripple


func setup(tide: Dictionary, field: TideField, walkers: Callable) -> bool:
	_field = field
	_walkers = walkers
	if field == null or field.is_empty():
		set_process(false)
		return false
	var look: Dictionary = tide.get("look", {})
	_extent = field.wet_extent(float(tide.get("level_high", 0.78)), float(look.get("wet_band", 0.10)) + 0.03)
	if _extent.size.y <= 0.0:
		set_process(false)
		return false
	var tex := ImageTexture.create_from_image(field.to_image())
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("seabed", tex)
	var r := field.rect()
	_mat.set_shader_parameter("field_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	_mat.set_shader_parameter("deep_elev", field.deep_elev)
	for key in ["deep", "shallow", "foam", "wet", "sheen"]:
		if look.has(key):
			_mat.set_shader_parameter(key + "_col", WorldData.to_color(look[key]))
	for key in ["wet_band", "foam_band", "shallow_alpha", "deep_alpha"]:
		if look.has(key):
			_mat.set_shader_parameter(key, float(look[key]))
	material = _mat
	return true


func extent() -> Rect2:
	return _extent


func level() -> float:
	return _level


## The director's one call per frame.
func set_level(l: float) -> void:
	_level = l
	if _mat != null:
		_mat.set_shader_parameter("level", l)


func _process(delta: float) -> void:
	_time += delta
	if _mat != null:
		_mat.set_shader_parameter("time", _time)
	_update_wading(delta)
	var keep: Array = []
	for r in _ripples:
		r["age"] = float(r["age"]) + delta
		if float(r["age"]) < RIPPLE_LIFE:
			keep.append(r)
	_ripples = keep
	queue_redraw()


## A ring spreads from the feet of you and your companion as you wade (only the two that are yours: a friend's
## ripples would need a velocity we don't have and cost more than they say).
func _update_wading(delta: float) -> void:
	if not _walkers.is_valid() or _field == null:
		return
	var list: Array = _walkers.call()
	for i in mini(2, list.size()):
		var w: Node2D = list[i]
		if not is_instance_valid(w):
			continue
		var id := w.get_instance_id()
		var foot: Vector2 = w.position + Vector2(0.0, 8.0)
		var last: Vector2 = _prev.get(id, foot)
		_prev[id] = foot
		var speed := foot.distance_to(last) / maxf(delta, 0.0001)
		var left := float(_wade_t.get(id, 0.0)) - delta
		if speed > 14.0 and left <= 0.0 and _field.depth(foot, _level) > 0.012 and not _field.is_deep(foot):
			_ripples.append({ "pos": foot, "age": 0.0 })
			left = RIPPLE_EVERY
		_wade_t[id] = left


func _draw() -> void:
	if _extent.size.y <= 0.0:
		return
	draw_rect(_extent, Color.WHITE)
	for r in _ripples:
		var p: float = float(r["age"]) / RIPPLE_LIFE
		var rad := 4.0 + p * 15.0
		draw_set_transform(r["pos"], 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, rad, 0.0, TAU, 20, Color(1.0, 1.0, 1.0, 0.55 * (1.0 - p)), 1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
