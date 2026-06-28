class_name WorldArt
extends Node2D
## Draws the hand-placed cozy world from the world spec: a mottled ground, worn paths,
## ponds that shimmer, scattered grass, flowers and tree canopies that sway in the
## wind, soft contact shadows for depth, and the interactable props (with a warm
## breathing glow on the lit ones). Pure presentation — it reads world data and the
## mood knobs in the "atmosphere" block, and renders them; it holds no game rules.
## Interactables can briefly "pulse" when touched, a little glow of acknowledgement.

var _ground_color := Color(0.43, 0.58, 0.36)
var _bounds := Rect2()
var _ponds: Array = []     # [ { center: Vector2, radius: float, color: Color } ]
var _river: Dictionary = {}  # { rect: Rect2, color: Color, rim: Color } — a long water band, or empty
var _paths: Array = []     # [ { from: Vector2, to: Vector2, color: Color } ]
var _flowers: Array = []   # [ { pos: Vector2, color: Color, phase: float } ]
var _grass: Array = []     # [ { pos: Vector2, len: float, color: Color, phase: float } ]
var _interactables: Array = []  # [ { pos, color, type, pulse, examined: bool, content: String } ]
var _region_tints: Array = []   # [ { rect: Rect2, color: Color } ] — per-area mood wash
# Trees, the border treeline and landmarks live in the y-sorted Scenery layer now, not here.

# --- atmosphere (presentation-only mood, from the world spec's "atmosphere") ---
var _time := 0.0
var _wind_strength := 2.6
var _wind_speed := 1.15
var _glow_pulse_speed := 1.4
var _region_tint_alpha := 0.12
var _ground_noise: ImageTexture = null
var _style: ArtStyle
var _ground_grad: GradientTexture2D = null


func render_world(data: Dictionary, style: ArtStyle = null) -> void:
	_style = style if style != null else ArtStyle.load_style()
	_ground_color = WorldData.to_color(data["ground_color"])
	var bmin := WorldData.to_vec2(data["bounds"]["min"])
	var bmax := WorldData.to_vec2(data["bounds"]["max"])
	_bounds = Rect2(bmin, bmax - bmin)
	# A soft top→bottom ground gradient (palette), baked once, drawn under the dapple.
	_ground_grad = _style.make_vertical_gradient_texture(_style.color("ground_top"), _style.color("ground_bottom"))

	var atmo: Dictionary = data.get("atmosphere", {})
	var wind: Dictionary = atmo.get("wind", {})
	_wind_strength = float(wind.get("strength", 2.6))
	_wind_speed = float(wind.get("speed", 1.15))
	_glow_pulse_speed = float(atmo.get("glow", {}).get("pulse_speed", 1.4))
	_region_tint_alpha = float(atmo.get("region_tint_alpha", 0.12))
	_build_ground_noise(atmo.get("ground_noise", {}))

	# Per-region mood wash: a soft color over each named area that carries a "tint", so
	# the grove, meadow, glade and hollow each feel like somewhere distinct underfoot.
	# Reads the same region rects the companion logic uses for area discovery.
	_region_tints.clear()
	for r in data.get("regions", []):
		if not r.has("tint"):
			continue
		var rmin := WorldData.to_vec2(r["min"])
		var rmax := WorldData.to_vec2(r["max"])
		_region_tints.append({ "rect": Rect2(rmin, rmax - rmin), "color": WorldData.to_color(r["tint"]) })

	# Water: accept a single "pond" and/or a "ponds" array, so the world can hold
	# more than one body of water without breaking older single-pond data.
	_ponds.clear()
	if data.has("pond"):
		_ponds.append(_parse_pond(data["pond"]))
	for p in data.get("ponds", []):
		_ponds.append(_parse_pond(p))

	# A long river band (the Riverbank world): one big water rectangle along an edge, drawn
	# like the ponds but rectangular, with a lighter rim and drifting ripples.
	_river = {}
	if data.has("river"):
		var rv: Dictionary = data["river"]
		var r: Array = rv["rect"]  # [x, y, w, h]
		_river = {
			"rect": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])),
			"color": WorldData.to_color(rv["color"]),
			"rim": WorldData.to_color(rv.get("rim", [0.78, 0.86, 0.88])),
		}

	_paths.clear()
	for p in data.get("paths", []):
		_paths.append({ "from": WorldData.to_vec2(p["from"]), "to": WorldData.to_vec2(p["to"]), "color": WorldData.to_color(p["color"]) })

	# Flowers carry a per-element wind "phase" (seeded from position) so they don't all
	# sway in lockstep — the breeze reads as organic, not a metronome.
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
			"examined": false,   # rocks flip this on when turned over
			"content": "",       # what a turned-over rock revealed: salamander | decoy | empty
			"missed": false,     # true if revealed by the run-out reveal-all (drawn dimmed)
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


