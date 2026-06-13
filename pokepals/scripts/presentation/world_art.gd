class_name WorldArt
extends Node2D
## Draws the hand-placed cozy clearing from world.json: ground, worn paths, a pond,
## trees, flowers, and the interactable props. Pure presentation — it reads world
## data and renders it; it holds no game rules. Interactables can briefly "pulse"
## when touched, a little glow of acknowledgement.

var _ground_color := Color(0.43, 0.58, 0.36)
var _bounds := Rect2()
var _ponds: Array = []     # [ { center: Vector2, radius: float, color: Color } ]
var _paths: Array = []     # [ { from: Vector2, to: Vector2, color: Color } ]
var _trees: Array = []     # [ Vector2 ]
var _flowers: Array = []   # [ { pos: Vector2, color: Color } ]
var _interactables: Array = []  # [ { pos: Vector2, color: Color, type: String, pulse: float } ]


func render_world(data: Dictionary) -> void:
	_ground_color = WorldData.to_color(data["ground_color"])
	var bmin := WorldData.to_vec2(data["bounds"]["min"])
	var bmax := WorldData.to_vec2(data["bounds"]["max"])
	_bounds = Rect2(bmin, bmax - bmin)

	# Water: accept a single "pond" and/or a "ponds" array, so the world can hold
	# more than one body of water without breaking older single-pond data.
	_ponds.clear()
	if data.has("pond"):
		_ponds.append(_parse_pond(data["pond"]))
	for p in data.get("ponds", []):
		_ponds.append(_parse_pond(p))

	_paths.clear()
	for p in data.get("paths", []):
		_paths.append({ "from": WorldData.to_vec2(p["from"]), "to": WorldData.to_vec2(p["to"]), "color": WorldData.to_color(p["color"]) })

	_trees.clear()
	for t in data.get("trees", []):
		_trees.append(WorldData.to_vec2(t))

	_flowers.clear()
	for f in data.get("flowers", []):
		_flowers.append({ "pos": Vector2(float(f[0]), float(f[1])), "color": Color(float(f[2]), float(f[3]), float(f[4])) })

	_interactables.clear()
	for it in data.get("interactables", []):
		_interactables.append({
			"pos": WorldData.to_vec2(it["position"]),
			"color": WorldData.to_color(it["color"]),
			"type": String(it.get("type", "")),
			"pulse": 0.0,
		})

	queue_redraw()


func _parse_pond(pond: Dictionary) -> Dictionary:
	return { "center": WorldData.to_vec2(pond["center"]), "radius": float(pond["radius"]), "color": WorldData.to_color(pond["color"]) }


## Briefly glow the interactable at this index (called when it's touched).
func pulse_interactable(index: int) -> void:
	if index >= 0 and index < _interactables.size():
		_interactables[index]["pulse"] = 1.0


func _process(delta: float) -> void:
	var redraw := false
	for it in _interactables:
		if it["pulse"] > 0.0:
			it["pulse"] = maxf(0.0, it["pulse"] - delta * 1.5)
			redraw = true
	if redraw:
		queue_redraw()


func _draw() -> void:
	draw_rect(_bounds, _ground_color)

	# worn paths
	for p in _paths:
		draw_line(p["from"], p["to"], p["color"], 16.0)

	# ponds, each with a lighter rim
	for pond in _ponds:
		draw_circle(pond["center"], pond["radius"], pond["color"])
		draw_arc(pond["center"], pond["radius"], 0.0, TAU, 48, Color(0.78, 0.86, 0.88, 0.5), 2.0)

	# flowers (a petal dot with a bright center)
	for f in _flowers:
		draw_circle(f["pos"], 4.0, f["color"])
		draw_circle(f["pos"], 1.6, Color(0.98, 0.92, 0.55))

	# interactable props: a soft glow when pulsing, then a distinct little shape per type
	for it in _interactables:
		var pulse: float = it["pulse"]
		if pulse > 0.0:
			draw_circle(it["pos"], 20.0 + 12.0 * pulse, Color(1, 1, 1, 0.18 * pulse))
		_draw_prop(it["type"], it["pos"], it["color"])

	# trees (trunk + layered canopy), drawn last so they sit above the grass
	for t in _trees:
		draw_rect(Rect2(t + Vector2(-4, -6), Vector2(8, 22)), Color(0.42, 0.31, 0.22))
		draw_circle(t + Vector2(0, -22), 22.0, Color(0.27, 0.44, 0.28))
		draw_circle(t + Vector2(-12, -16), 15.0, Color(0.30, 0.48, 0.31))
		draw_circle(t + Vector2(12, -16), 15.0, Color(0.30, 0.48, 0.31))


