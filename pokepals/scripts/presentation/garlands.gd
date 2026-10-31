class_name Garlands
extends Node2D
## What's strung over a souk's lane (the Bazaar): strings of little lights, lines of bunting, and brass
## lanterns hanging low on cords, each spanning the lane from wall to wall with a gentle sag. Drawn
## ABOVE everyone (a z_index over the y-sorted scenery), because it hangs overhead. Pure presentation,
## read from the spec's "garlands": [{ from, to, sag, kind: "lights" | "bunting" | "lanterns" }].

const BUNTING := [Color(0.86, 0.30, 0.22), Color(0.95, 0.72, 0.22), Color(0.30, 0.56, 0.62), Color(0.78, 0.42, 0.62), Color(0.96, 0.9, 0.78)]

var _lines: Array = []  # [{ a, b, sag, kind, seed }]
var _time := 0.0


func setup(garlands: Array) -> void:
	z_index = 20
	_lines.clear()
	for g in garlands:
		if not (g is Dictionary):
			continue
		var a := WorldData.to_vec2(g.get("from", [0, 0]))
		_lines.append({ "a": a, "b": WorldData.to_vec2(g.get("to", [0, 0])), "sag": float(g.get("sag", 16.0)),
			"kind": String(g.get("kind", "lights")), "seed": fposmod(a.x * 0.013 + a.y * 0.029, 1.0) })


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## A point along a sagging line, t in 0..1 (a parabola: deepest in the middle).
static func _along(a: Vector2, b: Vector2, sag: float, t: float) -> Vector2:
	return a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t))


func _draw() -> void:
	var vis := ViewCull.visible_world_rect(self, 120.0)
	for l in _lines:
		var a: Vector2 = l["a"]
		var b: Vector2 = l["b"]
		if vis.has_area() and not vis.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(40.0)):
			continue
		var sag: float = l["sag"]
		var steps := 16
		var pts := PackedVector2Array()
		for i in steps + 1:
			pts.append(_along(a, b, sag, float(i) / float(steps)))
		draw_polyline(pts, Color(0.18, 0.12, 0.08, 0.8), 1.0)
		match String(l["kind"]):
			"bunting":
				var n := int(a.distance_to(b) / 14.0)
				for i in n:
					var p := _along(a, b, sag, (float(i) + 0.5) / float(n))
					var c: Color = BUNTING[(i + int(l["seed"] * 10.0)) % BUNTING.size()]
					var flutter := sin(_time * 2.2 + float(i)) * 1.5
					draw_colored_polygon(PackedVector2Array([p + Vector2(-5, 0), p + Vector2(5, 0), p + Vector2(flutter, 9)]), c)
			"lanterns":
				var n := maxi(2, int(a.distance_to(b) / 70.0))
				for i in n:
					var p := _along(a, b, sag, (float(i) + 0.5) / float(n))
					var sway := sin(_time * 1.3 + float(i) + float(l["seed"]) * 6.0) * 2.0
					var hang := p + Vector2(sway, 16)
					draw_line(p, hang + Vector2(0, -6), Color(0.2, 0.14, 0.1), 1.0)
					var flick := 0.85 + 0.15 * sin(_time * 5.0 + float(i) * 1.7)
					SoftGlow.draw(self, hang, 22.0 * flick, Color(1.0, 0.7, 0.36, 0.32), 0.65)
					draw_colored_polygon(PackedVector2Array([hang + Vector2(-5, -6), hang + Vector2(5, -6), hang + Vector2(6, 2), hang + Vector2(0, 8), hang + Vector2(-6, 2)]), Color(0.66, 0.46, 0.2))
					draw_circle(hang + Vector2(0, 0), 3.2 * flick, Color(1.0, 0.86, 0.5))
			_:
				var n := int(a.distance_to(b) / 9.0)
				for i in n:
					var p := _along(a, b, sag, (float(i) + 0.5) / float(n))
					var tw := 0.6 + 0.4 * sin(_time * 3.0 + float(i) * 2.3 + float(l["seed"]) * 9.0)
					SoftGlow.draw(self, p, 5.0, Color(1.0, 0.82, 0.48, 0.35 * tw), 0.7)
					draw_circle(p, 1.4, Color(1.0, 0.92, 0.66, 0.6 + 0.4 * tw))
