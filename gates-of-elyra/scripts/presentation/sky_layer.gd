class_name SkyLayer
extends Node2D
## The BACKDROP of a sky-island world (Loftreach): the open sky, a sea of cloud drifting far below, and the
## islands and rope bridges standing in it. WorldArt builds one when the world spec has a `sky` block and
## stops drawing its own ground; this node sits BEHIND WorldArt's drawing, so every prop, tree and character
## lands on top of it. (The overhead things, the windmill's sails, kites, the high-cloud picture and the
## flying bird, are SkyAir, a child of this node drawn above everything.)
##
## Everything static is baked ONCE into meshes at build time (an island's turf, its cliff and tapering rock,
## a bridge's planks in chunks), so a frame is a handful of mesh draws no matter how many planks or edges,
## and nothing is drawn for an island or bridge the camera cannot see. The cloud sea is ~150 sprite quads of
## the same few textures (batched), culled to the view, drifting on a slow parallax so the islands feel high.
## Pure presentation: collision and walkability are SkyRealm, from the very same island and bridge data.
##
## The `sky` block (see tools/gen_loftreach_world.py): colors {top, mid, bottom}, turf / rock / details textures,
## clouds {textures, count, parallax, drift, alpha, seed}, cliff_depth, shadow, litter_density, islands, bridges,
## windmills, kites, picture.

const TILE := 128.0
const PLANK_PITCH := 10.0
const PLANKS_PER_CHUNK := 6

var _sky: Dictionary = {}
var _bounds := Rect2()
var _turf: Texture2D = null
var _rock: Texture2D = null
var _details: Texture2D = null
var _detail_rects := {}
var _sky_tex: Texture2D = null
var _cloud_tex: Array = []
var _clouds: Array = []         # [{ pos, tex, scale, alpha, par, speed }]
var _cloud_field := Rect2()
var _drift := Vector2(9.0, -3.0)
var _cloud_alpha := 0.9
var _islands: Array = []        # [{ id, poly, box, belly: Mesh, top: Mesh, litter: Array, center, shadow: PackedVector2Array }]
var _bridges: Array = []        # [{ id, a, b, u, n, w, hidden, reveal, length, chunks: Array, posts: Array, head_only }]
var _shadow_color := Color(0.28, 0.40, 0.62, 0.30)
var _depth := 58.0
var _time := 0.0
var _air: SkyAir = null


func _ready() -> void:
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


## Lay the sky out from the world's `sky` block. Called by WorldArt.render_world (and again on a re-render).
func build(sky: Dictionary, bounds: Rect2) -> void:
	_sky = sky
	_bounds = bounds
	_turf = _load(String(sky.get("turf", "")))
	_rock = _load(String(sky.get("rock", "")))
	_details = _load(String(sky.get("details", "")))
	_detail_rects.clear()
	var idx_path := String(sky.get("details_index", ""))
	if _details != null and idx_path != "" and FileAccess.file_exists(idx_path):
		var idx: Dictionary = WorldData.load_json(idx_path)
		for n in idx:
			var r: Array = idx[n]
			_detail_rects[n] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	_depth = float(sky.get("cliff_depth", 58.0))
	_shadow_color = Color(0.28, 0.40, 0.62, 0.30)
	if sky.has("shadow"):
		var sh: Array = sky["shadow"]
		_shadow_color = Color(float(sh[0]), float(sh[1]), float(sh[2]), float(sh[3]))
	_sky_tex = _gradient(sky.get("colors", {}))
	_build_clouds(sky.get("clouds", {}))
	_build_islands()
	_build_bridges()
	if is_instance_valid(_air):
		_air.queue_free()
	_air = SkyAir.new()
	_air.name = "SkyAir"
	add_child(_air)
	_air.build(sky, self)
	queue_redraw()


func air() -> SkyAir:
	return _air


func _load(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


func _gradient(colors: Dictionary) -> Texture2D:
	var top := WorldData.to_color(colors.get("top", [0.46, 0.70, 0.96]))
	var mid := WorldData.to_color(colors.get("mid", [0.66, 0.84, 0.99]))
	var bot := WorldData.to_color(colors.get("bottom", [0.90, 0.95, 1.0]))
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bot)
	g.add_point(0.5, mid)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	t.width = 8
	t.height = 256
	return t


