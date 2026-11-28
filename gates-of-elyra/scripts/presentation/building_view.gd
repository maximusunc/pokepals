class_name BuildingView
extends Node2D
## One brick BUILDING (Clickton, the city made of bricks). A y-sorted node in the Scenery layer, so you
## walk behind it when you're north of it and in front of it when you're south, like a tree. Its origin
## is the south-centre of its footprint (its feet). Everything is drawn from a few greyscale tiles
## (assets/sprites/ck_*.png, tinted per building) plus plain rects, in the game's oblique view: the
## front wall, then the roof's top face above it, studs and all.
##
## Built from a spec dictionary (the world's `buildings` list):
##   rect [x, y, w, d]  footprint (top-left, width, depth)      h        wall height in px (multiple of 6)
##   wall / roof / trim / door_color / awning / shutters  [r,g,b]
##   roof_style "flat" (a studded top) | "gable" (a pitched roof's front slope)
##   door true      a door in the middle of the front, with its steps     windows true   rows of windows
##   tiers [{inset, h, wall}]  smaller boxes stacked on the roof (towers, stepped skyscrapers)
##   chimney true (with a puff of smoke) | flag [r,g,b] | clock true | antenna true
##   inlay {prop, row, col}  a one-off swirling brick set into the wall courses (the world's secret): drawn here, because a
##                       prop in WorldArt would be painted UNDER the building; hidden once it is taken.
## Pure presentation: the footprint's collision is built from the same spec by Solids.

const PLINTH := 6.0

var hw := 60.0
var depth := 100.0
var wall_h := 60.0
var total_h := 60.0
var spec: Dictionary = {}

var _wall_tex: Texture2D = null
var _roof_tex: Texture2D = null
var _slope_tex: Texture2D = null
var _rainbow_tex: Texture2D = null
var _time := 0.0
var _animated := false
var _inlay_art: WorldArt = null
var _inlay_index := -1
var _inlay_gone := false
var _fade := 1.0


## Build from `s`; `style` supplies the tiles (the art direction's "building" entity).
func setup(s: Dictionary, style: ArtStyle) -> void:
	spec = s
	var r: Array = s["rect"]
	hw = float(r[2]) * 0.5
	depth = float(r[3])
	wall_h = float(s.get("h", 60))
	position = Vector2(float(r[0]) + hw, float(r[1]) + depth)
	var cfg := style.entity("building")
	_wall_tex = SpriteSlot.resolve(cfg, "wall")
	_roof_tex = SpriteSlot.resolve(cfg, "roof")
	_slope_tex = SpriteSlot.resolve(cfg, "slope")
	_rainbow_tex = SpriteSlot.resolve(cfg, "rainbow")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	total_h = wall_h
	if String(s.get("roof_style", "flat")) == "gable":
		total_h += _slope_h()
	var cur := wall_h
	for t in s.get("tiers", []):
		cur += float(t.get("h", 30))
	total_h = maxf(total_h, cur)
	_animated = bool(s.get("chimney", false)) or s.has("flag") or bool(s.get("clock", false)) or bool(s.get("antenna", false))
	name = "Building_%s" % String(s.get("id", "b"))


## The part of the world this building can paint, for the camera cull.
func cull_rect() -> Rect2:
	return Rect2(position.x - hw - 40.0, position.y - depth - total_h - 90.0, hw * 2.0 + 80.0, depth + total_h + 110.0)


## Whether standing at world point `p` (feet) puts you BEHIND this building's mass, hidden by it.
func occludes(p: Vector2) -> bool:
	var lp := p - position
	return absf(lp.x) <= hw + 6.0 and lp.y < -depth + 2.0 and lp.y > -depth - total_h - 4.0


## Attach the world's secret prop (by its render index in WorldArt) so its brick shows in the wall.
func bind_inlay(art: WorldArt, index: int) -> void:
	_inlay_art = art
	_inlay_index = index
	_inlay_gone = false
	queue_redraw()


## The secret this building holds is already found (or was never laid out): no brick in the wall.
func hide_inlay() -> void:
	_inlay_gone = true
	_inlay_art = null
	queue_redraw()


