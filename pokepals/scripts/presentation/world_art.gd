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
var _sparkles: Array = []  # [ { pos, color, phase } ] — a glowing world's twinkling ground specks
# The pixel-art ground (GroundLayer): when the art direction asks for it, the floor, the paths and the
# sandy shores are drawn by a shader child instead of the gradient + stretched noise + stroked paths
# below, and the ground is dressed with clustered pixel DETAILS from a sprite atlas.
var _ground: GroundLayer = null
var _detail_tex: Texture2D = null
var _detail_rects := {}   # name -> Rect2 in the atlas (tools/gen_ground.py's index)
var _details: Array = []  # [ { pos, rect, phase, sway, tint } ] — ground litter, under the water pass
var _shore_details: Array = []  # same shape — reeds and lily pads, drawn over the water
# The litter is drawn through two NEAREST-filtered proxies (WorldArt itself stays linear for its soft
# glows): one behind WorldArt's own drawing, right over the ground, and one in front, over the water.
var _litter_under: DrawProxy = null
var _litter_over: DrawProxy = null
var _glow_cells := {}  # Vector2i -> details that glow (their soft halos, drawn by WorldArt itself)
var _understory: Array = []  # [ { pos, type } ] — bush/stump spots Scenery plants (see understory_spots)
# Trees, the border treeline and landmarks live in the y-sorted Scenery layer now, not here.

# --- atmosphere (presentation-only mood, from the world spec's "atmosphere") ---
var _time := 0.0
var _dusk := 0.0   # 0 = full day .. 1 = deepest dusk (pushed by world_controller's day cycle)
var _wind_strength := 2.6
var _wind_speed := 1.15
var _glow_pulse_speed := 1.4
var _region_tint_alpha := 0.12
var _ground_noise: ImageTexture = null
var _water_rim := Color(0.78, 0.86, 0.88, 0.5)  # the shoreline line; palette "water_rim" re-tints it
var _grass_max := 240  # the tuft cap; a big world can raise it (atmosphere.grass.max) so it isn't bare
var _style: ArtStyle
var _ground_grad: GradientTexture2D = null

# --- C-3: the form hint layer ---
# Which interactables (by index into _interactables) the companion's CURRENT form could act on, and
# the colour that form lights them in. Pushed by world_controller whenever the worn form shifts, so
# switching shape changes what glows — the whole point of the layer. Empty = nothing highlighted.
var _form_highlights := {}   # index: int -> true (a set; dictionary lookup beats an array scan per frame)
var _form_highlight_color := Color(0.98, 0.92, 0.62)
var _fh_alpha := 0.20
var _fh_radius := 25.0
var _fh_pulse_speed := 0.9

# Optional pixel-art water tiles (tools/gen_water.py). Each is a seamless square the
# world tiles across a body of water; `world_tile` is how many world units it spans.
# Absent → the flat procedural fill below (so the smoke test stays green with no art).
var _pond_tex: Texture2D = null
var _river_tex: Texture2D = null
var _pool_tex: Texture2D = null
var _pond_world_tile := 64.0
var _river_world_tile := 64.0
var _pool_world_tile := 64.0
# Optional seamless leafy hedge tile (tools/gen_hedge.py), tiled along the maze walls.
# Absent → the flat-green procedural hedges below.
var _hedge_tex: Texture2D = null
var _hedge_world_tile := 44.0
# Optional grayscale portal sprite — tinted per-portal at draw time (each portal carries its
# own colour). Absent → the procedural shimmering ovals in _draw_prop's "portal" case.
var _portal_tex: Texture2D = null

# Optional pixel-art prop sprites (tools/gen_props.py), keyed by prop type. Each has a BASE
# layer (fixed materials) and, when its colour is data, a grayscale TINT layer drawn with the
# instance's colour. Absent for a type → that prop's procedural drawing below. Loaded from the
# `entities.props` list in art.json (convention: prop_<type>_base/_tint.png).
var _prop_base := {}   # type: String -> Texture2D
var _prop_tint := {}   # type: String -> Texture2D (only for tinted props)
# These props still animate (flame/glow), so they blit their baked vessel inside their own
# draw fn and keep the moving part procedural — they're NOT swapped wholesale like static props.
const _PROP_OVERLAY := { "torch": true, "ember": true, "brazier": true, "shopkeeper": true, "carving": true }

# A glowing world's prop LIGHTS (the "prop_lights" entity in a world's art override): per prop type,
# a soft halo in the prop's own colour — { radius, y, alpha, motes } — so a bloom, a vein of moss or a
# rune-stone lights the ground around it. "motes" makes it breathe little sparks upward (a spore vent,
# a puffball). Empty in the meadow worlds, which keep their hand-tuned _draw_glow warmth instead.
var _prop_lights := {}
# How long a FLARE (a touched glow-plant blazing up, seen by everyone in the world) takes to fade, and
# how much bigger + brighter its light gets at the peak.
const FLARE_FADE := 0.16   # per second → about six seconds of afterglow
const FLARE_GROW := 2.2


func render_world(data: Dictionary, style: ArtStyle = null) -> void:
	_style = style if style != null else ArtStyle.load_style()
	_ground_color = WorldData.to_color(data["ground_color"])
	_bounds = WorldData.bounds_rect(data)
	# A soft top→bottom ground gradient (palette), baked once, drawn under the dapple.
	_ground_grad = _style.make_vertical_gradient_texture(_style.color("ground_top"), _style.color("ground_bottom"))
	_water_rim = _style.color("water_rim")

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
	var hedge_cfg: Dictionary = _style.entity("hedge")
	_hedge_tex = SpriteSlot.resolve(hedge_cfg, "tile")
	_hedge_world_tile = float(hedge_cfg.get("world_tile", 44.0))
	if _pond_tex != null or _river_tex != null or _pool_tex != null or _hedge_tex != null:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_portal_tex = SpriteSlot.resolve(_style.entity("portal"), "sprite")

	# Pixel-art prop sprites: for each type listed in entities.props, load its base (and tint)
	# by convention if the files exist. Missing files just leave the type on procedural drawing.
	_prop_base.clear()
	_prop_tint.clear()
	var props_cfg: Dictionary = _style.entity("props")
	if String(props_cfg.get("render", "")) == "sprite":
		var prefix := String(props_cfg.get("prefix", "res://assets/sprites/prop_"))
		# A world's art override can ADD its own prop types ("extra_types") without restating the shared list.
		for t in props_cfg.get("types", []) + props_cfg.get("extra_types", []):
			var ty := String(t)
			var base_path := prefix + ty + "_base.png"
			if not ResourceLoader.exists(base_path):
				continue
			_prop_base[ty] = ResourceLoader.load(base_path)
			var tint_path := prefix + ty + "_tint.png"
			if ResourceLoader.exists(tint_path):
				_prop_tint[ty] = ResourceLoader.load(tint_path)

	# C-3's halo knobs, from the art direction (the set of lit objects comes from the controller).
	var fh: Dictionary = _style.form_highlight()
	_fh_alpha = float(fh.get("alpha", 0.20))
	_fh_radius = float(fh.get("radius", 25.0))
	_fh_pulse_speed = float(fh.get("pulse_speed", 0.9))
	_prop_lights = (_style.entity("prop_lights") as Dictionary).duplicate(true)

	var atmo: Dictionary = data.get("atmosphere", {})
	var wind: Dictionary = atmo.get("wind", {})
	_wind_strength = float(wind.get("strength", 2.6))
	_wind_speed = float(wind.get("speed", 1.15))
	_glow_pulse_speed = float(atmo.get("glow", {}).get("pulse_speed", 1.4))
	_region_tint_alpha = float(atmo.get("region_tint_alpha", 0.12))
	_grass_max = int((atmo.get("grass", {}) as Dictionary).get("max", 240))
	_build_ground_noise(atmo.get("ground_noise", {}))
	_scatter_sparkles(atmo.get("sparkles", {}))

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
	# Ponds are static: bake each one's organic outline and its visible SHORE once, here, rather than
	# every frame. Ponds that overlap (one big lake made of several — Nocthollow's Mere) read as one body
	# of water: a shore skips any stretch that runs through another pond's water instead of drawing a
	# seam across the lake. A lone pond (every meadow pond) keeps its whole ring as its shore.
	for pd in _ponds:
		pd["ring"] = _organic_ring(pd["center"], pd["radius"], _phase_for(pd["center"]))
	for i in _ponds.size():
		_ponds[i]["shore"] = _shore_runs(i)
		_ponds[i]["shallows"] = _inset_runs(_ponds[i], SHALLOWS_INSET)
		_ponds[i]["foam"] = _foam_specks(_ponds[i]["shore"], _ponds[i]["center"])

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
		var rrect: Rect2 = _river["rect"]
		_river["foam"] = _foam_specks([_river_bank(rrect, rrect.position.y, _phase_for(rrect.position)), _river_bank(rrect, rrect.end.y, _phase_for(rrect.end))], rrect.get_center(), [Vector2.DOWN, Vector2.UP])

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
	# Paths are authored as straight from→to segments; PathShape chains the ones that meet end to end
	# and rounds them into meandering curves (grouped by look, so a glowing vein never chains onto a
	# dirt trail). Each entry is one curve: { pts, color, glow }.
	var groups := {}
	for p in data.get("paths", []):
		# "glow": true makes a path a luminous VEIN (a bright breathing thread down its middle) — the
		# night planet's trails of glowing moss — rather than worn earth.
		var glow := bool(p.get("glow", false))
		var col := WorldData.to_color(p["color"])
		var key := "%s|%s" % [glow, col.to_html()]
		if not groups.has(key):
			groups[key] = { "color": col, "glow": glow, "segs": [] }
		groups[key]["segs"].append({ "from": WorldData.to_vec2(p["from"]), "to": WorldData.to_vec2(p["to"]) })
	for key in groups:
		var g: Dictionary = groups[key]
		for pts in PathShape.curves(g["segs"]):
			_paths.append({ "pts": pts, "color": g["color"], "glow": g["glow"], "box": _poly_box(pts) })

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

	_build_pixel_ground(data)
	if _ground == null:
		_scatter_grass()

	_interactables.clear()
	_form_highlights.clear()   # the indices they keyed just went away with the old list
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
			"flare": 0.0,  # a touched glow-plant's blaze, 1 → 0 (see flare_interactable)
		})

	queue_redraw()


