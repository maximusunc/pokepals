class_name PalSprite
extends RefCounted
## Draws a real-animal sprite from a pal sheet (data/pals.json + tools/gen_pals.py, art in
## tools/pixelart) — the shared drawing core behind both the ambient PalView and the bonded
## companion's daemon form. Given the sheet, a look direction and a speed, it picks the right
## facing row + motion column and blits it, anchored feet-on-ground. An optional idle bounce and
## a squash/stretch let the same rig carry the companion's little reaction beats (a perk pop, a
## hop dip) on top of the flat sheet; ambient pals pass neither and render exactly as before.
##
## Sheet convention:
##   cols = motion frames, col 0 = idle; rows = the RIGHT-handed facing family
##   (down, down_right, right, up_right, up) — the left family is that row mirrored. A bird carries
##   an extra 'fly_row' it switches to while moving, so it flutters between spots.
##
## Pure presentation; nothing here reads game state. Pixel-crisp: integer-ish translations plus a
## gentle vertical scale about the ground line (which can shimmer a touch, but stays subtle).

const MOVE_GATE := 4.0   # px/sec of eased motion that counts as "moving"
const FOOT_Y := 8.0      # feet sit at origin+8, like SpriteActor/SpriteSlot


## params: look (Vector2 facing/attention), speed (px/s), time (s), bounce (px, +down), squash
##         (+pop up / -dip down). cfg: frame:[w,h], fps, cols, rows:{down,down_right,right,up_right,up},
##         fly_row (-1 if none).
static func draw(ci: CanvasItem, tex: Texture2D, params: Dictionary, cfg: Dictionary) -> void:
	if tex == null:
		return
	var look: Vector2 = params.get("look", Vector2.DOWN)
	var speed: float = params.get("speed", 0.0)
	var t: float = params.get("time", 0.0)
	var bounce: float = params.get("bounce", 0.0)
	var squash: float = params.get("squash", 0.0)

	var frame: Array = cfg.get("frame", [32, 32])
	var fw := int(frame[0])
	var fh := int(frame[1])
	var fps: float = cfg.get("fps", 10.0)
	var cols := maxi(1, int(cfg.get("cols", 8)))
	var rows: Dictionary = cfg.get("rows", {})
	var fly_row := int(cfg.get("fly_row", -1))

	var moving := speed > MOVE_GATE
	var rf := _facing_row(look, rows)
	var row := int(rf[0])
	var flip := bool(rf[1])
	if moving and fly_row >= 0:
		# Airborne cycle reads as a profile: face strictly left/right of travel.
		row = fly_row
		flip = look.x < 0.0
	var col := int(t * fps) % cols if moving else 0
	var region := Rect2(col * fw, row * fh, fw, fh)
	var dest := Rect2(-fw * 0.5, FOOT_Y - fh, fw, fh)

	# Fold the left-facing mirror, the reaction squash (scaled about the ground line so it pops from
	# its feet, not its centre) and the idle bounce into one transform. With squash=0, bounce=0 and
	# no flip this is the identity — so an ambient pal renders pixel-for-pixel as it did untransformed.
	var sy := 1.0 + squash
	var sx := -1.0 if flip else 1.0
	ci.draw_set_transform(Vector2(0.0, FOOT_Y * (1.0 - sy) + bounce), 0.0, Vector2(sx, sy))
	ci.draw_texture_rect_region(tex, dest, region)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The right-handed facing row for a look vector, plus whether to mirror (the left family).
static func _facing_row(dir: Vector2, rows: Dictionary) -> Array:
	if dir.length() < 0.01:
		dir = Vector2.DOWN
	var octant := roundi(dir.angle() / (PI / 4.0))  # 0=right, positive = screen-down
	match octant:
		0: return [int(rows.get("right", 2)), false]
		1: return [int(rows.get("down_right", 1)), false]
		2: return [int(rows.get("down", 0)), false]
		3: return [int(rows.get("down_right", 1)), true]
		-1: return [int(rows.get("up_right", 3)), false]
		-2: return [int(rows.get("up", 4)), false]
		-3: return [int(rows.get("up_right", 3)), true]
		_: return [int(rows.get("right", 2)), true]  # 4/-4 = left
