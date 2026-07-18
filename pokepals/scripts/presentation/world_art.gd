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
var _vein: Dictionary = {}   # { rect, color, rim, cracks } — the bazaar's sunken DRY riverbed artery, or empty
var _paths: Array = []     # [ { from: Vector2, to: Vector2, color: Color } ]
var _hedges: Array = []    # [ { a: Vector2, b: Vector2, t: float } ] — the maze's tall hedge walls
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

# Optional pixel-art water tiles (tools/gen_water.py). Each is a seamless square the
# world tiles across a body of water; `world_tile` is how many world units it spans.
# Absent → the flat procedural fill below (so the smoke test stays green with no art).
var _pond_tex: Texture2D = null
var _river_tex: Texture2D = null
var _pool_tex: Texture2D = null
var _pond_world_tile := 64.0
var _river_world_tile := 64.0
var _pool_world_tile := 64.0


func render_world(data: Dictionary, style: ArtStyle = null) -> void:
	_style = style if style != null else ArtStyle.load_style()
	_ground_color = WorldData.to_color(data["ground_color"])
	var bmin := WorldData.to_vec2(data["bounds"]["min"])
	var bmax := WorldData.to_vec2(data["bounds"]["max"])
	_bounds = Rect2(bmin, bmax - bmin)
	# A soft top→bottom ground gradient (palette), baked once, drawn under the dapple.
	_ground_grad = _style.make_vertical_gradient_texture(_style.color("ground_top"), _style.color("ground_bottom"))

	# Optional pixel-art water tiles. When present, ponds/river/pools draw as a tiled,
	# gently-scrolling pixel surface instead of a flat fill; when absent, the procedural
	# fill below still runs. texture_repeat must be ON for the UVs to tile (they run past
	# 0..1 across a body of water); it's harmless for the non-tiling ground/gradient draws.
	var water_cfg: Dictionary = _style.entity("water")
	var river_cfg: Dictionary = _style.entity("river")
	var pool_cfg: Dictionary = _style.entity("pool")
	_pond_tex = SpriteSlot.resolve(water_cfg, "tile")
	_river_tex = SpriteSlot.resolve(river_cfg, "tile")
	_pool_tex = SpriteSlot.resolve(pool_cfg, "tile")
	_pond_world_tile = float(water_cfg.get("world_tile", 64.0))
	_river_world_tile = float(river_cfg.get("world_tile", 64.0))
	_pool_world_tile = float(pool_cfg.get("world_tile", 64.0))
	if _pond_tex != null or _river_tex != null or _pool_tex != null:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

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

	# The Vein: the bazaar's sunken DRY riverbed — a long dusty channel band the whole world drains
	# toward (the navigation spine: "follow the channel and you'll never be lost"). Drawn like the river
	# but bone-dry — sunken banks, an old high-water rim, cracked mud, and a faint dust "current"
	# drifting down its centre on the breeze. Cracks are seeded once so they don't shimmer frame to frame.
	_vein = {}
	if data.has("vein"):
		var vn: Dictionary = data["vein"]
		var va: Array = vn["rect"]  # [x, y, w, h]
		var vrect := Rect2(float(va[0]), float(va[1]), float(va[2]), float(va[3]))
		var cracks: Array = []
		var crng := RandomNumberGenerator.new()
		crng.seed = 0x5EA50
		var n := int(clampf(vrect.size.x / 90.0, 6, 40))
		for i in n:
			var a := Vector2(vrect.position.x + crng.randf() * vrect.size.x, vrect.position.y + 13.0 + crng.randf() * maxf(1.0, vrect.size.y - 26.0))
			cracks.append([a, a + Vector2(crng.randf_range(-15.0, 15.0), crng.randf_range(-11.0, 11.0))])
		_vein = {
			"rect": vrect,
			"color": WorldData.to_color(vn.get("color", [0.74, 0.66, 0.50])),
			"rim": WorldData.to_color(vn.get("rim", [0.86, 0.80, 0.66])),
			"cracks": cracks,
		}

	_paths.clear()
	for p in data.get("paths", []):
		_paths.append({ "from": WorldData.to_vec2(p["from"]), "to": WorldData.to_vec2(p["to"]), "color": WorldData.to_color(p["color"]) })

	# Hedge walls (the maze): segments with a thickness, drawn as tall rounded green walls.
	_hedges.clear()
	for h in data.get("hedges", []):
		_hedges.append({ "a": WorldData.to_vec2(h["from"]), "b": WorldData.to_vec2(h["to"]), "t": float(h.get("thickness", 28.0)) })

	# Flowers carry a per-element wind "phase" (seeded from position) so they don't all
	# sway in lockstep — the breeze reads as organic, not a metronome.
	_flowers.clear()
	for f in data.get("flowers", []):
		var fp := Vector2(float(f[0]), float(f[1]))
		_flowers.append({ "pos": fp, "color": Color(float(f[2]), float(f[3]), float(f[4])), "phase": _phase_for(fp) })

	_scatter_grass()

	_interactables.clear()
	for it in data.get("props", []):
		_interactables.append({
			"pos": WorldData.to_vec2(it["position"]),
			"color": WorldData.to_color(it["color"]),
			"type": String(it.get("type", "")),
			"pulse": 0.0,
			"examined": false,   # rocks flip this on when turned over
			"content": "",       # what a turned-over rock revealed: salamander | decoy | empty
			"missed": false,     # true if revealed by the run-out reveal-all (drawn dimmed)
			"wall": String(it.get("wall", "h")),  # "v" → this gate plugs a VERTICAL wall (rotate its art 90°)
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


## Toggle an interactable's lit/held state (the Paired Hall plate glow, which comes and goes as weight
## lands and lifts — unlike open_slab, which only ever turns ON). Pulses on the rising edge.
func set_lit(index: int, on: bool) -> void:
	if index >= 0 and index < _interactables.size():
		if on and not bool(_interactables[index].get("opened", false)):
			_interactables[index]["pulse"] = 1.0
		_interactables[index]["opened"] = on


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


# How far past the screen edge a prop/tuft still draws, so nothing pops at the frame edge.
# Sized to the tallest motif (a facade / light shaft reaches well above its ground point).
const CULL_MARGIN := 200.0


func _draw() -> void:
	# Cull to what the camera can see, so this loop's cost scales with the screen, not the
	# world. `has_area()` is false in headless / before the camera exists → we draw everything
	# (the whole-world backdrop below is never culled anyway, so the world is never blank).
	var vis := ViewCull.visible_world_rect(self, CULL_MARGIN)
	var cull := vis.has_area()

	# ground: a soft vertical palette gradient, with the dapple noise laid over it. Drawn whole
	# (clipping the full-bounds textures would seam), and it's a fixed cost regardless of size.
	if _ground_grad != null:
		draw_texture_rect(_ground_grad, _bounds, false, Color(1, 1, 1, 1))
	else:
		draw_rect(_bounds, _ground_color)
	if _ground_noise != null:
		draw_texture_rect(_ground_noise, _bounds, false, Color(1, 1, 1, 1))

	# per-region mood wash, so each named area feels distinct underfoot
	for rt in _region_tints:
		if cull and not vis.intersects(rt["rect"]):
			continue
		var c: Color = rt["color"]
		c.a = _region_tint_alpha
		draw_rect(rt["rect"], c)

	# grass tufts (drawn low, swaying), giving the ground some life and texture
	for g in _grass:
		if cull and not vis.has_point(g["pos"]):
			continue
		var sway := _sway(g["phase"], 0.25)
		var base: Vector2 = g["pos"]
		var tip := base + Vector2(sway, -float(g["len"]))
		draw_line(base, tip, g["color"], 1.5)
		draw_line(base + Vector2(-2, 0), base + Vector2(-2 + sway * 0.8, -float(g["len"]) * 0.7), g["color"], 1.3)
		draw_line(base + Vector2(2, 0), base + Vector2(2 + sway * 0.8, -float(g["len"]) * 0.7), g["color"], 1.3)

	# worn paths
	for p in _paths:
		if cull and not vis.intersects(Rect2(p["from"], Vector2.ZERO).expand(p["to"]).grow(8.0)):
			continue
		draw_line(p["from"], p["to"], p["color"], 16.0)

	# the Vein: the sunken dry channel, drawn under everything else (props sit on its bed)
	_draw_vein()

	# the river: a long water band. With a pixel-art tile, fill it with tiled water drifting
	# downstream; otherwise the flat fill with a couple of drifting ripple lines. Either way a
	# soft brighter rim marks the bank-side (top) edge where land meets water.
	if not _river.is_empty():
		var rrect: Rect2 = _river["rect"]
		if _river_tex != null:
			var corners := PackedVector2Array([rrect.position, rrect.position + Vector2(rrect.size.x, 0.0), rrect.end, rrect.position + Vector2(0.0, rrect.size.y)])
			_fill_water(corners, _river_tex, _river_world_tile, _water_scroll(_river_tex, true))
		else:
			draw_rect(rrect, _river["color"])
			for k in 3:
				var ry := rrect.position.y + 16.0 + float(k) * 26.0
				var drift := fposmod(_time * 12.0 + float(k) * 40.0, rrect.size.x)
				var rip := Color(0.85, 0.92, 0.95, 0.16)
				draw_line(rrect.position + Vector2(drift, ry - rrect.position.y), rrect.position + Vector2(minf(drift + 70.0, rrect.size.x), ry - rrect.position.y), rip, 1.5)
		draw_line(rrect.position, rrect.position + Vector2(rrect.size.x, 0.0), Color(_river["rim"].r, _river["rim"].g, _river["rim"].b, 0.6), 2.0)

	# ponds: a tiled pixel-water surface if we have art, else a flat fill with breathing
	# ripples. Both keep a lighter rim where the bank meets the water.
	for pond in _ponds:
		var center: Vector2 = pond["center"]
		var radius: float = pond["radius"]
		var rmax := radius * 1.25  # the organic bank can bulge past the nominal radius
		if cull and not vis.intersects(Rect2(center - Vector2(rmax, rmax), Vector2(rmax, rmax) * 2.0)):
			continue
		var ring := _organic_ring(center, radius, _phase_for(center))
		if _pond_tex != null:
			_fill_water(ring, _pond_tex, _pond_world_tile, _water_scroll(_pond_tex, false))
		else:
			draw_colored_polygon(ring, pond["color"])
			for k in 2:
				var t := fposmod(_time * 0.25 + float(k) * 0.5, 1.0)
				var rr := radius * (0.25 + 0.7 * t)
				draw_arc(center, rr, 0.0, TAU, 40, Color(0.85, 0.92, 0.95, 0.22 * (1.0 - t)), 1.5)
		_draw_ring_rim(ring, Color(0.78, 0.86, 0.88, 0.5), 2.0)

	# flowers (a petal dot with a bright center), nodding in the breeze
	for f in _flowers:
		if cull and not vis.has_point(f["pos"]):
			continue
		var fp: Vector2 = f["pos"] + Vector2(_sway(f["phase"], 0.45), 0.0)
		draw_circle(fp, 4.0, f["color"])
		draw_circle(fp, 1.6, Color(0.98, 0.92, 0.55))

	# the maze's hedge walls (tall, rounded, slightly extruded so they read as height)
	_draw_hedges()

	# interactable props: contact shadow, optional warm glow, then the prop silhouette
	for it in _interactables:
		if cull and not vis.has_point(it["pos"]):
			continue
		_draw_shadow(it["pos"] + Vector2(0, 6), 11.0, 0.16)
		_draw_glow(it["type"], it["pos"])
		var pulse: float = it["pulse"]
		if pulse > 0.0:
			draw_circle(it["pos"], 20.0 + 12.0 * pulse, Color(1, 1, 1, 0.18 * pulse))
		match String(it["type"]):
			"rock":
				_draw_rock(it["pos"], it["color"], bool(it["examined"]), String(it["content"]), bool(it.get("missed", false)))
			"slab":
				_draw_slab(it["pos"], it["color"], bool(it.get("opened", false)), String(it.get("wall", "h")) == "v")
			"plate":
				_draw_plate(it["pos"], it["color"], bool(it.get("opened", false)))
			"wedge":
				_draw_wedge(it["pos"], it["color"])
			"column":
				_draw_column(it["pos"], it["color"])
			"nook":
				_draw_nook(it["pos"], it["color"], bool(it.get("opened", false)), String(it.get("wall", "h")) == "v")
			"ember":
				_draw_ember(it["pos"], it["color"], bool(it.get("opened", false)))
			"brazier":
				_draw_brazier(it["pos"], it["color"], bool(it.get("opened", false)))
			"mural":
				_draw_mural(it["pos"], it["color"], bool(it.get("opened", false)))
			"facade":
				_draw_facade(it["pos"], it["color"])
			"stairs":
				_draw_stairs(it["pos"], it["color"])
			"carving":
				_draw_carving(it["pos"], it["color"])
			"torch":
				_draw_torch(it["pos"], it["color"])
			"roots":
				_draw_roots(it["pos"], it["color"])
			"broken_pillar":
				_draw_broken_pillar(it["pos"], it["color"])
			"rubble_pile":
				_draw_rubble_pile(it["pos"], it["color"])
			"pool":
				_draw_pool(it["pos"], it["color"])
			"light_shaft":
				_draw_light_shaft(it["pos"], it["color"])
			_:
				_draw_prop(it["type"], it["pos"], it["color"])

	# NOTE: trees and landmarks (great trees) are no longer drawn here. They're spawned
	# as individual TreeView nodes under the y-sorted Scenery layer so the player and
	# companion can pass behind/in front of them by ground position. This pass renders
	# only the always-underneath backdrop (ground, grass, flowers, paths, ponds, props).


## --- pixel-art water --------------------------------------------------------------------
## Fill a convex polygon with a tiled, scrolling water texture. Each vertex's UV is its
## world position in tile-units (world_tile world units == one tile), so the pixel grid is
## locked to the world and only `scroll` animates it; texture_repeat (enabled in
## render_world) wraps the past-1 UVs into a seamless tiling. A no-op with no texture.
func _fill_water(points: PackedVector2Array, tex: Texture2D, world_tile: float, scroll: Vector2) -> void:
	if tex == null or points.is_empty():
		return
	var uvs := PackedVector2Array()
	for p in points:
		uvs.append(p / world_tile + scroll)
	draw_colored_polygon(points, Color(1, 1, 1, 1), uvs, tex)


## A closed, gently irregular ring around `center` — a pond/pool shoreline that reads as an
## organic bank instead of a perfect circle. The radius is nudged in and out by a few INTEGER
## harmonics (integer frequencies are what let the loop close seamlessly at a == TAU) whose
## phases are offset by `seed`, so every body of water keeps its own stable, distinct shape.
## Amplitudes are small enough to stay pond-like, not blobby; draw_colored_polygon fills the
## (mildly concave) result directly, and the water UVs stay correct because they're just a
## linear function of world position.
func _organic_ring(center: Vector2, radius: float, seed: float, segments := 56) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		var wobble := 0.11 * sin(3.0 * a + seed) + 0.06 * sin(5.0 * a - seed * 1.7) + 0.035 * sin(8.0 * a + seed * 2.3)
		pts.append(center + Vector2(cos(a), sin(a)) * radius * (1.0 + wobble))
	return pts


## Trace a closed outline (an organic shoreline) as a thin line — the waterline where the
## bank meets the water. Copies the ring (COW) and closes it back to the first point.
func _draw_ring_rim(ring: PackedVector2Array, color: Color, width: float) -> void:
	if ring.size() < 2:
		return
	var loop := ring
	loop.append(ring[0])
	draw_polyline(loop, color, width)


## The animated water scroll, in tile-units, QUANTIZED to whole texels so the surface steps
## crisply (pixel-art) instead of smearing. Still water (ponds/pools) shimmers in place with a
## slow lissajous wobble; a `flowing` river drifts steadily downstream along its long axis (+x).
func _water_scroll(tex: Texture2D, flowing: bool) -> Vector2:
	var s: Vector2
	if flowing:
		s = Vector2(_time * 0.12, sin(_time * 0.6) * 0.02)
	else:
		s = Vector2(sin(_time * 0.42) * 0.035, cos(_time * 0.30) * 0.030)
	var tw := maxf(1.0, float(tex.get_width()))  # uv 1.0 spans the whole tile (tw texels)
	return Vector2(round(s.x * tw) / tw, round(s.y * tw) / tw)


## The Vein — the sunken dry riverbed. A dusty channel band with darker sunken banks top and bottom,
## a faint pale high-water rim just inside each bank (the river stood that high once), a scatter of
## cracked mud across the bed, and a faint dust "current" drifting down the centre on the breeze.
func _draw_vein() -> void:
	if _vein.is_empty():
		return
	var rect: Rect2 = _vein["rect"]
	var col: Color = _vein["color"]
	var rim: Color = _vein["rim"]
	draw_rect(rect, col)
	# the sunken banks (the channel walls) along the top and bottom edges
	var bank := col.darkened(0.28)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 8.0)), bank)
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 8.0), Vector2(rect.size.x, 8.0)), bank)
	# the old high-water rim, a hand's-width below each bank
	var rimc := Color(rim.r, rim.g, rim.b, 0.40)
	draw_line(rect.position + Vector2(0, 11), rect.position + Vector2(rect.size.x, 11), rimc, 1.5)
	draw_line(rect.position + Vector2(0, rect.size.y - 11), rect.position + Vector2(rect.size.x, rect.size.y - 11), rimc, 1.5)
	# cracked mud across the bed (seeded once)
	var crackc := col.darkened(0.18)
	for c in _vein["cracks"]:
		draw_line(c[0], c[1], crackc, 1.0)
	# the dust "current": pale streaks drifting along the centre line
	var cy := rect.position.y + rect.size.y * 0.5
	for k in 4:
		var drift := fposmod(_time * 10.0 + float(k) * (rect.size.x / 4.0), rect.size.x)
		draw_line(Vector2(rect.position.x + drift, cy), Vector2(rect.position.x + minf(drift + 90.0, rect.size.x), cy), Color(rim.r, rim.g, rim.b, 0.12), 2.0)


