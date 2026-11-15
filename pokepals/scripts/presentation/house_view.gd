class_name HouseView
extends BuildingView
## YOUR HOUSE (home building; docs/usable-items-design.md "Home building"), in your home's north. A
## BuildingView (the same y-sorted, walk-behind building the brick city uses: its origin is the south-centre of
## its footprint), chosen by a building spec's `"view": "house"`, whose `house` block (Server.HomeWorld, from
## tools/gen_home_house.py) says everything about it.
##
## Three looks:
##   * **Being built** (`state` "building"): the floor is down (WorldArt's plates) and a timber frame rises on
##     it as the build goes on, posts, then beams, then rafters, with boards climbing the walls; scaffolding
##     along the front, sawhorses and a stack of planks in the yard. The carpenter at work is a person
##     (HouseDirector). You can walk in among the posts.
##   * **Built, seen from outside**: a cottage, plaster and timber, a stone plinth, windows with flower boxes, a
##     green door with a lamp, a shingled roof with a chimney that smokes. It hides everything inside.
##   * **Built, from inside** (your feet are inside its walls): the roof and front wall lift away (a cutaway, like
##     a doll's house): you see the back wall of every room (windows, shelves, pictures, the chimney breast)
##     and the furniture, while the front wall stays as a low strip. The floors, rugs and display shelves are
##     WorldArt plates, and your finds on them are WorldArt props, so they draw under everything here.
##
## The pieces that must sort among the people inside (the back wall, the furniture) are their own nodes in the
## Scenery, made here (HouseBackWall, HouseFurniture); this node draws the shell in front of them. Pure
## presentation: the walls' collision is the spec's `solid_rects` (Solids), the state is the server's.

const CUT_STRIP := 10.0     # how tall the front wall stands in the cutaway
const FADE_SPEED := 4.0

var house: Dictionary = {}
var built := false
var progress := 0.0         # 0..1 through the build (while being built)

var _inside := 0.0          # 0 outside .. 1 inside (the cutaway's blend)
var _shell: Painter
var _strip: Painter
var _back: HouseBackWall
var _furniture: Array = []
var _celebrate := -1.0      # seconds since it was finished, for a little moment of dust and sparkle
var _wall_t := 8.0
var _origin := Vector2.ZERO # the footprint's top-left, in world space


func setup(s: Dictionary, style: ArtStyle) -> void:
	super.setup(s, style)
	house = s.get("house", {})
	built = String(house.get("state", "")) == "built"
	_wall_t = float(house.get("wall_t", 8))
	_origin = position - Vector2(hw, depth)
	_animated = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	name = "House"
	_strip = Painter.new(_draw_strip)
	_strip.name = "Strip"
	add_child(_strip)
	_shell = Painter.new(_draw_shell)
	_shell.name = "Shell"
	add_child(_shell)
	_back = HouseBackWall.new()
	_back.house_view = self
	_back.position = Vector2(position.x, position.y - depth)
	_back.name = "HouseBackWall"
	_back.set_meta("understory", true)
	for f in house.get("furniture", []):
		var fv := HouseFurniture.new()
		fv.kind = String(f.get("kind", ""))
		fv.w = float(f.get("w", 20))
		fv.house_view = self
		fv.position = WorldData.to_vec2(f.get("at", [0, 0]))
		fv.name = "Furniture_%s_%d" % [fv.kind, _furniture.size()]
		fv.set_meta("understory", true)
		_furniture.append(fv)
	_sync_parts()


func _ready() -> void:
	# The back wall and the furniture are siblings in the Scenery, so they sort among the people inside.
	var parent := get_parent()
	if parent != null:
		parent.add_child.call_deferred(_back)
		for fv in _furniture:
			parent.add_child.call_deferred(fv)


## The footprint, in world space.
func footprint() -> Rect2:
	return Rect2(_origin, Vector2(hw * 2.0, depth))


## Whether a world point is inside the house's walls (feet a little past the front wall's line).
func is_inside(p: Vector2) -> bool:
	var r := footprint()
	return p.x > r.position.x and p.x < r.end.x and p.y > r.position.y and p.y < r.end.y - 2.0


