class_name HouseBackWall
extends Node2D
## The back (north) wall of YOUR HOUSE, seen from inside (home building; HouseView). A y-sorted node in the
## Scenery at the wall's foot, so everything in the rooms stands in front of it. Its origin is the middle of
## the house's north edge; the wall's face rises above it.
##
## Built: each room's wall (kitchen cream over a tiled splashback, the living room's warm striped paper over a
## wooden wainscot, the bedroom's soft blue), the partitions' ends rising as timber posts, and what hangs on it
## (windows with curtains, a shelf of jars, pans, pictures, a clock), from the house's `decor` list. Shown only
## while you're inside (it fades in with the cutaway). While the house is being built: the back of the frame,
## posts and the boards climbing it, always shown.

var house_view: HouseView

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta


func _draw() -> void:
	if house_view == null:
		return
	if not house_view.built:
		_draw_frame()
		return
	var h := house_view.house
	var wall_h := house_view.wall_h
	var hw := house_view.hw
	var timber := _c(h, "timber", Color(0.42, 0.28, 0.18))
	var rooms: Array = h.get("rooms", [])
	for r in rooms:
		var x0 := float(r["x0"]) - position.x
		var x1 := float(r["x1"]) - position.x
		match String(r.get("id", "")):
			"kitchen":
				_paper(x0, x1, wall_h, Color(0.96, 0.92, 0.82), Color(0.94, 0.88, 0.78), 0)
				_tiles(Rect2(x0, -24.0, x1 - x0, 24.0), Color(0.80, 0.88, 0.86))
			"bedroom":
				_paper(x0, x1, wall_h, Color(0.78, 0.86, 0.92), Color(0.86, 0.92, 0.96), 2)
				_wainscot(x0, x1, Color(0.86, 0.84, 0.80))
			_:
				_paper(x0, x1, wall_h, Color(0.90, 0.74, 0.66), Color(0.86, 0.68, 0.60), 1)
				_wainscot(x0, x1, Color(0.58, 0.40, 0.26))
	# the posts between the rooms and at the corners, rising the wall's full height
	var posts: Array = [-hw, hw - 8.0]
	for i in range(1, rooms.size()):
		posts.append(float(rooms[i - 1]["x1"]) - position.x)
	for px in posts:
		draw_rect(Rect2(px, -wall_h, 8.0, wall_h + 8.0), timber)
		draw_rect(Rect2(px, -wall_h, 2.0, wall_h + 8.0), timber.lightened(0.18))
		draw_rect(Rect2(px + 6.0, -wall_h, 2.0, wall_h + 8.0), timber.darkened(0.2))
	# the top beam, and the wall's cut edge above it
	draw_rect(Rect2(-hw, -wall_h, hw * 2.0, 4.0), timber)
	draw_rect(Rect2(-hw, -wall_h - 3.0, hw * 2.0, 3.0), timber.lightened(0.25))
	# the baseboard
	draw_rect(Rect2(-hw, -3.0, hw * 2.0, 3.0), timber.darkened(0.1))
	for d in h.get("decor", []):
		_decor(String(d.get("kind", "")), float(d["x0"]) - position.x, float(d["x1"]) - position.x, wall_h)


static func _c(h: Dictionary, key: String, fallback: Color) -> Color:
	var cols: Dictionary = h.get("colors", {})
	return WorldData.to_color(cols[key]) if cols.has(key) else fallback


## A room's wall: a base colour with a gentle pattern (0 plain, 1 stripes, 2 little dots).
func _paper(x0: float, x1: float, wall_h: float, base: Color, alt: Color, pattern: int) -> void:
	draw_rect(Rect2(x0, -wall_h, x1 - x0, wall_h), base)
	if pattern == 1:
		var x := x0 + 3.0
		while x < x1:
			draw_rect(Rect2(x, -wall_h, 3.0, wall_h), alt)
			x += 10.0
	elif pattern == 2:
		var y := -wall_h + 6.0
		var row := 0
		while y < -6.0:
			var x := x0 + (4.0 if row % 2 == 0 else 9.0)
			while x < x1 - 2.0:
				draw_rect(Rect2(x, y, 1.0, 1.0), alt)
				x += 10.0
			y += 8.0
			row += 1
	# a soft shade down from the ceiling
	draw_rect(Rect2(x0, -wall_h, x1 - x0, 8.0), Color(0, 0, 0, 0.06))


