class_name GlyphPage
extends Node2D
## GLYPHFALL's look (issue #159): the whole world written as monospace characters. This node lays ONE quad
## over the view whose shader (assets/glyph_page.gdshader) writes the page a character cell at a time. It sits
## in the world BETWEEN the ground and everything that stands on it (just before Scenery): the page covers
## the pixel world's ground and props, and visitors are drawn on top of it. The HUD, the message pill and
## every panel are on their own layers above and stay as they are everywhere else.
##
## What the page shows is the world's own DATA, not a picture (the first build read the finished picture
## back, and every sway and sub-pixel step of the camera made characters flicker). The pure GlyphMap
## (scripts/world) works out, once, what each cell is: the ground there, and the character, ink and tint of
## any thing standing there (a tree, a bench and the portal are small pictures made of characters, "stamps",
## authored in the spec). This node turns that into two small textures and hands them to the shader.
##
## VISITORS (players, companions, wild animals, and what they carry) write themselves: OtherworldLook's glyph
## look gives them one shared material (assets/glyph_actor.gdshader) that redraws each as fine print, small
## dense letters on solid blocks of its own colours. This node only keeps that material's settings current.
## The sprites of things the page draws itself (trees, the portal) are made see-through, so nothing unseen
## stands in front of a visitor.
##
## A felled tree shows its stump: this node looks over the world's trees a couple of times a second (only in
## a world that allows chopping) and re-lays the stamps when one has fallen or grown back.
##
## The quad is laid over the view in world px each frame; the cells are pinned to world coordinates.
##
## Tuned by the world's `atmosphere.glyphs` block (all optional unless said):
##   enabled      true             false turns it off (the world shows as the pixel art underneath)
##   cell         [8, 12]          one character, in world px
##   page         [r,g,b]          the dark page
##   stamps       { name: look }   REQUIRED for things to show: a tree kind, "great_tree", "stump", "portal" or a
##                                 prop type -> { rows, fg, map, fill, fillmap } (see GlyphMap)
##   shore / path_half  14 / 9     the shore band round a pond and a path's half width, world px
##   sentences    [text, ...]      the lines the paths are written in
##   grass        { chars, inks, gap, sway }     the tufts, their three dim colours, the share left empty, the lean
##   water        { chars, ink, bg, rate }       its two characters, colours, and how fast the bands drift
##   shore_look   { chars, ink, bg }             the shore's two characters and colours
##   path         { ink, bg }                    the colours a path is written in
##   print        { chars, dark, light, vivid }  the dense letters visitors are set in, their contrast and colour boost
##   type_in      1.6              seconds the page takes to be written in on arrival (0: at once)

const SHADER := preload("res://assets/glyph_page.gdshader")
const ATLAS := "res://assets/sprites/gf_glyphs.png"
const LAYOUT := "res://data/gf_glyphs.json"
const MARGIN := 64.0
const TREE_CHECK := 0.5   # seconds between looks at the trees for a felled one

var _rect: ColorRect
var _mat: ShaderMaterial
var _map: GlyphMap
var _places := {}          # character -> atlas place
var _cell := Vector2(8.0, 12.0)
var _atlas_cell_w := 32.0
var _type_in := 1.6
var _time := 0.0
var _enabled := true
var _scenery: Node
var _watch_trees := false
var _tree_clock := 0.0
var _cell_img: Image
var _actor_mat: ShaderMaterial   # the visitors' shared fine-print material (OtherworldLook's)


func _init() -> void:
	process_priority = 1000   # after the player and the camera have moved this frame
	# The page keeps itself over the view even while the tree is paused (the connection gate, a cutscene):
	# a frame without it would show the pixel world underneath.
	process_mode = Node.PROCESS_MODE_ALWAYS


static func wanted(data: Dictionary) -> bool:
	var cfg: Dictionary = data.get("atmosphere", {}).get("glyphs", {})
	return not cfg.is_empty() and bool(cfg.get("enabled", true))