## Turn over the rock at this index: mark it searched and record what it revealed
## (salamander | decoy | empty) so it draws differently from here on, with a little pulse
## of acknowledgement. Called by world_controller after the hunt resolves the examine.
## `missed` flags a rock flipped by the end-of-hunt run-out reveal (not by the player) — those
## draw dimmed, reading as "here's what you missed" rather than a triumphant find.
func reveal_rock(index: int, content: String, missed: bool = false) -> void:
	if index >= 0 and index < _interactables.size():
		_interactables[index]["examined"] = true
		_interactables[index]["content"] = content
		_interactables[index]["missed"] = missed
		_interactables[index]["pulse"] = 0.0 if missed else 1.0


## Append a freshly-created interactable (e.g. the completion portal that opens when the
## last salamander is found) so it draws alongside the rest. Returns its index.
func add_interactable(pos: Vector2, color: Color, type: String) -> int:
	_interactables.append({
		"pos": pos, "color": color, "type": type, "pulse": 1.0,
		"examined": false, "content": "", "missed": false,
	})
	queue_redraw()
	return _interactables.size() - 1


## Raise a Ruin slab: it draws lifted (an open doorway under a hoisted lintel) from here on, with a
## pulse of acknowledgement. The collider is removed separately by the controller (Solids rebuild) —
## this is the visual half. Called when a ward's plate is weighted and the slab opens.
func open_slab(index: int) -> void:
	if index >= 0 and index < _interactables.size():
		_interactables[index]["opened"] = true
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
	# ground: a soft vertical palette gradient, with the dapple noise laid over it
	if _ground_grad != null:
		draw_texture_rect(_ground_grad, _bounds, false, Color(1, 1, 1, 1))
	else:
		draw_rect(_bounds, _ground_color)
	if _ground_noise != null:
		draw_texture_rect(_ground_noise, _bounds, false, Color(1, 1, 1, 1))

	# per-region mood wash, so each named area feels distinct underfoot
	for rt in _region_tints:
		var c: Color = rt["color"]
		c.a = _region_tint_alpha
		draw_rect(rt["rect"], c)

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

	# the river: a long water band with a lit upper edge and a few ripples drifting downstream
	if not _river.is_empty():
		var rrect: Rect2 = _river["rect"]
		draw_rect(rrect, _river["color"])
		# a soft brighter rim along the bank-side (top) edge where land meets water
		draw_line(rrect.position, rrect.position + Vector2(rrect.size.x, 0.0), Color(_river["rim"].r, _river["rim"].g, _river["rim"].b, 0.6), 2.0)
		for k in 3:
			var ry := rrect.position.y + 16.0 + float(k) * 26.0
			var drift := fposmod(_time * 12.0 + float(k) * 40.0, rrect.size.x)
			var rip := Color(0.85, 0.92, 0.95, 0.16)
			draw_line(rrect.position + Vector2(drift, ry - rrect.position.y), rrect.position + Vector2(minf(drift + 70.0, rrect.size.x), ry - rrect.position.y), rip, 1.5)

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
		match String(it["type"]):
			"rock":
				_draw_rock(it["pos"], it["color"], bool(it["examined"]), String(it["content"]), bool(it.get("missed", false)))
			"slab":
				_draw_slab(it["pos"], it["color"], bool(it.get("opened", false)))
			"plate":
				_draw_plate(it["pos"], it["color"])
			"column":
				_draw_column(it["pos"], it["color"])
			"nook":
				_draw_nook(it["pos"], it["color"], bool(it.get("opened", false)))
			_:
				_draw_prop(it["type"], it["pos"], it["color"])

	# NOTE: trees and landmarks (great trees) are no longer drawn here. They're spawned
	# as individual TreeView nodes under the y-sorted Scenery layer so the player and
	# companion can pass behind/in front of them by ground position. This pass renders
	# only the always-underneath backdrop (ground, grass, flowers, paths, ponds, props).