func _wainscot(x0: float, x1: float, c: Color) -> void:
	draw_rect(Rect2(x0, -20.0, x1 - x0, 20.0), c)
	draw_rect(Rect2(x0, -21.0, x1 - x0, 2.0), c.lightened(0.2))
	var x := x0 + 8.0
	while x < x1 - 4.0:
		draw_rect(Rect2(x, -17.0, 1.0, 14.0), c.darkened(0.15))
		x += 12.0


func _tiles(r: Rect2, c: Color) -> void:
	draw_rect(r, c)
	var y := r.position.y
	while y < r.end.y:
		draw_rect(Rect2(r.position.x, y, r.size.x, 1.0), c.darkened(0.12))
		y += 6.0
	var row := 0
	y = r.position.y
	while y < r.end.y:
		var x := r.position.x + (0.0 if row % 2 == 0 else 6.0)
		while x < r.end.x:
			draw_rect(Rect2(x, y, 1.0, 6.0), c.darkened(0.12))
			x += 12.0
		y += 6.0
		row += 1


func _decor(kind: String, x0: float, x1: float, wall_h: float) -> void:
	var w := x1 - x0
	var mid := (x0 + x1) * 0.5
	match kind:
		"window":
			var r := Rect2(x0, -wall_h + 12.0, w, 26.0)
			draw_rect(r.grow(2.0), Color(0.46, 0.32, 0.20))
			draw_rect(r, Color(0.62, 0.80, 0.92))
			draw_rect(Rect2(r.position.x, r.end.y - 8.0, r.size.x, 8.0), Color(0.56, 0.74, 0.50))   # the garden outside
			draw_circle(r.position + Vector2(r.size.x * 0.3, 8.0), 3.0, Color(1, 1, 1, 0.8))      # a cloud
			draw_rect(Rect2(mid - 1.0, r.position.y, 2.0, r.size.y), Color(0.46, 0.32, 0.20))
			draw_rect(Rect2(r.position.x, r.get_center().y - 1.0, r.size.x, 2.0), Color(0.46, 0.32, 0.20))
			# curtains, tied back
			draw_colored_polygon(PackedVector2Array([r.position + Vector2(-3, -3), r.position + Vector2(7, -3), r.position + Vector2(2, r.size.y + 2)]), Color(0.90, 0.56, 0.52))
			draw_colored_polygon(PackedVector2Array([Vector2(r.end.x + 3, r.position.y - 3), Vector2(r.end.x - 7, r.position.y - 3), Vector2(r.end.x - 2, r.end.y + 2)]), Color(0.90, 0.56, 0.52))
			draw_rect(Rect2(x0 - 4.0, r.end.y + 2.0, w + 8.0, 3.0), Color(0.56, 0.40, 0.26))       # the sill
			draw_circle(Vector2(x1 - 6.0, r.end.y), 3.0, Color(0.42, 0.62, 0.36))                # a pot plant on it
			draw_rect(Rect2(x1 - 8.0, r.end.y, 4.0, 3.0), Color(0.72, 0.42, 0.30))
		"jar_shelf":
			for row in 2:
				var sy := -wall_h + 22.0 + float(row) * 16.0
				draw_rect(Rect2(x0, sy, w, 3.0), Color(0.56, 0.40, 0.26))
				var x := x0 + 3.0
				var k := 0
				while x < x1 - 6.0:
					var jc: Color = [Color(0.92, 0.70, 0.36), Color(0.62, 0.30, 0.30), Color(0.70, 0.82, 0.62), Color(0.96, 0.92, 0.80)][(k + row) % 4]
					draw_rect(Rect2(x, sy - 8.0, 6.0, 8.0), Color(jc, 0.9))
					draw_rect(Rect2(x, sy - 9.0, 6.0, 2.0), Color(0.78, 0.66, 0.50))
					x += 9.0
					k += 1
		"pots":
			draw_rect(Rect2(x0, -wall_h + 14.0, w, 2.0), Color(0.30, 0.28, 0.26))   # the rail
			var x := x0 + 4.0
			var k := 0
			while x < x1 - 4.0:
				draw_line(Vector2(x, -wall_h + 16.0), Vector2(x, -wall_h + 20.0), Color(0.30, 0.28, 0.26), 1.0)
				var pc := Color(0.80, 0.52, 0.32) if k % 2 == 0 else Color(0.36, 0.36, 0.38)
				draw_circle(Vector2(x, -wall_h + 24.0), 4.0, pc)
				x += 10.0
				k += 1
		"painting", "small_painting", "picture":
			var ph := 20.0 if kind == "painting" else 14.0
			var r := Rect2(x0, -wall_h + 14.0, w, ph)
			draw_rect(r.grow(2.0), Color(0.72, 0.56, 0.24))
			if kind == "picture":
				draw_rect(r, Color(0.96, 0.90, 0.78))
				draw_circle(r.get_center() + Vector2(0, -1), 3.0, Color(0.74, 0.52, 0.40))   # a little portrait
				draw_rect(Rect2(r.get_center().x - 4.0, r.get_center().y + 2.0, 8.0, 4.0), Color(0.40, 0.56, 0.68))
			else:
				draw_rect(r, Color(0.66, 0.82, 0.92))
				draw_rect(Rect2(r.position.x, r.end.y - ph * 0.4, r.size.x, ph * 0.4), Color(0.48, 0.66, 0.40))
				draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + 2, r.end.y - ph * 0.4), Vector2(r.get_center().x, r.position.y + 4), Vector2(r.end.x - 2, r.end.y - ph * 0.4)]), Color(0.58, 0.64, 0.74))
				draw_circle(Vector2(r.end.x - 5.0, r.position.y + 4.0), 2.0, Color(1.0, 0.92, 0.60))
		"clock":
			var c := Vector2(mid, -wall_h + 22.0)
			draw_rect(Rect2(c + Vector2(-5, -6), Vector2(10, 24)), Color(0.50, 0.34, 0.20))
			draw_circle(c, 4.0, Color(0.98, 0.96, 0.90))
			draw_line(c, c + Vector2(0, -3), Color(0.2, 0.2, 0.2), 1.0)
			draw_line(c, c + Vector2(2, 0), Color(0.2, 0.2, 0.2), 1.0)
			var sw := sin(_t * 3.0) * 2.0
			draw_line(c + Vector2(0, 6), c + Vector2(sw, 14), Color(0.86, 0.70, 0.30), 1.0)
			draw_circle(c + Vector2(sw, 15), 1.5, Color(0.86, 0.70, 0.30))


## The back of the frame while it's being built: posts, and boards climbing as it goes.
func _draw_frame() -> void:
	var hv := house_view
	var timber := Color(0.74, 0.56, 0.34)
	var p := hv.progress
	var post_h := hv.wall_h * clampf(p / 0.35, 0.15, 1.0)
	var x := -hv.hw
	while x <= hv.hw - 4.0:
		draw_rect(Rect2(x, -post_h, 4.0, post_h), timber)
		draw_rect(Rect2(x + 3.0, -post_h, 1.0, post_h), timber.darkened(0.3))
		x += 40.0
	if p > 0.35:
		draw_rect(Rect2(-hv.hw, -hv.wall_h - 3.0, hv.hw * 2.0, 4.0), timber)
	if p > 0.4:
		var rows := int(clampf((p - 0.4) / 0.4, 0.0, 1.0) * (hv.wall_h - 6.0) / 6.0)
		for k in rows:
			var by := -6.0 - float(k) * 6.0
			draw_rect(Rect2(-hv.hw, by, hv.hw * 2.0, 5.0), Color(0.82, 0.66, 0.44).darkened(0.04 * float(k % 2)))