## data: the world spec (its `atmosphere.glyphs` is the page's settings). scenery: the node the world's trees
## stand in, watched for felled ones.
func setup(data: Dictionary, scenery: Node = null) -> void:
	var cfg: Dictionary = data.get("atmosphere", {}).get("glyphs", {})
	_scenery = scenery
	_enabled = bool(cfg.get("enabled", true))
	if not _enabled:
		visible = false
		return
	_cell = WorldData.to_vec2(cfg.get("cell", [8, 12]))
	var layout: Dictionary = WorldData.load_json(LAYOUT)
	var chars: Array = layout.get("chars", [])
	_places = {}
	for i in chars.size():
		_places[String(chars[i])] = i
	var cols := int(layout.get("cols", 16))
	_atlas_cell_w = float((layout.get("cell", [32, 48]) as Array)[0])
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	# The atlas is sampled smaller than it is baked on most screens, so it wants mipmaps; made here, once.
	var img := (load(ATLAS) as Texture2D).get_image()
	img.generate_mipmaps()
	_mat.set_shader_parameter("atlas", ImageTexture.create_from_image(img))
	_mat.set_shader_parameter("atlas_grid", Vector2(cols, int(layout.get("rows", 8))))
	_mat.set_shader_parameter("cell", _cell)
	_mat.set_shader_parameter("page", WorldData.to_color(cfg.get("page", [0.035, 0.04, 0.06])))

	# The page itself: the ground and every thing, from the spec.
	_map = GlyphMap.from_spec(data, cfg, _places)
	_mat.set_shader_parameter("map_origin", Vector2(_map.origin))
	_mat.set_shader_parameter("map_size", Vector2(_map.width, _map.height))
	_push_map()
	_watch_trees = bool(data.get("chopping", true)) and scenery != null
	# The page draws every tree and the portal itself, so their sprites are made see-through: a visitor
	# walking "behind" one would otherwise be hidden by a thing nobody can see. (Not `visible`: Scenery's
	# culling owns that. They still stand, collide and fall.)
	if scenery != null:
		for c in scenery.get_children():
			if c is TreeView or c is PortalView:
				(c as CanvasItem).modulate.a = 0.0

	_set_sentences(cfg.get("sentences", []))
	var grass: Dictionary = cfg.get("grass", {})
	_mat.set_shader_parameter("tufts", _places_of(String(grass.get("chars", ".,'`\";")), 6))
	_mat.set_shader_parameter("grass_ink", _colors(grass.get("inks", [[0.29, 0.33, 0.14], [0.35, 0.40, 0.16], [0.41, 0.46, 0.19]]), 3))
	_mat.set_shader_parameter("grass_gap", float(grass.get("gap", 0.62)))
	_mat.set_shader_parameter("sway", float(grass.get("sway", 0.025)))
	var water: Dictionary = cfg.get("water", {})
	_mat.set_shader_parameter("waves", _places_of(String(water.get("chars", "~≈")), 2))
	_mat.set_shader_parameter("water_ink", _vec3(water.get("ink", [0.47, 0.72, 0.96])))
	_mat.set_shader_parameter("water_bg", _vec3(water.get("bg", [0.06, 0.17, 0.30])))
	_mat.set_shader_parameter("water_rate", float(water.get("rate", 0.06)))
	var shore: Dictionary = cfg.get("shore_look", {})
	_mat.set_shader_parameter("dots", _places_of(String(shore.get("chars", ".:")), 2))
	_mat.set_shader_parameter("shore_ink", _vec3(shore.get("ink", [0.79, 0.67, 0.42])))
	_mat.set_shader_parameter("shore_bg", _vec3(shore.get("bg", [0.17, 0.14, 0.08])))
	var path: Dictionary = cfg.get("path", {})
	_mat.set_shader_parameter("path_ink", _vec3(path.get("ink", [0.96, 0.85, 0.60])))
	_mat.set_shader_parameter("path_bg", _vec3(path.get("bg", [0.17, 0.13, 0.07])))
	# The fine print visitors are written in: one shared material, kept by OtherworldLook.
	var fine: Dictionary = cfg.get("print", {})
	_actor_mat = OtherworldLook.glyph_material()
	_actor_mat.set_shader_parameter("atlas", _mat.get_shader_parameter("atlas"))
	_actor_mat.set_shader_parameter("atlas_grid", Vector2(cols, int(layout.get("rows", 8))))
	_actor_mat.set_shader_parameter("cell", _cell)
	_actor_mat.set_shader_parameter("print", _places_of(String(fine.get("chars", "%&#@")), 4))
	_actor_mat.set_shader_parameter("dark", float(fine.get("dark", 0.32)))
	_actor_mat.set_shader_parameter("light", float(fine.get("light", 0.72)))
	_actor_mat.set_shader_parameter("vivid", float(fine.get("vivid", 1.25)))

	_type_in = maxf(0.0, float(cfg.get("type_in", 1.6)))
	_mat.set_shader_parameter("typed", 0.0 if _type_in > 0.0 else 1.0)
	_rect = ColorRect.new()
	_rect.name = "Page"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	_rect.material = _mat
	add_child(_rect)
	_time = 0.0


## The page's data (for tests, and for anything that wants to know what stands in a cell).
func map() -> GlyphMap:
	return _map


