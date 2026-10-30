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
##   cols = motion frames (col 0 = the rest pose without an idle loop); rows = the RIGHT-handed facing family
##   (down, down_right, right, up_right, up) — the left family is that row mirrored. A bird carries
##   an extra 'fly_row' it switches to while moving, so it flutters between spots. A sheet that
##   carries an IDLE loop (tools/pixelart/gait.py: a tail swish, a blink, a breath) keeps it in the
##   'idle_cols' columns right after the motion frames, played at 'idle_fps' while standing still.
##
## Pure presentation; nothing here reads game state. Pixel-crisp: integer-ish translations plus a
## gentle vertical scale about the ground line (which can shimmer a touch, but stays subtle).

const MOVE_GATE := 4.0   # px/sec of eased motion that counts as "moving"
const FOOT_Y := 8.0      # feet sit at origin+8, like SpriteActor/SpriteSlot


## params: look (Vector2 facing/attention), speed (px/s), time (s), bounce (px, +down), squash
##         (+pop up / -dip down), offset (Vector2 px nudge, e.g. a shy creature shrinking back). cfg:
##         frame:[w,h], fps, cols, rows:{down,down_right,right,up_right,up}, fly_row (-1 if none),
##         animate_idle (keep cycling while still — floaters), idle_cols (resting-loop frames after
##         the motion columns, 0 = none: rest on col 0), idle_fps.
static func draw(ci: CanvasItem, tex: Texture2D, params: Dictionary, cfg: Dictionary) -> void:
	if tex == null:
		return
	var look: Vector2 = params.get("look", Vector2.DOWN)
	var speed: float = params.get("speed", 0.0)
	var t: float = params.get("time", 0.0)
	var bounce: float = params.get("bounce", 0.0)
	var squash: float = params.get("squash", 0.0)
	var offset: Vector2 = params.get("offset", Vector2.ZERO)

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
	# A hovering creature (a world's native floater) keeps its motion cycle running at rest, so it
	# drifts and ripples rather than freezing on the idle frame.
	var col := 0
	var idle_cols := int(cfg.get("idle_cols", 0))
	if moving or bool(cfg.get("animate_idle", false)):
		col = int(t * fps) % cols
	elif idle_cols > 0:
		# Offset each drawer's loop by its node id so a flock standing together never blinks in unison.
		var phase := float(ci.get_instance_id() % 997) * 0.37
		col = cols + int((t + phase) * float(cfg.get("idle_fps", 5.0))) % idle_cols
	var region := Rect2(col * fw, row * fh, fw, fh)
	var dest := Rect2(-fw * 0.5, FOOT_Y - fh, fw, fh)

	# Fold the left-facing mirror, the reaction squash (scaled about the ground line so it pops from
	# its feet, not its centre) and the idle bounce into one transform. With squash=0, bounce=0 and
	# no flip this is the identity — so an ambient pal renders pixel-for-pixel as it did untransformed.
	var sy := 1.0 + squash
	var sx := -1.0 if flip else 1.0
	ci.draw_set_transform(offset + Vector2(0.0, FOOT_Y * (1.0 - sy) + bounce), 0.0, Vector2(sx, sy))
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
