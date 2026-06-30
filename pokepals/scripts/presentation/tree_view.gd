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
var tex: Texture2D = null  # optional user-supplied sprite (absent → procedural art)
var wind_strength := 2.6
var wind_speed := 1.15

var _time := 0.0


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


func _draw() -> void:
	if is_great:
		_draw_great()
	else:
		_draw_normal()


func _draw_normal() -> void:
	var cs := _sway(1.0)  # canopy catches the most wind
	_draw_shadow(Vector2(0, 4), 18.0, 0.20)
	if tex != null:
		var sz := tex.get_size()
		draw_texture(tex, Vector2(cs - sz.x * 0.5, 6.0 - sz.y))
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
	var sway := _sway(1.4)
	_draw_shadow(Vector2(0, 8), 36.0, 0.22)
	if tex != null:
		var gsz := tex.get_size()
		draw_texture(tex, Vector2(sway - gsz.x * 0.5, 8.0 - gsz.y))
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


## A soft, flattened ground shadow — the cheapest, biggest depth cue we have. Drawn as
## a circle squashed vertically via the draw transform, then the transform is reset.
## (Copied from WorldArt, which keeps its own for props.)
func _draw_shadow(pos: Vector2, r: float, alpha: float) -> void:
	var c := style.color("shadow")
	var off := -style.light_dir() * (r * 0.16)  # shadows fall away from the light
	draw_set_transform(pos + off, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, r, Color(c.r, c.g, c.b, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