# ------------------------------------------------------------------------------------------ clouds
func _build_clouds(cfg: Dictionary) -> void:
	_clouds.clear()
	_cloud_tex.clear()
	for n in cfg.get("textures", []):
		var t := _load("res://assets/sprites/%s.png" % String(n))
		if t != null:
			_cloud_tex.append(t)
	var d: Array = cfg.get("drift", [9.0, -3.0])
	_drift = Vector2(float(d[0]), float(d[1]))
	_cloud_alpha = float(cfg.get("alpha", 0.9))
	if _cloud_tex.is_empty():
		return
	var par: float = float(cfg.get("parallax", 0.72))
	_cloud_field = _bounds.grow(800.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 17))
	for i in int(cfg.get("count", 150)):
		var far := rng.randf() < 0.45
		_clouds.append({
			"pos": _cloud_field.position + Vector2(rng.randf() * _cloud_field.size.x, rng.randf() * _cloud_field.size.y),
			"tex": rng.randi() % _cloud_tex.size(),
			"scale": [1.0, 1.5, 2.0][rng.randi() % 3] * (0.75 if far else 1.0),
			"alpha": (0.55 if far else 0.9) * rng.randf_range(0.8, 1.0),
			"par": par - (0.14 if far else 0.0),
			"speed": rng.randf_range(0.6, 1.5) * (0.7 if far else 1.0),
		})
	_clouds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["par"]) < float(b["par"]))


# ------------------------------------------------------------------------------------------ islands
func _build_islands() -> void:
	_islands.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for isl in _sky.get("islands", []):
		var poly := SkyRealm.poly_points(isl)
		var c := SkyRealm.centroid(poly)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in poly:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var radius := maxf(hi.x - lo.x, hi.y - lo.y) * 0.5
		var box := Rect2(lo, hi - lo)
		box.size.y += _depth + radius * 0.75 + 40.0
		box = box.grow(30.0)
		var shadow := PackedVector2Array()
		for p in poly:
			shadow.append(c + (p - c) * 0.9 + Vector2(40.0, _depth + radius * 0.8 + 70.0))
		var entry := {
			"id": String(isl.get("id", "")), "poly": poly, "box": box, "center": c, "radius": radius,
			"belly": _belly_mesh(poly, c, radius), "top": _top_mesh(poly), "shadow": shadow,
			"litter": _scatter_litter(poly, rng),
		}
		_islands.append(entry)
	_islands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["center"] as Vector2).y < (b["center"] as Vector2).y)


func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


func _scatter_litter(poly: PackedVector2Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if _details == null or _detail_rects.is_empty():
		return out
	var names := ["tuft_a", "tuft_a", "tuft_a", "tuft_b", "tuft_b", "clover", "clover", "daisy", "windflower", "poppy", "buttercup", "buttercup", "pebbles", "feather"]
	var n := int(_area(poly) * float(_sky.get("litter_density", 0.0005)))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var tries := 0
	while out.size() < n and tries < n * 6:
		tries += 1
		var p := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		var name := String(names[rng.randi() % names.size()])
		if not _detail_rects.has(name):
			continue
		var cluster := rng.randi_range(1, 3)
		for k in cluster:
			var q := p + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-8.0, 8.0))
			if Geometry2D.is_point_in_polygon(q, poly):
				out.append({ "pos": q, "rect": _detail_rects[name] })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["pos"] as Vector2).y < (b["pos"] as Vector2).y)
	return out