## The hedge maze, drawn in four whole-maze passes so the extruded "height" layers stay
## consistent where runs cross: every contact shadow first, then every front face, then every
## sunlit top (offset up), then a thin top highlight. Butt-capped lines meet inside the
## perpendicular hedge at each junction, so long runs read as one continuous, solid wall.
const HEDGE_HEIGHT := 14.0
func _draw_hedges() -> void:
	if _hedges.is_empty():
		return
	var lift := Vector2(0, -HEDGE_HEIGHT)
	var shadow := Color(0.04, 0.06, 0.04, 0.20)
	var front := Color(0.16, 0.30, 0.17)
	var top := Color(0.27, 0.47, 0.25)
	var hi := Color(0.41, 0.61, 0.34)
	for h in _hedges:
		draw_line(h["a"] + Vector2(5, 8), h["b"] + Vector2(5, 8), shadow, float(h["t"]) + 2.0)
	for h in _hedges:
		draw_line(h["a"], h["b"], front, float(h["t"]))
	for h in _hedges:
		draw_line(h["a"] + lift, h["b"] + lift, top, float(h["t"]))
	for h in _hedges:
		draw_line(h["a"] + lift + Vector2(0, -1), h["b"] + lift + Vector2(0, -1), hi, float(h["t"]) * 0.42)


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
		# ── The Thousand-Knot Bazaar: the five Vanes (one tall landmark per Knot, the skyline compass),
		# the Knuckle furniture (dry well, notice-board, shrine), the wet-boots wanderer, and cargo crates.
		# Each is a small placeholder silhouette; the Vanes are drawn tall so they read as "steer by me".
		"chimney":
			_draw_chimney(p, color)
		"prism_tower":
			_draw_prism_tower(p, color)
		"ivory_spire":
			_draw_ivory_spire(p, color)
		"crooked_mast":
			_draw_crooked_mast(p, color)
		"sky_anchor":
			_draw_sky_anchor(p, color)
		"dry_well":
			_draw_dry_well(p, color)
		"notice_board":
			_draw_notice_board(p, color)
		"shrine":
			_draw_shrine(p, color)
		"wanderer":
			_draw_wanderer(p, color)
		"crate":
			_draw_crate(p, color)
		_:
			# fallback: the original ringed disc
			draw_circle(p, 8.0, color)
			draw_arc(p, 8.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 1.5)


