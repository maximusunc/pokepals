class_name TreeView
extends Node2D
## A single tree (or great tree), drawn relative to its own origin so the engine can
## depth-sort it. Its origin (0,0) sits at the trunk base / "feet" — the same anchor
## the player and companion use — so when these all live under a `y_sort_enabled`
## parent (see Scenery), Godot draws them back-to-front by their ground position.
## That's what lets you walk *behind* a tree's canopy on its far side and *in front*
## of its trunk on the near side.
##
## Pure presentation: it holds a wind phase and an art style and paints itself. The
## drawing was lifted from WorldArt so the trees look exactly as before — only *where
## in the draw order* they land has changed.

var phase := 0.0          # per-tree wind offset so the grove doesn't sway in lockstep
var is_great := false      # great-tree (landmark) vs. an ordinary tree
var style: ArtStyle
# Optional drop-in art, in order of preference (each absent → next fallback):
#  • trunk_tex + canopy_tex: two layers — trunk stays planted, only the canopy sways.
#  • tex: one whole-tree sprite — the whole thing sways together.
#  • none: the procedural circles below.
var tex: Texture2D = null
var trunk_tex: Texture2D = null
var canopy_tex: Texture2D = null
var wind_strength := 2.6
var wind_speed := 1.15
# How much of the wind this kind catches (a crystal spire is 0: it doesn't sway at all).
var sway_gain := 1.0
# An optional light the growth gives off (Nocthollow): a breathing halo around its crown at glow_y,
# plus a faint pool of it on the ground. Alpha 0 / radius 0 = no glow (every meadow tree).
var glow_color := Color(0, 0, 0, 0)
var glow_radius := 0.0
var glow_y := -24.0
# How many world units one texel covers. 1 for the pixel-art groves; 0.5 for smooth "@2x" art
# (Bobbledown's), which is baked at twice the world resolution and drawn at half size, linearly
# filtered, so its curves stay smooth when the view is scaled up.
var tex_scale := 1.0
# Where the art's feet are, in px below the node's origin: the bottom edge of the image sits this far down. -1
# keeps the house default (6 for a tree, 8 for a great tree). Lingerlong's art bakes a polished-floor reflection
# below each thing's foot, so its kinds say how deep that margin is (the art entity's "foot").
var foot := -1.0
# A thing that FLOATS (the art entity's "float": Lingerlong's busts over their plinths): its canopy layer is not
# a crown in the wind but something hovering `height` px over a resting line `rest` px above the feet, bobbing
# `bob` px every `period` seconds, out of phase with its neighbours, over a soft contact shadow (`shadow`: its
# half-width) that tightens as it dips. Drawn from the shared clock Scenery already ticks, so a floating thing
# costs no more than a swaying one. Empty = nothing floats.
var float_cfg: Dictionary = {}
# Perspective worlds (Horizon) see things from every side. `facing` is the way its front looks (a bearing in
# radians: 0 north, PI/2 east, PI south, toward the top-down viewer). Something drawn from several bearings
# round it gives them as `angle_frames` (frame k: seen by a viewer whose heading is k steps clockwise of looking
# straight at its front), and shows the one for where you look from (PerspectiveView.view_yaw). A flat thing (a
# fence panel, a signpost) is instead a "card": PerspectiveView narrows it by the angle it's seen at.
var facing := PI
var angle_frames: Array = []
## A card painted on its front only (Farmeadow's farmyard): what it shows when seen from behind.
var back_tex: Texture2D = null
## In a perspective view, a card is drawn in upright slices PerspectiveView lays out (4 points per slice, local:
## bottom-left, bottom-right, top-right, top-left; `_card_us` the texture's u at each slice edge). Empty otherwise.
var _card_quads := PackedVector2Array()
var _card_us := PackedFloat32Array()


func set_card_quads(quads: PackedVector2Array, us: PackedFloat32Array) -> void:
	_card_quads = quads
	_card_us = us
	queue_redraw()