## Called by Scenery every frame while on screen: `fade` is 1 normally and ~0.5 while someone is behind
## the building, so you never lose your companion to a roof.
func tick(delta: float, t: float, want_fade: bool) -> void:
	_time = t
	var target := 0.5 if want_fade else 1.0
	if not is_equal_approx(_fade, target):
		_fade = move_toward(_fade, target, delta * 3.0)
		modulate.a = _fade
	var gone := _inlay_gone
	if _inlay_art != null and _inlay_index >= 0:
		gone = _inlay_art.is_interactable_gone(_inlay_index)
		if gone != _inlay_gone:
			_inlay_gone = gone
			queue_redraw()
	if _animated or (_inlay_art != null and not gone):
		queue_redraw()


func _col(key: String, fallback: Color) -> Color:
	return WorldData.to_color(spec[key]) if spec.has(key) else fallback


func _slope_h() -> float:
	return clampf(floorf(depth * 0.5 / 6.0) * 6.0, 18.0, 48.0)


func _draw() -> void:
	var wall := _col("wall", Color(0.80, 0.30, 0.25))
	var roof := _col("roof", Color(0.30, 0.30, 0.40))
	var trim := _col("trim", Color(0.95, 0.94, 0.90))
	_draw_shadow()
	var gable := String(spec.get("roof_style", "flat")) == "gable"
	_draw_wall(hw, 0.0, wall_h, wall, true)
	if gable:
		_draw_gable(roof)
	else:
		_draw_top(hw, 0.0 - wall_h, depth, roof)
	_draw_front(wall, trim)
	# stacked tiers: a smaller box on the roof, each on the one below
	var lift := wall_h
	var cur_hw := hw
	var cur_depth := depth
	for t in spec.get("tiers", []):
		var inset := float(t.get("inset", 12))
		var th := float(t.get("h", 30))
		cur_hw = maxf(8.0, cur_hw - inset)
		cur_depth = maxf(12.0, cur_depth - inset * 1.5)
		var fb := -lift - inset * 0.75
		var tw := WorldData.to_color(t["wall"]) if t.has("wall") else wall.darkened(0.08)
		var tr := WorldData.to_color(t["roof"]) if t.has("roof") else roof
		_draw_wall(cur_hw, fb, th, tw, false)
		_draw_top(cur_hw, fb - th, cur_depth, tr)
		if bool(spec.get("clock", false)) and t == (spec.get("tiers", [])[0]):
			_draw_clock(Vector2(0, fb - th * 0.5), minf(cur_hw - 3.0, 11.0))
		lift += th
	if bool(spec.get("chimney", false)):
		_draw_chimney(Vector2(hw * 0.55, -wall_h - (_slope_h() * 0.55 if gable else depth * 0.35)))
	if spec.has("flag"):
		_draw_flag(Vector2(-hw + 10.0, -total_h - (0.0 if gable else depth * 0.4)), WorldData.to_color(spec["flag"]))
	if bool(spec.get("antenna", false)):
		_draw_antenna(Vector2(hw * 0.4, -total_h - depth * 0.25))
	if bool(spec.get("clock", false)) and spec.get("tiers", []).is_empty():
		_draw_clock(Vector2(0, -wall_h * 0.62), 11.0)
	if spec.has("inlay") and not _inlay_gone:
		_draw_inlay(spec["inlay"])


# ── the pieces ────────────────────────────────────────────────────────────────────────────────────
## A hard shadow on the ground: the light comes from the upper left, so it falls to the right and a
## little toward you.
func _draw_shadow() -> void:
	var slen := minf(26.0, total_h * 0.3)
	draw_rect(Rect2(hw, -depth + 6.0, slen, depth), Color(0.05, 0.05, 0.15, 0.20))
	draw_rect(Rect2(-hw + 6.0, 0.0, hw * 2.0 + slen - 6.0, 7.0), Color(0.05, 0.05, 0.15, 0.20))


