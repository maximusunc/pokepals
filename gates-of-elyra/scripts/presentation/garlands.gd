class_name Garlands
extends Node2D
## What's strung over a souk's lane (the Bazaar): strings of little lights, lines of bunting, and brass
## lanterns hanging low on cords, each spanning the lane from wall to wall with a gentle sag. Drawn
## ABOVE everyone (a z_index over the y-sorted scenery), because it hangs overhead. Pure presentation,
## read from the spec's "garlands": [{ from, to, sag, kind: "lights" | "bunting" | "lanterns" }].
##
## Built ONCE and animated on the GPU. Everything that moves (a bulb's twinkle, a pennant's flutter, a
## lantern's sway and flicker) is a MultiMesh instance, which is Godot's way to draw many copies of one
## small mesh in a single call, each copy with its own transform, colour and a "custom" number we use
## as its phase. assets/garland.gdshader animates them from that phase and the shader's clock. The
## cords never move, so they're drawn once in _draw. So the script does no work at all per frame,
## where it used to rebuild hundreds of bulbs every frame (the fountain-view lag on phones).

const BUNTING := [Color(0.86, 0.30, 0.22), Color(0.95, 0.72, 0.22), Color(0.30, 0.56, 0.62), Color(0.78, 0.42, 0.62), Color(0.96, 0.9, 0.78)]
const SHADER := preload("res://assets/garland.gdshader")

var _lines: Array = []  # [{ a, b, sag, kind, seed }]
var _cords := PackedVector2Array()  # segment pairs, drawn once


func setup(garlands: Array) -> void:
	z_index = 20
	set_process(false)
	_lines.clear()
	for c in get_children():
		c.queue_free()
	for g in garlands:
		if not (g is Dictionary):
			continue
		var a := WorldData.to_vec2(g.get("from", [0, 0]))
		_lines.append({ "a": a, "b": WorldData.to_vec2(g.get("to", [0, 0])), "sag": float(g.get("sag", 16.0)),
			"kind": String(g.get("kind", "lights")), "seed": fposmod(a.x * 0.013 + a.y * 0.029, 1.0) })
	_build()
	queue_redraw()


## A point along a sagging line, t in 0..1 (a parabola: deepest in the middle).
static func _along(a: Vector2, b: Vector2, sag: float, t: float) -> Vector2:
	return a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t))


func _build() -> void:
	_cords.clear()
	var bulbs: Array = []     # [pos, phase]
	var glows: Array = []     # [pos, phase]
	var lanterns: Array = []  # [pos, phase]
	var flags: Array = []     # [pos, phase, color]
	for l in _lines:
		var a: Vector2 = l["a"]
		var b: Vector2 = l["b"]
		var sag: float = l["sag"]
		var sd: float = l["seed"]
		var prev := a
		for i in range(1, 17):
			var q := _along(a, b, sag, float(i) / 16.0)
			_cords.append(prev)
			_cords.append(q)
			prev = q
		match String(l["kind"]):
			"bunting":
				var n := int(a.distance_to(b) / 14.0)
				for i in n:
					flags.append([_along(a, b, sag, (float(i) + 0.5) / float(n)), float(i), BUNTING[(i + int(sd * 10.0)) % BUNTING.size()]])
			"lanterns":
				var n := maxi(2, int(a.distance_to(b) / 70.0))
				for i in n:
					var p := _along(a, b, sag, (float(i) + 0.5) / float(n))
					var ph := float(i) + sd * 6.0
					lanterns.append([p, ph])
					glows.append([p + Vector2(0, 16), float(i) * 1.7])
			_:
				var n := int(a.distance_to(b) / 9.0)
				for i in n:
					bulbs.append([_along(a, b, sag, (float(i) + 0.5) / float(n)), float(i) * 2.3 + sd * 9.0])
	# Drawn in this order: lantern glows, lanterns, then the bulbs and pennants over everything.
	_add_layer(1, _quad(Vector2(44, 44 * 0.65)), glows, Color(1.0, 0.7, 0.36, 0.32))
	_add_layer(2, _lantern_mesh(), lanterns, Color.WHITE)
	_add_layer(0, _quad(Vector2(10, 10)), bulbs, Color.WHITE)
	_add_layer(3, _pennant_mesh(), flags, Color.WHITE)


func _add_layer(kind: int, mesh: Mesh, items: Array, color: Color) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		var it: Array = items[i]
		mm.set_instance_transform_2d(i, Transform2D(0.0, it[0]))
		mm.set_instance_color(i, it[2] if it.size() > 2 else color)
		mm.set_instance_custom_data(i, Color(it[1], 0.0, 0.0, 0.0))
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("kind", kind)
	node.material = mat
	add_child(node)


## A quad centred on the origin, UV 0..1 across it (the shader draws a round glow inside).
static func _quad(size: Vector2) -> ArrayMesh:
	var h := size * 0.5
	var v := PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	return _mesh(v, uv, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), PackedInt32Array([0, 1, 2, 0, 2, 3]))


## A pennant hanging from the cord: its tip (y > 1) is what flutters.
static func _pennant_mesh() -> ArrayMesh:
	var v := PackedVector2Array([Vector2(-5, 0), Vector2(5, 0), Vector2(0, 9)])
	return _mesh(v, PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]), PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]), PackedInt32Array([0, 1, 2]))


## A brass lantern hanging 16 px below its cord point (the origin): a short cord, the body, and a
## bright heart (UV.x = 1 marks the heart, which the shader flickers).
static func _lantern_mesh() -> ArrayMesh:
	var v := PackedVector2Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var add_poly := func(pts: Array, c: Color, heart: bool) -> void:
		var base := v.size()
		for q in pts:
			v.append(q)
			uv.append(Vector2(1.0 if heart else 0.0, 0.0))
			col.append(c)
		for k in range(1, pts.size() - 1):
			idx.append_array([base, base + k, base + k + 1])
	var cord := Color(0.2, 0.14, 0.1)
	add_poly.call([Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0.5, 10), Vector2(-0.5, 10)], cord, false)
	var o := Vector2(0, 16)
	add_poly.call([o + Vector2(-5, -6), o + Vector2(5, -6), o + Vector2(6, 2), o + Vector2(0, 8), o + Vector2(-6, 2)], Color(0.66, 0.46, 0.2), false)
	var heart: Array = []
	for k in 8:
		var ang := TAU * float(k) / 8.0
		heart.append(o + Vector2(cos(ang), sin(ang)) * 3.2)
	add_poly.call(heart, Color(1.0, 0.86, 0.5), true)
	return _mesh(v, uv, col, idx)


static func _mesh(v: PackedVector2Array, uv: PackedVector2Array, col: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _draw() -> void:
	if not _cords.is_empty():
		draw_multiline(_cords, Color(0.18, 0.12, 0.08, 0.8), 1.0)