func _parse_pond(pond: Dictionary) -> Dictionary:
	return { "center": WorldData.to_vec2(pond["center"]), "radius": float(pond["radius"]), "color": WorldData.to_color(pond["color"]) }


## A stable pseudo-random phase in [0, TAU) derived from a world position, so each
## swaying thing keeps the same offset every frame (and across runs).
func _phase_for(p: Vector2) -> float:
	return fposmod(p.x * 0.013 + p.y * 0.021, TAU)


## The one quality knob (art.json's "quality" entity, "detail": 1 = full): scales how much litter,
## understory and ambient life a world gets, so a struggling phone can be turned down in one place.
static func detail_quality(style: ArtStyle) -> float:
	return clampf(float((style.entity("quality") as Dictionary).get("detail", 1.0)), 0.0, 2.0)


static func _poly_box(pts: PackedVector2Array) -> Rect2:
	var box := Rect2(pts[0], Vector2.ZERO) if not pts.is_empty() else Rect2()
	for q in pts:
		box = box.expand(q)
	return box


## ---- the pixel-art ground ---------------------------------------------------------------------

## If the art direction asks for it (the "ground" entity, render "pixel"), put the GroundLayer shader
## under everything and dress it with clustered pixel details; otherwise leave the classic gradient +
## noise + tufts in charge (a world can opt out in its art block, as Nocthollow does).
func _build_pixel_ground(data: Dictionary) -> void:
	if _ground != null:
		_ground.queue_free()
		_ground = null
	for proxy in [_litter_under, _litter_over]:
		if proxy != null:
			proxy.queue_free()
	_litter_under = null
	_litter_over = null
	_details.clear()
	_shore_details.clear()
	_glow_cells.clear()
	_understory.clear()
	_detail_tex = null
	if not GroundLayer.wanted(_style):
		return
	var cfg := _style.entity("ground")
	# every trail goes into the floor (a glowing vein becomes luminous moss there, by the path ramp);
	# a glowing one still gets its breathing thread of light drawn over it in _draw
	var dirt_paths: Array = []
	for p in _paths:
		dirt_paths.append(p["pts"])
	var ponds: Array = []
	for pd in _ponds:
		ponds.append({ "center": pd["center"], "radius": pd["radius"], "seed": _phase_for(pd["center"]) })
	var river := {}
	if not _river.is_empty():
		var rr: Rect2 = _river["rect"]
		river = { "rect": rr, "top_seed": _phase_for(rr.position), "bot_seed": _phase_for(rr.end) }
	var shade: Array = []
	for t in data.get("trees", []) + data.get("border_trees", []):
		shade.append({ "pos": WorldData.to_vec2(t), "r": 24.0 })
	for lm in data.get("landmarks", []):
		shade.append({ "pos": WorldData.to_vec2(lm["position"]), "r": 50.0 })
	for it in data.get("props", []):
		shade.append({ "pos": WorldData.to_vec2(it["position"]) + Vector2(0, 6), "r": 12.0 })
	_ground = GroundLayer.new()
	_ground.name = "Ground"
	add_child(_ground)
	_ground.build(_bounds, _style, { "paths": dirt_paths, "ponds": ponds, "river": river, "shade": shade })

	_detail_tex = GroundLayer.texture(cfg, "details")
	_detail_rects.clear()
	var index_path := String(cfg.get("details_index", ""))
	if _detail_tex != null and index_path != "" and FileAccess.file_exists(index_path):
		var idx: Dictionary = WorldData.load_json(index_path)
		for n in idx:
			var r: Array = idx[n]
			_detail_rects[n] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	if not _detail_rects.is_empty():
		_scatter_details(data, cfg.get("scatter", {}), dirt_paths)
		# behind WorldArt's drawing, but added after the ground so it lands on top of it
		_litter_under = _make_litter_proxy("LitterUnder", true, _bucket(_details))
		_litter_over = _make_litter_proxy("LitterOver", false, _bucket(_shore_details))


## Litter is grouped into square BUCKETS of world space, so a frame only walks the buckets on screen
## instead of every tuft in the world (a big world holds thousands). Each bucket keeps its back-to-front
## order; buckets are drawn row by row. { Vector2i cell: Array of details }.
const LITTER_CELL := 160.0