## A wall face `h` tall whose bottom edge is at y = fb, in brick courses tinted `wall`.
func _draw_wall(half: float, fb: float, h: float, wall: Color, main: bool) -> void:
	var rect := Rect2(-half, fb - h, half * 2.0, h)
	if _wall_tex != null:
		draw_texture_rect(_wall_tex, rect, true, wall)
	else:
		draw_rect(rect, wall)
	draw_rect(Rect2(-half, fb - h, 2.0, h), Color(1, 1, 1, 0.20))       # the lit left edge
	draw_rect(Rect2(half - 2.0, fb - h, 2.0, h), Color(0, 0, 0, 0.22))  # the shaded right edge
	if main:
		var plinth := Rect2(-half, fb - PLINTH, half * 2.0, PLINTH)
		if _wall_tex != null:
			draw_texture_rect(_wall_tex, plinth, true, Color(0.58, 0.58, 0.62))
		else:
			draw_rect(plinth, Color(0.58, 0.58, 0.62))
		draw_rect(Rect2(-half, fb - PLINTH - 1.0, half * 2.0, 1.0), Color(0, 0, 0, 0.25))


## A flat studded roof: the box's top face, `dep` deep, whose FRONT edge is at y = top_y.
func _draw_top(half: float, top_y: float, dep: float, roof: Color) -> void:
	var rect := Rect2(-half, top_y - dep, half * 2.0, dep)
	if _roof_tex != null:
		draw_texture_rect(_roof_tex, rect, true, roof)
	else:
		draw_rect(rect, roof)
	draw_rect(Rect2(-half, top_y - 3.0, half * 2.0, 3.0), roof.lightened(0.3))     # the front lip
	draw_rect(Rect2(-half, top_y - dep, half * 2.0, 2.0), roof.darkened(0.25))     # the back edge
	draw_rect(Rect2(-half, top_y - dep, 2.0, dep), roof.lightened(0.2))
	draw_rect(Rect2(half - 2.0, top_y - dep, 2.0, dep), roof.darkened(0.2))


## A pitched roof seen from the front: the near slope, rising from the eaves to a ridge.
func _draw_gable(roof: Color) -> void:
	var sh := _slope_h()
	var rect := Rect2(-hw - 4.0, -wall_h - sh, hw * 2.0 + 8.0, sh + 4.0)
	if _slope_tex != null:
		draw_texture_rect(_slope_tex, rect, true, roof)
	else:
		draw_rect(rect, roof)
	draw_rect(Rect2(-hw - 4.0, -wall_h - sh - 2.0, hw * 2.0 + 8.0, 3.0), roof.lightened(0.35))   # the ridge
	draw_rect(Rect2(-hw - 4.0, -wall_h + 4.0, hw * 2.0 + 8.0, 3.0), Color(0, 0, 0, 0.28))        # the eave's shadow


## The doors and windows of the front wall.
func _draw_front(wall: Color, trim: Color) -> void:
	var has_door := bool(spec.get("door", false))
	var awning: Variant = spec.get("awning", null)
	var upper_from := 36.0 if (has_door or awning != null) else PLINTH + 4.0
	if bool(spec.get("windows", true)):
		var floors := maxi(0, int((wall_h - upper_from - 6.0) / 28.0))
		var cols := maxi(1, int((hw * 2.0 - 16.0) / 32.0))
		var spacing := hw * 2.0 / float(cols)
		for f in floors:
			var cy := -(upper_from + 28.0 * float(f) + 14.0)
			for c in cols:
				var cx := -hw + spacing * (float(c) + 0.5)
				_draw_window(Vector2(cx, cy), trim)
	if has_door:
		var dc := _col("door_color", Color(0.45, 0.25, 0.16))
		if awning != null:
			var lw := hw - 16.0
			if lw > 8.0:
				for side in [-1.0, 1.0]:
					var x0 := 14.0 if side > 0.0 else -hw + 8.0
					var w := hw - 8.0 - 14.0
					if w > 6.0:
						_draw_shop_window(Rect2(x0, -28.0, w, 18.0), trim)
		draw_rect(Rect2(-12.0, -2.0, 24.0, 2.0), Color(0.62, 0.62, 0.66))       # the step
		draw_rect(Rect2(-9.0, -28.0, 18.0, 26.0), dc)
		draw_rect(Rect2(-9.0, -28.0, 18.0, 2.0), dc.lightened(0.2))
		draw_rect(Rect2(-9.0, -28.0, 2.0, 26.0), dc.lightened(0.12))
		draw_rect(Rect2(-5.0, -24.0, 10.0, 10.0), dc.darkened(0.18))           # a panel
		draw_rect(Rect2(4.0, -13.0, 3.0, 3.0), Color(0.96, 0.80, 0.20))         # the knob is a stud
		draw_rect(Rect2(-11.0, -31.0, 22.0, 3.0), trim)                        # the lintel
	if awning != null:
		var ac := WorldData.to_color(awning)
		var x := -hw + 2.0
		var k := 0
		while x < hw - 2.0:
			var w := minf(8.0, hw - 2.0 - x)
			var c := ac if k % 2 == 0 else Color(0.96, 0.96, 0.95)
			draw_rect(Rect2(x, -38.0, w, 6.0), c)
			draw_rect(Rect2(x, -32.0, w, 3.0), c.darkened(0.15))
			x += 8.0
			k += 1
		draw_rect(Rect2(-hw + 2.0, -39.0, hw * 2.0 - 4.0, 1.0), Color(1, 1, 1, 0.4))