## Draw a single interactable prop, shaped by its 'type'. Each is a small, readable
## silhouette so the world reads as a place full of distinct things rather than rows
## of identical dots. Unknown types fall back to the original ringed disc.
func _draw_prop(type: String, p: Vector2, color: Color) -> void:
	match type:
		"chime_stone":
			# a little cairn: three stacked, settling stones
			draw_circle(p + Vector2(0, 4), 9.0, color.darkened(0.15))
			draw_circle(p + Vector2(-1, -3), 6.5, color)
			draw_circle(p + Vector2(1, -10), 4.5, color.lightened(0.12))
		"lantern":
			# a post topped with a warm, glowing globe
			draw_rect(Rect2(p + Vector2(-1.5, -6), Vector2(3, 18)), Color(0.30, 0.24, 0.18))
			draw_circle(p + Vector2(0, -28), 11.0, Color(color.r, color.g, color.b, 0.30))
			draw_circle(p + Vector2(0, -28), 6.5, color)
			draw_circle(p + Vector2(-1.5, -30), 2.0, Color(1, 1, 0.9, 0.9))
		"wildflowers":
			# a small clustered patch of blossoms
			var spots := [Vector2(-6, 2), Vector2(6, 1), Vector2(0, -6), Vector2(-3, -1), Vector2(4, -5)]
			for s in spots:
				draw_circle(p + s, 3.2, color)
				draw_circle(p + s, 1.2, Color(0.98, 0.92, 0.55))
		"mushrooms":
			# a tiny ring of spotted toadstools
			for s in [Vector2(-7, 4), Vector2(0, 6), Vector2(7, 3)]:
				draw_rect(Rect2(p + s + Vector2(-1.5, -1), Vector2(3, 6)), Color(0.93, 0.90, 0.82))
				draw_circle(p + s + Vector2(0, -2), 4.5, color)
				draw_circle(p + s + Vector2(-1.5, -3), 1.0, Color(1, 1, 1, 0.9))
				draw_circle(p + s + Vector2(1.5, -1.5), 1.0, Color(1, 1, 1, 0.9))
		"berry_bush":
			# a rounded shrub dotted with red berries
			draw_circle(p + Vector2(-6, 0), 8.0, color)
			draw_circle(p + Vector2(6, 0), 8.0, color)
			draw_circle(p + Vector2(0, -5), 9.0, color.lightened(0.08))
			for s in [Vector2(-7, -2), Vector2(3, -6), Vector2(7, 1), Vector2(-2, 3)]:
				draw_circle(p + s, 2.2, Color(0.82, 0.20, 0.26))
		"bench":
			# a simple weathered seat
			draw_rect(Rect2(p + Vector2(-12, -4), Vector2(24, 4)), color)
			draw_rect(Rect2(p + Vector2(-12, -14), Vector2(24, 3)), color.lightened(0.08))
			draw_rect(Rect2(p + Vector2(-10, 0), Vector2(3, 8)), color.darkened(0.2))
			draw_rect(Rect2(p + Vector2(7, 0), Vector2(3, 8)), color.darkened(0.2))
		"signpost":
			# a leaning post with a board
			draw_rect(Rect2(p + Vector2(-2, -6), Vector2(4, 20)), Color(0.34, 0.26, 0.18))
			draw_rect(Rect2(p + Vector2(-11, -18), Vector2(22, 12)), color)
			draw_line(p + Vector2(-7, -13), p + Vector2(7, -13), color.darkened(0.3), 1.5)
			draw_line(p + Vector2(-7, -9), p + Vector2(4, -9), color.darkened(0.3), 1.5)
		"crystal":
			# a faceted gem with an inner glow
			draw_circle(p, 13.0, Color(color.r, color.g, color.b, 0.22))
			var pts := PackedVector2Array([p + Vector2(0, -14), p + Vector2(7, -2), p + Vector2(4, 10), p + Vector2(-4, 10), p + Vector2(-7, -2)])
			draw_colored_polygon(pts, color)
			draw_line(p + Vector2(0, -14), p + Vector2(0, 10), color.lightened(0.4), 1.0)
			draw_line(p + Vector2(0, -14), p + Vector2(-7, -2), color.lightened(0.25), 1.0)
		"log":
			# a fallen, mossy log lying on its side
			draw_rect(Rect2(p + Vector2(-14, -5), Vector2(28, 10)), color)
			draw_circle(p + Vector2(-14, 0), 5.0, color.lightened(0.12))
			draw_circle(p + Vector2(-14, 0), 2.2, color.darkened(0.3))
			draw_arc(p + Vector2(6, -5), 6.0, PI, TAU, 10, Color(0.40, 0.52, 0.34), 3.0)
		"basin":
			# a small stone basin holding still water
			draw_circle(p + Vector2(0, 2), 12.0, color)
			draw_circle(p + Vector2(0, 0), 8.0, Color(0.40, 0.56, 0.64))
			draw_arc(p + Vector2(0, 0), 8.0, 0.0, TAU, 20, Color(0.85, 0.92, 0.95, 0.6), 1.0)
		_:
			# fallback: the original ringed disc
			draw_circle(p, 8.0, color)
			draw_arc(p, 8.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 1.5)
