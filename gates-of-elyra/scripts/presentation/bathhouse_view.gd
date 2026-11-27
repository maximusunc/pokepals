class_name BathhouseView
extends BuildingView
## One BATHHOUSE of Steamhollow: a BuildingView (the same y-sorted, walk-behind, fade-when-hidden building
## the brick city uses) dressed as a timber bathhouse instead of a toy brick. The walls and roof are the
## world's own plank and tile art (the art direction's `building` entity); this swaps the brick windows,
## door and chimney for paper-screen windows that glow warm, a dark noren curtain over the doorway, a
## hanging paper lantern that sways, a small sign, and a stack that breathes steam.
##
## Chosen by a building spec's `"view": "bathhouse"` (Scenery.add_buildings). Everything else about the
## spec is the BuildingView's own (rect, h, wall / roof / trim / door_color, roof_style, chimney); extra
## keys read here: `glow` [r,g,b] (the paper's light), `curtain` [r,g,b] (the noren). Pure presentation.

const PAPER := Color(1.0, 0.86, 0.56)
const LATTICE := Color(0.30, 0.20, 0.14)


func setup(s: Dictionary, style: ArtStyle) -> void:
	super.setup(s, style)
	_animated = true   # the lantern sways and the steam rises, always


## Warm paper-screen windows either side of the door, a noren curtain over the door, a sign over it and a
## paper lantern hanging at its side. Upper floors (a tall house) get a row of small screens.
func _draw_front(wall: Color, trim: Color) -> void:
	var glow := WorldData.to_color(spec["glow"]) if spec.has("glow") else PAPER
	var curtain := WorldData.to_color(spec["curtain"]) if spec.has("curtain") else Color(0.20, 0.26, 0.46)
	var has_door := bool(spec.get("door", true))
	var door_w := 13.0
	# windows: as many as fit in each flank, never crowding the door
	var flank := hw - door_w - 14.0
	var cols := maxi(0, int(flank / 30.0))
	if flank > 18.0:
		cols = maxi(cols, 1)
	for side in [-1.0, 1.0]:
		for c in cols:
			var cx: float = side * (door_w + 16.0 + 28.0 * float(c) + 8.0)
			if absf(cx) < hw - 12.0:
				_draw_screen(Vector2(cx, -23.0), glow, trim, 7.0, 9.0)
	var upper := wall_h - 44.0
	if upper >= 18.0:
		var ucols := maxi(1, int((hw * 2.0 - 20.0) / 30.0))
		var spacing := hw * 2.0 / float(ucols)
		for c in ucols:
			_draw_screen(Vector2(-hw + spacing * (float(c) + 0.5), -wall_h + 22.0), glow, trim, 7.0, 8.0)
	if has_door:
		var dc := _col("door_color", Color(0.30, 0.20, 0.14))
		# the doorway: a warm dark inside, a lintel rail, and the curtain hanging in three panels
		draw_rect(Rect2(-door_w, -32.0, door_w * 2.0, 32.0), dc.darkened(0.35))
		draw_rect(Rect2(-door_w + 3.0, -29.0, door_w * 2.0 - 6.0, 29.0), glow.darkened(0.45))
		draw_rect(Rect2(-door_w - 2.0, -35.0, door_w * 2.0 + 4.0, 4.0), dc.lightened(0.1))
		draw_rect(Rect2(-door_w - 2.0, -35.0, door_w * 2.0 + 4.0, 1.0), dc.lightened(0.35))
		var sway := sin(_time * 1.3 + position.x * 0.05) * 1.2
		for k in 3:
			var x0 := -door_w + 2.0 + float(k) * ((door_w * 2.0 - 4.0) / 3.0)
			var w := (door_w * 2.0 - 4.0) / 3.0 - 1.5
			var drop := 22.0 + (3.0 if k == 1 else 0.0)
			draw_rect(Rect2(x0 + sway * float(k - 1) * 0.3, -32.0, w, drop), curtain)
			draw_rect(Rect2(x0 + sway * float(k - 1) * 0.3, -32.0, w, 2.0), curtain.lightened(0.25))
			draw_rect(Rect2(x0 + sway * float(k - 1) * 0.3, -32.0 + drop - 2.0, w, 2.0), curtain.darkened(0.2))
		# a cream circle on the middle panel: the bathhouse's mark
		draw_circle(Vector2(sway * 0.0, -22.0), 3.2, Color(0.96, 0.92, 0.82), true, -1.0, true)
		draw_arc(Vector2(0.0, -22.0), 1.6, 0.4, PI * 1.6, 8, curtain, 1.0, true)
		draw_rect(Rect2(-door_w - 3.0, -2.0, door_w * 2.0 + 6.0, 2.0), Color(0.46, 0.42, 0.40))   # the step
		# a small sign over the door
		var sign_y := -wall_h * 0.5 - 8.0 if wall_h > 62.0 else -44.0
		draw_rect(Rect2(-14.0, sign_y - 7.0, 28.0, 12.0), dc.lightened(0.05))
		draw_rect(Rect2(-14.0, sign_y - 7.0, 28.0, 1.0), dc.lightened(0.4))
		draw_rect(Rect2(-14.0, sign_y + 4.0, 28.0, 1.0), dc.darkened(0.4))
		for q in 3:
			var a0 := _time * 0.0 + float(q) * 1.1
			draw_arc(Vector2(-8.0 + float(q) * 8.0, sign_y - 1.0), 2.6, a0 + 3.4, a0 + 6.2, 8, glow.lightened(0.2), 1.0, true)
		# a paper lantern on a short bracket at the door's right
		_draw_hanging_lantern(Vector2(door_w + 10.0, -34.0), glow)