func _draw_window(c: Vector2, trim: Color) -> void:
	draw_rect(Rect2(c.x - 9.0, c.y - 9.0, 18.0, 18.0), trim)
	draw_rect(Rect2(c.x - 7.0, c.y - 7.0, 14.0, 14.0), Color(0.46, 0.70, 0.86))
	draw_rect(Rect2(c.x - 7.0, c.y - 7.0, 14.0, 5.0), Color(0.62, 0.82, 0.94))
	draw_rect(Rect2(c.x - 1.0, c.y - 7.0, 2.0, 14.0), trim)                      # the mullion
	draw_rect(Rect2(c.x - 6.0, c.y - 6.0, 3.0, 1.0), Color(1, 1, 1, 0.8))      # a glint
	draw_rect(Rect2(c.x - 10.0, c.y + 9.0, 20.0, 2.0), trim.darkened(0.12))      # the sill
	if spec.has("shutters"):
		var sc := WorldData.to_color(spec["shutters"])
		draw_rect(Rect2(c.x - 14.0, c.y - 9.0, 5.0, 18.0), sc)
		draw_rect(Rect2(c.x + 9.0, c.y - 9.0, 5.0, 18.0), sc)


func _draw_shop_window(r: Rect2, trim: Color) -> void:
	draw_rect(r.grow(2.0), trim)
	draw_rect(r, Color(0.52, 0.76, 0.90))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), Color(0.70, 0.88, 0.96))
	draw_rect(Rect2(r.position.x + 3.0, r.position.y + 2.0, 6.0, 1.0), Color(1, 1, 1, 0.8))


func _draw_clock(c: Vector2, r: float) -> void:
	draw_rect(Rect2(c.x - r - 2.0, c.y - r - 2.0, r * 2.0 + 4.0, r * 2.0 + 4.0), Color(0.30, 0.30, 0.34))
	draw_rect(Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), Color(0.97, 0.96, 0.90))
	for k in 4:
		var a := float(k) * PI * 0.5
		var tp := c + Vector2(sin(a), -cos(a)) * (r - 2.0)
		draw_rect(Rect2(tp.x - 1.0, tp.y - 1.0, 2.0, 2.0), Color(0.2, 0.2, 0.24))
	var minute := _time * 0.5
	draw_line(c, c + Vector2(sin(minute), -cos(minute)) * (r - 3.0), Color(0.15, 0.15, 0.2), 1.0)
	draw_line(c, c + Vector2(sin(minute / 12.0), -cos(minute / 12.0)) * (r - 6.0), Color(0.75, 0.15, 0.12), 2.0)


func _draw_chimney(p: Vector2) -> void:
	draw_rect(Rect2(p.x - 6.0, p.y - 12.0, 12.0, 14.0), Color(0.62, 0.22, 0.18))
	draw_rect(Rect2(p.x - 6.0, p.y - 12.0, 3.0, 14.0), Color(0.78, 0.34, 0.26))
	draw_rect(Rect2(p.x - 7.0, p.y - 16.0, 14.0, 4.0), Color(0.45, 0.45, 0.50))
	draw_rect(Rect2(p.x - 4.0, p.y - 19.0, 3.0, 3.0), Color(0.62, 0.62, 0.68))      # studs
	draw_rect(Rect2(p.x + 1.0, p.y - 19.0, 3.0, 3.0), Color(0.62, 0.62, 0.68))
	# smoke: square puffs of white brick rising and drifting, each one a little later in its climb
	for k in 3:
		var ph := fposmod(_time * 0.35 + float(k) / 3.0, 1.0)
		var s := 3.0 + ph * 5.0
		var q := p + Vector2(sin(ph * 4.0 + float(k)) * 4.0 + ph * 8.0, -22.0 - ph * 30.0)
		draw_rect(Rect2(q.x - s * 0.5, q.y - s * 0.5, s, s), Color(0.97, 0.97, 0.98, 0.85 * (1.0 - ph)))