func _draw_card_slices() -> void:
	var t := tex
	if back_tex != null and cos(angle_difference(facing - PI, PerspectiveView.view_yaw)) < 0.0:
		t = back_tex   # seen from behind
	if t == null:
		return
	var white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	for i in _card_us.size() - 1:
		var u0 := _card_us[i]
		var u1 := _card_us[i + 1]
		var q := _card_quads.slice(i * 4, i * 4 + 4)
		draw_polygon(q, white, PackedVector2Array([Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)]), t)

var _time := 0.0

# Home building: a tree can be chopped down (HarvestDirector). It topples, a puff of leaves, and leaves a
# stump, until it grows back up out of it. `felled` is the shared truth (the server's); the rest is animation,
# timed on this tree's own clock (set_time).
const FALL_TIME := 0.55
const POOF_TIME := 0.35
const GROW_TIME := 1.4
var felled := false
var _fell_at := -100.0      # when it began to topple (in _time)
var _grow_at := -100.0      # when it began to grow back
var _shake_at := -100.0     # an axe's last bite (while a chop takes time)
var _fall_dir := 1.0


## The grove no longer self-animates: with hundreds of trees in a large world (the Ruin's
## border ring alone is several hundred), one `_process` + `queue_redraw` per tree every
## frame is the bulk of the cost. Scenery now drives a single shared clock and only ticks
## the trees the camera can see — so this pushes the time in from the parent (the very
## fallback the old comment here anticipated). Each tree keeps its own stable `phase`, so a
## shared `_time` sways them all out of lockstep exactly as before.
func set_time(t: float) -> void:
	_time = t
	queue_redraw()


## Horizontal wind offset for this tree's canopy. Taller things catch more wind, so
## the caller scales by `gain` (mirrors WorldArt._sway).
func _sway(gain: float) -> float:
	return sin(_time * wind_speed + phase) * wind_strength * gain


## Chopped down: it topples away from you (`away` is the side, -1 left / 1 right), then a stump.
func fell(away := 1.0) -> void:
	felled = true
	_fall_dir = 1.0 if away >= 0.0 else -1.0
	_fell_at = _time
	queue_redraw()


## Already down when we arrived: just the stump, no toppling.
func set_felled_now() -> void:
	felled = true
	_fell_at = -100.0
	queue_redraw()


## It grows back up out of its stump.
func regrow() -> void:
	felled = false
	_grow_at = _time
	queue_redraw()


## An axe bites (while a chop takes several swings): a shiver through the crown.
func shake() -> void:
	_shake_at = _time


func _draw() -> void:
	if not _card_quads.is_empty():
		_draw_card_slices()
		return
	if is_great:
		_draw_great()
		return
	if felled:
		_draw_stump()
		var t := _time - _fell_at
		if t < FALL_TIME:
			var k := t / FALL_TIME
			draw_set_transform(Vector2.ZERO, _fall_dir * 1.45 * k * k, Vector2.ONE)
			_draw_normal()
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif t < FALL_TIME + POOF_TIME:
			_draw_poof((t - FALL_TIME) / POOF_TIME)
		return
	var g := _time - _grow_at
	if g < GROW_TIME:
		var k := clampf(g / GROW_TIME, 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)
		_draw_stump()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.25 + 0.75 * k, 0.15 + 0.85 * k))
		_draw_normal()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var sh := _time - _shake_at
	if sh < 0.3:
		draw_set_transform(Vector2(sin(sh * 60.0) * 1.5 * (1.0 - sh / 0.3), 0.0), 0.0, Vector2.ONE)
		_draw_normal()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	_draw_normal()