func cull_rect() -> Rect2:
	var top := depth + wall_h + 70.0
	return Rect2(position.x - hw - 60.0, position.y - top, hw * 2.0 + 120.0, top + 60.0)


## Behind the house (north of it), you're hidden by its roof; inside a built one, never.
func occludes(p: Vector2) -> bool:
	if is_inside(p):
		return false
	var lp := p - position
	return absf(lp.x) <= hw + 6.0 and lp.y < -depth + 2.0 and lp.y > -depth - wall_h - 30.0


## How far through the build it is now (0..1), from when it started and how long it takes.
func build_progress() -> float:
	var started := float(house.get("started_at", 0))
	var ms := maxf(1.0, float(house.get("build_ms", 600000)))
	return clampf((float(Net.server_unix_ms()) - started) / ms, 0.0, 1.0)


## How long until it's done (seconds; 0 once built).
func seconds_left() -> float:
	if built:
		return 0.0
	var started := float(house.get("started_at", 0))
	var ms := float(house.get("build_ms", 600000))
	return maxf(0.0, (started + ms - float(Net.server_unix_ms())) / 1000.0)


## It's finished (HouseDirector calls this the moment the build time runs out): the furniture goes in.
func finish() -> void:
	if built:
		return
	built = true
	house["state"] = "built"
	_celebrate = 0.0
	_sync_parts()


func _sync_parts() -> void:
	for fv in _furniture:
		(fv as Node2D).visible = built and _inside > 0.01
	if _back != null:
		_back.visible = (built and _inside > 0.01) or not built


## Called by Scenery every frame while on screen. `want_fade` is true while our player or companion is behind
## the house; the cutaway follows our own player's feet.
func tick(delta: float, t: float, want_fade: bool) -> void:
	_time = t
	progress = 1.0 if built else build_progress()
	var player := get_parent().get_node_or_null("Player") as Node2D if get_parent() != null else null
	var want_inside := built and player != null and is_inside(player.position)
	var target := 1.0 if want_inside else 0.0
	var before := _inside
	_inside = move_toward(_inside, target, delta * FADE_SPEED)
	# Inside, the camera keeps the top of the back wall in view, so the room is seen whole.
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	if cam is CameraRig:
		(cam as CameraRig).keep_top_in_view = (position.y - depth - wall_h - 4.0) if want_inside else INF
	if (before > 0.01) != (_inside > 0.01):
		_sync_parts()
	_shell.modulate.a = (1.0 - _inside) * (0.5 if want_fade and _inside < 0.01 else 1.0)
	_strip.modulate.a = _inside
	for fv in _furniture:
		(fv as Node2D).modulate.a = _inside
	if _back != null:
		_back.modulate.a = _inside if built else 1.0
		_back.queue_redraw()
	if _celebrate >= 0.0:
		_celebrate += delta
		if _celebrate > 3.0:
			_celebrate = -1.0
	queue_redraw()
	_shell.queue_redraw()
	_strip.queue_redraw()
	for fv in _furniture:
		if (fv as HouseFurniture).animated and (fv as Node2D).visible:
			(fv as Node2D).queue_redraw()


func _col(key: String, fallback: Color) -> Color:
	var cols: Dictionary = house.get("colors", {})
	return WorldData.to_color(cols[key]) if cols.has(key) else fallback


## Local x of a world x.
func lx(world_x: float) -> float:
	return world_x - position.x


# ── this node: the ground round it (a shadow; the yard while it's being built) ─────────────────────────────
func _draw() -> void:
	if built:
		var a := 1.0 - _inside
		draw_rect(Rect2(hw, -depth + 10.0, 22.0, depth), Color(0.05, 0.05, 0.15, 0.18 * a))
		draw_rect(Rect2(-hw + 8.0, 0.0, hw * 2.0 + 14.0, 8.0), Color(0.05, 0.05, 0.15, 0.18 * a))
		if _celebrate >= 0.0:
			_draw_celebration()
		return
	_draw_yard()


