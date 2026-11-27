class_name ShadowPuppet
extends Node2D
## One SHADOW on Lanternfold's screen: the cut-paper silhouette a player or a companion throws from the great
## lantern onto the cliff face. A child of the ShadowScreenView, so it lives in the face's own space; the view
## hands it the projection (ShadowCast, via the MuralGuide) and this node only draws.
##
## It is a PROFILE: a shadow puppet is always seen from the side, so whatever way the caster is walking or
## facing on the ground, the shadow shows its right-hand profile row (mirrored for left) and plays the walk
## cycle while it moves and the idle loop while it stands. A bird's shadow takes wing (its sheet's fly row,
## flapping): that is what lets it hang in the air where the mural's bird is missing.
##
## It draws the very same sheet the caster draws (an animal's PalSprite sheet, or the player's worn wardrobe
## layers), so a wolf's shadow IS a wolf and a player's IS that player, in whatever they are wearing; the
## silhouette shader (assets/silhouette.gdshader, set on this node by the view) keeps only the shape.
## Presentation only: it reads the caster, it changes nothing about it.

const MOVE_GATE := 6.0

var caster: Node2D = null
var kind := "player"            # "player" or "companion"
var species := ""               # what a companion wears right now ("" for a player)

var _facing := 1.0              # +1 right, -1 left: the way its profile faces
var _speed := 0.0               # eased px/s the caster is moving at
var _last_pos := Vector2.ZERO
var _have_last := false
var _time := 0.0
var _sheet: Dictionary = {}


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## How fast the caster is moving and which way (read off its position, so it works for any puppet, local or
## remote), and what a companion is wearing. Call once a frame.
func observe(delta: float) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	_time += delta
	if _have_last and delta > 0.0:
		var v := (caster.position - _last_pos) / delta
		_speed = lerpf(_speed, v.length(), clampf(delta * 14.0, 0.0, 1.0))
		if absf(v.x) > MOVE_GATE:
			_facing = 1.0 if v.x > 0.0 else -1.0
	_last_pos = caster.position
	_have_last = true
	if kind == "companion":
		species = caster.current_form_species()
		_sheet = caster.form_sheet_info()


func speed() -> float:
	return _speed


func _draw() -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var look := Vector2(_facing, 0.0)
	if kind == "companion":
		var tex: Texture2D = _sheet.get("tex")
		if tex == null:
			return
		var spd := _speed
		if species == "bird":
			spd = 20.0   # a bird's shadow is in flight: the wing-beat cycle
		PalSprite.draw(self, tex, { "look": look, "speed": spd, "time": _time }, _sheet["sheet"])
	else:
		var layers: Array = caster.avatar_layers()
		if AvatarCompositor.has_drawable(layers):
			AvatarCompositor.draw(self, layers, { "facing": look, "speed": _speed, "time": _time })
