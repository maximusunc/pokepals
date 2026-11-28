class_name DigSites
extends Node2D
## What is on the sand at EBBMERE's buried spots, drawn flat on the flats (a child of WorldArt, above the
## water layer): the little ring of bubbles that tells you something is under there (and, when your companion's
## shape can dig it, a soft pulse in the form's colour, the same cue the Vale's diggable mounds use); the hole
## once it has been dug and what came out of it; a crab running for the sea; and the spray of sand while a dig
## is under way. Pure presentation. The TideDirector owns every decision and hands this node what to show
## each frame (`signs`, `holes`) and the one-off effects (`spray`, `crab`, `flash`).

var signs: Array = []      # { pos: Vector2, color: Color, pulse: bool }
var holes: Array = []      # { pos, kind: "shell"|"crab"|"glass"|"dollar", name, age }
var _crabs: Array = []     # { pos, dir, age }
var _sprays: Array = []    # { pos, vel, age }
var _flashes: Array = []   # { pos, age }
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	var any := not signs.is_empty() or not holes.is_empty() or not _crabs.is_empty() or not _sprays.is_empty() or not _flashes.is_empty()
	for c in _crabs:
		c["age"] = float(c["age"]) + delta
		c["pos"] = (c["pos"] as Vector2) + (c["dir"] as Vector2) * 46.0 * delta
	_crabs = _crabs.filter(func(c: Dictionary) -> bool: return float(c["age"]) < 3.2)
	for s in _sprays:
		s["age"] = float(s["age"]) + delta
		s["vel"] = (s["vel"] as Vector2) + Vector2(0.0, 120.0) * delta
		s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * delta
	_sprays = _sprays.filter(func(s: Dictionary) -> bool: return float(s["age"]) < 0.7)
	for f in _flashes:
		f["age"] = float(f["age"]) + delta
	_flashes = _flashes.filter(func(f: Dictionary) -> bool: return float(f["age"]) < 0.8)
	if any:
		queue_redraw()


func add_crab(pos: Vector2, dir: Vector2) -> void:
	_crabs.append({ "pos": pos, "dir": dir.normalized() if dir.length() > 0.01 else Vector2.UP, "age": 0.0 })


func add_spray(pos: Vector2, n: int = 3) -> void:
	for _i in n:
		_sprays.append({ "pos": pos + Vector2(randf_range(-4.0, 4.0), -2.0), "vel": Vector2(randf_range(-34.0, 34.0), randf_range(-70.0, -34.0)), "age": 0.0 })


## A brief ring where a tap landed on a spot that cannot be dug in this shape.
func flash(pos: Vector2) -> void:
	_flashes.append({ "pos": pos, "age": 0.0 })


func _draw() -> void:
	for h in holes:
		_draw_hole(h)
	for s in signs:
		_draw_sign(s)
	for c in _crabs:
		_draw_crab(c)
	for p in _sprays:
		var a := 1.0 - float(p["age"]) / 0.7
		draw_rect(Rect2((p["pos"] as Vector2) - Vector2(1, 1), Vector2(2, 2)), Color(0.88, 0.80, 0.64, a))
	for f in _flashes:
		var t := float(f["age"]) / 0.8
		draw_set_transform(f["pos"], 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 8.0 + t * 12.0, 0.0, TAU, 20, Color(1.0, 1.0, 1.0, 0.7 * (1.0 - t)), 1.2, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_sign(s: Dictionary) -> void:
	var p: Vector2 = s["pos"]
	var col: Color = s["color"]
	# a dark dimple with a ring of small bubbles that rise and pop, each on its own beat
	draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 6.0, Color(0.30, 0.25, 0.19, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 5:
		var ph := fposmod(_time * 0.9 + float(i) * 0.37 + p.x * 0.013, 1.0)
		var ang := float(i) / 5.0 * TAU + p.y * 0.02
		var q := p + Vector2(cos(ang) * 5.0, sin(ang) * 2.5 - ph * 7.0)
		draw_circle(q, 1.2 + 0.8 * (1.0 - ph), Color(0.95, 0.98, 1.0, 0.85 * (1.0 - ph * ph)))
	if bool(s.get("pulse", false)):
		var k := 0.5 + 0.5 * sin(_time * 3.0 + p.x * 0.05)
		draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 10.0 + k * 3.0, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.5 + 0.3 * k), 1.4, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_hole(h: Dictionary) -> void:
	var p: Vector2 = h["pos"]
	# a heap of turned sand with a dark hollow in it
	draw_set_transform(p + Vector2(0, 1), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2(5, -1), 8.0, Color(0.70, 0.62, 0.48, 0.9))
	draw_circle(Vector2.ZERO, 7.0, Color(0.26, 0.21, 0.16, 0.95))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var kind := String(h.get("kind", "shell"))
	var off := p + Vector2(11, 2)
	match kind:
		"shell":
			draw_circle(off, 3.2, Color(0.90, 0.80, 0.68))
			draw_circle(off + Vector2(-1, -1), 1.6, Color(0.99, 0.94, 0.86))
			draw_line(off + Vector2(0, -3), off + Vector2(0, 3), Color(0.70, 0.56, 0.46), 1.0)
		"glass":
			draw_circle(off, 2.6, Color(0.50, 0.82, 0.70, 0.9))
			draw_circle(off + Vector2(-1, -1), 1.0, Color(0.90, 1.0, 0.95, 0.9))
		"dollar":
			draw_circle(off, 4.2, Color(0.96, 0.93, 0.86))
			draw_circle(off, 1.4, Color(0.78, 0.72, 0.62))


func _draw_crab(c: Dictionary) -> void:
	var p: Vector2 = c["pos"]
	var scuttle := sin(float(c["age"]) * 26.0)
	draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
	draw_circle(Vector2.ZERO, 4.0, Color(0.84, 0.36, 0.28))
	draw_circle(Vector2(-1, -1), 2.0, Color(0.94, 0.52, 0.40))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for sgn in [-1.0, 1.0]:
		draw_line(p + Vector2(sgn * 3, 1), p + Vector2(sgn * (6 + scuttle), 3), Color(0.70, 0.26, 0.20), 1.0)
		draw_line(p + Vector2(sgn * 3, 0), p + Vector2(sgn * (6 - scuttle), 4), Color(0.70, 0.26, 0.20), 1.0)
		draw_circle(p + Vector2(sgn * 5.5, -3 + scuttle * 0.5), 1.6, Color(0.90, 0.44, 0.34))
	draw_circle(p + Vector2(-1.5, -3), 0.8, Color(0.1, 0.1, 0.1))
	draw_circle(p + Vector2(1.5, -3), 0.8, Color(0.1, 0.1, 0.1))