## A Ruin gate slab. CLOSED: a heavy upright stone filling the doorway, a worn groove down its face.
## OPENED: it has risen into a lintel, leaving a dark, open doorway — the way through. `vertical` rotates
## the whole motif 90° so it plugs a gap in a VERTICAL wall (the maze's east/west doorways) correctly,
## instead of reading as a stone laid the wrong way across the opening.
func _draw_slab(p: Vector2, color: Color, opened: bool, vertical: bool = false) -> void:
	var w := 56.0
	draw_set_transform(p, PI * 0.5 if vertical else 0.0, Vector2.ONE)
	if opened:
		# the dark doorway gap left behind
		draw_rect(Rect2(Vector2(-w * 0.5 + 4, -64), Vector2(w - 8, 64)), Color(0.06, 0.08, 0.07, 0.85))
		# the slab, hoisted into a lintel beside the opening
		draw_rect(Rect2(Vector2(-w * 0.5, -82), Vector2(w, 16)), color.darkened(0.1))
		draw_rect(Rect2(Vector2(-w * 0.5, -82), Vector2(w, 4)), color.lightened(0.12))
		# jambs framing the open doorway
		draw_rect(Rect2(Vector2(-w * 0.5 - 2, -64), Vector2(4, 64)), color.darkened(0.2))
		draw_rect(Rect2(Vector2(w * 0.5 - 2, -64), Vector2(4, 64)), color.darkened(0.2))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# closed: the lowered slab barring the way
	draw_rect(Rect2(Vector2(-w * 0.5, -68), Vector2(w, 72)), color.darkened(0.08))
	draw_rect(Rect2(Vector2(-w * 0.5, -68), Vector2(w, 5)), color.lightened(0.10))
	draw_line(Vector2(0, -62), Vector2(0, 0), color.darkened(0.28), 2.0)
	# a couple of weathered cracks
	draw_line(Vector2(-12, -50), Vector2(-8, -20), color.darkened(0.22), 1.0)
	draw_line(Vector2(14, -56), Vector2(10, -30), color.darkened(0.22), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A companion-plate: a worn round stone set flush in the floor. HELD (a companion's or a wedge's
## weight on it — `held`): it sinks a touch and lights with a warm glow, so you can read at a glance
## which plates are bearing weight (the Paired Hall feedback). Idle: a quiet sunken ring with a glyph.
func _draw_plate(p: Vector2, color: Color, held: bool = false) -> void:
	if held:
		var breathe := 0.8 + 0.2 * sin(_time * 2.4)
		for k in 3:
			draw_circle(p + Vector2(0, -2), (26.0 - float(k) * 7.0) * breathe, Color(1.0, 0.86, 0.5, 0.10))
	draw_circle(p + Vector2(0, 1), 15.0, color.darkened(0.25))
	draw_circle(p, 13.0, color if not held else color.lightened(0.15))
	draw_arc(p, 9.0, 0.0, TAU, 24, (color.darkened(0.3) if not held else Color(1.0, 0.84, 0.5)), 1.5)
	draw_arc(p, 4.0, 0.0, TAU, 16, color.lightened(0.15), 1.0)


## A wedge stone — the lonely workaround in the Paired Hall: a carved chock you can jam onto a plate
## to hold it while your companion bears the other. A blocky stone with a tapered edge.
func _draw_wedge(p: Vector2, color: Color) -> void:
	_draw_shadow(p + Vector2(0, 5), 8.0, 0.14)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-8, 4), p + Vector2(8, 4), p + Vector2(6, -6), p + Vector2(-6, -2)]), color)
	draw_line(p + Vector2(-6, -2), p + Vector2(6, -6), color.lightened(0.18), 1.5)


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
func _draw_nook(p: Vector2, color: Color, opened: bool, vertical: bool = false) -> void:
	draw_set_transform(p, PI * 0.5 if vertical else 0.0, Vector2.ONE)
	# the rubble shoulders either side of the gap
	draw_circle(Vector2(-13, 5), 10.0, color.darkened(0.12))
	draw_circle(Vector2(13, 5), 10.0, color.darkened(0.12))
	draw_circle(Vector2(-9, -4), 8.0, color)
	draw_circle(Vector2(9, -4), 8.0, color)
	if opened:
		# cleared: an open mouth with depth you can see into (the way through)
		draw_rect(Rect2(Vector2(-7, -18), Vector2(14, 22)), Color(0.16, 0.22, 0.20, 0.92))
		draw_arc(Vector2(0, -7), 8.5, PI, TAU, 16, color.lightened(0.22), 2.0)
		# a faint glimmer of the space beyond
		draw_circle(Vector2(0, -10), 2.2, Color(0.70, 0.86, 0.82, 0.7))
	else:
		# blocked: a shallow, dead-looking hollow
		draw_circle(Vector2(0, -3), 7.0, Color(0.08, 0.10, 0.09, 0.85))
		draw_arc(Vector2(0, -3), 7.0, PI, TAU, 14, color.darkened(0.28), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The Cistern's ember source, in a cracked bowl. DEAD: a dark coal with the faintest red breath (so
## you can find it in the gloom, but it reads as spent). KINDLED (opened): it wakes into a bright,
## breathing coal with a mote of light hovering above — the thing the companion can carry.
func _draw_ember(p: Vector2, color: Color, kindled: bool) -> void:
	# the cracked bowl
	draw_arc(p + Vector2(0, 2), 9.0, 0.1, PI - 0.1, 14, Color(0.34, 0.30, 0.26), 3.0)
	if kindled:
		var breathe := 0.78 + 0.22 * sin(_time * 3.0)
		for k in 3:
			draw_circle(p + Vector2(0, -2), (16.0 - float(k) * 5.0) * breathe, Color(color.r, color.g, color.b, 0.10))
		draw_circle(p + Vector2(0, -1), 5.5, color)
		draw_circle(p + Vector2(-1, -2), 2.5, Color(1, 0.95, 0.8))
		# the carryable mote, hovering
		var bob := sin(_time * 2.2) * 2.0
		draw_circle(p + Vector2(0, -16 + bob), 3.0, Color(1.0, 0.92, 0.7, 0.9))
		draw_circle(p + Vector2(0, -16 + bob), 6.0, Color(1.0, 0.9, 0.6, 0.18))
	else:
		draw_circle(p + Vector2(0, -1), 5.0, Color(0.22, 0.16, 0.14))
		draw_circle(p + Vector2(-1, -2), 1.6, Color(0.55, 0.22, 0.14, 0.7 + 0.2 * sin(_time * 1.5)))


## The Cistern's brazier — a bowl on a stand. COLD: dark and dead. LIT (opened): full of warm flame
## with a breathing glow, the moment the companion's carried light catches and the dark lifts.
func _draw_brazier(p: Vector2, color: Color, lit: bool) -> void:
	# stand + bowl
	draw_rect(Rect2(p + Vector2(-2.5, -2), Vector2(5, 16)), color.darkened(0.25))
	draw_rect(Rect2(p + Vector2(-9, 12), Vector2(18, 3)), color.darkened(0.2))
	var bowl := PackedVector2Array([p + Vector2(-11, -8), p + Vector2(11, -8), p + Vector2(7, 0), p + Vector2(-7, 0)])
	draw_colored_polygon(bowl, color.darkened(0.1))
	if lit:
		var warm := Color(1.0, 0.78, 0.40)
		var breathe := 0.8 + 0.2 * sin(_time * _glow_pulse_speed)
		for k in 3:
			draw_circle(p + Vector2(0, -10), (40.0 - float(k) * 11.0) * breathe, Color(warm.r, warm.g, warm.b, 0.08))
		# a couple of flame tongues
		var f := sin(_time * 6.0) * 2.0
		draw_colored_polygon(PackedVector2Array([p + Vector2(-6, -8), p + Vector2(0, -8), p + Vector2(-2 + f, -22)]), Color(1.0, 0.66, 0.28))
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(7, -8), p + Vector2(3 + f, -19)]), Color(1.0, 0.80, 0.42))
		draw_circle(p + Vector2(0, -9), 4.0, Color(1, 0.95, 0.8))
	else:
		# cold coals
		draw_circle(p + Vector2(-3, -7), 2.2, Color(0.18, 0.18, 0.18))
		draw_circle(p + Vector2(3, -7), 2.2, Color(0.16, 0.16, 0.16))