## The atlas places of the first `n` characters of `text` (short text repeats its last character).
func _places_of(text: String, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in n:
		var ch := text[mini(i, text.length() - 1)] if text.length() > 0 else " "
		out.append(float(int(_places.get(ch, 0))))
	return out


static func _vec3(rgb: Variant) -> Vector3:
	return Vector3(float(rgb[0]), float(rgb[1]), float(rgb[2]))


static func _colors(list: Variant, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var arr: Array = list
	for i in n:
		out.append(_vec3(arr[mini(i, arr.size() - 1)]))
	return out


## Hand the map to the shader: one texel a cell (r: a thing's character, g: the ground, b: its ink, a: its
## tint), and the things' palette as a 256 x 1 strip. Called again whenever the stamps are re-laid.
func _push_map() -> void:
	var n := _map.width * _map.height
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i in n:
		bytes[i * 4] = _map.glyph[i]
		bytes[i * 4 + 1] = _map.ground[i]
		bytes[i * 4 + 2] = _map.ink[i]
		bytes[i * 4 + 3] = _map.fill[i]
	_cell_img = Image.create_from_data(_map.width, _map.height, false, Image.FORMAT_RGBA8, bytes)
	_mat.set_shader_parameter("cell_tex", ImageTexture.create_from_image(_cell_img))
	var pal := Image.create_empty(256, 1, false, Image.FORMAT_RGB8)
	for i in _map.palette.size():
		pal.set_pixel(i, 0, _map.palette[i])
	_mat.set_shader_parameter("palette_tex", ImageTexture.create_from_image(pal))


## The sentences the paths are written in: packed into a small texture, a line a row, each texel the atlas
## place of one letter. No sentences: a path is a bare warm band.
func _set_sentences(lines: Array) -> void:
	if lines.is_empty():
		return
	var width := 1
	for l in lines:
		width = maxi(width, String(l).length())
	var img := Image.create_empty(width, lines.size(), false, Image.FORMAT_R8)
	for y in lines.size():
		var text := String(lines[y])
		for x in width:
			# a short line is written again from its start, so no row of the page runs out of words
			var ch := text[x % text.length()] if text.length() > 0 else " "
			img.set_pixel(x, y, Color(float(int(_places.get(ch, 0))) / 255.0, 0.0, 0.0))
	_mat.set_shader_parameter("text_tex", ImageTexture.create_from_image(img))
	_mat.set_shader_parameter("text_size", Vector2(width, lines.size()))
	_mat.set_shader_parameter("text_on", 1.0)


## The atlas place of a character (the wrong glyph's "&"), or -1 if the atlas has no such character.
func special_index(ch: String) -> int:
	return int(_places.get(ch, -1))


func cell_size() -> Vector2:
	return _cell


## The world cell (in cell coordinates) a world point falls in: where a character stands.
func cell_of(world: Vector2) -> Vector2:
	return (world / _cell).floor()


## Put the WRONG glyph in the cell holding `world` (the atlas place `index`), or take it away (on = false).
func set_wrong_glyph(world: Vector2, index: int, on: bool = true, shine := Color(1.0, 0.86, 0.42)) -> void:
	if _mat != null:
		_mat.set_shader_parameter("wrong_color", Vector3(shine.r, shine.g, shine.b))
		_mat.set_shader_parameter("wrong_cell", cell_of(world) if on else Vector2(-99999.0, -99999.0))
		_mat.set_shader_parameter("wrong_index", float(index))


## 0..1: how much the wrong glyph catches the light (once you are close and your companion has shown you).
func set_wrong_glow(amount: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("wrong_glow", clampf(amount, 0.0, 1.0))


## Look over the world's trees: one that has fallen shows its stump, one that has grown back stands again.
## Returns whether the page changed.
func check_trees() -> bool:
	if _map == null or _scenery == null:
		return false
	var changed := false
	for c in _scenery.get_children():
		if c is TreeView and _map.set_down((c as TreeView).position, (c as TreeView).felled):
			changed = true
	if changed:
		_map.restamp()
		_push_map()
	return changed


func _process(delta: float) -> void:
	if not _enabled or _mat == null:
		return
	_time += delta
	if _watch_trees:
		_tree_clock += delta
		if _tree_clock >= TREE_CHECK:
			_tree_clock = 0.0
			check_trees()
	var vp := get_viewport()
	var ct := vp.get_canvas_transform()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var inv := ct.affine_inverse()
	var view := Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * size).grow(MARGIN)
	_rect.position = view.position
	_rect.size = view.size
	# physical pixels per world px: the camera's zoom times the window's stretch
	var px_scale := ct.get_scale().x * vp.get_stretch_transform().get_scale().x
	_mat.set_shader_parameter("px_scale", px_scale)
	var lod := maxf(0.0, log(_atlas_cell_w / maxf(1.0, _cell.x * px_scale)) / log(2.0))
	_mat.set_shader_parameter("lod", lod)
	if _actor_mat != null:
		_actor_mat.set_shader_parameter("lod", lod)
	_mat.set_shader_parameter("time", _time)
	if _type_in > 0.0:
		_mat.set_shader_parameter("typed", clampf(_time / _type_in, 0.0, 1.0))