func _draw_flag(p: Vector2, c: Color) -> void:
	draw_rect(Rect2(p.x - 1.0, p.y - 26.0, 2.0, 26.0), Color(0.88, 0.88, 0.90))
	draw_rect(Rect2(p.x - 2.0, p.y - 28.0, 4.0, 3.0), Color(0.96, 0.80, 0.20))
	for i in 5:
		var wave := sin(_time * 3.0 + float(i) * 0.9) * 1.5
		draw_rect(Rect2(p.x + 1.0 + float(i) * 3.0, p.y - 24.0 + wave, 3.0, 10.0), c if i % 2 == 0 else c.lightened(0.15))


func _draw_antenna(p: Vector2) -> void:
	draw_rect(Rect2(p.x - 1.0, p.y - 22.0, 2.0, 22.0), Color(0.55, 0.55, 0.60))
	draw_rect(Rect2(p.x - 6.0, p.y - 18.0, 12.0, 2.0), Color(0.55, 0.55, 0.60))
	draw_rect(Rect2(p.x - 4.0, p.y - 12.0, 8.0, 2.0), Color(0.55, 0.55, 0.60))
	var on := fposmod(_time, 1.6) < 0.3
	draw_rect(Rect2(p.x - 2.0, p.y - 26.0, 4.0, 4.0), Color(1.0, 0.25, 0.2) if on else Color(0.5, 0.15, 0.12))


## The secret brick: one wall brick that is part of the building (it sits exactly in the courses, `row`
## down from the top and `col` along, so it is flush with its neighbours and shares their seams and lit
## edge) but is alive: bands of every colour swirl slowly through it, and a soft halo of the same colours
## breathes round it, so a careful eye notices one brick that isn't like the others.
func _draw_inlay(inlay: Dictionary) -> void:
	var row := int(inlay.get("row", 6))
	var col := int(inlay.get("col", 1))
	var x0 := -hw + 16.0 * float(col) + (8.0 if row % 2 == 1 else 0.0)
	var y0 := -wall_h + 6.0 * float(row)
	var halo := 0.5 + 0.5 * sin(_time * 1.2)
	var mid := Vector2(x0 + 8.0, y0 + 3.0)
	SoftGlow.draw(self, mid, 22.0, Color.from_hsv(fposmod(_time * 0.08, 1.0), 0.5, 1.0, 0.16 + 0.10 * halo), 0.7)
	# the face, in 2 px cells: a diagonal rainbow whose bands drift across the brick and round again
	for cx in 8:
		for cy in 3:
			var hue := fposmod(float(cx) * 0.07 + float(cy) * 0.11 - _time * 0.16, 1.0)
			var c := Color.from_hsv(hue, 0.82, 1.0)
			draw_rect(Rect2(x0 + float(cx) * 2.0, y0 + float(cy) * 2.0, 2.0, 2.0), c)
	# a brick's own edges: lit top and left, shaded bottom and right, like every other brick in the wall
	draw_rect(Rect2(x0, y0, 16.0, 1.0), Color(1, 1, 1, 0.35))
	draw_rect(Rect2(x0, y0, 1.0, 6.0), Color(1, 1, 1, 0.25))
	draw_rect(Rect2(x0, y0 + 5.0, 16.0, 1.0), Color(0, 0, 0, 0.30))
	draw_rect(Rect2(x0 + 15.0, y0, 1.0, 6.0), Color(0, 0, 0, 0.25))
	# a glint that crosses it now and then
	var ph := fposmod(_time * 0.4, 1.0)
	if ph < 0.3:
		var gx := x0 + 2.0 + ph / 0.3 * 12.0
		draw_rect(Rect2(gx, y0 + 1.0, 2.0, 4.0), Color(1, 1, 1, 0.55))
