class_name WorldArt
extends Node2D
## Draws the hand-placed cozy clearing from world.json: ground, worn paths, a pond,
## trees, flowers, and the interactable props. Pure presentation — it reads world
## data and renders it; it holds no game rules. Interactables can briefly "pulse"
## when touched, a little glow of acknowledgement.

var _ground_color := Color(0.43, 0.58, 0.36)
var _bounds := Rect2()
var _pond := {}            # { center: Vector2, radius: float, color: Color }
var _paths: Array = []     # [ { from: Vector2, to: Vector2, color: Color } ]
var _trees: Array = []     # [ Vector2 ]
var _flowers: Array = []   # [ { pos: Vector2, color: Color } ]
var _interactables: Array = []  # [ { pos: Vector2, color: Color, pulse: float } ]


func render_world(data: Dictionary) -> void:
	_ground_color = WorldData.to_color(data["ground_color"])
	var bmin := WorldData.to_vec2(data["bounds"]["min"])
	var bmax := WorldData.to_vec2(data["bounds"]["max"])
	_bounds = Rect2(bmin, bmax - bmin)

	var pond: Dictionary = data["pond"]
	_pond = { "center": WorldData.to_vec2(pond["center"]), "radius": float(pond["radius"]), "color": WorldData.to_color(pond["color"]) }

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
		_interactables.append({ "pos": WorldData.to_vec2(it["position"]), "color": WorldData.to_color(it["color"]), "pulse": 0.0 })

	queue_redraw()


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

	# pond with a lighter rim
	draw_circle(_pond["center"], _pond["radius"], _pond["color"])
	draw_arc(_pond["center"], _pond["radius"], 0.0, TAU, 48, Color(0.78, 0.86, 0.88, 0.5), 2.0)

	# flowers (a petal dot with a bright center)
	for f in _flowers:
		draw_circle(f["pos"], 4.0, f["color"])
		draw_circle(f["pos"], 1.6, Color(0.98, 0.92, 0.55))

	# interactable props (square-ish base + glow when pulsing)
	for it in _interactables:
		var pulse: float = it["pulse"]
		if pulse > 0.0:
			draw_circle(it["pos"], 18.0 + 10.0 * pulse, Color(1, 1, 1, 0.18 * pulse))
		draw_circle(it["pos"], 8.0, it["color"])
		draw_arc(it["pos"], 8.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 1.5)

	# trees (trunk + layered canopy), drawn last so they sit above the grass
	for t in _trees:
		draw_rect(Rect2(t + Vector2(-4, -6), Vector2(8, 22)), Color(0.42, 0.31, 0.22))
		draw_circle(t + Vector2(0, -22), 22.0, Color(0.27, 0.44, 0.28))
		draw_circle(t + Vector2(-12, -16), 15.0, Color(0.30, 0.48, 0.31))
		draw_circle(t + Vector2(12, -16), 15.0, Color(0.30, 0.48, 0.31))