## A soft, flattened ground shadow — the cheapest, biggest depth cue we have. Drawn as
## a circle squashed vertically via the draw transform, then the transform is reset.
func _draw_shadow(pos: Vector2, r: float, alpha: float) -> void:
	var c := _style.color("shadow")
	var off := -_style.light_dir() * (r * 0.16)  # shadows fall away from the light
	draw_set_transform(pos + off, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, r, Color(c.r, c.g, c.b, alpha))
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
		"portal":
			warm = Color(0.74, 0.7, 1.0)
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
		"stall":
			# a market stall: a timber counter under a striped, slightly billowing awning on two posts
			var stall_awning := color
			var stall_awning_alt := color.lightened(0.25)
			var stall_sway := _sway(_phase_for(p), 0.35)
			# posts
			draw_rect(Rect2(p + Vector2(-20, -8), Vector2(3, 24)), Color(0.34, 0.26, 0.18))
			draw_rect(Rect2(p + Vector2(17, -8), Vector2(3, 24)), Color(0.34, 0.26, 0.18))
			# counter
			draw_rect(Rect2(p + Vector2(-22, 6), Vector2(44, 10)), Color(0.52, 0.40, 0.28))
			draw_rect(Rect2(p + Vector2(-22, 6), Vector2(44, 3)), Color(0.62, 0.49, 0.34))
			# striped awning (a shallow slanted roof of alternating bands), nodding in the breeze
			for stripe in 4:
				var x0 := -22.0 + float(stripe) * 11.0
				var band := PackedVector2Array([
					p + Vector2(x0, -10), p + Vector2(x0 + 11.0, -10),
					p + Vector2(x0 + 11.0 + stall_sway, -22), p + Vector2(x0 + stall_sway, -22)])
				draw_colored_polygon(band, stall_awning if stripe % 2 == 0 else stall_awning_alt)
			draw_line(p + Vector2(-22, -10), p + Vector2(22, -10), color.darkened(0.25), 1.5)
		"shopkeeper":
			# a friendly standing figure behind the counter: an apron-coloured body, a warm head, a
			# little idle sway so they read as alive rather than a prop
			var keeper_skin := Color(0.92, 0.76, 0.62)
			var keeper_bob := sin(_time * 1.6 + _phase_for(p)) * 1.0
			# body (apron/robe)
			var keeper_body := PackedVector2Array([
				p + Vector2(-7, 8), p + Vector2(7, 8), p + Vector2(5, -8 + keeper_bob), p + Vector2(-5, -8 + keeper_bob)])
			draw_colored_polygon(keeper_body, color)
			draw_line(p + Vector2(0, -6 + keeper_bob), p + Vector2(0, 6), color.darkened(0.2), 1.0)
			# head
			draw_circle(p + Vector2(0, -14 + keeper_bob), 5.0, keeper_skin)
			# a little hood/cap of the apron colour
			draw_arc(p + Vector2(0, -14 + keeper_bob), 5.0, PI, TAU, 12, color.darkened(0.1), 3.0)
		"portal":
			# an upright shimmering oval doorway, gently breathing, with sparks circling its rim
			var sway := 0.9 + 0.1 * sin(_time * 2.0)
			var center := p + Vector2(0, -18)
			draw_set_transform(center, 0.0, Vector2(1.0, 1.9))
			draw_circle(Vector2.ZERO, 13.0, Color(color.r, color.g, color.b, 0.22))
			draw_circle(Vector2.ZERO, 10.0 * sway, Color(color.r, color.g, color.b, 0.5))
			draw_circle(Vector2.ZERO, 6.0 * sway, Color(1, 1, 1, 0.35))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for k in 3:
				var ang := _time * 1.6 + float(k) * TAU / 3.0
				draw_circle(center + Vector2(cos(ang) * 11.0, sin(ang) * 20.0), 1.6, Color(1, 1, 1, 0.7))
		_:
			# fallback: the original ringed disc
			draw_circle(p, 8.0, color)
			draw_arc(p, 8.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 1.5)