func _bucket(list: Array) -> Dictionary:
	var cells := {}
	for d in list:
		var p: Vector2 = d["pos"]
		var key := Vector2i(floori(p.x / LITTER_CELL), floori(p.y / LITTER_CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(d)
	return cells


func _make_litter_proxy(proxy_name: String, behind: bool, cells: Dictionary) -> DrawProxy:
	var proxy := DrawProxy.new()
	proxy.name = proxy_name
	proxy.show_behind_parent = behind
	proxy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	proxy.draw_fn = func(ci: CanvasItem) -> void:
		var vis := ViewCull.visible_world_rect(ci, 24.0)
		if not vis.has_area():
			for key in cells:   # headless / no camera: draw it all
				_draw_details(ci, cells[key], vis, false)
			return
		var x0 := floori(vis.position.x / LITTER_CELL)
		var x1 := floori(vis.end.x / LITTER_CELL)
		for cy in range(floori(vis.position.y / LITTER_CELL), floori(vis.end.y / LITTER_CELL) + 1):
			for cx in range(x0, x1 + 1):
				var bucket: Array = cells.get(Vector2i(cx, cy), [])
				if not bucket.is_empty():
					_draw_details(ci, bucket, vis, true)
	add_child(proxy)
	return proxy


## The meadow's litter, used for any key a world's ground.scatter doesn't name. A world (Nocthollow)
## swaps in its own sets; see data/art.json's ground entity.
const DEFAULT_SCATTER := {
	"open": [
		{ "names": ["tuft_a", "tuft_b", "tuft_c"], "weight": 52, "count": [4, 10], "sway": 0.35, "tinted": true },
		{ "names": ["clover"], "weight": 10, "tinted": true },
		{ "names": ["pebbles"], "weight": 9 },
		{ "names": ["daisies"], "weight": 8 },
		{ "names": ["twig"], "weight": 5 },
		{ "names": ["stone", "stone_b"], "weight": 3 },
	],
	"under_trees": { "names": ["leaf_gold", "leaf_rust"], "ring": ["mushroom"] },
	"path_edge": ["pebbles", "pebbles", "pebbles", "pebbles", "pebbles", "pebbles", "stone", "stone_b"],
	"reeds": ["reed_a", "reed_a", "reed_a", "reed_b", "reed_b"],
	"lilies": ["lily", "lily", "lily", "lily_bloom"],
}


## Is `p` on open, dry, unpathed ground (where litter may lie)?
func _open_ground(p: Vector2, path_clear: float) -> bool:
	if not _bounds.has_point(p):
		return false
	for pd in _ponds:
		var off: Vector2 = p - (pd["center"] as Vector2)
		if off.length() < organic_radius(off.angle(), float(pd["radius"]), _phase_for(pd["center"])) + 4.0:
			return false
	if not _river.is_empty() and (_river["rect"] as Rect2).grow(6.0).has_point(p):
		return false
	if not _vein.is_empty() and (_vein["rect"] as Rect2).has_point(p):
		return false
	return _ground.path_value(p) < path_clear


func _add_detail(list: Array, name: String, p: Vector2, sway: float = 0.0, tint := Color.WHITE) -> void:
	if not _detail_rects.has(name):
		return
	list.append({ "name": name, "pos": p.round(), "rect": _detail_rects[name], "phase": _phase_for(p), "sway": sway, "tint": tint })


## Scatter the ground's litter in natural CLUSTERS (a patch of tufts, a ring of mushrooms by a trunk,
## pebbles where a trail frays, reeds in clumps along a shore) instead of an even sprinkle. Seeded, so
## the same world is dressed the same way every visit. scatter = { density (1 = default), grass_tint }.
func _scatter_details(data: Dictionary, scfg: Dictionary, paths: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xD371A + int(_bounds.position.x) * 7 + int(_bounds.size.y)
	var density := float(scfg.get("density", 1.0)) * detail_quality(_style)
	# a world can re-tint its living litter (a sun-baked market's tufts are straw, not green)
	var grass_tint := WorldData.to_color(scfg.get("grass_tint", [1.0, 1.0, 1.0]))
	var area := _bounds.size.x * _bounds.size.y
	var trees: Array = []
	for t in data.get("trees", []):
		if not (t is Array and t.size() > 2):   # a plain meadow tree, not a world's special growth
			trees.append(WorldData.to_vec2(t))
	for lm in data.get("landmarks", []):
		trees.append(WorldData.to_vec2(lm["position"]))

	# open-ground clusters: weighted SETS of litter (a set = some sprites + how many per cluster)
	var sets: Array = scfg.get("open", DEFAULT_SCATTER["open"])
	var total := 0
	for st in sets:
		total += int(st.get("weight", 1))
	var clusters := int(clampf(area / 7000.0 * density, 20.0, 1600.0)) if total > 0 else 0
	for _i in clusters:
		var c := Vector2(_bounds.position.x + rng.randf() * _bounds.size.x, _bounds.position.y + rng.randf() * _bounds.size.y)
		var roll := rng.randi() % total
		var st: Dictionary = sets[0]
		for cand in sets:
			roll -= int(cand.get("weight", 1))
			if roll < 0:
				st = cand
				break
		var names: Array = st.get("names", [])
		if names.is_empty():
			continue
		var count: Array = st.get("count", [1, 4])
		var n := rng.randi_range(int(count[0]), int(count[1]))
		var sway := float(st.get("sway", 0.0))
		var tint := grass_tint if bool(st.get("tinted", false)) else Color.WHITE
		var spread := rng.randf_range(10.0, 28.0)
		for _j in n:
			var p := c + Vector2(rng.randfn(0.0, spread), rng.randfn(0.0, spread * 0.7))
			if _open_ground(p, 0.3):
				_add_detail(_details, String(names[rng.randi() % names.size()]), p, sway, tint)

	# under the trees: litter fallen around the trunk, and a little ring of something by the roots
	var under: Dictionary = scfg.get("under_trees", DEFAULT_SCATTER["under_trees"])
	var fallen: Array = under.get("names", [])
	var ring: Array = under.get("ring", [])
	for t in trees:
		if not fallen.is_empty() and rng.randf() < 0.55:
			for _j in rng.randi_range(1, 4):
				var p: Vector2 = t + Vector2(rng.randfn(0.0, 16.0), rng.randfn(4.0, 9.0))
				if _open_ground(p, 0.5):
					_add_detail(_details, String(fallen[rng.randi() % fallen.size()]), p)
		if not ring.is_empty() and rng.randf() < 0.3:
			var a := rng.randf() * TAU
			for _j in rng.randi_range(1, 3):
				var p: Vector2 = t + Vector2(cos(a), sin(a) * 0.6) * rng.randf_range(12.0, 20.0) + Vector2(rng.randfn(0.0, 3.0), rng.randfn(0.0, 2.0))
				if _open_ground(p, 0.5):
					_add_detail(_details, String(ring[rng.randi() % ring.size()]), p)

	# where a trail frays: pebbles on its shoulders and the odd half-sunk stone
	var edge: Array = scfg.get("path_edge", DEFAULT_SCATTER["path_edge"])
	for pts in (paths if not edge.is_empty() else []):
		var acc := 0.0
		for k in range(1, pts.size()):
			acc += pts[k].distance_to(pts[k - 1])
			if acc < 28.0:
				continue
			acc = 0.0
			if rng.randf() > 0.35:
				continue
			var tangent: Vector2 = (pts[k] - pts[k - 1]).normalized()
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var p: Vector2 = pts[k] + Vector2(-tangent.y, tangent.x) * side * rng.randf_range(9.0, 15.0)
			_add_detail(_details, String(edge[rng.randi() % edge.size()]), p)

	# the spec's own flowers, as tinted pixel flowers
	for f in _flowers:
		_add_detail(_details, "flower", f["pos"], 0.45, f["color"])

	_pick_understory(rng, trees, float((_style.entity("understory") as Dictionary).get("density", 1.0)) * detail_quality(_style))
	_scatter_shores(rng, density, scfg.get("reeds", DEFAULT_SCATTER["reeds"]), scfg.get("lilies", DEFAULT_SCATTER["lilies"]))
	# litter that glows gets a soft halo (see _draw_litter_glow)
	var glow: Dictionary = scfg.get("glow", {})
	for list in [_details, _shore_details]:
		for d in list:
			if glow.has(d["name"]):
				d["glow"] = WorldData.to_color(glow[d["name"]])
	_glow_cells.clear()
	for list in [_details, _shore_details]:
		for d in list:
			if d.has("glow"):
				var key := Vector2i(floori(d["pos"].x / LITTER_CELL), floori(d["pos"].y / LITTER_CELL))
				if not _glow_cells.has(key):
					_glow_cells[key] = []
				_glow_cells[key].append(d)
	# draw back-to-front so a nearer tuft overlaps a farther one
	_details.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["pos"].y < b["pos"].y)
	_shore_details.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["pos"].y < b["pos"].y)


## Where the bushes and stumps go: a bush or two at the foot of many trees, the odd stump, and a few
## loose thickets out in the open — never on a trail or in the water, never on top of a trunk.
func _pick_understory(rng: RandomNumberGenerator, trees: Array, density: float) -> void:
	var types: Array = (_style.entity("understory") as Dictionary).get("types", [])
	if types.is_empty() or density <= 0.0:
		return
	var bushes: Array = []
	for t in types:
		if String(t) != "stump":
			bushes.append(t)
	if bushes.is_empty():
		return
	var placed: Array = []
	var try_place := func(p: Vector2, ty: String) -> void:
		if not _open_ground(p, 0.12):
			return
		for t in trees:
			if p.distance_to(t) < 14.0:
				return
		for q in placed:
			if p.distance_to(q) < 12.0:
				return
		placed.append(p)
		_understory.append({ "pos": p.round(), "type": ty })
	for t in trees:
		if rng.randf() < 0.45 * density:
			for _j in rng.randi_range(1, 2):
				var a := rng.randf() * TAU
				try_place.call(t + Vector2(cos(a), sin(a) * 0.7) * rng.randf_range(18.0, 32.0), String(bushes[rng.randi() % bushes.size()]))
		if rng.randf() < 0.05 and types.has("stump"):
			var a := rng.randf() * TAU
			try_place.call(t + Vector2(cos(a), sin(a)) * rng.randf_range(30.0, 60.0), "stump")
	var thickets := int(_bounds.size.x * _bounds.size.y / 90000.0 * density)
	for _i in thickets:
		var c := Vector2(_bounds.position.x + rng.randf() * _bounds.size.x, _bounds.position.y + rng.randf() * _bounds.size.y)
		var ty := String(bushes[rng.randi() % bushes.size()])
		for _j in rng.randi_range(1, 3):
			try_place.call(c + Vector2(rng.randfn(0.0, 14.0), rng.randfn(0.0, 9.0)), ty)


## Bush/stump spots for Scenery to plant as y-sorted sprites (empty without the pixel ground).
func understory_spots() -> Array:
	return _understory


## Reeds in clumps along every shore and lily pads resting on the water.
func _scatter_shores(rng: RandomNumberGenerator, density: float, reeds: Array, lilies: Array) -> void:
	if reeds.is_empty() and lilies.is_empty():
		return
	var pick := func(names: Array) -> String:
		return String(names[rng.randi() % names.size()]) if not names.is_empty() else ""
	for pd in _ponds:
		var c: Vector2 = pd["center"]
		var radius := float(pd["radius"])
		var seed := _phase_for(c)
		var clumps := int(radius * TAU / 55.0 * density)
		for _i in clumps:
			var a := rng.randf() * TAU
			for _j in rng.randi_range(2, 4):
				var aa := a + rng.randf_range(-0.09, 0.09)
				var r := organic_radius(aa, radius, seed) + rng.randf_range(-3.0, 2.0)
				_add_detail(_shore_details, pick.call(reeds), c + Vector2(cos(aa), sin(aa)) * r, 0.5)
		for _i in int(radius * radius / 1500.0 * density):
			var a := rng.randf() * TAU
			var r := organic_radius(a, radius, seed) * rng.randf_range(0.3, 0.82)
			_add_detail(_shore_details, pick.call(lilies), c + Vector2(cos(a), sin(a)) * r)
	if not _river.is_empty():
		var rr: Rect2 = _river["rect"]
		var x := rr.position.x + rng.randf_range(0.0, 40.0)
		while x < rr.end.x:
			for bank in [[rr.position.y, _phase_for(rr.position), 1.0], [rr.end.y, _phase_for(rr.end), -1.0]]:
				if rng.randf() < 0.45:
					var by: float = bank[0] + river_bank_offset(x, bank[1])
					for _j in rng.randi_range(2, 4):
						var px := x + rng.randf_range(-8.0, 8.0)
						_add_detail(_shore_details, pick.call(reeds), Vector2(px, by + rng.randf_range(-2.0, 3.0) * float(bank[2])), 0.5)
				if rng.randf() < 0.25:
					var ly: float = bank[0] + river_bank_offset(x, bank[1]) + float(bank[2]) * rng.randf_range(10.0, 26.0)
					_add_detail(_shore_details, pick.call(lilies), Vector2(x + rng.randf_range(-10.0, 10.0), ly))
			x += rng.randf_range(34.0, 70.0)


## The halos of glowing litter, one soft breathing pool each, drawn here (linear filtering) rather than
## in the NEAREST litter proxies, so the light stays smooth while the sprites stay crisp. Only the
## buckets on screen are walked.
func _draw_litter_glow(vis: Rect2, cull: bool) -> void:
	if _glow_cells.is_empty():
		return
	var keys: Array = []
	if cull:
		for cy in range(floori(vis.position.y / LITTER_CELL), floori(vis.end.y / LITTER_CELL) + 1):
			for cx in range(floori(vis.position.x / LITTER_CELL), floori(vis.end.x / LITTER_CELL) + 1):
				if _glow_cells.has(Vector2i(cx, cy)):
					keys.append(Vector2i(cx, cy))
	else:
		keys = _glow_cells.keys()
	for key in keys:
		for d in _glow_cells[key]:
			var c: Color = d["glow"]
			var breathe := 0.75 + 0.25 * sin(_time * 1.3 + float(d["phase"]) * 3.0)
			var r: Rect2 = d["rect"]
			SoftGlow.draw(self, (d["pos"] as Vector2) + Vector2(0, -r.size.y * 0.5), 9.0 * breathe, Color(c.r, c.g, c.b, 0.34 * breathe))


## Draw one batch of details (culled), each tuft/reed nodding a whole pixel at a time in the breeze.
func _draw_details(ci: CanvasItem, list: Array, vis: Rect2, cull: bool) -> void:
	for d in list:
		var p: Vector2 = d["pos"]
		if cull and not vis.has_point(p):
			continue
		var r: Rect2 = d["rect"]
		var sx := 0.0
		if d["sway"] > 0.0:
			sx = roundf(_sway(d["phase"], d["sway"]))
		ci.draw_texture_rect_region(_detail_tex, Rect2(p + Vector2(sx - roundf(r.size.x * 0.5), -r.size.y), r.size), r, d["tint"])


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
	var count := int(clampf(_bounds.size.x * _bounds.size.y / 26000.0, 40, _grass_max))
	var base := _style.color("grass")
	for i in count:
		var pos := Vector2(
			_bounds.position.x + rng.randf() * _bounds.size.x,
			_bounds.position.y + rng.randf() * _bounds.size.y)
		var shade := rng.randf_range(-0.05, 0.06)
		_grass.append({
			"pos": pos,
			"len": rng.randf_range(4.0, 8.0),
			"color": Color(base.r + shade, base.g + shade, base.b + shade, 0.85),
			"phase": _phase_for(pos),
		})


## A glowing world's ground: tiny specks of light (spores, starmoss) scattered over the whole map,
## each twinkling on its own slow beat. atmosphere.sparkles = { count, colors: [[r,g,b], …] }; absent
## (every meadow world) means none. Seeded, so the same specks twinkle in the same places every visit.
func _scatter_sparkles(cfg: Dictionary) -> void:
	_sparkles.clear()
	var count := int(cfg.get("count", 0))
	var colors: Array = cfg.get("colors", [[0.6, 1.0, 0.95]])
	if count <= 0 or colors.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5A1C1E
	for i in count:
		var pos := Vector2(
			_bounds.position.x + rng.randf() * _bounds.size.x,
			_bounds.position.y + rng.randf() * _bounds.size.y)
		_sparkles.append({
			"pos": pos,
			"color": WorldData.to_color(colors[rng.randi() % colors.size()]),
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.5, 1.4),
		})


