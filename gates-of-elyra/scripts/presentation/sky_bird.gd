class_name SkyBird
extends Node2D
## The companion in flight (Loftreach): a puppet that draws the companion's own animal sheet (the bird it is
## wearing) wheeling in the air, lifted above a soft shadow on the ground it passes over. SkyDirector places it
## (`position` is the point on the ground beneath), sets how high it is and how big it should look, and hides the
## real companion while it is up. It draws with PalSprite, the very core the companion draws itself with, so it is
## never a copy of the art. Presentation only.

var lift := 0.0              # px above its ground point
var look := Vector2.RIGHT    # which way it is flying
var _tex: Texture2D = null
var _sheet: Dictionary = {}
var _time := 0.0


func _ready() -> void:
	z_index = 30
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## The sheet the bird is drawn from (CompanionView.form_sheet_info()).
func set_sheet(info: Dictionary) -> void:
	_tex = info.get("tex")
	_sheet = info.get("sheet", {})


func has_sheet() -> bool:
	return _tex != null


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	# the shadow it throws on the ground far below: it shrinks and fades as the bird climbs
	# (the node's origin is the BIRD, `lift` px above its ground point; the node is scaled up as it climbs, so
	# the shadow's offset back down to the ground is divided by that scale)
	var k := clampf(1.0 - lift / 420.0, 0.2, 1.0)
	var s := maxf(0.01, scale.y)
	SoftGlow.draw(self, Vector2(0.0, lift / s + 6.0), 14.0 * k, Color(0.1, 0.16, 0.3, 0.30 * k), 0.4)
	if _tex == null:
		return
	PalSprite.draw(self, _tex, { "look": look, "speed": 140.0, "time": _time }, _sheet)
