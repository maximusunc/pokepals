class_name ReflectionLayer
extends Node2D
## STILLGLASS's mirror: everything standing near the lake's north bank is drawn again, upside down, in the
## water. It sits above the world's water (a child of WorldArt) and under every character and tree (the
## y-sorted Scenery), and draws:
##   * YOU, your companion and every friend and friend's companion within `reach` px of the waterline, each
##     a ReflectionPuppet (the actor's own drawing code, flipped), fading as they stand further from the edge;
##   * the shore's TREES within `tree_reach` of the water, baked once into a few chunks (a chunk draws only
##     while the camera can see it, so cost follows the view) as flipped quads that fade toward the crown;
##   * the PHANTOMS: trees in the water with nothing on the shore to cast them (`phantoms`), a touch paler
##     and bluer and rippling on their own beat, so they are wrong in a way you can feel before you can
##     name it;
##   * the ripples a walking reflection leaves on the water, and the rings that mark the stone.
## Everything is clipped to the water by assets/reflect.gdshader, which samples a small bitmap of the lake
## (WaterMask) baked once from the very outlines WorldArt draws. Nothing is rendered to a texture and
## nothing is allocated per frame: it is plain sprite draws with one cheap shader, which is what keeps it
## phone-friendly (the lesson of MistVeil). The seam to the secret is small: the ReflectionDirector asks
## for the waterline (`waterline_below`), dims your companion's own mirror (`set_companion_mirror`), shows
## the walking reflection (`set_walker`) and lays ripples (`add_ripple`).
## Config: the world's `atmosphere.reflections` block.

const SHADER := preload("res://assets/reflect.gdshader")
const CHUNK_WIDTH := 512.0
const CULL_MARGIN := 220.0
const TREE_FADE_TOP := 0.22     # a tree's image is this fraction of its base strength at the crown

var _cfg: Dictionary = {}
var _mask: WaterMask
var _mask_tex: ImageTexture
var _walkers: Callable
var _reach := 110.0
var _strength := 0.8
var _fade_len := 96.0
var _puppets: Dictionary = {}      # instance id -> ReflectionPuppet
var _chunks: Array = []            # [Chunk]
var _companion_k := 1.0            # how much of the LOCAL companion's own mirror shows (1 normally)
var _walker: ReflectionPuppet
var _walker_state: Dictionary = {}
var _ripples: Array = []           # { pos, age, life, r, color }
var _ripple_mat: ShaderMaterial
var _base_mat: ShaderMaterial


## One chunk of baked tree reflections: a node that draws its items once and is switched on only while on screen.
class Chunk extends Node2D:
	var items: Array = []          # { x, base_y, axis, w, h, tex_a, tex_b, strength }
	var rect := Rect2()

	func _ready() -> void:
		texture_filter = TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		for it in items:
			var a0: float = it["strength"]
			var cols := PackedColorArray([Color(1, 1, 1, a0), Color(1, 1, 1, a0), Color(1, 1, 1, a0 * ReflectionLayer.TREE_FADE_TOP), Color(1, 1, 1, a0 * ReflectionLayer.TREE_FADE_TOP)])
			for tex in it["texs"]:
				var t: Texture2D = tex["tex"]
				var sz: Vector2 = t.get_size() * float(it["scale"])
				var x: float = it["x"]
				var top: float = it["axis"] + (it["axis"] - it["base_y"])    # where the image's feet (the trunk base) land
				var sway: float = float(tex.get("off", 0.0))
				var pts := PackedVector2Array([
					Vector2(x - sz.x * 0.5 + sway, top), Vector2(x + sz.x * 0.5 + sway, top),
					Vector2(x + sz.x * 0.5 + sway, top + sz.y), Vector2(x - sz.x * 0.5 + sway, top + sz.y)])
				var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
				draw_primitive(pts, cols, uvs, t)