## A wall carving. LOST IN THE DARK: barely-there scratches. REVEALED (opened, once the brazier lights):
## a legible relief of TWO figures and their companions before a great door — the first foreshadowing of
## the Paired Hall (a door that "needs more than one"). Examinable for the flavour line in the spec label.
func _draw_mural(p: Vector2, color: Color, revealed: bool) -> void:
	var a := 0.9 if revealed else 0.16
	var c := Color(color.r, color.g, color.b, a)
	# the stone panel
	draw_rect(Rect2(p + Vector2(-16, -22), Vector2(32, 40)), Color(0.22, 0.24, 0.24, 0.5 if revealed else 0.18))
	# two little figures side by side, each with a small companion shape at their feet
	for sx in [-7, 7]:
		draw_rect(Rect2(p + Vector2(sx - 2, -12), Vector2(4, 14)), c)        # body
		draw_circle(p + Vector2(sx, -15), 3.0, c)                            # head
		draw_circle(p + Vector2(sx + (4 if sx > 0 else -4), 4), 2.4, c)      # companion
	# the great door arch above/behind them
	draw_arc(p + Vector2(0, -2), 13.0, PI, TAU, 18, c, 2.0)


# ── ARRIVAL / RUIN dressing — PLACEHOLDER ART. Each of these is a single `type` drawn by one small
# function over a known footprint, ready to be swapped 1:1 for a Claude Design sprite later. They
# establish staging + mood (the mouth, the descent, the carvings, torchlight, overgrowth); the
# *surface* is meant to be replaced. See docs/the-ruin-narrative-and-world.md. ──