## A glow-plant was touched (by us, or — relayed by the server — by anyone in the world): blaze its
## light up, then let it fade back over several seconds. Also pulses it like any examine.
func flare_interactable(index: int) -> void:
	if index >= 0 and index < _interactables.size():
		_interactables[index]["flare"] = 1.0
		_interactables[index]["pulse"] = 1.0


## C-3 — light the objects the companion's CURRENT form could act on, in that form's colour. The
## controller works out the set (pure FormAffordance logic) and pushes it here on every form shift;
## this side only draws it. Passing an empty list clears the layer, which is what a form that affords
## nothing here should look like: a quiet world.
func set_form_highlights(indices: Array, color: Color) -> void:
	_form_highlights.clear()
	for i in indices:
		var idx := int(i)
		if idx >= 0 and idx < _interactables.size():
			_form_highlights[idx] = true
	_form_highlight_color = color
	queue_redraw()


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
		"examined": false, "content": "", "missed": false, "flare": 0.0,
	})
	queue_redraw()
	return _interactables.size() - 1


## Take an interactable out of the world (a world secret, picked up once found): it stops drawing.
## Its index stays reserved, so every other prop's render index is untouched.
func take_interactable(index: int) -> void:
	if index >= 0 and index < _interactables.size():
		_interactables[index]["taken"] = true
		queue_redraw()


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
		if it.get("flare", 0.0) > 0.0:
			it["flare"] = maxf(0.0, it["flare"] - delta * FLARE_FADE)
	# The world is gently animated (wind, shimmer, breathing glow), so redraw each frame.
	queue_redraw()
	if _litter_under != null:
		_litter_under.queue_redraw()
		_litter_over.queue_redraw()


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
	# (With the pixel ground, the GroundLayer child draws the floor, the paths and the shores instead.)
	if _ground == null:
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

	# (the pixel ground's litter — tufts, clover, pebbles, leaves, flowers — is drawn by _litter_under)

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

	# twinkling ground specks (a glowing world only)
	for sp in _sparkles:
		if cull and not vis.has_point(sp["pos"]):
			continue
		var tw := 0.5 + 0.5 * sin(_time * float(sp["speed"]) + float(sp["phase"]))
		var sc: Color = sp["color"]
		draw_circle(sp["pos"], 0.8 + 0.7 * tw, Color(sc.r, sc.g, sc.b, 0.25 + 0.6 * tw * tw))

	# worn paths (or, on a glowing world, luminous veins of moss with a breathing thread of light),
	# following their curves. On the pixel ground a dirt trail is part of the floor shader instead.
	for p in _paths:
		if _ground != null and not p["glow"]:
			continue
		if cull and not vis.intersects((p["box"] as Rect2).grow(8.0)):
			continue
		var pts: PackedVector2Array = p["pts"]
		if _ground == null:
			draw_polyline(pts, p["color"], 16.0)   # on the pixel ground the floor itself is the trail
		if p["glow"]:
			var pc: Color = (p["color"] as Color).lightened(0.4)
			var core: Color = (p["color"] as Color).lightened(0.6)
			var pb := 0.55 + 0.25 * sin(_time * 0.9 + _phase_for(pts[0]))
			draw_polyline(pts, Color(pc.r, pc.g, pc.b, 0.16), 6.0)
			draw_polyline(pts, Color(core.r, core.g, core.b, pb * 0.6), 1.5)

	# the Vein: the sunken dry channel, drawn under everything else (props sit on its bed)
	_draw_vein()

	# the river: a long water band with gently undulating banks (not a dead-straight edge). With
	# a pixel-art tile, fill the band with tiled water drifting downstream; otherwise the flat
	# fill with a couple of drifting ripple lines. Either way a soft brighter rim traces the near
	# (top) bank where land meets water.
	if not _river.is_empty():
		var rrect: Rect2 = _river["rect"]
		var top_bank := _river_bank(rrect, rrect.position.y, _phase_for(rrect.position))
		var bot_bank := _river_bank(rrect, rrect.end.y, _phase_for(rrect.end))
		var band := PackedVector2Array()
		band.append_array(top_bank)
		for i in range(bot_bank.size() - 1, -1, -1):  # bottom bank right→left, closing the loop
			band.append(bot_bank[i])
		if _river_tex != null:
			_fill_water(band, _river_tex, _river_world_tile, _water_scroll(_river_tex, true))
		else:
			draw_colored_polygon(band, _river["color"])
			for k in 3:
				var ry := rrect.position.y + 16.0 + float(k) * 26.0
				var drift := fposmod(_time * 12.0 + float(k) * 40.0, rrect.size.x)
				var rip := Color(0.85, 0.92, 0.95, 0.16)
				draw_line(rrect.position + Vector2(drift, ry - rrect.position.y), rrect.position + Vector2(minf(drift + 70.0, rrect.size.x), ry - rrect.position.y), rip, 1.5)
		var down := PackedVector2Array()
		var up := PackedVector2Array()
		for q in top_bank:
			down.append(q + Vector2(0, SHALLOWS_INSET))
		for q in bot_bank:
			up.append(q - Vector2(0, SHALLOWS_INSET))
		_draw_shallows([down, up], _river["foam"], vis if cull else Rect2())
		draw_polyline(top_bank, Color(_river["rim"].r, _river["rim"].g, _river["rim"].b, 0.6), 2.0)

	# ponds: a tiled pixel-water surface if we have art, else a flat fill with breathing
	# ripples. Both keep a lighter rim where the bank meets the water — all the water first, then
	# the (pre-baked, see render_world) shores, so overlapping ponds join without a seam.
	var shown: Array = []  # the ponds on screen, whose shores the rim pass then draws
	for pond in _ponds:
		var center: Vector2 = pond["center"]
		var radius: float = pond["radius"]
		var rmax := radius * 1.25  # the organic bank can bulge past the nominal radius
		if cull and not vis.intersects(Rect2(center - Vector2(rmax, rmax), Vector2(rmax, rmax) * 2.0)):
			continue
		var ring: PackedVector2Array = pond["ring"]
		if _pond_tex != null:
			_fill_water(ring, _pond_tex, _pond_world_tile, _water_scroll(_pond_tex, false))
		else:
			draw_colored_polygon(ring, pond["color"])
			for k in 2:
				var t := fposmod(_time * 0.25 + float(k) * 0.5, 1.0)
				var rr := radius * (0.25 + 0.7 * t)
				draw_arc(center, rr, 0.0, TAU, 40, Color(0.85, 0.92, 0.95, 0.22 * (1.0 - t)), 1.5)
		shown.append(pond)
	for pond in shown:
		_draw_shallows(pond["shallows"], pond["foam"], vis if cull else Rect2())
		for run in pond["shore"]:
			draw_polyline(run, _water_rim, 2.0)

	# soft halos around glowing litter (a night world's glowcaps, shards, reeds, lilies)
	_draw_litter_glow(vis, cull)

	# (reeds and lily pads, over the water's edge, are drawn by _litter_over)

	# flowers (a petal dot with a bright center), nodding in the breeze (pixel flowers ride with the
	# ground's details instead)
	for f in ([] if _detail_tex != null and not _details.is_empty() else _flowers):
		if cull and not vis.has_point(f["pos"]):
			continue
		var fp: Vector2 = f["pos"] + Vector2(_sway(f["phase"], 0.45), 0.0)
		draw_circle(fp, 4.0, f["color"])
		draw_circle(fp, 1.6, Color(0.98, 0.92, 0.55))

	# the maze's hedge walls (tall, rounded, slightly extruded so they read as height)
	_draw_hedges()

	# interactable props: contact shadow, the form-hint halo, optional warm glow, then the silhouette.
	# Indexed (not a plain for-in) because the C-3 highlight set is keyed by index.
	for i in _interactables.size():
		var it: Dictionary = _interactables[i]
		if cull and not vis.has_point(it["pos"]):
			continue
		if bool(it.get("taken", false)):
			continue  # picked up (a world secret, once found): gone from the world
		_draw_prop_light(it)
		_draw_light_pool(it["type"], it["pos"])
		_draw_shadow(it["pos"] + Vector2(0, 6), 11.0, 0.16)
		if _form_highlights.has(i):
			_draw_form_highlight(it["pos"])
		_draw_glow(it["type"], it["pos"])
		var pulse: float = it["pulse"]
		if pulse > 0.0:
			draw_circle(it["pos"], 20.0 + 12.0 * pulse, Color(1, 1, 1, 0.18 * pulse))
		# stateless props with baked pixel-art get drawn from the sprite and skip the match;
		# stateful/animated ones (rock, slab, torch, …) fall through to their procedural draw
		if _try_blit_prop(it):
			continue
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
			"warden_lantern":
				_draw_warden_lantern(it["pos"], it["color"], bool(it.get("opened", false)))
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
		pts.append(center + Vector2(cos(a), sin(a)) * organic_radius(a, radius, seed))
	return pts


