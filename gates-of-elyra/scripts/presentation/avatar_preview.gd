class_name AvatarPreview
extends Control
## A live, self-animating portrait of a PlayerAppearance — the customizer's mirror. It runs
## the EXACT render path the world uses (PlayerAppearance.resolved_layers -> AvatarCompositor),
## so what you see here is what you'll be in the world: same layers, same recolor, same walk.
##
## Pure presentation: hand it a working PlayerAppearance + the shared catalog; it resolves the
## worn loadout into drawable layers once per change (not per frame) and blits them, integer-
## scaled up and centred, gently walking so the avatar feels alive while you dress it.

@export var pixel_scale := 4.0     # integer zoom so pixels stay crisp
@export var walk := true           # a gentle idle stroll so the portrait breathes

var _catalog: CosmeticsCatalog
var _appearance: PlayerAppearance
var _layers: Array = []
var _time := 0.0


func _ready() -> void:
	# The composited layers are drawn nearest-neighbour for crisp pixels at integer zoom.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Point the preview at a working appearance (and the catalog it resolves against). Call again
## after any equip/color change — it re-resolves the drawable layers and redraws.
func show_appearance(appearance: PlayerAppearance, catalog: CosmeticsCatalog) -> void:
	_appearance = appearance
	_catalog = catalog
	_refresh()


## Re-resolve the worn loadout into loaded (recolored) layers. Cheap enough to call on every
## wardrobe tweak; the recolor bake itself is cached by (sheet, ramp) in AvatarCompositor.
func _refresh() -> void:
	if _appearance == null or _catalog == null:
		_layers = []
	else:
		_layers = AvatarCompositor.load_layers(_appearance.resolved_layers(_catalog))
	queue_redraw()


func _process(delta: float) -> void:
	if walk:
		_time += delta
		queue_redraw()


func _draw() -> void:
	if _layers.is_empty():
		return
	# Anchor the avatar centred horizontally with its feet a little below the middle, then draw
	# through the shared compositor at an integer zoom. Facing 'down' avoids SpriteActor's flip
	# transform so our scale stays intact.
	var origin := Vector2(size.x * 0.5, size.y * 0.5 + 8.0 * pixel_scale)
	draw_set_transform(origin, 0.0, Vector2(pixel_scale, pixel_scale))
	AvatarCompositor.draw(self, _layers, {
		"facing": Vector2.DOWN,
		"speed": 100.0 if walk else 0.0,   # above SpriteActor's MOVE_GATE -> the walk cycle plays
		"time": _time,
	})
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