## The ruin's MOUTH: a broken stone archway half-swallowed by the wood, framing the dark way in.
## Footprint ~120×90. Non-solid (collision is the front wall + corridor); this is the face over the gap.
func _draw_facade(p: Vector2, color: Color) -> void:
	# the dark opening behind the arch
	draw_rect(Rect2(p + Vector2(-42, -86), Vector2(84, 90)), Color(0.05, 0.07, 0.07, 0.92))
	# two weathered jambs
	draw_rect(Rect2(p + Vector2(-58, -88), Vector2(18, 92)), color.darkened(0.1))
	draw_rect(Rect2(p + Vector2(40, -88), Vector2(18, 92)), color.darkened(0.1))
	# the broken arch lintel (a shallow span, a chunk missing on the right)
	draw_arc(p + Vector2(0, -86), 50.0, PI + 0.25, TAU - 0.55, 22, color.lightened(0.06), 9.0)
	draw_rect(Rect2(p + Vector2(-58, -100), Vector2(40, 14)), color)
	# cracks + a drape of vines off the top
	draw_line(p + Vector2(-30, -90), p + Vector2(-22, -40), color.darkened(0.3), 1.5)
	for vx in [-46, -10, 30]:
		var s := _sway(_phase_for(p + Vector2(vx, 0)), 0.5)
		draw_line(p + Vector2(vx, -96), p + Vector2(vx + s, -96 + 34.0), Color(0.32, 0.42, 0.26), 2.0)


## Worn STEPS going down into the dark — a few stacked bands, each darker, to read as a descent.
func _draw_stairs(p: Vector2, color: Color) -> void:
	for k in 4:
		var w := 60.0 - float(k) * 8.0
		var y := -float(k) * 7.0
		var shade := color.darkened(0.08 + 0.12 * float(k))
		draw_rect(Rect2(p + Vector2(-w * 0.5, y - 5), Vector2(w, 6)), shade)
		draw_rect(Rect2(p + Vector2(-w * 0.5, y - 7), Vector2(w, 2)), shade.lightened(0.12))
	draw_rect(Rect2(p + Vector2(-26, -34), Vector2(52, 8)), Color(0.04, 0.06, 0.06, 0.85))  # the dark mouth at the top


## A wall CARVING / relief panel — the ruin's story, told in stone. Two figures and a companion shape,
## faint until you're close. Examinable (the spec label carries the line). Placeholder for a real relief.
func _draw_carving(p: Vector2, color: Color) -> void:
	draw_rect(Rect2(p + Vector2(-17, -24), Vector2(34, 42)), color.darkened(0.35))   # the recessed panel
	draw_rect(Rect2(p + Vector2(-15, -22), Vector2(30, 38)), color.darkened(0.18))
	var c := Color(color.r, color.g, color.b, 0.85)
	for sx in [-7, 7]:                                  # two figures, side by side
		draw_rect(Rect2(p + Vector2(sx - 2, -12), Vector2(4, 13)), c)
		draw_circle(p + Vector2(sx, -15), 2.6, c)
	draw_circle(p + Vector2(0, 6), 2.6, c)             # a companion shape between/below them
	# a faint catch-light so it reads as "look here"
	draw_arc(p + Vector2(0, -3), 13.0, PI * 1.1, PI * 1.9, 14, Color(0.9, 0.86, 0.7, 0.10 + 0.06 * sin(_time * 1.3)), 1.5)