## What's left of a felled tree: a short trunk with its cut face up, rings and all.
func _draw_stump() -> void:
	var bark := style.color("bark") if style != null else Color(0.42, 0.30, 0.20)
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-6, -6, 12, 9), bark)
	draw_rect(Rect2(-6, -6, 3, 9), bark.lightened(0.14))
	draw_rect(Rect2(3, -6, 3, 9), bark.darkened(0.18))
	draw_rect(Rect2(-8, 1, 3, 2), bark.darkened(0.1))     # a root either side
	draw_rect(Rect2(5, 1, 3, 2), bark.darkened(0.1))
	draw_set_transform(Vector2(0, -6), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 6.0, Color(0.86, 0.72, 0.50))
	draw_arc(Vector2.ZERO, 3.8, 0.0, TAU, 12, Color(0.72, 0.56, 0.36), 1.0)
	draw_arc(Vector2.ZERO, 1.8, 0.0, TAU, 8, Color(0.72, 0.56, 0.36), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The crown hits the ground in a soft puff of leaves.
func _draw_poof(k: float) -> void:
	var f := style.color("foliage_mid") if style != null else Color(0.36, 0.56, 0.30)
	var base := Vector2(_fall_dir * 22.0, -6.0)
	for i in 9:
		var a := TAU * float(i) / 9.0 + phase
		var r := 4.0 + 18.0 * k
		draw_circle(base + Vector2(cos(a), sin(a) * 0.6) * r, 4.0 * (1.0 - k) + 1.0, Color(f.r, f.g, f.b, 1.0 - k))


func _draw_normal() -> void:
	var cs := _sway(sway_gain)  # canopy catches the most wind
	# (In a perspective world the shadow lies on the ground instead: GroundShadows.)
	if tex_scale == 1.0 and not has_meta("card") and PerspectiveView.active == null:
		_draw_shadow(Vector2(0, 4), 18.0, 0.20)  # smooth @2x art bakes its own soft shadow; a flat card casts none
	_draw_glow(cs)
	if not float_cfg.is_empty() and trunk_tex != null and canopy_tex != null:
		_draw_floating(6.0 if foot < 0.0 else foot)
		return
	if _draw_sprite(cs, 6.0 if foot < 0.0 else foot):
		return
	var bark := style.color("bark")
	var f_dark := style.color("foliage_dark")
	var f_mid := style.color("foliage_mid")
	var f_light := style.color("foliage_light")
	# trunk with a lit left edge (light comes from up-left by default)
	draw_rect(Rect2(Vector2(-4, -6), Vector2(8, 22)), bark)
	draw_rect(Rect2(Vector2(-4, -6), Vector2(2.5, 22)), bark.lightened(0.12))
	# canopy: dark side-lobes first, a mid mass, then a lit blob on top for volume
	draw_circle(Vector2(-11 + cs, -15), 14.0, f_dark)
	draw_circle(Vector2(11 + cs, -15), 14.0, f_dark)
	draw_circle(Vector2(cs, -20), 21.0, f_mid)
	style.draw_blob(self, Vector2(cs, -23), 15.0, f_light)


## A prominent, beckoning feature you can spot from across the world — a great tree:
## a big, slow-swaying canopy on a heavy trunk that anchors a region (mirrors the old
## WorldArt._draw_landmark, now origin-relative so it sorts like any other tree).
func _draw_great() -> void:
	var sway := _sway(1.4 * sway_gain)
	if tex_scale == 1.0:
		if PerspectiveView.active == null:
			_draw_shadow(Vector2(0, 8), 36.0, 0.22)
	_draw_glow(sway)
	if _draw_sprite(sway, 8.0 if foot < 0.0 else foot):
		return
	var bark := style.color("bark")
	var f_dark := style.color("foliage_dark")
	var f_mid := style.color("foliage_mid")
	var f_light := style.color("foliage_light")
	draw_rect(Rect2(Vector2(-7, -10), Vector2(14, 40)), bark)
	draw_rect(Rect2(Vector2(-7, -10), Vector2(4.0, 40)), bark.lightened(0.12))
	draw_circle(Vector2(-28 + sway, -40), 30.0, f_dark)
	draw_circle(Vector2(28 + sway, -40), 30.0, f_dark)
	draw_circle(Vector2(sway, -50), 44.0, f_mid)
	style.draw_blob(self, Vector2(sway * 0.8, -60), 32.0, f_light)


## The growth's own light, drawn behind its art: a pool on the ground beneath it and a breathing halo
## around its crown (which leans with the crown's sway). A no-op for trees that don't glow.
func _draw_glow(crown_sway: float) -> void:
	if glow_radius <= 0.0 or glow_color.a <= 0.0:
		return
	var breathe := 0.86 + 0.14 * sin(_time * 1.1 + phase * 3.0)
	SoftGlow.draw(self, Vector2(0, 2), glow_radius * 1.4, Color(glow_color.r, glow_color.g, glow_color.b, 0.24 * breathe), 0.4)
	SoftGlow.draw(self, Vector2(crown_sway, glow_y), glow_radius * breathe, Color(glow_color.r, glow_color.g, glow_color.b, 0.36))


## Draw the tree from drop-in sprite art if any is set; return true if it did (so the
## caller skips the procedural fallback). Split trunk/canopy art is preferred: the trunk
## is drawn at rest and only the canopy is shifted by `canopy_sway`, so the base stays
## planted while the crown leans in the wind. A single whole-tree `tex` sways as one
## piece (the older, less lively path). All parts are bottom-anchored at `base_y` so
## their feet meet the ground at the node origin — the same anchor SpriteSlot.draw uses.
func _draw_sprite(canopy_sway: float, base_y: float) -> bool:
	if not angle_frames.is_empty():
		_blit(angle_frames[angle_frame(angle_frames.size(), facing, PerspectiveView.view_yaw)], 0.0, base_y)
		return true
	if back_tex != null and tex != null and PerspectiveView.active != null \
			and cos(angle_difference(facing - PI, PerspectiveView.view_yaw)) < 0.0:
		_blit(back_tex, canopy_sway, base_y)   # seen from behind
		return true
	if trunk_tex != null and canopy_tex != null:
		_blit(trunk_tex, 0.0, base_y)
		_blit(canopy_tex, canopy_sway, base_y)
		return true
	if tex != null:
		_blit(tex, canopy_sway, base_y)
		return true
	return false


## The resting layer (a plinth) at its feet, then a shadow on its top, then the floating layer over it, bobbing.
func _draw_floating(base_y: float) -> void:
	_blit(trunk_tex, 0.0, base_y)
	var rest := float(float_cfg.get("rest", 20.0))
	var bob := float(float_cfg.get("bob", 3.0))
	var period := maxf(0.5, float(float_cfg.get("period", 5.0)))
	var b := sin(_time * TAU / period + phase * 3.0) * bob
	var dip := (bob - b) / maxf(0.001, 2.0 * bob) if bob > 0.0 else 1.0   # 1 at the lowest point of the bob
	var hw := float(float_cfg.get("shadow", 12.0)) * (1.12 - 0.24 * dip)
	var c := style.color("shadow") if style != null else Color(0.45, 0.4, 0.6)
	draw_set_transform(Vector2(0, -rest + 1.0), 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, hw, Color(c.r, c.g, c.b, 0.14 + 0.12 * dip))
	draw_circle(Vector2.ZERO, hw * 0.6, Color(c.r, c.g, c.b, 0.08 + 0.10 * dip))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_blit(canopy_tex, 0.0, -(rest + float(float_cfg.get("height", 14.0)) + b))


## Which of n views round a thing faces a viewer with heading `view_yaw` (0 = its front, then clockwise).
static func angle_frame(n: int, front_facing: float, view_yaw: float) -> int:
	var rel := wrapf(view_yaw - (front_facing - PI), 0.0, TAU)
	return int(roundf(rel / (TAU / float(n)))) % n


func _blit(t: Texture2D, off_x: float, base_y: float) -> void:
	var sz := t.get_size() * tex_scale
	if tex_scale == 1.0:
		draw_texture(t, Vector2(off_x - sz.x * 0.5, base_y - sz.y))
	else:
		draw_texture_rect(t, Rect2(Vector2(off_x - sz.x * 0.5, base_y - sz.y), sz), false)


## A soft, flattened ground shadow — the cheapest, biggest depth cue we have. Drawn as
## a circle squashed vertically via the draw transform, then the transform is reset.
## (Copied from WorldArt, which keeps its own for props.)
func _draw_shadow(pos: Vector2, r: float, alpha: float) -> void:
	var c := style.color("shadow")
	var off := -style.light_dir() * (r * 0.16)  # shadows fall away from the light
	draw_set_transform(pos + off, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, r, Color(c.r, c.g, c.b, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