## The organic shoreline's distance from its centre at angle `a` — the one formula both the drawn ring
## and the pixel ground's sandy shore band (GroundLayer) read, so the sand hugs the water exactly.
static func organic_radius(a: float, radius: float, seed: float) -> float:
	var wobble := 0.11 * sin(3.0 * a + seed) + 0.06 * sin(5.0 * a - seed * 1.7) + 0.035 * sin(8.0 * a + seed * 2.3)
	return radius * (1.0 + wobble)


## Trace a closed outline (an organic shoreline) as a thin line — the waterline where the
## bank meets the water. Copies the ring (COW) and closes it back to the first point.
func _draw_ring_rim(ring: PackedVector2Array, color: Color, width: float) -> void:
	if ring.size() < 2:
		return
	var loop := ring
	loop.append(ring[0])
	draw_polyline(loop, color, width)


## Pond `index`'s shoreline as a list of open polylines: its whole ring (closed) for a lone pond, or
## just the stretches lying outside every OTHER pond's water when ponds overlap. "Inside" tests against
## the other pond's organic ring, so each gap lines up with the water that's actually drawn there.
func _shore_runs(index: int) -> Array:
	var me: Dictionary = _ponds[index]
	var ring: PackedVector2Array = me["ring"]
	var others: Array = []
	for j in _ponds.size():
		var o: Dictionary = _ponds[j]
		if j != index and (o["center"] as Vector2).distance_to(me["center"]) < (float(o["radius"]) + float(me["radius"])) * 1.3:
			others.append(o["ring"])
	if others.is_empty():
		var loop := ring.duplicate()
		loop.append(ring[0])
		return [loop]
	var n := ring.size()
	# Start the walk on open shore, so a run never wraps across the seam.
	var start := -1
	for i in n:
		if not _inside_any(ring[i], others):
			start = i
			break
	if start < 0:
		return []  # wholly inside other water: no shore of its own
	var runs: Array = []
	var run := PackedVector2Array()
	for k in n + 1:
		var p := ring[(start + k) % n]
		if _inside_any(p, others):
			if run.size() >= 2:
				runs.append(run)
			run = PackedVector2Array()
		else:
			run.append(p)
	if run.size() >= 2:
		runs.append(run)
	return runs


func _inside_any(p: Vector2, rings: Array) -> bool:
	for r in rings:
		if Geometry2D.is_point_in_polygon(p, r):
			return true
	return false


## ---- shallows + foam ---------------------------------------------------------------------------
## Just inside every waterline: a soft lighter band where the water runs shallow over the sand, and
## a scatter of foam specks that glint on and off, each on its own beat, a whole pixel at a time.
const SHALLOWS_INSET := 5.0


## A pond's shore runs pulled `inset` units toward its centre (the shallows band follows the shore,
## gaps and all, so overlapping ponds don't get a band across their shared water).
func _inset_runs(pond: Dictionary, inset: float) -> Array:
	var out: Array = []
	var c: Vector2 = pond["center"]
	for run in pond["shore"]:
		var r := PackedVector2Array()
		for q in run:
			r.append(q + (c - q).normalized() * inset)
		out.append(r)
	return out


## Foam specks just inside a set of shore polylines, toward the point `inward` (or, per run, along
## `run_dirs[i]` — a long river's banks face straight across it): [{ pos, phase, len }].
func _foam_specks(runs: Array, inward: Vector2, run_dirs: Array = []) -> Array:
	var out: Array = []
	var k := 0
	for ri in runs.size():
		var pts: PackedVector2Array = runs[ri]
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var steps := int(a.distance_to(b) / 7.0)
			for j in steps:
				k += 1
				var q := a.lerp(b, (float(j) + 0.5) / float(maxi(steps, 1)))
				var dir: Vector2 = run_dirs[ri] if ri < run_dirs.size() else (inward - q).normalized()
				var depth := 2.0 + float((k * 7) % 5)
				out.append({ "pos": (q + dir * depth).round(), "phase": fposmod(float(k) * 2.399, TAU), "len": 1.0 + float(k % 3) })
	return out


func _draw_shallows(bands: Array, foam: Array, vis := Rect2()) -> void:
	var sh := Color(_water_rim.r, _water_rim.g, _water_rim.b, 0.16)
	for band in bands:
		if (band as PackedVector2Array).size() >= 2:
			draw_polyline(band, sh, 7.0)
	var fc := Color(_water_rim.r, _water_rim.g, _water_rim.b, 0.85)
	for f in foam:
		if vis.has_area() and not vis.has_point(f["pos"]):
			continue
		# on for a moment, then off: a glint, not a glow (stepped, so it stays pixel-crisp)
		if sin(_time * 1.3 + float(f["phase"])) > 0.55:
			draw_rect(Rect2(f["pos"], Vector2(float(f["len"]), 1.0)), fc)


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


## Sample one river bank (its top or bottom edge) as a gently undulating line of points along
## the river's length, so the shore waves a little instead of running dead straight. `base_y`
## is the straight edge; the wobble comes from _river_bank_offset. Points run left→right, one
## every ~48px, with the exact right end appended so the band always spans the full width.
func _river_bank(rect: Rect2, base_y: float, seed: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := rect.position.x
	while x < rect.end.x:
		pts.append(Vector2(x, base_y + _river_bank_offset(x, seed)))
		x += 48.0
	pts.append(Vector2(rect.end.x, base_y + _river_bank_offset(rect.end.x, seed)))
	return pts


## The vertical wobble of a river bank at world-x `x` — two summed sines (a long lazy bend plus
## a shorter ripple), only ~10px at most so the shore is subtly uneven, not a pronounced curve.
## `seed` shifts the phase so the top and bottom banks wave independently, not mirroring.
func _river_bank_offset(x: float, seed: float) -> float:
	return river_bank_offset(x, seed)


## (Static so GroundLayer's shore band follows the same banks.)
static func river_bank_offset(x: float, seed: float) -> float:
	return 7.0 * sin(x * 0.017 + seed) + 3.5 * sin(x * 0.011 - seed * 1.6)


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
	if _hedge_tex != null:
		# leafy pixel foliage: the shaded front face (tile darkened), then the sunlit top
		# (same tile, shifted up), then the thin bright top edge.
		for h in _hedges:
			_fill_hedge_seg(h, Vector2.ZERO, Color(0.62, 0.62, 0.62))
		for h in _hedges:
			_fill_hedge_seg(h, lift, Color(1, 1, 1))
		for h in _hedges:
			draw_line(h["a"] + lift + Vector2(0, -1), h["b"] + lift + Vector2(0, -1), hi, float(h["t"]) * 0.42)
		return
	# flat-green fallback: front face, sunlit top (shifted up), thin top highlight
	for h in _hedges:
		draw_line(h["a"], h["b"], front, float(h["t"]))
	for h in _hedges:
		draw_line(h["a"] + lift, h["b"] + lift, top, float(h["t"]))
	for h in _hedges:
		draw_line(h["a"] + lift + Vector2(0, -1), h["b"] + lift + Vector2(0, -1), hi, float(h["t"]) * 0.42)


## The world-space rectangle a hedge run covers (its thick line as a rect). Every maze run is
## axis-aligned, so this is just the segment grown by half its thickness across its short axis.
func _hedge_rect(h: Dictionary) -> Rect2:
	var a: Vector2 = h["a"]
	var b: Vector2 = h["b"]
	var t: float = h["t"]
	if absf(a.y - b.y) < 0.5:   # horizontal run
		var x0 := minf(a.x, b.x)
		return Rect2(x0, a.y - t * 0.5, maxf(a.x, b.x) - x0, t)
	var y0 := minf(a.y, b.y)    # vertical run
	return Rect2(a.x - t * 0.5, y0, t, maxf(a.y, b.y) - y0)


## Fill a hedge run's rect (shifted by `offset` for the raised top) with the tiled leafy
## texture, modulated by `mod` (the front face darkens it). UVs are world position in
## tile-units so the foliage flows continuously across abutting runs (texture_repeat wraps).
func _fill_hedge_seg(h: Dictionary, offset: Vector2, mod: Color) -> void:
	var r := _hedge_rect(h)
	r.position += offset
	var pts := PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0.0), r.end, r.position + Vector2(0.0, r.size.y)])
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(p / _hedge_world_tile)
	draw_colored_polygon(pts, mod, uvs, _hedge_tex)