## A wall TORCH — sconce + a flickering warm flame and a breathing glow pool (animation). Placeholder.
func _draw_torch(p: Vector2, color: Color) -> void:
	# a fast, irregular flicker from two out-of-phase sines (cheap "fire")
	var flick := 0.72 + 0.18 * sin(_time * 11.0 + p.x) + 0.10 * sin(_time * 23.0 + p.y)
	for k in 3:                                          # the glow pool
		draw_circle(p + Vector2(0, -10), (46.0 - float(k) * 13.0) * flick, Color(color.r, color.g, color.b, 0.07))
	draw_rect(Rect2(p + Vector2(-2, -8), Vector2(4, 14)), Color(0.28, 0.22, 0.16))   # bracket
	var f := sin(_time * 9.0 + p.x) * 1.6
	draw_colored_polygon(PackedVector2Array([p + Vector2(-4, -8), p + Vector2(4, -8), p + Vector2(f, -22 - 4.0 * flick)]), Color(1.0, 0.64, 0.26))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-2, -8), p + Vector2(2, -8), p + Vector2(f * 0.5, -16 - 2.0 * flick)]), Color(1.0, 0.86, 0.5))
	draw_circle(p + Vector2(0, -9), 2.2, Color(1, 0.95, 0.8))


## ROOTS prying up the old flagstones — the wood reclaiming the stone. Non-solid overgrowth.
func _draw_roots(p: Vector2, color: Color) -> void:
	# a couple of cracked flags
	draw_rect(Rect2(p + Vector2(-14, -6), Vector2(13, 12)), Color(0.40, 0.42, 0.36, 0.7))
	draw_rect(Rect2(p + Vector2(2, -4), Vector2(12, 11)), Color(0.38, 0.40, 0.34, 0.7))
	# sinuous roots over them
	for r in [[-18, 4, 16, -8], [-4, 8, 14, -2], [6, 6, 18, 6]]:
		draw_line(p + Vector2(r[0], r[1]), p + Vector2(r[2], r[3]), color, 2.0)
	draw_circle(p + Vector2(-2, 2), 2.0, color.lightened(0.1))


## A toppled PILLAR lying among the wood — a long drum on its side beside a broken stump.
func _draw_broken_pillar(p: Vector2, color: Color) -> void:
	draw_rect(Rect2(p + Vector2(-22, -6), Vector2(40, 13)), color)                   # the fallen shaft
	draw_circle(p + Vector2(-22, 0), 7.0, color.lightened(0.1))
	draw_circle(p + Vector2(-22, 0), 3.0, color.darkened(0.3))
	draw_arc(p + Vector2(18, 0), 7.0, -PI * 0.5, PI * 0.5, 10, color.darkened(0.2), 2.0)
	draw_rect(Rect2(p + Vector2(20, -4), Vector2(9, 11)), color.darkened(0.08))      # the stump it broke from


## A heap of fallen stone — a low rubble mound. (Solid in the spec; the art is just the silhouette.)
func _draw_rubble_pile(p: Vector2, color: Color) -> void:
	draw_circle(p + Vector2(-8, 4), 9.0, color.darkened(0.12))
	draw_circle(p + Vector2(9, 5), 8.0, color.darkened(0.16))
	draw_circle(p + Vector2(0, -2), 10.0, color)
	draw_circle(p + Vector2(-3, -6), 5.0, color.lightened(0.08))
	draw_circle(p + Vector2(7, -3), 4.0, color.lightened(0.05))


## A still, dark POOL in the Sunken Grove — rain gathered where the ceiling fell. Drawn like a pond but
## colder and darker (the "pool" water tile when present, else a flat fill), with a pale patch where the
## daylight shaft falls in. Solid (its spec collision_radius is the real footprint; the art radius here
## just needs to read close to it).
func _draw_pool(p: Vector2, color: Color) -> void:
	var rad := 88.0
	var ring := _organic_ring(p, rad, _phase_for(p))
	if _pool_tex != null:
		_fill_water(ring, _pool_tex, _pool_world_tile, _water_scroll(_pool_tex, false))
	else:
		draw_colored_polygon(ring, color)
		for k in 2:                                                        # slow, breathing ripples
			var t := fposmod(_time * 0.16 + float(k) * 0.5, 1.0)
			draw_arc(p, rad * (0.3 + 0.6 * t), 0.0, TAU, 40, Color(0.8, 0.9, 0.95, 0.14 * (1.0 - t)), 1.5)
	_draw_ring_rim(ring, Color(0.5, 0.6, 0.62, 0.32), 2.0)             # a faint stone rim
	# the pale reflected glow where the light-shaft strikes the water
	draw_circle(p + Vector2(-4, -10), 22.0, Color(0.88, 0.93, 0.82, 0.10))
	draw_circle(p + Vector2(-4, -10), 9.0, Color(0.95, 0.97, 0.9, 0.10))


## A SHAFT of daylight falling through the Sunken Grove's broken ceiling — the one place the dark lifts.
## A soft translucent column (narrow at the top, splaying to a pool of light on the floor) with dust motes
## drifting down it. Non-solid; pure mood. Placeholder for a real volumetric-light asset.
func _draw_light_shaft(p: Vector2, color: Color) -> void:
	var top := p + Vector2(22, -150)
	var glow := 0.10 + 0.03 * sin(_time * 0.8)
	var beam := PackedVector2Array([top + Vector2(-14, 0), top + Vector2(18, 0), p + Vector2(58, 0), p + Vector2(-44, 0)])
	draw_colored_polygon(beam, Color(color.r, color.g, color.b, glow))
	var core := PackedVector2Array([top + Vector2(-4, 0), top + Vector2(6, 0), p + Vector2(22, 0), p + Vector2(-16, 0)])
	draw_colored_polygon(core, Color(1.0, 0.98, 0.9, glow * 1.3))
	for k in 6:                                                        # dust motes drifting down the beam
		var ph := float(k) * 1.7
		var ty := fposmod(_time * 0.2 + float(k) / 6.0, 1.0)
		var mx := top.x - 22.0 * ty + sin(_time * 0.6 + ph) * 9.0
		var my := top.y + ty * 150.0
		draw_circle(Vector2(mx, my), 1.4, Color(1.0, 0.98, 0.85, 0.5 * (1.0 - ty)))
	draw_circle(p, 30.0, Color(color.r, color.g, color.b, 0.06))       # the pool of light on the floor


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


# ════════════════════════════════════════════════════════════════════════════════════════════
# THE THOUSAND-KNOT BAZAAR — placeholder vane + plaza art. The five Vanes are the navigation pillar
# made visible: one tall, unmistakable landmark per Knot, drawn well above the rooftops so it reads
# as a thing to steer by. (In this top-down 2D presentation "skyline-visible" is honoured by drawing
# them tall and distinct rather than by a real occlusion pass.) All are single-`type` placeholders
# over a known footprint, ready to swap 1:1 for real sprites later. ──
# ════════════════════════════════════════════════════════════════════════════════════════════

