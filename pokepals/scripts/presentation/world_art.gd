class_name WorldArt
extends Node2D
## Draws the hand-placed cozy world from world.json: a mottled ground, worn paths,
## ponds that shimmer, scattered grass, flowers and tree canopies that sway in the
## wind, soft contact shadows for depth, and the interactable props (with a warm
## breathing glow on the lit ones). Pure presentation — it reads world data and the
## mood knobs in the "atmosphere" block, and renders them; it holds no game rules.
## Interactables can briefly "pulse" when touched, a little glow of acknowledgement.

var _ground_color := Color(0.43, 0.58, 0.36)
var _bounds := Rect2()
var _ponds: Array = []     # [ { center: Vector2, radius: float, color: Color } ]
var _paths: Array = []     # [ { from: Vector2, to: Vector2, color: Color } ]
var _trees: Array = []     # [ { pos: Vector2, phase: float } ]
var _flowers: Array = []   # [ { pos: Vector2, color: Color, phase: float } ]
var _grass: Array = []     # [ { pos: Vector2, len: float, color: Color, phase: float } ]
var _interactables: Array = []  # [ { pos: Vector2, color: Color, type: String, pulse: float } ]

# --- atmosphere (presentation-only mood, from world.json "atmosphere") ---
var _time := 0.0
var _wind_strength := 2.6
var _wind_speed := 1.15
var _glow_pulse_speed := 1.4
var _ground_noise: ImageTexture = null


func render_world(data: Dictionary) -> void:
	_ground_color = WorldData.to_color(data["ground_color"])
	var bmin := WorldData.to_vec2(data["bounds"]["min"])
	var bmax := WorldData.to_vec2(data["bounds"]["max"])
	_bounds = Rect2(bmin, bmax - bmin)

	var atmo: Dictionary = data.get("atmosphere", {})
	var wind: Dictionary = atmo.get("wind", {})
	_wind_strength = float(wind.get("strength", 2.6))
	_wind_speed = float(wind.get("speed", 1.15))
	_glow_pulse_speed = float(atmo.get("glow", {}).get("pulse_speed", 1.4))
	_build_ground_noise(atmo.get("ground_noise", {}))

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

	# Trees and flowers each carry a per-element wind "phase" (seeded from position) so
	# they don't all sway in lockstep — the breeze reads as organic, not a metronome.
	_trees.clear()
	for t in data.get("trees", []):
		var tp := WorldData.to_vec2(t)
		_trees.append({ "pos": tp, "phase": _phase_for(tp) })

	_flowers.clear()
	for f in data.get("flowers", []):
		var fp := Vector2(float(f[0]), float(f[1]))
		_flowers.append({ "pos": fp, "color": Color(float(f[2]), float(f[3]), float(f[4])), "phase": _phase_for(fp) })

	_scatter_grass()

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


## A stable pseudo-random phase in [0, TAU) derived from a world position, so each
## swaying thing keeps the same offset every frame (and across runs).
func _phase_for(p: Vector2) -> float:
	return fposmod(p.x * 0.013 + p.y * 0.021, TAU)


## Bake a small, soft noise texture once and stretch it over the whole ground so the
## grass reads as dappled rather than a single flat fill. Cheap: one texture, one draw.
func _build_ground_noise(cfg: Dictionary) -> void:
	var contrast := float(cfg.get("contrast", 0.12))
	var tint := WorldData.to_color(cfg.get("tint", [0.30, 0.42, 0.26]))
	if contrast <= 0.0:
		_ground_noise = null
		return
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.05
	n.fractal_octaves = 3
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := (n.get_noise_2d(float(x), float(y)) + 1.0) * 0.5  # 0..1
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, v * contrast))
	_ground_noise = ImageTexture.create_from_image(img)


## Scatter little grass tufts across the ground for texture. Seeded so the layout is
## identical every run; each tuft gets its own wind phase.
func _scatter_grass() -> void:
	_grass.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0FFEE
	var count := int(clampf(_bounds.size.x * _bounds.size.y / 26000.0, 40, 240))
	for i in count:
		var pos := Vector2(
			_bounds.position.x + rng.randf() * _bounds.size.x,
			_bounds.position.y + rng.randf() * _bounds.size.y)
		var shade := rng.randf_range(-0.05, 0.06)
		_grass.append({
			"pos": pos,
			"len": rng.randf_range(4.0, 8.0),
			"color": Color(0.30 + shade, 0.46 + shade, 0.28 + shade, 0.85),
			"phase": _phase_for(pos),
		})


## Briefly glow the interactable at this index (called when it's touched).
func pulse_interactable(index: int) -> void:
	if index >= 0 and index < _interactables.size():
		_interactables[index]["pulse"] = 1.0