## The building site's yard: sawhorses, a stack of planks and a sign with how long is left.
func _draw_yard() -> void:
	var wood := Color(0.70, 0.52, 0.32)
	# a stack of planks, west of the door
	var sp := Vector2(-hw * 0.55, 30.0)
	var left := 1.0 - progress
	var rows := maxi(1, int(round(5.0 * left)))
	for k in rows:
		draw_rect(Rect2(sp + Vector2(-24, -float(k) * 3.0), Vector2(48, 3)), wood.darkened(0.04 * float(k % 2)))
		draw_rect(Rect2(sp + Vector2(-24, -float(k) * 3.0), Vector2(48, 1)), wood.lightened(0.12))
	# two sawhorses with a plank across, east of the door
	var hp := Vector2(hw * 0.5, 34.0)
	for dx in [-14.0, 14.0]:
		draw_line(hp + Vector2(dx - 5, 0), hp + Vector2(dx, -10), wood.darkened(0.3), 2.0)
		draw_line(hp + Vector2(dx + 5, 0), hp + Vector2(dx, -10), wood.darkened(0.3), 2.0)
	draw_rect(Rect2(hp + Vector2(-22, -12), Vector2(44, 3)), wood)
	# sawdust
	for k in 6:
		draw_rect(Rect2(hp + Vector2(-10 + k * 4, 2 + (k % 2) * 2), Vector2(2, 1)), Color(0.92, 0.82, 0.60, 0.8))
	# the sign: a little board on a post, saying how long is left
	var sg := Vector2(-40.0, 26.0)
	draw_rect(Rect2(sg + Vector2(-1, -22), Vector2(2, 22)), wood.darkened(0.35))
	draw_rect(Rect2(sg + Vector2(-16, -30), Vector2(32, 12)), Color(0.86, 0.74, 0.52))
	draw_rect(Rect2(sg + Vector2(-16, -30), Vector2(32, 1)), Color(0.96, 0.88, 0.70))
	var mins := int(ceil(seconds_left() / 60.0))
	var font := ThemeDB.fallback_font
	var txt := "%d min" % mins if mins > 1 else ("1 min" if mins == 1 else "done!")
	draw_string(font, sg + Vector2(-14, -21), txt, HORIZONTAL_ALIGNMENT_CENTER, 28, 8, Color(0.30, 0.20, 0.12))


func _draw_celebration() -> void:
	var k := _celebrate / 3.0
	for i in 18:
		var a := float(i) * 1.7
		var p := Vector2(sin(a * 3.1) * hw, -depth * 0.5 - wall_h - k * 40.0 * (0.5 + 0.5 * sin(a)))
		var tw := 0.5 + 0.5 * sin(_time * 8.0 + a)
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.94, 0.66, (1.0 - k) * tw))