## Build the layer for this world. Returns false (and draws nothing) when it has no water.
func setup(cfg: Dictionary, world_art: WorldArt, scenery: Node, walkers: Callable) -> bool:
	_cfg = cfg
	_walkers = walkers
	_reach = float(cfg.get("reach", 110.0))
	_strength = float(cfg.get("strength", 0.8))
	_fade_len = float(cfg.get("fade_len", 96.0))
	_mask = WaterMask.build(world_art.pond_rings(), 2.0, 16.0)
	if _mask.is_empty():
		set_process(false)
		return false
	_mask_tex = ImageTexture.create_from_image(_mask.to_image())
	_base_mat = _make_material(_strength, _fade_len, 1.0, 1.0, Color(1, 1, 1))
	_ripple_mat = _make_material(1.0, 0.0, 1.0, 1.0, Color(1, 1, 1))
	material = _ripple_mat
	texture_filter = TEXTURE_FILTER_NEAREST
	_bake_trees(scenery)
	_bake_phantoms()
	_walker = ReflectionPuppet.new()
	_walker.name = "WalkerReflection"
	add_child(_walker)
	var wm := _make_material(1.0, _fade_len * 2.0, 1.0, 1.0, Color(1, 1, 1))
	wm.set_shader_parameter("silver_mix", float(_cfg.get("walker_silver_mix", 0.12)))   # the odd one reads more clearly than a plain image
	_walker.set_shader_material(wm)
	_walker.visible = false
	return true


func mask() -> WaterMask:
	return _mask


func has_water() -> bool:
	return _mask != null and not _mask.is_empty()


## The waterline straight below a point on the bank, within the layer's reach (NAN when none).
func waterline_below(foot: Vector2) -> float:
	if _mask == null or _mask.is_empty():
		return NAN
	return MirrorGeometry.waterline_below(foot, _mask.is_water, _reach)


func reach() -> float:
	return _reach


## How much of the LOCAL companion's own mirror shows (0..1): the director takes it away while the lake is
## showing someone else walking off in its place.
func set_companion_mirror(k: float) -> void:
	_companion_k = clampf(k, 0.0, 1.0)


## The odd reflection: { on: bool, species, variant, pos (feet, on the waterline), face, moving, k (0..1
## visibility), boost (0..1 shimmer) }. Anything else hides it.
func set_walker(d: Dictionary) -> void:
	_walker_state = d


## A ring spreading on the water at `pos` (world), squashed to lie flat, clipped to the water.
func add_ripple(pos: Vector2, life: float = 1.4, radius: float = 22.0, color: Color = Color(0.92, 0.97, 1.0, 0.7)) -> void:
	_ripples.append({ "pos": pos, "age": 0.0, "life": maxf(0.1, life), "r": radius, "color": color })
	queue_redraw()