## A Ruin gate slab. CLOSED: a heavy upright stone filling the doorway, a worn groove down its face.
## OPENED: it has risen into a lintel up top, leaving a dark, open doorway beneath — the way through.
func _draw_slab(p: Vector2, color: Color, opened: bool) -> void:
	var w := 56.0
	if opened:
		# the dark doorway gap left behind
		draw_rect(Rect2(p + Vector2(-w * 0.5 + 4, -64), Vector2(w - 8, 64)), Color(0.06, 0.08, 0.07, 0.85))
		# the slab, hoisted up into a lintel above the opening
		draw_rect(Rect2(p + Vector2(-w * 0.5, -82), Vector2(w, 16)), color.darkened(0.1))
		draw_rect(Rect2(p + Vector2(-w * 0.5, -82), Vector2(w, 4)), color.lightened(0.12))
		# jambs framing the open doorway
		draw_rect(Rect2(p + Vector2(-w * 0.5 - 2, -64), Vector2(4, 64)), color.darkened(0.2))
		draw_rect(Rect2(p + Vector2(w * 0.5 - 2, -64), Vector2(4, 64)), color.darkened(0.2))
		return
	# closed: the lowered slab barring the way
	draw_rect(Rect2(p + Vector2(-w * 0.5, -68), Vector2(w, 72)), color.darkened(0.08))
	draw_rect(Rect2(p + Vector2(-w * 0.5, -68), Vector2(w, 5)), color.lightened(0.10))
	draw_line(p + Vector2(0, -62), p + Vector2(0, 0), color.darkened(0.28), 2.0)
	# a couple of weathered cracks
	draw_line(p + Vector2(-12, -50), p + Vector2(-8, -20), color.darkened(0.22), 1.0)
	draw_line(p + Vector2(14, -56), p + Vector2(10, -30), color.darkened(0.22), 1.0)


## A companion-plate: a worn round stone set flush in the floor, uncovered by the search. A sunken
## ring with a faint carved glyph — the kind of thing only a creature nosing the moss would find.
func _draw_plate(p: Vector2, color: Color) -> void:
	draw_circle(p + Vector2(0, 1), 15.0, color.darkened(0.25))
	draw_circle(p, 13.0, color)
	draw_arc(p, 9.0, 0.0, TAU, 24, color.darkened(0.3), 1.5)
	draw_arc(p, 4.0, 0.0, TAU, 16, color.lightened(0.15), 1.0)


## A fallen/broken column from the ruined cross-wall: a stout stone stump with a broken top and a
## drum or two toppled beside it. Solid (the wall you can't pass); drawn squat so the slab reads as
## the doorway between them.
func _draw_column(p: Vector2, color: Color) -> void:
	draw_rect(Rect2(p + Vector2(-12, -26), Vector2(24, 30)), color.darkened(0.06))
	draw_rect(Rect2(p + Vector2(-12, -26), Vector2(24, 4)), color.lightened(0.10))
	# broken, uneven crown
	draw_line(p + Vector2(-12, -26), p + Vector2(-4, -32), color.darkened(0.15), 2.0)
	draw_line(p + Vector2(-4, -32), p + Vector2(6, -24), color.darkened(0.15), 2.0)
	draw_line(p + Vector2(6, -24), p + Vector2(12, -28), color.darkened(0.15), 2.0)
	# a toppled drum at its base
	draw_circle(p + Vector2(15, 2), 6.0, color.darkened(0.12))
	draw_circle(p + Vector2(15, 2), 2.5, color.darkened(0.3))


## A gap in the Warren's collapsed rubble — one of several that look alike, so the player can't tell
## which goes through (only the companion's nose can). CLOSED: a rubble mound around a shallow dark
## hollow (a dead-end look). OPENED: the rubble has shifted aside into a cleared passage you can see
## through — the one the companion nosed out and squeezed into.
func _draw_nook(p: Vector2, color: Color, opened: bool) -> void:
	# the rubble shoulders either side of the gap
	draw_circle(p + Vector2(-13, 5), 10.0, color.darkened(0.12))
	draw_circle(p + Vector2(13, 5), 10.0, color.darkened(0.12))
	draw_circle(p + Vector2(-9, -4), 8.0, color)
	draw_circle(p + Vector2(9, -4), 8.0, color)
	if opened:
		# cleared: an open mouth with depth you can see into (the way through)
		draw_rect(Rect2(p + Vector2(-7, -18), Vector2(14, 22)), Color(0.16, 0.22, 0.20, 0.92))
		draw_arc(p + Vector2(0, -7), 8.5, PI, TAU, 16, color.lightened(0.22), 2.0)
		# a faint glimmer of the space beyond
		draw_circle(p + Vector2(0, -10), 2.2, Color(0.70, 0.86, 0.82, 0.7))
	else:
		# blocked: a shallow, dead-looking hollow
		draw_circle(p + Vector2(0, -3), 7.0, Color(0.08, 0.10, 0.09, 0.85))
		draw_arc(p + Vector2(0, -3), 7.0, PI, TAU, 14, color.darkened(0.28), 1.5)