# ── the shell: the house seen from outside (or, while it's being built, its frame) ────────────────────────
func _draw_shell(ci: CanvasItem) -> void:
	if not built:
		_draw_frame(ci)
		return
	var plaster := _col("plaster", Color(0.93, 0.88, 0.78))
	var timber := _col("timber", Color(0.42, 0.28, 0.18))
	var roof := _col("roof", Color(0.58, 0.30, 0.22))
	var stone := _col("stone", Color(0.62, 0.60, 0.56))
	var door_c := _col("door", Color(0.44, 0.58, 0.40))
	# the front wall: plaster over a stone plinth, timber framing
	ci.draw_rect(Rect2(-hw, -wall_h, hw * 2.0, wall_h), plaster)
	ci.draw_rect(Rect2(-hw, -10.0, hw * 2.0, 10.0), stone)
	for x in range(int(-hw), int(hw), 12):
		ci.draw_rect(Rect2(float(x) + (6.0 if (x / 12) % 2 == 0 else 0.0), -10.0, 1.0, 5.0), stone.darkened(0.2))
	ci.draw_rect(Rect2(-hw, -5.0, hw * 2.0, 1.0), stone.darkened(0.2))
	ci.draw_rect(Rect2(-hw, -11.0, hw * 2.0, 2.0), timber)                       # the sill beam
	ci.draw_rect(Rect2(-hw, -wall_h, hw * 2.0, 3.0), timber)                     # the top beam
	var posts := [-hw, -hw * 0.66, -hw * 0.33, hw * 0.33, hw * 0.66, hw - 4.0]
	for px in posts:
		ci.draw_rect(Rect2(px, -wall_h, 4.0, wall_h - 10.0), timber)
	ci.draw_rect(Rect2(-hw, -wall_h, 2.0, wall_h), Color(1, 1, 1, 0.16))
	ci.draw_rect(Rect2(hw - 2.0, -wall_h, 2.0, wall_h), Color(0, 0, 0, 0.18))
	# windows, each with shutters and a box of flowers
	for wnd in house.get("front_windows", []):
		var x0 := lx(float(wnd[0]))
		var x1 := lx(float(wnd[1]))
		_draw_front_window(ci, Rect2(x0, -wall_h + 16.0, x1 - x0, 24.0), timber)
	# the door, a lamp beside it, a step
	var door: Array = house.get("door", [-24, 24])
	var dx0 := lx(float(door[0]))
	var dx1 := lx(float(door[1]))
	var dmid := (dx0 + dx1) * 0.5
	ci.draw_rect(Rect2(dmid - 16.0, -44.0, 32.0, 44.0), timber)
	ci.draw_rect(Rect2(dmid - 13.0, -41.0, 26.0, 41.0), door_c)
	ci.draw_rect(Rect2(dmid - 13.0, -41.0, 26.0, 2.0), door_c.lightened(0.2))
	ci.draw_rect(Rect2(dmid - 1.0, -41.0, 1.0, 41.0), door_c.darkened(0.25))
	for k in 3:
		ci.draw_rect(Rect2(dmid - 10.0, -36.0 + float(k) * 12.0, 7.0, 8.0), door_c.darkened(0.12))
		ci.draw_rect(Rect2(dmid + 3.0, -36.0 + float(k) * 12.0, 7.0, 8.0), door_c.darkened(0.12))
	ci.draw_circle(Vector2(dmid + 8.0, -20.0), 1.5, Color(0.92, 0.78, 0.36))
	ci.draw_rect(Rect2(dmid - 20.0, -2.0, 40.0, 4.0), stone.lightened(0.1))
	var lamp := Vector2(dmid + 24.0, -34.0)
	ci.draw_rect(Rect2(lamp + Vector2(-4, -2), Vector2(8, 10)), Color(0.22, 0.20, 0.18))
	ci.draw_rect(Rect2(lamp + Vector2(-3, -1), Vector2(6, 8)), Color(1.0, 0.86, 0.52))
	SoftGlow.draw(ci, lamp + Vector2(0, 3), 22.0, Color(1.0, 0.80, 0.42, 0.22 + 0.06 * sin(_time * 2.0)), 0.6)
	# the roof: a shingled slope from the eaves up to the ridge, then the far side, darker
	var eave := -wall_h
	var top := -wall_h - depth
	var ridge := eave - depth * 0.62
	ci.draw_rect(Rect2(-hw - 8.0, top - 4.0, hw * 2.0 + 16.0, ridge - top + 4.0), roof.darkened(0.25))
	ci.draw_rect(Rect2(-hw - 8.0, ridge, hw * 2.0 + 16.0, eave - ridge + 6.0), roof)
	var row := 0
	var y := ridge + 6.0
	while y < eave + 4.0:
		ci.draw_rect(Rect2(-hw - 8.0, y, hw * 2.0 + 16.0, 1.0), roof.darkened(0.18))
		var off := 0.0 if row % 2 == 0 else 7.0
		var x := -hw - 8.0 + off
		while x < hw + 8.0:
			ci.draw_rect(Rect2(x, y - 6.0, 1.0, 6.0), roof.darkened(0.12))
			x += 14.0
		y += 7.0
		row += 1
	var fy := top
	while fy < ridge - 2.0:
		ci.draw_rect(Rect2(-hw - 8.0, fy, hw * 2.0 + 16.0, 1.0), roof.darkened(0.38))
		fy += 8.0
	ci.draw_rect(Rect2(-hw - 8.0, ridge - 2.0, hw * 2.0 + 16.0, 4.0), roof.lightened(0.18))   # the ridge cap
	ci.draw_rect(Rect2(-hw - 8.0, eave + 4.0, hw * 2.0 + 16.0, 3.0), Color(0, 0, 0, 0.25))    # under the eaves
	ci.draw_rect(Rect2(-hw - 8.0, top - 4.0, 2.0, eave - top + 10.0), roof.lightened(0.12))
	ci.draw_rect(Rect2(hw + 6.0, top - 4.0, 2.0, eave - top + 10.0), roof.darkened(0.35))
	# the chimney, over the hearth, smoking
	var cx := lx(float(house.get("chimney_x", position.x)))
	var cbase := ridge - depth * 0.12
	ci.draw_rect(Rect2(cx - 9.0, cbase - 30.0, 18.0, 34.0), stone)
	ci.draw_rect(Rect2(cx - 9.0, cbase - 30.0, 4.0, 34.0), stone.lightened(0.15))
	ci.draw_rect(Rect2(cx - 11.0, cbase - 34.0, 22.0, 5.0), stone.darkened(0.2))
	for k in 4:
		var ph := fposmod(_time * 0.25 + float(k) / 4.0, 1.0)
		var r := 3.0 + ph * 7.0
		var q := Vector2(cx + sin(ph * 5.0 + float(k)) * 4.0 + ph * 10.0, cbase - 40.0 - ph * 46.0)
		ci.draw_circle(q, r, Color(0.94, 0.94, 0.96, 0.55 * (1.0 - ph)))