## COPPER CHIMNEY — the Spice Knot's Vane: a tall, banded copper flue, forever smoking. The smoke is the
## landmark you can find from anywhere over in the warm rows. Footprint ~36 wide; solid at its base.
func _draw_chimney(p: Vector2, color: Color) -> void:
	var h := 150.0
	var top := p + Vector2(0, -h)
	# the tapered stack
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-16, 0), p + Vector2(16, 0), top + Vector2(11, 0), top + Vector2(-11, 0)]), color.darkened(0.05))
	# a sunlit left edge + shaded right, to give it round volume
	draw_line(p + Vector2(-15, 0), top + Vector2(-10, 0), color.lightened(0.18), 2.0)
	draw_line(p + Vector2(15, 0), top + Vector2(10, 0), color.darkened(0.18), 2.0)
	# copper bands
	for k in 5:
		var y := -22.0 - float(k) * 28.0
		var hw := lerpf(15.0, 10.0, float(k) / 5.0)
		draw_line(p + Vector2(-hw, y), p + Vector2(hw, y), color.lightened(0.22), 2.0)
	# the rim, then rising smoke (drifting up and fading)
	draw_rect(Rect2(top + Vector2(-12, -4), Vector2(24, 5)), color.darkened(0.2))
	for k in 4:
		var t := fposmod(_time * 0.18 + float(k) / 4.0, 1.0)
		var sx := sin(_time * 0.6 + float(k) * 1.7) * 12.0 * t
		draw_circle(top + Vector2(sx, -8.0 - t * 70.0), 6.0 + 12.0 * t, Color(0.52, 0.47, 0.42, 0.20 * (1.0 - t)))


## PRISM TOWER — the Glassblowers' Run Vane: a tall tower of stacked glass panes that throws a slow
## halo of rainbow motes. Bright and jewel-toned; the colour you steer by.
func _draw_prism_tower(p: Vector2, color: Color) -> void:
	var h := 152.0
	var top := p + Vector2(0, -h)
	# the pane body
	draw_rect(Rect2(p + Vector2(-13, -h), Vector2(26, h)), Color(color.r, color.g, color.b, 0.85))
	# vertical facet seams
	draw_line(p + Vector2(-5, 0), p + Vector2(-5, -h), color.lightened(0.3), 1.0)
	draw_line(p + Vector2(6, 0), p + Vector2(6, -h), color.darkened(0.18), 1.0)
	# horizontal pane lines
	for k in 7:
		var y := -float(k) * 20.0 - 8.0
		draw_line(p + Vector2(-13, y), p + Vector2(13, y), color.darkened(0.1), 1.0)
	# a faceted crystal crown with a white catch-light
	draw_colored_polygon(PackedVector2Array([top + Vector2(-13, 0), top + Vector2(13, 0), top + Vector2(0, -24)]), color.lightened(0.22))
	draw_circle(top + Vector2(0, -7), 3.0, Color(1, 1, 1, 0.85))
	# the rainbow halo — small hue-cycling motes circling the crown (the Run's refracted-light identity)
	for k in 6:
		var ang := _time * 0.5 + float(k) * TAU / 6.0
		var hue := fposmod(float(k) / 6.0 + _time * 0.05, 1.0)
		draw_circle(top + Vector2(cos(ang) * 28.0, -18.0 + sin(ang) * 13.0), 2.2, Color.from_hsv(hue, 0.6, 1.0, 0.55))


## IVORY FINGER — the Bonewrights' Knot Vane: a tall, carved bone-white spire with a rounded tip, cold
## and still. It points at the sky over the hushed relic rows.
func _draw_ivory_spire(p: Vector2, color: Color) -> void:
	var h := 162.0
	var top := p + Vector2(0, -h)
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-13, 0), p + Vector2(13, 0), top + Vector2(7, 0), top + Vector2(-7, 0)]), color)
	# carved rings up the shaft
	for k in 7:
		var y := -float(k) * 21.0 - 10.0
		var hw := lerpf(12.0, 7.0, float(k) / 7.0)
		draw_line(p + Vector2(-hw, y), p + Vector2(hw, y), color.darkened(0.16), 1.5)
	# cold shaded right edge + a rounded fingertip
	draw_line(p + Vector2(11, 0), top + Vector2(6, 0), color.darkened(0.14), 2.0)
	draw_circle(top, 7.0, color.lightened(0.06))
	draw_circle(top + Vector2(-2, -2), 2.4, color.lightened(0.2))


## CROOKED MAST — the Ragpicker's Tangle Vane: a leaning ship's mast with a tattered, swaying sail and a
## thin pennant — a boat run aground in a dry river, fitting the Tangle's salvage-and-secrets mood.
func _draw_crooked_mast(p: Vector2, color: Color) -> void:
	var h := 150.0
	var top := p + Vector2(-h * 0.2, -h)  # leans to the left
	draw_line(p, top, color.darkened(0.1), 6.0)
	draw_line(p + Vector2(-2, 0), top + Vector2(-2, 0), color.lightened(0.12), 1.5)
	# a yard (cross-spar) two-thirds up
	var spar := p.lerp(top, 0.62)
	draw_line(spar + Vector2(-26, -2), spar + Vector2(22, -2), color.darkened(0.18), 3.0)
	# the tattered sail hanging from the yard, billowing in the breeze
	var s := _sway(_phase_for(p), 0.7)
	var sail := Color(0.74, 0.68, 0.56, 0.82)
	draw_colored_polygon(PackedVector2Array([
		spar + Vector2(-22, 0), spar + Vector2(18, 0),
		spar + Vector2(14 + s, 44), spar + Vector2(-18 + s * 0.6, 40)]), sail)
	# a couple of torn edges
	draw_line(spar + Vector2(14 + s, 44), spar + Vector2(2 + s, 36), sail.darkened(0.2), 1.5)
	# a thin pennant at the top
	draw_colored_polygon(PackedVector2Array([
		top + Vector2(0, 2), top + Vector2(18 + s, 6), top + Vector2(0, 12)]), Color(0.66, 0.32, 0.26, 0.85))


