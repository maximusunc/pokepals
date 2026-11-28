class_name CliffView
extends BuildingView
## One CLIFF of Hollowsong, the echo canyon: a BuildingView (the same y-sorted, walk-behind,
## fade-when-hidden mass the brick city uses) dressed as banded red rock instead of a toy brick. The face
## is the world's own rock-grain tile (the art direction's `building.wall`) tinted in horizontal strata
## bands, a lighter scree at the foot, hairline fissures, a lit left edge and a shaded right one; the top is
## windblown sand; `tiers` step the mass up like a mesa. Chosen by a spec's `"view": "cliff"`
## (Scenery.add_buildings). Extra spec keys read here:
##   bands [[r,g,b], ...]   the strata colours, cycled bottom to top (a few shades of red / ochre / cream)
##   arch {x0, x1, h}       an ARCH: the mass has a round-topped opening from x0 to x1 (relative to the
##                          centre) `h` px high that you can walk through. Its collision is the spec's
##                          `solid_rects` (the two legs; see Solids.build), not the whole footprint.
##   cave {x, w, h}         a hidden CAVE in the face: a hairline fissure at x (relative to the centre)
##                          until `open_cave()` is called, then a crack that widens to w x h, breathing a
##                          violet glow. The echo canyon's secret (HowlDirector asks for it).
## Pure presentation; the footprint collision and the echoes' wall segments are built from the spec.

const FISSURE := Color(0.10, 0.05, 0.06)
const GLOW := Color(0.66, 0.56, 1.0)

var _bands: Array = []          # [{ y: float (from the foot, up), h: float, color: Color }]
var _seams: Array = []          # vertical fissures [x, y0, len]
var _cave_target := 0.0
var _cave_open := 0.0


func setup(s: Dictionary, style: ArtStyle) -> void:
	super.setup(s, style)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(s.get("id", "cliff")) + str(s["rect"]))
	var palette: Array = []
	for c in s.get("bands", [[0.62, 0.30, 0.22], [0.74, 0.40, 0.28], [0.82, 0.56, 0.40], [0.56, 0.24, 0.20]]):
		palette.append(WorldData.to_color(c))
	var y := 0.0
	var k := rng.randi() % palette.size()
	while y < total_h + 24.0:
		var th := float(rng.randi_range(8, 22))
		var col: Color = palette[k % palette.size()]
		var jitter := rng.randf_range(-0.04, 0.04)
		_bands.append({ "y": y, "h": th, "color": Color(clampf(col.r + jitter, 0, 1), clampf(col.g + jitter, 0, 1), clampf(col.b + jitter, 0, 1)) })
		y += th
		k += 1 + (rng.randi() % 2)
	for i in int(hw / 40.0) + 1:
		_seams.append([rng.randf_range(-hw + 6.0, hw - 6.0), rng.randf_range(10.0, wall_h * 0.6), rng.randf_range(16.0, minf(60.0, wall_h * 0.7))])


## Open the hidden cave (the crack widens and begins to glow). A no-op for a cliff without one.
func open_cave() -> void:
	if spec.has("cave"):
		_cave_target = 1.0
		_animated = true
		queue_redraw()


## The cave is simply open (the secret was found on an earlier visit): no widening, no waiting.
func snap_open() -> void:
	if spec.has("cave"):
		_cave_target = 1.0
		_cave_open = 1.0
		_animated = true
		queue_redraw()


func cave_open_amount() -> float:
	return _cave_open


func tick(delta: float, t: float, want_fade: bool) -> void:
	if not is_equal_approx(_cave_open, _cave_target):
		_cave_open = move_toward(_cave_open, _cave_target, delta * 0.55)
	super.tick(delta, t, want_fade)


## The colour of the strata at `y` px above the foot of a face.
func _band_color(y: float) -> Color:
	for b in _bands:
		if y < float(b["y"]) + float(b["h"]):
			return b["color"]
	return (_bands.back() as Dictionary)["color"]


func _draw() -> void:
	var roof := _col("roof", Color(0.86, 0.70, 0.52))
	if not spec.has("arch"):
		_draw_shadow()
	_draw_strata(-hw, hw, 0.0, wall_h, true)
	_draw_top(hw, -wall_h, depth, roof)
	var lift := wall_h
	var cur_hw := hw
	var cur_depth := depth
	for t in spec.get("tiers", []):
		var inset := float(t.get("inset", 14))
		var th := float(t.get("h", 40))
		cur_hw = maxf(10.0, cur_hw - inset)
		cur_depth = maxf(14.0, cur_depth - inset * 1.4)
		var fb := -lift - inset * 0.7
		_draw_strata(-cur_hw, cur_hw, fb, th, false)
		_draw_top(cur_hw, fb - th, cur_depth, roof.lightened(0.04))
		lift += th
	if spec.has("cave"):
		_draw_cave(spec["cave"])