## A soft, flattened ground shadow — the cheapest, biggest depth cue we have. Drawn as
## a circle squashed vertically via the draw transform, then the transform is reset.
func _draw_shadow(pos: Vector2, r: float, alpha: float) -> void:
	var c := _style.color("shadow")
	var off := -_style.light_dir() * (r * 0.16)  # shadows fall away from the light
	draw_set_transform(pos + off, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, r, Color(c.r, c.g, c.b, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## C-3 — the form hint: a soft, slowly breathing pool of the current form's colour on the ground
## under an object that form could act on, ringed by a thin arc so it reads as deliberate rather
## than a smudge. Squashed onto the ground plane by the same draw transform trick as _draw_shadow,
## so it lies on the floor instead of floating. Deliberately quiet — the brief is a hint layer you
## notice, not a quest marker that shouts; it should feel like the world warming to your shape.
func _draw_form_highlight(p: Vector2) -> void:
	var breathe := 0.80 + 0.20 * sin(_time * _fh_pulse_speed)
	var c := _form_highlight_color
	draw_set_transform(p + Vector2(0, 5), 0.0, Vector2(1.0, 0.42))
	for k in 3:
		var rr := (_fh_radius - float(k) * 6.0) * breathe
		draw_circle(Vector2.ZERO, rr, Color(c.r, c.g, c.b, _fh_alpha * 0.30))
	draw_arc(Vector2.ZERO, _fh_radius * breathe, 0.0, TAU, 32, Color(c.r, c.g, c.b, _fh_alpha), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The Vale's GATEWAY — the hub's door to every world. Two standing stones and a lintel frame a tall
## shimmering doorway (the portal oval, scaled up) whose colour drifts slowly through the hues, since
## it leads everywhere rather than to one place. `color` is the stone-tinted base hue from the spec.
func _draw_gateway(p: Vector2, color: Color) -> void:
	var stone := Color(0.62, 0.6, 0.56)
	var stone_dark := stone.darkened(0.25)
	var center := p + Vector2(0, -30)
	# the doorway's light: hue drifts around the spec colour; alpha breathes
	var hue := color
	hue.h = fposmod(color.h + 0.08 * sin(_time * 0.35), 1.0)
	var breathe := 0.8 + 0.2 * sin(_time * 1.6)
	draw_set_transform(center, 0.0, Vector2(1.0, 1.7))
	draw_circle(Vector2.ZERO, 21.0, Color(hue.r, hue.g, hue.b, 0.22 * breathe))
	draw_circle(Vector2.ZERO, 16.0 * (0.94 + 0.06 * breathe), Color(hue.r, hue.g, hue.b, 0.5))
	draw_circle(Vector2.ZERO, 9.0, Color(1, 1, 1, 0.3 + 0.15 * breathe))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for k in 5:
		var ang := _time * 1.1 + float(k) * TAU / 5.0
		draw_circle(center + Vector2(cos(ang) * 18.0, sin(ang) * 32.0), 1.8, Color(1, 1, 1, 0.75))
	# the standing stones, each a slightly leaning slab with a darker face edge
	for side in [-1.0, 1.0]:
		var x: float = side * 27.0
		var pillar := PackedVector2Array([
			p + Vector2(x - 7, 4), p + Vector2(x + 7, 4),
			p + Vector2(x + 6 - side, -62), p + Vector2(x - 6 - side, -62)])
		draw_colored_polygon(pillar, stone)
		draw_line(p + Vector2(x + side * 6, 4), p + Vector2(x + side * 5 - side, -62), stone_dark, 2.0)
	# the lintel laid across the top
	var lintel := Rect2(p + Vector2(-38, -72), Vector2(76, 12))
	draw_rect(lintel, stone.lightened(0.06))
	draw_rect(Rect2(lintel.position + Vector2(0, 9), Vector2(lintel.size.x, 3)), stone_dark)


## A warm, breathing radial glow under the lit props (lantern, crystal). Faked with a
## few stacked translucent circles so it works everywhere without a real 2D light.
## How far into dusk the day cycle is (0 day .. 1 dusk): lamps and fires glow brighter and throw
## bigger pools of light as the evening comes on, and the fireflies come out (AmbientLife).
func set_dusk(v: float) -> void:
	_dusk = clampf(v, 0.0, 1.0)


# The things that light their surroundings, and the colour of that light on the ground.
const LIGHT_POOLS := {
	"lantern": Color(1.0, 0.84, 0.52), "torch": Color(1.0, 0.66, 0.34), "brazier": Color(1.0, 0.62, 0.30),
	"crystal": Color(0.62, 0.86, 1.0),
}


## A pool of light on the ground around a lamp or a fire, faint by day and warm at dusk.
func _draw_light_pool(type: String, p: Vector2) -> void:
	if not LIGHT_POOLS.has(type) or not _prop_lights.is_empty():
		return  # a glowing world (Nocthollow) lights its props its own way
	var c: Color = LIGHT_POOLS[type]
	var flicker := 0.92 + 0.08 * sin(_time * (5.0 if type != "crystal" and type != "lantern" else 1.4) + _phase_for(p) * 3.0)
	var a := (0.07 + 0.30 * _dusk) * flicker
	SoftGlow.draw(self, p + Vector2(0, 6), (34.0 + 22.0 * _dusk) * flicker, Color(c.r, c.g, c.b, a), 0.55)


func _draw_glow(type: String, p: Vector2) -> void:
	var warm: Color
	match type:
		"lantern":
			warm = Color(1.0, 0.85, 0.5)
		"crystal":
			warm = Color(0.6, 0.85, 1.0)
		"portal":
			warm = Color(0.74, 0.7, 1.0)
		"gateway":
			# the hub's great gate: a wider, brighter halo than a small portal, so it reads from afar
			var breathe_g := 0.85 + 0.15 * sin(_time * _glow_pulse_speed)
			for k in 4:
				draw_circle(p + Vector2(0, -30), (64.0 - float(k) * 13.0) * breathe_g, Color(0.84, 0.78, 1.0, 0.06))
			return
		_:
			return
	var breathe := 0.82 + 0.18 * sin(_time * _glow_pulse_speed)
	var top := p + Vector2(0, -22)
	var dusk_gain := 0.8 + 1.1 * _dusk   # the halo strengthens as the evening comes on
	for k in 3:
		var rr := (34.0 - float(k) * 9.0) * breathe
		draw_circle(top, rr, Color(warm.r, warm.g, warm.b, 0.07 * dusk_gain))


## A glowing world's prop light (see _prop_lights): a soft halo in the prop's own colour, a breathing
## pool on the ground, sparks drifting up from emitters — all blazing up while the prop is FLARED.
func _draw_prop_light(it: Dictionary) -> void:
	var cfg: Dictionary = _prop_lights.get(String(it["type"]), {})
	if cfg.is_empty():
		return
	var p: Vector2 = it["pos"]
	var c: Color = it["color"]
	var flare: float = it["flare"]
	var phase := _phase_for(p)
	var breathe := 0.85 + 0.15 * sin(_time * _glow_pulse_speed + phase)
	var r := float(cfg.get("radius", 26.0)) * breathe * (1.0 + FLARE_GROW * flare)
	var a := float(cfg.get("alpha", 0.30)) + 0.45 * flare
	SoftGlow.draw(self, p + Vector2(0, 4), r * 1.2, Color(c.r, c.g, c.b, a * 0.6), 0.42)
	SoftGlow.draw(self, p + Vector2(0, float(cfg.get("y", -8.0))), r, Color(c.r, c.g, c.b, a))
	var motes := int(cfg.get("motes", 0)) + (6 if flare > 0.05 else 0)
	var lc := c.lightened(0.5)
	for k in motes:
		var t := fposmod(_time * (0.22 + 0.05 * float(k % 3)) + float(k) / float(maxi(1, motes)) + phase, 1.0)
		var mp := p + Vector2(sin(t * 7.0 + float(k) * 1.7) * (4.0 + 10.0 * flare), -6.0 - t * (36.0 + 40.0 * flare))
		draw_circle(mp, 1.3, Color(lc.r, lc.g, lc.b, (1.0 - t) * 0.85))


## Blit a baked prop's sprite, bottom-centred on its ground point `p` (feet on the ground,
## like the trees/characters). Draws the fixed BASE layer, then the grayscale TINT layer
## modulated by the instance's `color` (so a lantern globe / mushroom cap / crystal takes the
## prop's own colour). No-op if this type has no baked base. `lift` nudges it up (an idle bob).
func _blit_prop_sprite(type: String, p: Vector2, color: Color, lift := 0.0) -> void:
	var base: Texture2D = _prop_base.get(type)
	if base == null:
		return
	var sz := base.get_size()
	# Feet at p + 8, matching the player/companion ground plane (SpriteSlot.draw), so props
	# sit ON the ground next to the characters instead of floating a few px above it.
	var origin := p + Vector2(-sz.x * 0.5, 8.0 - sz.y - lift)
	draw_texture(base, origin)
	var tint: Texture2D = _prop_tint.get(type)
	if tint != null:
		draw_texture(tint, origin, color)


## True (and drawn) if this prop is a plain static type with baked pixel-art — those are drawn
## straight from the sprite. Animated/stateful types (flame vessels, the hunt rocks, Ruin gates)
## return false so they keep their procedural draw (the flame ones blit their vessel themselves).
func _try_blit_prop(it: Dictionary) -> bool:
	var t := String(it["type"])
	if _PROP_OVERLAY.has(t) or not _prop_base.has(t):
		return false
	_blit_prop_sprite(t, it["pos"], it["color"])
	return true


## The last Warden's lantern (W-1): an old iron lantern on a stone post before the great door. Dark and
## cold until it's relit (`lit`); then a warm flame and a pool of light. `size` scales it (the keepsake).
func _draw_warden_lantern(p: Vector2, color: Color, lit: bool, size := 1.0) -> void:
	var s := size
	draw_rect(Rect2(p + Vector2(-4, -2) * s, Vector2(8, 10) * s), Color(0.42, 0.4, 0.38))
	draw_rect(Rect2(p + Vector2(-1.5, -14) * s, Vector2(3, 12) * s), Color(0.26, 0.22, 0.2))
	var cage := Rect2(p + Vector2(-6, -28) * s, Vector2(12, 14) * s)
	if lit:
		var flicker := 0.85 + 0.15 * sin(_time * 7.0 + _phase_for(p))
		SoftGlow.draw(self, p + Vector2(0, -21) * s, 34.0 * s * flicker, Color(1.0, 0.76, 0.42, 0.32 * flicker), 0.6)
		draw_rect(cage, Color(1.0, 0.82, 0.5, 0.55))
		draw_circle(p + Vector2(0, -21) * s, 3.2 * s * flicker, Color(1.0, 0.9, 0.6))
	else:
		draw_rect(cage, Color(0.12, 0.12, 0.14, 0.7))
	draw_rect(cage, color.darkened(0.3), false, 1.5 * s)
	draw_line(cage.position + Vector2(cage.size.x * 0.5, 0), cage.position + Vector2(cage.size.x * 0.5, cage.size.y), color.darkened(0.3), 1.0)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-7, -28) * s, p + Vector2(7, -28) * s, p + Vector2(0, -34) * s]), color.darkened(0.2))


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
		"hedge_seed":
			# a curled seed nestled in a small cushion of moss, with the faint green warmth of
			# something alive inside: the hedge maze's secret, resting at its heart
			var warm := 0.75 + 0.25 * sin(_time * 1.6)
			draw_circle(p + Vector2(0, -2), 15.0, Color(0.62, 0.9, 0.5, 0.12 * warm))
			draw_circle(p + Vector2(-5, 4), 7.0, Color(0.34, 0.5, 0.3))
			draw_circle(p + Vector2(5, 4), 6.5, Color(0.38, 0.55, 0.32))
			draw_circle(p + Vector2(0, 2), 7.5, Color(0.42, 0.6, 0.34))
			draw_circle(p + Vector2(0, -3), 5.0, color)
			draw_arc(p + Vector2(1, -3), 3.0, -PI * 0.2, PI * 1.3, 10, color.darkened(0.35), 1.5)
			draw_circle(p + Vector2(-1.5, -5), 1.2, color.lightened(0.4))
			draw_line(p + Vector2(3, -7), p + Vector2(6, -11), Color(0.55, 0.82, 0.42), 1.5)
		"potted_hedge":
			# the hedge seed's keepsake (HS-6): a clay pot holding a tiny spiral of clipped hedge
			draw_rect(Rect2(p + Vector2(-9, -2), Vector2(18, 11)), Color(0.66, 0.4, 0.28))
			draw_rect(Rect2(p + Vector2(-10, -4), Vector2(20, 4)), Color(0.74, 0.47, 0.32))
			draw_line(p + Vector2(-8, 4), p + Vector2(8, 4), Color(0.56, 0.33, 0.22), 1.0)
			draw_circle(p + Vector2(0, -11), 9.0, color.darkened(0.25))
			draw_circle(p + Vector2(0, -12), 8.0, color)
			draw_arc(p + Vector2(0, -12), 5.5, 0.2, TAU * 0.85, 14, color.darkened(0.4), 1.5)
			draw_arc(p + Vector2(0.8, -12), 2.6, 1.4, TAU * 0.95, 10, color.darkened(0.4), 1.5)
			draw_circle(p + Vector2(-3, -16), 1.3, color.lightened(0.35))
		"journal_stand":
			# a little wooden lectern with an open book: the home's journal (HS-5)
			draw_rect(Rect2(p + Vector2(-2, -6), Vector2(4, 14)), color.darkened(0.2))
			draw_rect(Rect2(p + Vector2(-7, 6), Vector2(14, 3)), color.darkened(0.3))
			var top := PackedVector2Array([p + Vector2(-12, -8), p + Vector2(12, -8), p + Vector2(10, -16), p + Vector2(-10, -16)])
			draw_colored_polygon(top, color)
			draw_rect(Rect2(p + Vector2(-10, -18), Vector2(9, 8)), Color(0.96, 0.93, 0.84))
			draw_rect(Rect2(p + Vector2(1, -18), Vector2(9, 8)), Color(0.93, 0.9, 0.8))
			draw_line(p + Vector2(0, -18), p + Vector2(0, -10), Color(0.6, 0.5, 0.4), 1.0)
			for k in 3:
				draw_line(p + Vector2(-8, -16 + k * 2), p + Vector2(-3, -16 + k * 2), Color(0.55, 0.5, 0.45), 1.0)
				draw_line(p + Vector2(3, -16 + k * 2), p + Vector2(8, -16 + k * 2), Color(0.55, 0.5, 0.45), 1.0)
		"kept_lantern":
			# the Ruin's keepsake (W-1): the last Warden's lantern, small now, and lit for good
			_draw_warden_lantern(p + Vector2(0, 4), color, true, 0.75)
		"mere_pearl":
			# Nocthollow's secret (W-2): a pale pearl that rose to the Mere's shore, glowing softly
			var pearl_glow := 0.8 + 0.2 * sin(_time * 1.3)
			SoftGlow.draw(self, p + Vector2(0, -3), 16.0, Color(0.62, 0.92, 1.0, 0.35 * pearl_glow), 0.7)
			draw_circle(p + Vector2(0, 2), 6.0, Color(0.2, 0.3, 0.36, 0.5))
			draw_circle(p + Vector2(0, -3), 5.0, color)
			draw_circle(p + Vector2(-1.5, -4.5), 1.6, Color(1, 1, 1, 0.9))
		"mere_jar":
			# its keepsake: a little stoppered jar with a light from the Mere drifting inside
			var jar_glow := 0.75 + 0.25 * sin(_time * 1.1)
			SoftGlow.draw(self, p + Vector2(0, -6), 14.0, Color(0.62, 0.92, 1.0, 0.3 * jar_glow), 0.7)
			draw_rect(Rect2(p + Vector2(-6, -12), Vector2(12, 16)), Color(0.8, 0.92, 0.96, 0.35))
			draw_rect(Rect2(p + Vector2(-6, -12), Vector2(12, 16)), Color(0.86, 0.96, 1.0, 0.7), false, 1.0)
			draw_rect(Rect2(p + Vector2(-4, -16), Vector2(8, 4)), Color(0.62, 0.46, 0.32))
			draw_circle(p + Vector2(sin(_time * 0.9) * 2.0, -5 + cos(_time * 0.7) * 2.0), 2.6, color)
			draw_circle(p + Vector2(sin(_time * 0.9) * 2.0, -5 + cos(_time * 0.7) * 2.0), 1.0, Color(1, 1, 1, 0.9))
		"elder_salamander":
			# the Riverbank's secret (W-3): an old golden salamander sunning on its stone
			draw_circle(p + Vector2(0, 5), 13.0, Color(0.5, 0.5, 0.48))
			draw_circle(p + Vector2(-2, 3), 11.0, Color(0.6, 0.6, 0.56))
			var sal_breath := sin(_time * 1.4) * 0.6
			var body := PackedVector2Array([p + Vector2(-11, 0), p + Vector2(-4, -3 - sal_breath), p + Vector2(6, -2), p + Vector2(10, 0), p + Vector2(6, 2), p + Vector2(-4, 3 + sal_breath)])
			draw_colored_polygon(body, color)
			draw_line(p + Vector2(-11, 0), p + Vector2(-17, -3), color.darkened(0.1), 2.0)
			for leg in [Vector2(-5, -3), Vector2(-5, 3), Vector2(4, -2), Vector2(4, 2)]:
				draw_line(p + leg, p + leg + Vector2(-1, signf(leg.y) * 4.0), color.darkened(0.2), 1.5)
			draw_circle(p + Vector2(10, 0), 3.0, color.lightened(0.1))
			draw_circle(p + Vector2(11, -1), 0.9, Color(0.15, 0.1, 0.05))
			for spot in [Vector2(-6, 0), Vector2(-1, -1), Vector2(3, 0)]:
				draw_circle(p + spot, 1.0, color.lightened(0.35))
		"elder_scale":
			# its keepsake: one shed golden scale, laid on a scrap of river-cloth
			draw_circle(p + Vector2(0, 3), 9.0, Color(0.42, 0.56, 0.62))
			var scale_pts := PackedVector2Array([p + Vector2(0, -9), p + Vector2(6, -2), p + Vector2(4, 5), p + Vector2(-4, 5), p + Vector2(-6, -2)])
			draw_colored_polygon(scale_pts, color)
			draw_line(p + Vector2(0, -8), p + Vector2(0, 4), color.lightened(0.35), 1.0)
			draw_circle(p + Vector2(-2, -3), 1.2, Color(1, 1, 0.9, 0.8 + 0.2 * sin(_time * 2.0)))
		"river_drop":
			# the Bazaar's secret (W-5) and its keepsake: a single drop of river-glass holding a ripple of light
			var drop_glow := 0.7 + 0.3 * sin(_time * 1.6)
			SoftGlow.draw(self, p + Vector2(0, -4), 15.0, Color(color.r, color.g, color.b, 0.35 * drop_glow), 0.7)
			var drop := PackedVector2Array([p + Vector2(0, -12), p + Vector2(5, -2), p + Vector2(4, 3), p + Vector2(0, 5), p + Vector2(-4, 3), p + Vector2(-5, -2)])
			draw_colored_polygon(drop, Color(color.r, color.g, color.b, 0.85))
			draw_arc(p + Vector2(0, -1), 2.5 + 1.5 * fmod(_time * 0.6, 1.0), 0.0, TAU, 14, Color(1, 1, 1, 0.6 * (1.0 - fmod(_time * 0.6, 1.0))), 1.0)
			draw_circle(p + Vector2(-1.5, -5), 1.2, Color(1, 1, 1, 0.9))
		"stallholder":
			# a stallholder minding their stall (the Bazaar's packed market): the shopkeeper figure in their
			# own colours, with a little idle bob, offset so each seems to breathe on their own
			var holder_bob := sin(_time * 1.5 + _phase_for(p) * 2.0) * 1.0
			if _prop_base.has("shopkeeper"):
				_blit_prop_sprite("shopkeeper", p, color, holder_bob)
			else:
				draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 8), p + Vector2(7, 8), p + Vector2(5, -8 + holder_bob), p + Vector2(-5, -8 + holder_bob)]), color)
				draw_circle(p + Vector2(0, -14 + holder_bob), 5.0, Color(0.92, 0.76, 0.62))
		"hedge_sprout":
			# the seed, grown: a young sapling curling up out of a moss mound, a few bright leaves
			draw_circle(p + Vector2(0, 5), 11.0, Color(0.34, 0.5, 0.3))
			draw_circle(p + Vector2(-3, 3), 7.0, Color(0.4, 0.58, 0.34))
			draw_line(p + Vector2(0, 2), p + Vector2(-1, -14), Color(0.42, 0.32, 0.22), 2.5)
			draw_arc(p + Vector2(3, -16), 4.0, PI * 0.6, PI * 1.9, 10, Color(0.42, 0.32, 0.22), 2.0)
			for leaf in [Vector2(-7, -10), Vector2(6, -8), Vector2(-4, -19), Vector2(7, -19), Vector2(0, -24)]:
				draw_circle(p + leaf, 4.0, color)
				draw_circle(p + leaf + Vector2(-1, -1), 1.4, color.lightened(0.35))
		"dig_mound":
			# a low hump of loose, turned earth — a couple of overlapping mounds with a darker
			# scuffed crown, reading as "something's been buried here" (a fox form can dig it up)
			draw_circle(p + Vector2(-4, 3), 9.0, color.darkened(0.1))
			draw_circle(p + Vector2(5, 3), 8.0, color)
			draw_circle(p + Vector2(0, -1), 10.0, color.lightened(0.06))
			for s in [Vector2(-3, -3), Vector2(3, -1), Vector2(0, 2)]:
				draw_circle(p + s, 1.6, color.darkened(0.28))
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
			# a friendly standing figure behind the counter, with a little idle bob so they read
			# as alive rather than a prop. Baked sprite (bobbing) if we have it, else procedural.
			var keeper_bob := sin(_time * 1.6 + _phase_for(p)) * 1.0
			if _prop_base.has("shopkeeper"):
				_blit_prop_sprite("shopkeeper", p, color, keeper_bob)
			else:
				var keeper_skin := Color(0.92, 0.76, 0.62)
				var keeper_body := PackedVector2Array([
					p + Vector2(-7, 8), p + Vector2(7, 8), p + Vector2(5, -8 + keeper_bob), p + Vector2(-5, -8 + keeper_bob)])
				draw_colored_polygon(keeper_body, color)
				draw_line(p + Vector2(0, -6 + keeper_bob), p + Vector2(0, 6), color.darkened(0.2), 1.0)
				draw_circle(p + Vector2(0, -14 + keeper_bob), 5.0, keeper_skin)
				draw_arc(p + Vector2(0, -14 + keeper_bob), 5.0, PI, TAU, 12, color.darkened(0.1), 3.0)
		"gateway":
			_draw_gateway(p, color)
		"portal":
			# an upright shimmering doorway, gently breathing, with sparks circling its rim
			var center := p + Vector2(0, -18)
			if _portal_tex != null:
				# the baked pixel-art energy oval, tinted this portal's colour; its alpha breathes
				var breathe := 0.82 + 0.18 * sin(_time * 2.0)
				var sz := _portal_tex.get_size()
				draw_texture(_portal_tex, center - sz * 0.5, Color(color.r, color.g, color.b, breathe))
				draw_circle(center, 3.0 + 0.8 * sin(_time * 2.0), Color(1, 1, 1, 0.5))  # hot core pulse
				for k in 3:
					var ang := _time * 1.6 + float(k) * TAU / 3.0
					draw_circle(center + Vector2(cos(ang) * 11.0, sin(ang) * 20.0), 1.6, Color(1, 1, 1, 0.7))
			else:
				# procedural fallback: upright shimmering ovals, gently breathing, sparks circling
				var sway := 0.9 + 0.1 * sin(_time * 2.0)
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
	# the cracked bowl (baked sprite if we have it, else the procedural arc)
	# the coals/mote follow the bowl: when we blit the baked bowl (dropped to the p+8 ground
	# plane) they drop with it so they stay in the bowl rather than hovering above it.
	var bp := (p + Vector2(0, 6.0)) if _prop_base.has("ember") else p
	if _prop_base.has("ember"):
		_blit_prop_sprite("ember", p, color)
	else:
		draw_arc(p + Vector2(0, 2), 9.0, 0.1, PI - 0.1, 14, Color(0.34, 0.30, 0.26), 3.0)
	if kindled:
		var breathe := 0.78 + 0.22 * sin(_time * 3.0)
		for k in 3:
			draw_circle(bp + Vector2(0, -2), (16.0 - float(k) * 5.0) * breathe, Color(color.r, color.g, color.b, 0.10))
		draw_circle(bp + Vector2(0, -1), 5.5, color)
		draw_circle(bp + Vector2(-1, -2), 2.5, Color(1, 0.95, 0.8))
		# the carryable mote, hovering
		var bob := sin(_time * 2.2) * 2.0
		draw_circle(bp + Vector2(0, -16 + bob), 3.0, Color(1.0, 0.92, 0.7, 0.9))
		draw_circle(bp + Vector2(0, -16 + bob), 6.0, Color(1.0, 0.9, 0.6, 0.18))
	else:
		draw_circle(bp + Vector2(0, -1), 5.0, Color(0.22, 0.16, 0.14))
		draw_circle(bp + Vector2(-1, -2), 1.6, Color(0.55, 0.22, 0.14, 0.7 + 0.2 * sin(_time * 1.5)))