func _mesh(verts: PackedVector2Array, cols: PackedColorArray, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	if uvs.size() == verts.size():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if idx.size() > 0:
		arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## The island's top: its outline triangulated once, the turf tile mapped by world position (so the pixel grid is
## fixed to the world), a touch of lushness toward the middle.
func _top_mesh(poly: PackedVector2Array) -> ArrayMesh:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return null
	var c := SkyRealm.centroid(poly)
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for p in poly:
		cols.append(Color(1, 1, 1, 1))
		uvs.append(p / TILE)
	var _unused := c
	return _mesh(poly, cols, uvs, idx)


## The cliff face under the lip (quads dropped from every edge, lit from the upper left and darker lower down),
## the island's underside (the outline dropped by the cliff depth, then a fan of rock closing to a point below).
func _belly_mesh(poly: PackedVector2Array, c: Vector2, radius: float) -> ArrayMesh:
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := poly.size()
	var drop := Vector2(0.0, _depth)
	# the closing point: below the middle, a little toward the wind
	var apex := c + Vector2(radius * 0.12, _depth + radius * 0.75)
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var edge := b - a
		var normal := Vector2(edge.y, -edge.x).normalized()
		# the outward normal: pointing away from the centre
		if normal.dot((a + b) * 0.5 - c) < 0.0:
			normal = -normal
		var lit_f := clampf(0.82 - normal.x * 0.22 + normal.y * 0.06, 0.55, 1.05)
		var top_col := Color(lit_f, lit_f * 0.98, lit_f * 0.96, 1.0)
		var bot_col := Color(lit_f * 0.62, lit_f * 0.6, lit_f * 0.66, 1.0)
		var base := verts.size()
		verts.append_array(PackedVector2Array([a, b, b + drop, a + drop]))
		cols.append_array(PackedColorArray([top_col, top_col, bot_col, bot_col]))
		uvs.append_array(PackedVector2Array([a / TILE, b / TILE, (b + drop) / TILE, (a + drop) / TILE]))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		# the fan triangle closing to the apex
		var f := verts.size()
		var fc := Color(lit_f * 0.62, lit_f * 0.6, lit_f * 0.66, 1.0)
		var tip := Color(0.30, 0.28, 0.36, 1.0)
		verts.append_array(PackedVector2Array([a + drop, b + drop, apex]))
		cols.append_array(PackedColorArray([fc, fc, tip]))
		uvs.append_array(PackedVector2Array([(a + drop) / TILE, (b + drop) / TILE, apex / TILE]))
		idx.append_array(PackedInt32Array([f, f + 1, f + 2]))
	return _mesh(verts, cols, uvs, idx)


# ------------------------------------------------------------------------------------------ bridges
func _build_bridges() -> void:
	_bridges.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for b in _sky.get("bridges", []):
		var ends := SkyRealm.bridge_ends(b)
		var a: Vector2 = ends[0]
		var c: Vector2 = ends[1]
		var length := a.distance_to(c)
		var u := (c - a) / maxf(1.0, length)
		var n := u.orthogonal()
		var w := SkyRealm.bridge_width(b)
		var hw := w * 0.5 - 4.0
		var planks := int(length / PLANK_PITCH)
		var chunks: Array = []
		var i := 0
		while i < planks:
			var verts := PackedVector2Array()
			var cols := PackedColorArray()
			var idx := PackedInt32Array()
			for k in range(i, mini(planks, i + PLANKS_PER_CHUNK)):
				var s0 := 3.0 + float(k) * PLANK_PITCH
				var s1 := s0 + PLANK_PITCH - 2.0
				var shade := rng.randf_range(0.86, 1.06)
				var wood := Color(0.66 * shade, 0.49 * shade, 0.31 * shade, 1.0)
				var under := Color(0.34 * shade, 0.24 * shade, 0.2 * shade, 1.0)
				var pts := [a + u * s0 - n * hw, a + u * s1 - n * hw, a + u * s1 + n * hw, a + u * s0 + n * hw]
				for layer in 2:
					var off := Vector2(0.0, 5.0) if layer == 0 else Vector2.ZERO
					var col := under if layer == 0 else wood
					var base := verts.size()
					for p in pts:
						verts.append(p + off)
						cols.append(col)
					idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
			chunks.append({ "mesh": _mesh(verts, cols, PackedVector2Array(), idx), "from": float(i) * PLANK_PITCH, "to": float(mini(planks, i + PLANKS_PER_CHUNK)) * PLANK_PITCH })
			i += PLANKS_PER_CHUNK
		var hidden := bool(b.get("hidden", false))
		var box := Rect2(a, Vector2.ZERO).expand(c).grow(w + 60.0)
		_bridges.append({
			"id": String(b.get("id", "")), "a": a, "b": c, "u": u, "n": n, "w": w, "hw": hw, "length": length, "box": box,
			"hidden": hidden, "reveal": 1.0 if (not hidden or SkyRealm.is_open(b, _sky)) else 0.0, "chunks": chunks,
		})


## 0 (not there) .. 1 (all of it) for a hidden bridge: it unspools from its head toward the far end.
func set_bridge_reveal(id: String, t: float) -> void:
	for b in _bridges:
		if String(b["id"]) == id:
			b["reveal"] = clampf(t, 0.0, 1.0)
	queue_redraw()


func bridge_reveal(id: String) -> float:
	for b in _bridges:
		if String(b["id"]) == id:
			return float(b["reveal"])
	return 1.0


## Where a bridge's far edge of unspooling has reached right now (for sparkles), or the head if hidden.
func bridge_front(id: String) -> Vector2:
	for b in _bridges:
		if String(b["id"]) == id:
			return (b["a"] as Vector2) + (b["u"] as Vector2) * float(b["length"]) * float(b["reveal"])
	return Vector2.ZERO


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# ------------------------------------------------------------------------------------------ drawing
func _draw() -> void:
	var vis := ViewCull.visible_world_rect(self, 120.0)
	var cull := vis.has_area()
	var center := vis.get_center() if cull else _bounds.get_center()

	if _sky_tex != null:
		draw_texture_rect(_sky_tex, _bounds.grow(200.0), false)
	_draw_clouds(vis, cull, center)
	# every shadow on the cloud sea first, so none of them falls across an island or a bridge
	for isl in _islands:
		if not cull or vis.intersects(isl["box"]):
			draw_colored_polygon(isl["shadow"], _shadow_color)
	for b in _bridges:
		if (not cull or vis.intersects(b["box"])) and float(b["reveal"]) > 0.0:
			var a: Vector2 = b["a"]
			var u: Vector2 = b["u"]
			var far := a + u * float(b["length"]) * float(b["reveal"])
			draw_line(a + Vector2(30.0, _depth + 90.0), far + Vector2(30.0, _depth + 90.0), _shadow_color, float(b["w"]) * 0.8)
	for isl in _islands:
		if cull and not vis.intersects(isl["box"]):
			continue
		_draw_island(isl)
	for b in _bridges:
		if cull and not vis.intersects(b["box"]):
			continue
		_draw_bridge(b)


func _draw_clouds(vis: Rect2, cull: bool, center: Vector2) -> void:
	if _clouds.is_empty():
		return
	var field := _cloud_field
	for c in _clouds:
		var par: float = c["par"]
		var t: Texture2D = _cloud_tex[int(c["tex"])]
		var sc: float = c["scale"]
		var size := t.get_size() * sc
		var p: Vector2 = c["pos"]
		var wx := field.position.x + fposmod(p.x - field.position.x + _drift.x * _time * float(c["speed"]), field.size.x)
		var wy := field.position.y + fposmod(p.y - field.position.y + _drift.y * _time * float(c["speed"]), field.size.y)
		var pos := Vector2(wx, wy) + center * (1.0 - par)
		var r := Rect2(pos - size * 0.5, size)
		if cull and not vis.intersects(r):
			continue
		draw_texture_rect(t, r, false, Color(1, 1, 1, float(c["alpha"]) * _cloud_alpha))


func _draw_island(isl: Dictionary) -> void:
	if isl["belly"] != null and _rock != null:
		draw_mesh(isl["belly"], _rock)
	if isl["top"] != null and _turf != null:
		draw_mesh(isl["top"], _turf)
	var poly: PackedVector2Array = isl["poly"]
	var loop := poly.duplicate()
	loop.append(poly[0])
	draw_polyline(loop, Color(0.80, 0.94, 0.58, 0.55), 2.0)
	draw_polyline(loop, Color(0.18, 0.36, 0.22, 0.45), 1.0)
	if _details != null:
		for d in isl["litter"]:
			var r: Rect2 = d["rect"]
			var p: Vector2 = d["pos"]
			draw_texture_rect_region(_details, Rect2(p + Vector2(-r.size.x * 0.5, -r.size.y), r.size), r)
	_draw_paths(isl)


## Worn tracks from each bridge's mouth in toward the island's heart, so the way across reads on the grass.
func _draw_paths(isl: Dictionary) -> void:
	var c: Vector2 = isl["center"]
	for b in _bridges:
		if bool(b["hidden"]):
			continue
		for end in [b["a"], b["b"]]:
			var m: Vector2 = end
			if not Geometry2D.is_point_in_polygon(m + (c - m).normalized() * 6.0, isl["poly"]):
				continue
			if m.distance_to(c) > float(isl["radius"]) * 1.4:
				continue
			var mid := m.lerp(c, 0.5) + (c - m).orthogonal().normalized() * 14.0
			var end_pt := m.lerp(c, 0.72)
			var pts := PackedVector2Array([m, m.lerp(mid, 0.5), mid, mid.lerp(end_pt, 0.5), end_pt])
			draw_polyline(pts, Color(0.62, 0.50, 0.34, 0.9), 24.0, true)
			draw_polyline(pts, Color(0.78, 0.66, 0.46, 0.9), 16.0, true)


func _draw_bridge(b: Dictionary) -> void:
	var reveal: float = b["reveal"]
	var a: Vector2 = b["a"]
	var u: Vector2 = b["u"]
	var n: Vector2 = b["n"]
	var length: float = b["length"]
	var hw: float = b["hw"]
	var hidden: bool = b["hidden"]
	# planks, chunk by chunk as it unspools
	var front := length * reveal
	for ch in b["chunks"]:
		if float(ch["from"]) >= front:
			break
		var k := clampf((front - float(ch["from"])) / 28.0, 0.0, 1.0)
		draw_mesh(ch["mesh"], null, Transform2D.IDENTITY, Color(1, 1, 1, k))
	var shown := front
	# rails: ropes hung between posts, a little slack and a little sway
	var sway := sin(_time * 1.3 + a.x * 0.01) * 1.4
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		var steps := maxi(2, int(shown / 40.0))
		for s in steps + 1:
			var d := minf(shown, float(s) * 40.0) if s < steps else shown
			var sag := sin(PI * fposmod(d, 40.0) / 40.0) * 3.0 if s < steps else 0.0
			pts.append(a + u * d + n * hw * side + Vector2(0.0, -13.0 + sag * 0.0))
		if pts.size() >= 2 and shown > 4.0:
			# slack: draw each span as a sagging polyline
			for s in pts.size() - 1:
				var p0 := pts[s]
				var p1 := pts[s + 1]
				var pm := (p0 + p1) * 0.5 + Vector2(sway * 0.4, 3.5)
				draw_polyline(PackedVector2Array([p0, pm, p1]), Color(0.86, 0.76, 0.56), 1.6, true)
			for s in pts.size():
				var top := pts[s]
				draw_line(top, top + Vector2(0.0, 13.0), Color(0.46, 0.34, 0.24), 2.0)
	# posts at the head (always), and at the far end once it is down
	_draw_posts(a, n, hw, 1.0 if not hidden else clampf(1.0, 0.0, 1.0))
	if reveal >= 0.999:
		_draw_posts(b["b"], n, hw, 1.0)
	elif hidden and reveal <= 0.001:
		# frayed rope ends stir at the head: two anchors that go nowhere
		for side in [-1.0, 1.0]:
			var base: Vector2 = a + n * hw * side + Vector2(0.0, -13.0)
			for k in 3:
				var sw := sin(_time * 2.0 + float(k) * 1.7 + side) * 3.0
				draw_line(base, base + Vector2(float(k - 1) * 4.0 + sw, 14.0 + float(k) * 3.0), Color(0.82, 0.72, 0.52, 0.9), 1.3, true)
	if hidden and reveal > 0.0 and reveal < 1.0:
		# a shimmer at the leading edge
		var tip := a + u * front
		for k in 5:
			var ang := _time * 3.0 + float(k) * 1.26
			var q := tip + Vector2(cos(ang) * 10.0, sin(ang) * 14.0 - 6.0)
			draw_circle(q, 1.6, Color(1, 1, 0.9, 0.8))


func _draw_posts(p: Vector2, n: Vector2, hw: float, alpha: float) -> void:
	for side in [-1.0, 1.0]:
		var base: Vector2 = p + n * hw * side
		draw_rect(Rect2(base + Vector2(-3.0, -22.0), Vector2(6.0, 26.0)), Color(0.38, 0.27, 0.19, alpha))
		draw_rect(Rect2(base + Vector2(-3.0, -22.0), Vector2(2.0, 26.0)), Color(0.56, 0.42, 0.28, alpha))
		draw_rect(Rect2(base + Vector2(-4.0, -25.0), Vector2(8.0, 4.0)), Color(0.50, 0.36, 0.24, alpha))