## A rock face from x0 to x1 whose foot is at y = fb and which is `h` tall, in strata bands. An arch spec
## cuts a round-topped opening from the foot.
func _draw_strata(x0: float, x1: float, fb: float, h: float, main: bool) -> void:
	var arch: Dictionary = spec.get("arch", {}) if main else {}
	if arch.is_empty():
		_draw_band_rect(x0, x1, fb, h, 0.0)
	else:
		var ax0 := float(arch["x0"])
		var ax1 := float(arch["x1"])
		var ah := float(arch["h"])
		_draw_band_rect(x0, ax0, fb, h, 0.0)          # the left leg
		_draw_band_rect(ax1, x1, fb, h, 0.0)          # the right leg
		# above the opening: columns, each starting at the arch's round underside
		var mid := (ax0 + ax1) * 0.5
		var half := (ax1 - ax0) * 0.5
		var x := ax0
		while x < ax1:
			var u := clampf((x + 2.0 - mid) / half, -1.0, 1.0)
			var under := ah - (1.0 - sqrt(maxf(0.0, 1.0 - u * u))) * minf(ah * 0.55, half * 0.7) * 1.0
			_draw_band_rect(x, minf(x + 4.0, ax1), fb - under, h - under, under)
			x += 4.0
	draw_rect(Rect2(x0, fb - h, 2.0, h), Color(1, 1, 1, 0.20))        # the lit left edge
	draw_rect(Rect2(x1 - 3.0, fb - h, 3.0, h), Color(0, 0, 0, 0.26))  # the shaded right edge
	if main:
		for s in _seams:
			var sx: float = s[0]
			if sx > x0 and sx < x1 and arch.is_empty():
				draw_rect(Rect2(sx, fb - float(s[1]) - float(s[2]), 1.0, float(s[2])), Color(0, 0, 0, 0.26))
		draw_rect(Rect2(x0, fb - 7.0, x1 - x0, 7.0), Color(0.40, 0.22, 0.16, 0.35))   # the scree at the foot


## One rectangle of face, as strata: `lo` is how far up the foot is from the cliff's own foot (so a column
## above an arch keeps the bands of the mass it is part of).
func _draw_band_rect(x0: float, x1: float, fb: float, h: float, lo: float) -> void:
	if x1 <= x0 or h <= 0.0:
		return
	for b in _bands:
		var by0: float = float(b["y"]) - lo
		var by1: float = by0 + float(b["h"])
		if by1 <= 0.0 or by0 >= h:
			continue
		var y0 := maxf(by0, 0.0)
		var y1 := minf(by1, h)
		var rect := Rect2(x0, fb - y1, x1 - x0, y1 - y0)
		var col: Color = b["color"]
		if _wall_tex != null:
			draw_texture_rect(_wall_tex, rect, true, col)
		else:
			draw_rect(rect, col)
		if by0 >= 0.0:
			draw_rect(Rect2(x0, fb - y0 - 1.0, x1 - x0, 1.0), col.darkened(0.30))   # the band's lower seam


## The cave in the face: a fissure, widening into a dark opening with a violet glow and drifting motes.
func _draw_cave(cave: Dictionary) -> void:
	var cx := float(cave.get("x", 0.0))
	var w := float(cave.get("w", 54.0))
	var h := float(cave.get("h", 74.0))
	var o := smoothstep(0.0, 1.0, _cave_open)
	var half := lerpf(1.0, w * 0.5, o)
	var top := lerpf(30.0, h, o)
	# the opening: a tall pointed slot, drawn in horizontal runs from the foot up
	var steps := 18
	for i in steps:
		var f := float(i) / float(steps)
		var y := -f * top
		var run := half * (1.0 - f * f * 0.85) * (1.0 + 0.12 * sin(f * 9.0 + cx))
		var col := FISSURE.lerp(Color(0.08, 0.05, 0.16), o)
		draw_rect(Rect2(cx - run, y - top / float(steps) - 0.5, run * 2.0, top / float(steps) + 1.0), col)
	if o > 0.02:
		var breathe := 0.75 + 0.25 * sin(_time * 1.6)
		SoftGlow.draw(self, Vector2(cx, -top * 0.4), w * 0.8, Color(GLOW.r, GLOW.g, GLOW.b, 0.30 * o * breathe), 0.8)
		SoftGlow.draw(self, Vector2(cx, 4.0), w * 0.9, Color(GLOW.r, GLOW.g, GLOW.b, 0.16 * o * breathe), 0.5)
		for k in 4:
			var ph := fposmod(_time * 0.3 + float(k) * 0.27, 1.0)
			var px := cx + sin(ph * 5.0 + float(k) * 2.0) * half * 0.5
			var py := -ph * top * 0.9
			draw_rect(Rect2(px - 1.0, py - 1.0, 2.0, 2.0), Color(0.86, 0.80, 1.0, 0.7 * o * sin(ph * PI)))
		draw_rect(Rect2(cx - half - 1.0, -top * 0.55, 1.0, top * 0.55), Color(1, 1, 1, 0.12))      # a lit lip