## The Cistern's brazier — a bowl on a stand. COLD: dark and dead. LIT (opened): full of warm flame
## with a breathing glow, the moment the companion's carried light catches and the dark lifts.
func _draw_brazier(p: Vector2, color: Color, lit: bool) -> void:
	# stand + bowl (baked sprite if we have it, else the procedural stand/bowl)
	# the flame/coals follow the bowl: when we blit the baked bowl (dropped to the p+8 ground
	# plane) they drop with it so the fire sits in the bowl rather than above it.
	var fp := (p + Vector2(0, 6.0)) if _prop_base.has("brazier") else p
	if _prop_base.has("brazier"):
		_blit_prop_sprite("brazier", p, color)
	else:
		draw_rect(Rect2(p + Vector2(-2.5, -2), Vector2(5, 16)), color.darkened(0.25))
		draw_rect(Rect2(p + Vector2(-9, 12), Vector2(18, 3)), color.darkened(0.2))
		var bowl := PackedVector2Array([p + Vector2(-11, -8), p + Vector2(11, -8), p + Vector2(7, 0), p + Vector2(-7, 0)])
		draw_colored_polygon(bowl, color.darkened(0.1))
	if lit:
		var warm := Color(1.0, 0.78, 0.40)
		var breathe := 0.8 + 0.2 * sin(_time * _glow_pulse_speed)
		for k in 3:
			draw_circle(fp + Vector2(0, -10), (40.0 - float(k) * 11.0) * breathe, Color(warm.r, warm.g, warm.b, 0.08))
		# a couple of flame tongues
		var f := sin(_time * 6.0) * 2.0
		draw_colored_polygon(PackedVector2Array([fp + Vector2(-6, -8), fp + Vector2(0, -8), fp + Vector2(-2 + f, -22)]), Color(1.0, 0.66, 0.28))
		draw_colored_polygon(PackedVector2Array([fp + Vector2(0, -8), fp + Vector2(7, -8), fp + Vector2(3 + f, -19)]), Color(1.0, 0.80, 0.42))
		draw_circle(fp + Vector2(0, -9), 4.0, Color(1, 0.95, 0.8))
	else:
		# cold coals
		draw_circle(fp + Vector2(-3, -7), 2.2, Color(0.18, 0.18, 0.18))
		draw_circle(fp + Vector2(3, -7), 2.2, Color(0.16, 0.16, 0.16))


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
	# a faint catch-light so it reads as "look here" (procedural over sprite or fallback); its
	# height differs because the sprite is feet-anchored while the fallback is centred on p.
	var glint := Color(0.9, 0.86, 0.7, 0.10 + 0.06 * sin(_time * 1.3))
	if _prop_base.has("carving"):
		_blit_prop_sprite("carving", p, color)
		draw_arc(p + Vector2(0, -22), 13.0, PI * 1.1, PI * 1.9, 14, glint, 1.5)
	else:
		draw_rect(Rect2(p + Vector2(-17, -24), Vector2(34, 42)), color.darkened(0.35))   # the recessed panel
		draw_rect(Rect2(p + Vector2(-15, -22), Vector2(30, 38)), color.darkened(0.18))
		var c := Color(color.r, color.g, color.b, 0.85)
		for sx in [-7, 7]:                                  # two figures, side by side
			draw_rect(Rect2(p + Vector2(sx - 2, -12), Vector2(4, 13)), c)
			draw_circle(p + Vector2(sx, -15), 2.6, c)
		draw_circle(p + Vector2(0, 6), 2.6, c)             # a companion shape between/below them
		draw_arc(p + Vector2(0, -3), 13.0, PI * 1.1, PI * 1.9, 14, glint, 1.5)


