class_name TrottingFox
extends Control
## The little fox from the loading screen: fox_0's right-facing row from the pal sheets, trotting in
## place over a soft oval of shade, or standing still. It's the same fox, at the same size and the
## same spot, that the web loading page and the boot splash show (tools/gen_loading.py bakes those),
## so the connection gate continues the scene without a jump. The welcome panel borrows it too.
##
## A Control that draws itself in _draw() (Godot calls _draw when the node needs repainting; we ask
## for a repaint each frame with queue_redraw() while it trots). Pure presentation.

const SHEET_PATH := "res://assets/pals/fox_0.png"
const CELL := 32          # one sheet cell (data/pals.json "frame")
const ROW_RIGHT := 2      # the facing-right row
const TROT_FRAMES := 8    # move columns 0..7
const STAND_COL := 8      # the first idle-loop column: the calm standing pose
const FEET_ROW := 27      # last row of the feet inside the cell (keep in step with gen_loading.py)
const FPS := 10.0         # the pal sheets' walk rate
const SHADOW_W := 17.0    # shade width per pixel of scale (34 at the loading screen's 2x)

## Trot in place (true) or stand (false).
var trotting := true:
	set(v):
		trotting = v
		queue_redraw()

var _px := 2
var _tex: Texture2D
var _t := 0.0


func _init(px := 2) -> void:
	_px = px


func _ready() -> void:
	_tex = load(SHEET_PATH) as Texture2D
	custom_minimum_size = Vector2(CELL, CELL) * _px
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if trotting:
		_t += delta
		queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var s := float(_px)
	var cx := size.x * 0.5
	# The shade: a circle squashed flat into an oval, centred under the feet.
	var w := SHADOW_W * s
	draw_set_transform(Vector2(cx, FEET_ROW * s), 0.0, Vector2(1.0, 5.0 / 34.0))
	draw_circle(Vector2.ZERO, w * 0.5, Color(0.0, 0.0, 0.0, 0.27))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var col := (int(_t * FPS) % TROT_FRAMES) if trotting else STAND_COL
	var region := Rect2(col * CELL, ROW_RIGHT * CELL, CELL, CELL)
	draw_texture_rect_region(_tex, Rect2(cx - CELL * s * 0.5, 0.0, CELL * s, CELL * s), region)