## A paper-screen window: a warm lit pane with a wooden lattice, a soft glow spilling onto the ground
## beneath it, and a slow flicker so the village looks lived in.
func _draw_screen(c: Vector2, glow: Color, trim: Color, hw_: float, hh: float) -> void:
	var flick := 0.92 + 0.08 * sin(_time * 2.1 + c.x * 0.13 + position.x * 0.07)
	SoftGlow.draw(self, Vector2(c.x, 4.0), 24.0, Color(glow.r, glow.g, glow.b, 0.20 * flick), 0.45)
	draw_rect(Rect2(c.x - hw_ - 2.0, c.y - hh - 2.0, hw_ * 2.0 + 4.0, hh * 2.0 + 4.0), LATTICE)
	draw_rect(Rect2(c.x - hw_, c.y - hh, hw_ * 2.0, hh * 2.0), Color(glow.r * flick, glow.g * flick, glow.b * flick))
	draw_rect(Rect2(c.x - hw_, c.y - hh, hw_ * 2.0, 3.0), glow.lightened(0.3))
	draw_rect(Rect2(c.x - 0.5, c.y - hh, 1.0, hh * 2.0), LATTICE)
	draw_rect(Rect2(c.x - hw_, c.y - 0.5, hw_ * 2.0, 1.0), LATTICE)
	draw_rect(Rect2(c.x - hw_ - 3.0, c.y + hh + 2.0, hw_ * 2.0 + 6.0, 2.0), trim.darkened(0.3))   # the sill


func _draw_hanging_lantern(p: Vector2, glow: Color) -> void:
	var sway := sin(_time * 1.7 + position.y * 0.03) * 0.12
	draw_line(p + Vector2(-6.0, 0.0), p + Vector2(0.0, 0.0), LATTICE, 1.5)
	draw_set_transform(p, sway, Vector2.ONE)
	draw_line(Vector2.ZERO, Vector2(0.0, 4.0), LATTICE, 1.0)
	SoftGlow.draw(self, Vector2(0.0, 9.0), 17.0, Color(1.0, 0.7, 0.4, 0.34), 1.0)
	draw_rect(Rect2(-3.5, 4.0, 7.0, 10.0), Color(0.92, 0.44, 0.26))
	draw_rect(Rect2(-3.5, 4.0, 7.0, 2.0), Color(0.60, 0.26, 0.18))
	draw_rect(Rect2(-3.5, 12.0, 7.0, 2.0), Color(0.60, 0.26, 0.18))
	draw_rect(Rect2(-2.0, 6.5, 2.0, 5.0), Color(1.0, 0.8, 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The stack: a squat stone chimney, and the bathhouse's steam rising from it in soft round puffs.
func _draw_chimney(p: Vector2) -> void:
	draw_rect(Rect2(p.x - 6.0, p.y - 12.0, 12.0, 14.0), Color(0.40, 0.38, 0.42))
	draw_rect(Rect2(p.x - 6.0, p.y - 12.0, 3.0, 14.0), Color(0.55, 0.53, 0.57))
	draw_rect(Rect2(p.x - 7.0, p.y - 15.0, 14.0, 3.0), Color(0.30, 0.28, 0.32))
	for k in 4:
		var ph := fposmod(_time * 0.22 + float(k) / 4.0, 1.0)
		var r := 4.0 + ph * 9.0
		var q := p + Vector2(sin(ph * 4.0 + float(k)) * 5.0 + ph * 12.0, -17.0 - ph * 44.0)
		SoftGlow.draw(self, q, r, Color(1.0, 0.98, 0.96, 0.62 * sin(ph * PI)), 0.85)