func _process(delta: float) -> void:
	_time += delta
	for it in _interactables:
		if it["pulse"] > 0.0:
			it["pulse"] = maxf(0.0, it["pulse"] - delta * 1.5)
	# The world is gently animated (wind, shimmer, breathing glow), so redraw each frame.
	queue_redraw()


## Horizontal wind offset for a swaying element with the given phase. Things higher off
## the ground (a tall canopy vs. a flower) catch more wind — caller scales by `gain`.
func _sway(phase: float, gain: float) -> float:
	return sin(_time * _wind_speed + phase) * _wind_strength * gain


func _draw() -> void:
	draw_rect(_bounds, _ground_color)

	# dappled ground: a soft noise overlay stretched across the whole field
	if _ground_noise != null:
		draw_texture_rect(_ground_noise, _bounds, false, Color(1, 1, 1, 1))

	# grass tufts (drawn low, swaying), giving the ground some life and texture
	for g in _grass:
		var sway := _sway(g["phase"], 0.25)
		var base: Vector2 = g["pos"]
		var tip := base + Vector2(sway, -float(g["len"]))
		draw_line(base, tip, g["color"], 1.5)
		draw_line(base + Vector2(-2, 0), base + Vector2(-2 + sway * 0.8, -float(g["len"]) * 0.7), g["color"], 1.3)
		draw_line(base + Vector2(2, 0), base + Vector2(2 + sway * 0.8, -float(g["len"]) * 0.7), g["color"], 1.3)

	# worn paths
	for p in _paths:
		draw_line(p["from"], p["to"], p["color"], 16.0)

	# ponds, each with a lighter rim and a couple of slow, breathing ripples
	for pond in _ponds:
		var center: Vector2 = pond["center"]
		var radius: float = pond["radius"]
		draw_circle(center, radius, pond["color"])
		draw_arc(center, radius, 0.0, TAU, 48, Color(0.78, 0.86, 0.88, 0.5), 2.0)
		for k in 2:
			var t := fposmod(_time * 0.25 + float(k) * 0.5, 1.0)
			var rr := radius * (0.25 + 0.7 * t)
			draw_arc(center, rr, 0.0, TAU, 40, Color(0.85, 0.92, 0.95, 0.22 * (1.0 - t)), 1.5)

	# flowers (a petal dot with a bright center), nodding in the breeze
	for f in _flowers:
		var fp: Vector2 = f["pos"] + Vector2(_sway(f["phase"], 0.45), 0.0)
		draw_circle(fp, 4.0, f["color"])
		draw_circle(fp, 1.6, Color(0.98, 0.92, 0.55))

	# interactable props: contact shadow, optional warm glow, then the prop silhouette
	for it in _interactables:
		_draw_shadow(it["pos"] + Vector2(0, 6), 11.0, 0.16)
		_draw_glow(it["type"], it["pos"])
		var pulse: float = it["pulse"]
		if pulse > 0.0:
			draw_circle(it["pos"], 20.0 + 12.0 * pulse, Color(1, 1, 1, 0.18 * pulse))
		_draw_prop(it["type"], it["pos"], it["color"])

	# trees (shadow + trunk + layered, wind-swayed canopy), drawn last so they sit above
	for t in _trees:
		var tp: Vector2 = t["pos"]
		var cs := _sway(t["phase"], 1.0)  # canopy catches the most wind
		_draw_shadow(tp + Vector2(0, 4), 18.0, 0.20)
		draw_rect(Rect2(tp + Vector2(-4, -6), Vector2(8, 22)), Color(0.42, 0.31, 0.22))
		draw_circle(tp + Vector2(cs, -22), 22.0, Color(0.27, 0.44, 0.28))
		draw_circle(tp + Vector2(-12 + cs, -16), 15.0, Color(0.30, 0.48, 0.31))
		draw_circle(tp + Vector2(12 + cs, -16), 15.0, Color(0.30, 0.48, 0.31))


## A soft, flattened ground shadow — the cheapest, biggest depth cue we have. Drawn as
## a circle squashed vertically via the draw transform, then the transform is reset.
func _draw_shadow(pos: Vector2, r: float, alpha: float) -> void:
	draw_set_transform(pos, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, r, Color(0, 0, 0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A warm, breathing radial glow under the lit props (lantern, crystal). Faked with a
## few stacked translucent circles so it works everywhere without a real 2D light.
func _draw_glow(type: String, p: Vector2) -> void:
	var warm: Color
	match type:
		"lantern":
			warm = Color(1.0, 0.85, 0.5)
		"crystal":
			warm = Color(0.6, 0.85, 1.0)
		_:
			return
	var breathe := 0.82 + 0.18 * sin(_time * _glow_pulse_speed)
	var top := p + Vector2(0, -22)
	for k in 3:
		var rr := (34.0 - float(k) * 9.0) * breathe
		draw_circle(top, rr, Color(warm.r, warm.g, warm.b, 0.07))


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