func _make_material(strength: float, fade_len: float, wobble: float, wspeed: float, tint_mul: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var r := _mask.rect()
	m.set_shader_parameter("water_mask", _mask_tex)
	m.set_shader_parameter("mask_origin", r.position)
	m.set_shader_parameter("mask_size", r.size)
	var s: Array = _cfg.get("silver", [0.8, 0.88, 0.94])
	m.set_shader_parameter("silver", Color(float(s[0]), float(s[1]), float(s[2])))
	m.set_shader_parameter("silver_mix", float(_cfg.get("silver_mix", 0.28)))
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("wobble", float(_cfg.get("wobble", 1.0)) * wobble)
	m.set_shader_parameter("wobble_speed", wspeed)
	m.set_shader_parameter("fade_len", fade_len)
	m.set_shader_parameter("tint_mul", tint_mul)
	return m


# ------------------------------------------------------------------ the trees (baked once)
func _bake_trees(scenery: Node) -> void:
	if scenery == null:
		return
	var tree_reach := float(_cfg.get("tree_reach", 150.0))
	var by_key := {}
	for child in scenery.get_children():
		var tv := child as TreeView
		if tv == null:
			continue
		var base_off := 8.0 if tv.is_great else 6.0
		var base := tv.position + Vector2(0.0, base_off)
		var axis := MirrorGeometry.waterline_below(base, _mask.is_water, tree_reach)
		if is_nan(axis):
			continue
		var texs: Array = []
		if tv.trunk_tex != null and tv.canopy_tex != null:
			texs.append({ "tex": tv.trunk_tex })
			texs.append({ "tex": tv.canopy_tex })
		elif tv.tex != null:
			texs.append({ "tex": tv.tex })
		if texs.is_empty():
			continue
		_add_item(by_key, false, tv.position.x, base.y, axis, texs, tv.tex_scale, MirrorGeometry.strength(axis - base.y, tree_reach))
	_make_chunks(by_key, false)


func _bake_phantoms() -> void:
	var sprites: Array = _cfg.get("phantom_sprites", [])
	var by_key := {}
	var loaded: Array = []
	for s in sprites:
		var tr: Texture2D = load(String(s.get("trunk", ""))) if ResourceLoader.exists(String(s.get("trunk", ""))) else null
		var cn: Texture2D = load(String(s.get("canopy", ""))) if ResourceLoader.exists(String(s.get("canopy", ""))) else null
		loaded.append([tr, cn])
	for ph in _cfg.get("phantoms", []):
		var idx := clampi(int(ph[2]), 0, maxi(0, loaded.size() - 1))
		if loaded.is_empty() or loaded[idx][0] == null or loaded[idx][1] == null:
			continue
		var base := Vector2(float(ph[0]), float(ph[1]))
		var axis := MirrorGeometry.waterline_below(base, _mask.is_water, float(_cfg.get("tree_reach", 150.0)))
		if is_nan(axis):
			continue
		_add_item(by_key, true, base.x, base.y, axis, [{ "tex": loaded[idx][0] }, { "tex": loaded[idx][1] }], 1.0, 1.0)
	_make_chunks(by_key, true)


func _add_item(by_key: Dictionary, phantom: bool, x: float, base_y: float, axis: float, texs: Array, scale: float, strength: float) -> void:
	if strength <= 0.01:
		return
	var key := int(floor(x / CHUNK_WIDTH))
	if not by_key.has(key):
		by_key[key] = []
	by_key[key].append({ "x": x, "base_y": base_y, "axis": axis, "texs": texs, "scale": scale, "strength": strength })


func _make_chunks(by_key: Dictionary, phantom: bool) -> void:
	var mat: ShaderMaterial
	if phantom:
		var t: Array = _cfg.get("phantom_tint", [0.84, 0.92, 1.0])
		mat = _make_material(float(_cfg.get("phantom_strength", 0.9)), 0.0, 0.5, 0.55, Color(float(t[0]), float(t[1]), float(t[2])))
	else:
		mat = _make_material(_strength, 0.0, 1.0, 1.0, Color(1, 1, 1))
	for key in by_key:
		var chunk := Chunk.new()
		chunk.name = ("Phantoms_%d" if phantom else "Trees_%d") % int(key)
		chunk.items = by_key[key]
		var r := Rect2()
		var first := true
		for it in chunk.items:
			var h := 0.0
			for tex in it["texs"]:
				h = maxf(h, (tex["tex"] as Texture2D).get_height() * float(it["scale"]))
			var w := 0.0
			for tex in it["texs"]:
				w = maxf(w, (tex["tex"] as Texture2D).get_width() * float(it["scale"]))
			var top: float = it["axis"] + (it["axis"] - it["base_y"])
			var ir := Rect2(it["x"] - w * 0.5, top, w, h)
			r = ir if first else r.merge(ir)
			first = false
		chunk.rect = r
		chunk.material = mat
		add_child(chunk)
		_chunks.append(chunk)


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if _mask == null or _mask.is_empty():
		return
	var vis := ViewCull.visible_world_rect(self, CULL_MARGIN)
	var cull := vis.has_area()
	for c in _chunks:
		var on: bool = (not cull) or vis.intersects((c as Chunk).rect)
		if c.visible != on:
			c.visible = on
	_update_actors(vis, cull)
	_update_walker(vis, cull)
	if not _ripples.is_empty():
		var alive: Array = []
		for r in _ripples:
			r["age"] = float(r["age"]) + delta
			if float(r["age"]) < float(r["life"]):
				alive.append(r)
		_ripples = alive
		queue_redraw()


func _update_actors(vis: Rect2, cull: bool) -> void:
	var seen := {}
	if _walkers.is_valid():
		for node in _walkers.call():
			if not is_instance_valid(node) or not (node as CanvasItem).visible:
				continue
			var n2 := node as Node2D
			var foot := n2.global_position + Vector2(0.0, 8.0)
			if cull and not vis.has_point(foot):
				continue
			var kind := ""
			var pose: Dictionary = {}
			var local_companion := false
			if node is PlayerView:
				kind = "player"
				pose = (node as PlayerView).reflection_pose()
				if (pose.get("layers", []) as Array).is_empty():
					continue
			elif node is CompanionView:
				kind = "pal"
				pose = (node as CompanionView).reflection_pose()
				local_companion = (node as CompanionView).is_local()
				if pose.is_empty():
					continue
			else:
				continue
			var axis := MirrorGeometry.waterline_below(foot, _mask.is_water, _reach)
			if is_nan(axis):
				continue
			var k := MirrorGeometry.strength(axis - foot.y, _reach)
			if local_companion:
				k *= _companion_k
			if k <= 0.01:
				continue
			var id: int = node.get_instance_id()
			seen[id] = true
			var pup: ReflectionPuppet = _puppets.get(id)
			if pup == null:
				pup = ReflectionPuppet.new()
				pup.name = "Reflection_%d" % id
				add_child(pup)
				pup.set_shader_material(_make_material(_strength, _fade_len, 1.0, 1.0, Color(1, 1, 1)))
				_puppets[id] = pup
			pup.visible = true
			pup.set_pose(kind, pose)
			pup.place(foot.x, 2.0 * axis - foot.y)
			var m := pup.material_ref()
			m.set_shader_parameter("axis_y", axis)
			m.set_shader_parameter("strength", _strength * k)
	for id in _puppets.keys():
		var p: ReflectionPuppet = _puppets[id]
		if not seen.has(id):
			if is_instance_valid(p):
				if not is_instance_valid(instance_from_id(id)):
					p.queue_free()
					_puppets.erase(id)
				else:
					p.visible = false
			else:
				_puppets.erase(id)


func _update_walker(vis: Rect2, cull: bool) -> void:
	var d := _walker_state
	if d.is_empty() or not bool(d.get("on", false)) or float(d.get("k", 0.0)) <= 0.01:
		_walker.visible = false
		return
	var pos: Vector2 = d["pos"]
	if cull and not vis.has_point(pos):
		_walker.visible = false
		return
	var info := PalView.sheet_info(String(d.get("species", "")), int(d.get("variant", 0)))
	if info.is_empty():
		_walker.visible = false
		return
	var face: Vector2 = d.get("face", Vector2.RIGHT)
	var moving := bool(d.get("moving", false))
	_walker.visible = true
	_walker.set_pose("pal", { "tex": info["tex"], "sheet": info["sheet"], "look": face, "speed": 40.0 if moving else 0.0, "time": Time.get_ticks_msec() / 1000.0 })
	_walker.place(pos.x, pos.y)
	var m := _walker.material_ref()
	m.set_shader_parameter("axis_y", pos.y)
	m.set_shader_parameter("strength", clampf(float(d.get("k", 1.0)), 0.0, 1.0))
	m.set_shader_parameter("boost", clampf(float(d.get("boost", 0.0)), 0.0, 1.0))


func _draw() -> void:
	for r in _ripples:
		var t := float(r["age"]) / float(r["life"])
		var c: Color = r["color"]
		var rad := float(r["r"]) * (0.25 + 0.75 * t)
		draw_set_transform(r["pos"] + Vector2(0.0, 5.0), 0.0, Vector2(1.0, 0.36))
		draw_arc(Vector2.ZERO, rad, 0.0, TAU, 32, Color(c.r, c.g, c.b, c.a * (1.0 - t)), 1.5)
		draw_arc(Vector2.ZERO, rad * 0.6, 0.0, TAU, 24, Color(c.r, c.g, c.b, c.a * (1.0 - t) * 0.6), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