func _draw_front_window(ci: CanvasItem, r: Rect2, timber: Color) -> void:
	ci.draw_rect(r.grow(2.0), timber)
	ci.draw_rect(r, Color(0.98, 0.84, 0.52))                       # warm light inside
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 6.0)), Color(1.0, 0.92, 0.70))
	ci.draw_rect(Rect2(r.get_center().x - 1.0, r.position.y, 2.0, r.size.y), timber)
	ci.draw_rect(Rect2(r.position.x, r.get_center().y - 1.0, r.size.x, 2.0), timber)
	ci.draw_rect(Rect2(r.position.x - 8.0, r.position.y - 1.0, 6.0, r.size.y + 2.0), Color(0.40, 0.56, 0.42))
	ci.draw_rect(Rect2(r.end.x + 2.0, r.position.y - 1.0, 6.0, r.size.y + 2.0), Color(0.40, 0.56, 0.42))
	var box := Rect2(r.position.x - 2.0, r.end.y + 2.0, r.size.x + 4.0, 5.0)
	ci.draw_rect(box, Color(0.50, 0.34, 0.22))
	var flowers := [Color(0.92, 0.42, 0.46), Color(0.98, 0.86, 0.40), Color(0.74, 0.56, 0.90)]
	var x := box.position.x + 3.0
	var k := 0
	while x < box.end.x - 2.0:
		ci.draw_circle(Vector2(x, box.position.y - 1.0), 2.0, Color(0.36, 0.58, 0.32))
		ci.draw_circle(Vector2(x + 1.0, box.position.y - 2.5), 1.6, flowers[k % 3])
		x += 5.0
		k += 1