## A riverbank rock. Unexamined it's a rounded stone; once turned over it tips onto its
## side beside a damp hollow, and whatever was hiding under it (a salamander, a small
## decoy find, or nothing) is drawn in the hollow — so a searched rock reads at a glance.
func _draw_rock(p: Vector2, color: Color, examined: bool, content: String, missed: bool = false) -> void:
	if not examined:
		draw_circle(p + Vector2(0, 2), 11.0, color.darkened(0.12))
		draw_circle(p + Vector2(-2, -2), 9.0, color)
		draw_circle(p + Vector2(2, -4), 5.5, color.lightened(0.12))
		return
	# the damp hollow the rock used to sit in
	draw_circle(p + Vector2(0, 2), 11.0, Color(0.20, 0.22, 0.20, 0.55))
	draw_circle(p + Vector2(0, 2), 8.0, Color(0.26, 0.27, 0.22, 0.55))
	# what was hiding underneath, revealed in the hollow. A run-out reveal ("missed") draws it
	# faded — you can see what you passed over without it reading as a find you earned.
	var dim := 0.5 if missed else 1.0
	match content:
		"salamander":
			_draw_salamander(p + Vector2(-1, 1), dim)
		"decoy":
			_draw_decoy(p + Vector2(-1, 1), dim)
		_:
			pass
	# the stone itself, tipped up onto its side just beside the hollow
	draw_set_transform(p + Vector2(13, -1), -0.5, Vector2.ONE)
	draw_circle(Vector2(0, 2), 9.0, color.darkened(0.18))
	draw_circle(Vector2(0, -1), 7.0, color.darkened(0.04))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A little river salamander: a russet body with a curving, gently wagging tail, a small
## head with a bright eye, stubby legs and a couple of warm spots. The found-a-friend beat.
func _draw_salamander(p: Vector2, dim: float = 1.0) -> void:
	var warm := Color(0.86, 0.42, 0.30, dim)
	var belly := Color(0.96, 0.76, 0.42, dim)
	var wig := sin(_time * 5.0) * 3.0
	draw_line(p + Vector2(-2, 1), p + Vector2(-10, 2.0 + wig), warm, 2.5)  # tail
	draw_line(p + Vector2(-1, 3), p + Vector2(-3, 5), warm, 1.4)           # legs
	draw_line(p + Vector2(3, 3), p + Vector2(5, 5), warm, 1.4)
	draw_circle(p, 4.5, warm)                                              # body
	draw_circle(p + Vector2(0, 1.4), 2.6, belly)                           # belly
	draw_circle(p + Vector2(5, -1), 3.2, warm)                             # head
	draw_circle(p + Vector2(6.4, -2), 0.8, Color(0.10, 0.10, 0.12, dim))   # eye
	draw_circle(p + Vector2(-3, -1), 0.9, belly)                           # spots
	draw_circle(p + Vector2(1, -2), 0.9, belly)


## A small non-counting find (feather, river-glass, button, shell, beetle, pebble): a
## little gleam with a drifting sparkle. Generic on purpose — the label carries the flavor.
func _draw_decoy(p: Vector2, dim: float = 1.0) -> void:
	var c := Color(0.82, 0.78, 0.54, dim)
	draw_circle(p, 3.4, c)
	draw_circle(p + Vector2(-1, -1), 1.2, Color(1, 1, 1, 0.8 * dim))
	var s := 0.6 + 0.4 * sin(_time * 3.0)
	draw_line(p + Vector2(0, -6), p + Vector2(0, -3), Color(1, 1, 1, 0.6 * s * dim), 1.0)
	draw_line(p + Vector2(-3, -4), p + Vector2(-1, -4), Color(1, 1, 1, 0.5 * s * dim), 1.0)