## A wall TORCH — sconce + a flickering warm flame and a breathing glow pool (animation). Placeholder.
func _draw_torch(p: Vector2, color: Color) -> void:
	# the flame follows the vessel: when we blit the baked bracket (dropped to the p+8 ground
	# plane) the flame drops with it, so it keeps sitting on the torch head, not floating above.
	var fp := (p + Vector2(0, 6.0)) if _prop_base.has("torch") else p
	# a fast, irregular flicker from two out-of-phase sines (cheap "fire")
	var flick := 0.72 + 0.18 * sin(_time * 11.0 + p.x) + 0.10 * sin(_time * 23.0 + p.y)
	for k in 3:                                          # the glow pool
		draw_circle(fp + Vector2(0, -10), (46.0 - float(k) * 13.0) * flick, Color(color.r, color.g, color.b, 0.07))
	if _prop_base.has("torch"):
		_blit_prop_sprite("torch", p, color)             # baked bracket + torch head
	else:
		draw_rect(Rect2(p + Vector2(-2, -8), Vector2(4, 14)), Color(0.28, 0.22, 0.16))   # bracket
	var f := sin(_time * 9.0 + p.x) * 1.6
	draw_colored_polygon(PackedVector2Array([fp + Vector2(-4, -8), fp + Vector2(4, -8), fp + Vector2(f, -22 - 4.0 * flick)]), Color(1.0, 0.64, 0.26))
	draw_colored_polygon(PackedVector2Array([fp + Vector2(-2, -8), fp + Vector2(2, -8), fp + Vector2(f * 0.5, -16 - 2.0 * flick)]), Color(1.0, 0.86, 0.5))
	draw_circle(fp + Vector2(0, -9), 2.2, Color(1, 0.95, 0.8))


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
