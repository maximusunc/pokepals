class_name SpriteActor
extends RefCounted
## Draws one frame of a directional, animated character sheet — the sprite counterpart
## to VectorActor. Pure presentation: handed the actor's facing/speed/time each frame, it
## picks the right row (facing) and column (walk phase) and blits it, anchored bottom-centre
## so feet sit on the ground exactly like SpriteSlot/VectorActor.
##
## Sheet convention (see tools/gen_player_sprite.py):
##   rows = facings: "down", "side", "up"   (left = the "side" row drawn flipped)
##   cols = a walk cycle; column 0 doubles as the idle pose.
##
## All metadata lives in art.json so the look stays data-driven. A malformed/short sheet
## degrades gracefully (clamped frames), keeping the silent-fallback discipline.

const MOVE_GATE := 8.0   # matches PlayerView's walk gate (player_controller.gd)


## cfg keys (from art.json's character entry):
##   frame:[w,h], fps:float, walk_frames:int, idle_frame:int, dirs:{down,side,up -> row}
static func draw(ci: CanvasItem, tex: Texture2D, params: Dictionary, cfg: Dictionary) -> void:
	var facing: Vector2 = params.get("facing", Vector2.DOWN)
	var speed: float = params.get("speed", 0.0)
	var t: float = params.get("time", 0.0)

	var frame: Array = cfg.get("frame", [32, 32])
	var fw := int(frame[0])
	var fh := int(frame[1])
	var sheet := tex.get_size()
	var cols_total := maxi(1, int(sheet.x) / fw)
	var rows_total := maxi(1, int(sheet.y) / fh)

	# Which way are we facing? Same few facts VectorActor derives, so the two looks agree.
	var fdir := facing
	if fdir.length() < 0.01:
		fdir = Vector2.DOWN
	fdir = fdir.normalized()
	var dirs: Dictionary = cfg.get("dirs", {"down": 0, "side": 1, "up": 2})
	var row := int(dirs.get("down", 0))
	var flip := false
	if fdir.y < -0.5:
		row = int(dirs.get("up", 2))
	elif absf(fdir.x) > 0.35:
		row = int(dirs.get("side", 1))
		flip = fdir.x < 0.0   # the sheet faces right; mirror it for left
	else:
		row = int(dirs.get("down", 0))
	row = clampi(row, 0, rows_total - 1)

	# Walk cycle: advance with time when moving, hold the idle pose when still.
	var walk_frames := clampi(int(cfg.get("walk_frames", cols_total)), 1, cols_total)
	var idle_frame := clampi(int(cfg.get("idle_frame", 0)), 0, walk_frames - 1)
	var fps: float = cfg.get("fps", 8.0)
	var col := idle_frame
	if speed > MOVE_GATE:
		col = int(t * fps) % walk_frames

	var region := Rect2(col * fw, row * fh, fw, fh)
	# Anchor bottom-centre at the node origin (feet on the ground), like SpriteSlot.draw.
	var dest := Rect2(-fw * 0.5, 8.0 - fh, fw, fh)
	if flip:
		# Mirror around the origin via a scale transform (reliable, unlike a negative Rect2).
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
		ci.draw_texture_rect_region(tex, dest, region)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_texture_rect_region(tex, dest, region)
