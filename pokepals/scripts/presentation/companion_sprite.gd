class_name CompanionSprite
extends RefCounted
## Draws the companion as an expressive pixel-art RIG, so its pixel form keeps the mood-
## driven aliveness the procedural VectorActor had. It composites three layers from one
## sheet — a TAIL piece (behind), a directional walk-cycle BODY, and EAR pieces (in front) —
## and moves them from the live mood signals using only integer translations (no rotation or
## scaling), so everything stays pixel-crisp:
##   tail  -> horizontal slide  (wag: rate from arousal, width from valence)
##   ears  -> vertical slide    (droop when withdrawn, perk when happy)
##   whole -> vertical slide    (idle/walk bounce + a hop/perk reaction beat)
##
## Sheet convention (see tools/gen_companion_sprite.py):
##   rows 0-2 = BODY down/side/up, cols 0-3 = walk cycle (col 0 = idle)
##   ear_row  = EARS (cols 0-2 = down/side/up);  tail_row = TAIL (cols 0-2 = down/side/up)
##   side art faces right; left is the side column mirrored.
##
## Pure presentation; a malformed/short sheet degrades gracefully (clamped frames).

const MOVE_GATE := 6.0   # matches CompanionView's walk gate
const REACT_PX := 14.0   # how many px a full perk/hop squash becomes as a lift/dip


## params: facing, speed, time, squash, wag_rate, wag_amp, ear_offset, bounce_gain
## cfg (art.json): frame:[w,h], fps, walk_frames, idle_frame, dirs, ear_row, tail_row, tail_sway_px
static func draw(ci: CanvasItem, tex: Texture2D, params: Dictionary, cfg: Dictionary) -> void:
	var facing: Vector2 = params.get("facing", Vector2.DOWN)
	var speed: float = params.get("speed", 0.0)
	var t: float = params.get("time", 0.0)

	var frame: Array = cfg.get("frame", [32, 32])
	var fw := int(frame[0])
	var fh := int(frame[1])
	var rows_total := maxi(1, int(tex.get_size().y) / fh)

	# Facing -> a direction index (0 down, 1 side, 2 up) shared by all three layers, plus a
	# left flip. Same thresholds VectorActor/SpriteActor use, so the looks agree.
	var fdir := facing
	if fdir.length() < 0.01:
		fdir = Vector2.DOWN
	fdir = fdir.normalized()
	var dir_index := 0
	var flip := false
	if fdir.y < -0.5:
		dir_index = 2
	elif absf(fdir.x) > 0.35:
		dir_index = 1
		flip = fdir.x < 0.0

	# Body walk column: advance with time when moving, hold the idle pose when still.
	var walk_frames := maxi(1, int(cfg.get("walk_frames", 4)))
	var idle_frame := clampi(int(cfg.get("idle_frame", 0)), 0, walk_frames - 1)
	var fps: float = cfg.get("fps", 8.0)
	var body_col := idle_frame
	if speed > MOVE_GATE:
		body_col = int(t * fps) % walk_frames

	var body_row := clampi(dir_index, 0, rows_total - 1)
	var ear_row := clampi(int(cfg.get("ear_row", 3)), 0, rows_total - 1)
	var tail_row := clampi(int(cfg.get("tail_row", 4)), 0, rows_total - 1)

	# Mood -> pixel offsets (rounded so the pixel grid stays aligned and crisp).
	var wag_rate: float = params.get("wag_rate", 0.0)
	var wag_amp: float = params.get("wag_amp", 0.0)
	var sway_px: float = cfg.get("tail_sway_px", 3.0)
	var tail_dx := roundi(sin(t * wag_rate) * wag_amp * sway_px)
	var ear_dy := roundi(float(params.get("ear_offset", 0.0)))  # + droop, - perk
	var bounce_gain: float = params.get("bounce_gain", 1.0)
	var bounce := -absf(sin(t * 8.0)) * 1.6 if speed > MOVE_GATE else sin(t * 2.4) * 0.6 * bounce_gain
	var react := -float(params.get("squash", 0.0)) * REACT_PX  # perk springs up, hop dips down
	var vy := roundi(bounce + react)

	if flip:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))  # mirror around origin
	_blit(ci, tex, fw, fh, dir_index, tail_row, tail_dx, vy)          # tail (behind)
	_blit(ci, tex, fw, fh, body_col, body_row, 0, vy)                 # body
	_blit(ci, tex, fw, fh, dir_index, ear_row, 0, vy + ear_dy)        # ears (in front)
	if flip:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Blit one frame (col,row) anchored bottom-centre at the origin, offset by (ox, oy) px.
static func _blit(ci: CanvasItem, tex: Texture2D, fw: int, fh: int, col: int, row: int, ox: int, oy: int) -> void:
	var region := Rect2(col * fw, row * fh, fw, fh)
	var dest := Rect2(-fw * 0.5 + ox, (8.0 - fh) + oy, fw, fh)
	ci.draw_texture_rect_region(tex, dest, region)