## SKY-ANCHOR — the High Stalls Vane: a giant iron anchor suspended on chains above the wealthiest rows,
## swinging just perceptibly. Visible clear across the channel.
func _draw_sky_anchor(p: Vector2, color: Color) -> void:
	var iron := Color(0.46, 0.49, 0.54)
	var swing := sin(_time * 0.7) * 0.06   # a slow pendulum
	var ac := p + Vector2(sin(_time * 0.7) * 6.0, -78.0)  # the anchor body hangs above the ground
	# two chains rising off the top of the frame
	for cx in [-10.0, 10.0]:
		var prev := ac + Vector2(cx * 0.5, -34)
		for k in range(1, 7):
			var nxt := ac + Vector2(cx * 0.5 - cx * 0.04 * float(k), -34.0 - float(k) * 16.0)
			draw_line(prev, nxt, iron.darkened(0.1), 2.0)
			prev = nxt
	draw_set_transform(ac, swing, Vector2.ONE)
	# ring + shank
	draw_arc(Vector2(0, -34), 6.0, 0.0, TAU, 16, iron, 3.0)
	draw_line(Vector2(0, -30), Vector2(0, 30), iron, 6.0)
	# the stock (crossbar near the top)
	draw_line(Vector2(-16, -22), Vector2(16, -22), iron.lightened(0.1), 4.0)
	# the curved arms and flukes at the bottom
	draw_arc(Vector2(0, 20), 22.0, 0.18 * PI, 0.82 * PI, 20, iron, 6.0)
	for fx in [-22.0, 22.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(fx, 22), Vector2(fx + (4 if fx < 0 else -4), 10), Vector2(fx + (10 if fx < 0 else -10), 24)]), iron.lightened(0.08))
	# a faint tint band at the very top, from the spec colour, so the anchor reads against the gold sky
	draw_arc(Vector2(0, -34), 9.0, 0.0, TAU, 16, Color(color.r, color.g, color.b, 0.5), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A KNUCKLE'S DRY WELL — a stone fountain ring around an empty, cracked basin, with a green high-water
## stain a hand's-width above the floor: the river stood this high once. The plaza's quiet centrepiece.
func _draw_dry_well(p: Vector2, color: Color) -> void:
	draw_circle(p + Vector2(0, 4), 27.0, color.darkened(0.22))
	draw_circle(p, 25.0, color)
	# the empty sunken basin
	draw_circle(p, 18.0, Color(0.20, 0.19, 0.17))
	# cracked dry bottom
	draw_line(p + Vector2(-9, -2), p + Vector2(7, 5), Color(0.32, 0.29, 0.24), 1.0)
	draw_line(p + Vector2(3, -7), p + Vector2(-3, 9), Color(0.32, 0.29, 0.24), 1.0)
	# the old waterline: a faint green stain just inside the rim
	draw_arc(p, 20.0, 0.0, TAU, 30, Color(0.40, 0.55, 0.38, 0.5), 2.0)
	draw_arc(p, 24.0, 0.0, TAU, 30, color.lightened(0.12), 1.0)


## A KNUCKLE'S NOTICE-BOARD — a posted board on two legs, pinned with curling notes. Where lore and
## bounties gather; the natural meet-up point. Examinable (its line carries a Knot's story fragment).
func _draw_notice_board(p: Vector2, color: Color) -> void:
	draw_rect(Rect2(p + Vector2(-18, -6), Vector2(3, 22)), Color(0.34, 0.26, 0.18))
	draw_rect(Rect2(p + Vector2(15, -6), Vector2(3, 22)), Color(0.34, 0.26, 0.18))
	draw_rect(Rect2(p + Vector2(-22, -36), Vector2(44, 32)), color)
	draw_rect(Rect2(p + Vector2(-22, -36), Vector2(44, 4)), color.darkened(0.18))
	draw_rect(Rect2(p + Vector2(-22, -8), Vector2(44, 4)), color.darkened(0.18))
	# pinned notes, a couple curling at a corner
	for note in [Vector2(-15, -30), Vector2(2, -32), Vector2(-7, -18), Vector2(9, -20)]:
		draw_rect(Rect2(p + note, Vector2(10, 9)), Color(0.93, 0.89, 0.79))
		draw_circle(p + note + Vector2(5, 1), 1.1, Color(0.72, 0.22, 0.2))
		draw_line(p + note + Vector2(10, 9), p + note + Vector2(7, 7), Color(0.80, 0.76, 0.66), 1.0)


## A KNUCKLE'S SHRINE — a small stone niche holding a steady candle (a rest point). No mechanic, just a
## warm, breathing flame so a plaza reads as somewhere to pause.
func _draw_shrine(p: Vector2, color: Color) -> void:
	draw_rect(Rect2(p + Vector2(-11, -2), Vector2(22, 9)), color.darkened(0.16))
	# the niche
	draw_rect(Rect2(p + Vector2(-9, -18), Vector2(18, 16)), color.darkened(0.32))
	draw_arc(p + Vector2(0, -18), 9.0, PI, TAU, 14, color.darkened(0.18), 3.0)
	# the candle flame, warm and breathing
	var breathe := 0.72 + 0.28 * sin(_time * 3.0)
	draw_circle(p + Vector2(0, -10), 5.0 * breathe, Color(1.0, 0.82, 0.42, 0.28))
	draw_circle(p + Vector2(0, -10), 2.0, Color(1, 0.92, 0.66))
	draw_rect(Rect2(p + Vector2(-1.5, -9), Vector2(3, 7)), Color(0.92, 0.9, 0.82))


## THE MAN WITH WET BOOTS — a cloaked wanderer who haunts the Ragpicker's Tangle, dealing in charts of a
## river not yet returned. A standing figure with a quiet idle and, tellingly, dark wet boots and a sheen
## at his feet. Examinable (a `wanderer`, not a `shopkeeper`, so it opens no shop — just his line).
func _draw_wanderer(p: Vector2, color: Color) -> void:
	var bob := sin(_time * 1.4 + _phase_for(p)) * 1.0
	# a faint wet sheen on the dry ground at his feet
	draw_circle(p + Vector2(0, 11), 8.0, Color(0.40, 0.50, 0.55, 0.16))
	# cloak body
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-8, 8), p + Vector2(8, 8), p + Vector2(6, -10 + bob), p + Vector2(-6, -10 + bob)]), color)
	draw_line(p + Vector2(0, -8 + bob), p + Vector2(0, 7), color.darkened(0.22), 1.0)
	# hood + a shadowed face
	draw_circle(p + Vector2(0, -14 + bob), 5.5, color.darkened(0.12))
	draw_circle(p + Vector2(0, -13 + bob), 3.4, Color(0.80, 0.66, 0.56))
	# the wet boots
	draw_rect(Rect2(p + Vector2(-7, 7), Vector2(5, 4)), Color(0.17, 0.20, 0.24))
	draw_rect(Rect2(p + Vector2(2, 7), Vector2(5, 4)), Color(0.17, 0.20, 0.24))
	draw_circle(p + Vector2(-4.5, 7.5), 1.0, Color(0.6, 0.72, 0.78, 0.7))


## STACKED CARGO CRATES — market texture: a big crate with a smaller one perched on top. Solid; used to
## thicken the Ragpicker's Tangle into a maze and to dress the High Stalls' wealthy cargo.
func _draw_crate(p: Vector2, color: Color) -> void:
	draw_rect(Rect2(p + Vector2(-11, -9), Vector2(20, 17)), color)
	draw_rect(Rect2(p + Vector2(-11, -9), Vector2(20, 4)), color.lightened(0.1))
	draw_line(p + Vector2(-11, 0), p + Vector2(9, 0), color.darkened(0.22), 1.0)
	draw_line(p + Vector2(-1, -9), p + Vector2(-1, 8), color.darkened(0.22), 1.0)
	# a smaller crate stacked on top
	draw_rect(Rect2(p + Vector2(-6, -20), Vector2(13, 11)), color.lightened(0.05))
	draw_rect(Rect2(p + Vector2(-6, -20), Vector2(13, 3)), color.lightened(0.16))