## While it's being built: a timber frame that rises with the build, boards climbing it, scaffolding in front.
func _draw_frame(ci: CanvasItem) -> void:
	var timber := Color(0.74, 0.56, 0.34)
	var dark := timber.darkened(0.3)
	var p := progress
	var post_h := wall_h * clampf(p / 0.35, 0.15, 1.0)
	# posts along the front and down both sides (the back's are HouseBackWall's, so they sort right)
	var x := -hw
	while x <= hw - 4.0:
		ci.draw_rect(Rect2(x, -post_h, 4.0, post_h), timber)
		ci.draw_rect(Rect2(x + 3.0, -post_h, 1.0, post_h), dark)
		x += 40.0
	for side in [-hw, hw - 4.0]:
		var y := -depth * 0.5
		ci.draw_rect(Rect2(side, y - post_h, 4.0, post_h), timber)
	if p > 0.35:
		# the top beams, front and sides
		ci.draw_rect(Rect2(-hw, -wall_h - 3.0, hw * 2.0, 4.0), timber)
		ci.draw_rect(Rect2(-hw, -wall_h - depth - 3.0, 4.0, depth), timber.darkened(0.08))
		ci.draw_rect(Rect2(hw - 4.0, -wall_h - depth - 3.0, 4.0, depth), timber.darkened(0.08))
	if p > 0.5:
		# boards climbing the front wall, a row at a time
		var rows := int(clampf((p - 0.5) / 0.4, 0.0, 1.0) * (wall_h - 10.0) / 6.0)
		var door: Array = house.get("door", [-24, 24])
		var dx0 := lx(float(door[0]))
		var dx1 := lx(float(door[1]))
		for k in rows:
			var by := -6.0 - float(k) * 6.0
			ci.draw_rect(Rect2(-hw, by, dx0 + hw, 5.0), Color(0.82, 0.66, 0.44).darkened(0.04 * float(k % 2)))
			ci.draw_rect(Rect2(dx1, by, hw - dx1, 5.0), Color(0.82, 0.66, 0.44).darkened(0.04 * float(k % 2)))
	if p > 0.6:
		# rafters over where the roof will be
		var ridge := -wall_h - depth * 0.62
		var n := int(clampf((p - 0.6) / 0.3, 0.0, 1.0) * 14.0)
		for k in n:
			var rx := -hw + 8.0 + float(k) * (hw * 2.0 - 16.0) / 13.0
			ci.draw_line(Vector2(rx, -wall_h), Vector2(rx, ridge), timber, 2.0)
			ci.draw_line(Vector2(rx, ridge), Vector2(rx, -wall_h - depth), dark, 2.0)
		if n > 0:
			ci.draw_rect(Rect2(-hw, ridge - 2.0, hw * 2.0, 3.0), timber.lightened(0.1))
	# scaffolding along the front: poles, a plank to stand on, a ladder
	var pole := Color(0.58, 0.48, 0.36)
	for px in [-hw - 10.0, -hw * 0.3, hw * 0.3, hw + 6.0]:
		ci.draw_rect(Rect2(px, -wall_h - 8.0, 3.0, wall_h + 14.0), pole)
	ci.draw_rect(Rect2(-hw - 12.0, -wall_h * 0.55, hw * 2.0 + 22.0, 3.0), Color(0.76, 0.62, 0.42))
	var lad := Vector2(hw * 0.62, 6.0)
	ci.draw_rect(Rect2(lad + Vector2(-6, -wall_h * 0.55 - 6.0), Vector2(2, wall_h * 0.55 + 6.0)), pole)
	ci.draw_rect(Rect2(lad + Vector2(5, -wall_h * 0.55 - 6.0), Vector2(2, wall_h * 0.55 + 6.0)), pole)
	var ry := lad.y - 6.0
	while ry > -wall_h * 0.55:
		ci.draw_rect(Rect2(lad.x - 5.0, ry, 11.0, 1.5), pole.lightened(0.15))
		ry -= 7.0


## The cutaway: the front wall as a low strip, its door gap open.
func _draw_strip(ci: CanvasItem) -> void:
	var plaster := _col("plaster", Color(0.93, 0.88, 0.78))
	var timber := _col("timber", Color(0.42, 0.28, 0.18))
	var door: Array = house.get("door", [-24, 24])
	var dx0 := lx(float(door[0]))
	var dx1 := lx(float(door[1]))
	for seg in [[-hw, dx0], [dx1, hw]]:
		var a := float(seg[0])
		var b := float(seg[1])
		ci.draw_rect(Rect2(a, -CUT_STRIP, b - a, CUT_STRIP - 2.0), plaster.darkened(0.06))
		ci.draw_rect(Rect2(a, -CUT_STRIP - _wall_t + 2.0, b - a, _wall_t), timber.lightened(0.1))
		ci.draw_rect(Rect2(a, -CUT_STRIP - _wall_t + 2.0, b - a, 1.0), timber.lightened(0.35))
		ci.draw_rect(Rect2(a, -2.0, b - a, 2.0), _col("stone", Color(0.62, 0.60, 0.56)))


## A node that draws through a callback, so the house can paint its shell and its strip as separate layers
## (each fades on its own) with one set of drawing code.
class Painter extends Node2D:
	var _fn: Callable

	func _init(fn: Callable) -> void:
		_fn = fn
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		_fn.call(self)
