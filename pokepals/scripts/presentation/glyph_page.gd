class_name GlyphPage
extends CanvasLayer
## GLYPHFALL's look (issue #159): the whole world redrawn as monospace characters. The world underneath is
## drawn exactly as in any other world; this layer lays ONE quad over the view whose shader
## (assets/glyph_page.gdshader) reads the finished picture and writes it again as text, a character cell at
## a time. So everything becomes text with no work of its own: trees, water, props, friends, their
## companions, a fishing line, a lantern. On a CanvasLayer above the world, below the vignette and the HUD:
## the HUD, the message pill and every panel stay as they are everywhere else.
##
## Like MistVeil the layer FOLLOWS THE VIEWPORT (it is drawn with the camera's transform, like the world), and
## the quad is laid over the view in world px each frame. The shader pins its character cells to world
## coordinates, so the text is part of the place: it scrolls as you walk and never swims.
##
## Visitors (the walkers: your pair, and every friend's) are written at half size in dense letters with a
## tinted cell behind, so they stay readable among the grass; their boxes go to the shader each frame.
##
## Tuned by the world's `atmosphere.glyphs` block (all optional; these are the defaults):
##   enabled      true             false turns it off (the world shows as the pixel art underneath)
##   cell         [8, 12]          one character, in world px
##   page         [r,g,b]          the dark page
##   bg_tint      0.10             how much of what is under a cell tints the page there
##   actor_bg     0.42             ...and under a visitor's cells
##   ink_floor    0.5              the dimmest ink, as a fraction of full brightness
##   lum_lo/lum_hi 0.10 / 0.72     the brightness range spread over a row's four pairs of characters
##   sway         0.07             how far grass and leaves lean in the wind, in cell widths
##   water_rate   1.1              how often a water cell changes its character, per second
##   actor_box    [9, 17, -11]     half width, half height and y offset of a walker's fine-print box (world px)
##   type_in      1.6              seconds the page takes to be written in on arrival (0: at once)

const SHADER := preload("res://assets/glyph_page.gdshader")
const ATLAS := "res://assets/sprites/gf_glyphs.png"
const LAYOUT := "res://data/gf_glyphs.json"
const MAX_ACTORS := 16
const MARGIN := 64.0

var _rect: ColorRect
var _mat: ShaderMaterial
var _walkers: Callable
var _cell := Vector2(8.0, 12.0)
var _atlas_cell_w := 32.0
var _cols := 8
var _box := Vector3(9.0, 17.0, -11.0)
var _type_in := 1.6
var _time := 0.0
var _enabled := true
var _wrong_at := Vector2(-99999.0, -99999.0)


func _init() -> void:
	layer = 1
	follow_viewport_enabled = true
	process_priority = 1000   # after the player and the camera have moved this frame
	# The page keeps itself over the view even while the tree is paused (the connection gate, a cutscene):
	# a frame without it would show the pixel world underneath.
	process_mode = Node.PROCESS_MODE_ALWAYS


static func wanted(data: Dictionary) -> bool:
	var cfg: Dictionary = data.get("atmosphere", {}).get("glyphs", {})
	return not cfg.is_empty() and bool(cfg.get("enabled", true))


## cfg: the atmosphere's glyphs block. walkers: Callable returning the actors present (as GlowTrail's).
func setup(cfg: Dictionary, walkers: Callable) -> void:
	_walkers = walkers
	_enabled = bool(cfg.get("enabled", true))
	if not _enabled:
		visible = false
		return
	_cell = WorldData.to_vec2(cfg.get("cell", [8, 12]))
	var layout: Dictionary = WorldData.load_json(LAYOUT)
	_cols = int(layout.get("cols", 8))
	_atlas_cell_w = float((layout.get("cell", [32, 48]) as Array)[0])
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	# The atlas is sampled smaller than it is baked on most screens, so it wants mipmaps; made here, once.
	var img := (load(ATLAS) as Texture2D).get_image()
	img.generate_mipmaps()
	_mat.set_shader_parameter("atlas", ImageTexture.create_from_image(img))
	_mat.set_shader_parameter("atlas_grid", Vector2(_cols, int(layout.get("rows", 9))))
	_mat.set_shader_parameter("cell", _cell)
	_mat.set_shader_parameter("page", WorldData.to_color(cfg.get("page", [0.035, 0.04, 0.06])))
	_set_sentences(cfg.get("sentences", []), layout)
	for k in ["bg_tint", "actor_bg", "ink_floor", "lum_lo", "lum_hi", "sway", "water_rate", "blank_under", "grass_gap", "mark_under", "wood_under"]:
		if cfg.has(k):
			_mat.set_shader_parameter(k, float(cfg[k]))
	var box: Array = cfg.get("actor_box", [9, 17, -11])
	_box = Vector3(float(box[0]), float(box[1]), float(box[2]))
	_type_in = maxf(0.0, float(cfg.get("type_in", 1.6)))
	_mat.set_shader_parameter("typed", 0.0 if _type_in > 0.0 else 1.0)
	_rect = ColorRect.new()
	_rect.name = "Page"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	_rect.material = _mat
	add_child(_rect)
	_time = 0.0


## The sentences the paths are written in: packed into a small texture, a line a row, each texel the atlas
## place of one letter (looked up among the atlas's letter rows). No sentences: earth keeps its dots.
func _set_sentences(lines: Array, layout: Dictionary) -> void:
	if lines.is_empty():
		return
	var place := {}
	var rows: Array = layout.get("chars", [])
	var names: Array = layout.get("row_names", [])
	for r in rows.size():
		if String(names[r]) != "letters":
			continue
		for c in (rows[r] as Array).size():
			place[String(rows[r][c])] = r * _cols + c
	var width := 1
	for l in lines:
		width = maxi(width, String(l).length())
	var img := Image.create_empty(width, lines.size(), false, Image.FORMAT_R8)
	var blank := int(place.get(" ", 0))
	for y in lines.size():
		var text := String(lines[y])
		for x in width:
			# a short line is written again from its start, so no row of the page runs out of words
			var ch := text[x % text.length()] if text.length() > 0 else " "
			img.set_pixel(x, y, Color(float(int(place.get(ch, blank))) / 255.0, 0.0, 0.0))
	_mat.set_shader_parameter("text_tex", ImageTexture.create_from_image(img))
	_mat.set_shader_parameter("text_size", Vector2(width, lines.size()))
	_mat.set_shader_parameter("text_on", 1.0)


## The atlas place of a character among the special glyphs (the wrong glyph's "&"), or -1.
func special_index(ch: String) -> int:
	var layout: Dictionary = WorldData.load_json(LAYOUT)
	var rows: Array = layout.get("chars", [])
	var names: Array = layout.get("row_names", [])
	for r in rows.size():
		if String(names[r]) == "special":
			var c := (rows[r] as Array).find(ch)
			if c >= 0:
				return r * _cols + c
	return -1


func cell_size() -> Vector2:
	return _cell


## The world cell (in cell coordinates) a world point falls in: where a character stands.
func cell_of(world: Vector2) -> Vector2:
	return (world / _cell).floor()


## Put the WRONG glyph in the cell holding `world` (the atlas place `index`), or take it away (on = false).
func set_wrong_glyph(world: Vector2, index: int, on: bool = true, shine := Color(1.0, 0.86, 0.42)) -> void:
	_wrong_at = cell_of(world) if on else Vector2(-99999.0, -99999.0)
	if _mat != null:
		_mat.set_shader_parameter("wrong_color", Vector3(shine.r, shine.g, shine.b))
		_mat.set_shader_parameter("wrong_cell", _wrong_at)
		_mat.set_shader_parameter("wrong_index", float(index))


## 0..1: how much the wrong glyph catches the light (once you are close and your companion has shown you).
func set_wrong_glow(amount: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("wrong_glow", clampf(amount, 0.0, 1.0))


func _process(delta: float) -> void:
	if not _enabled or _mat == null:
		return
	_time += delta
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
	_mat.set_shader_parameter("lod", maxf(0.0, log(_atlas_cell_w / maxf(1.0, _cell.x * px_scale)) / log(2.0)))
	_mat.set_shader_parameter("time", _time)
	if _type_in > 0.0:
		_mat.set_shader_parameter("typed", clampf(_time / _type_in, 0.0, 1.0))
	var packed := PackedVector4Array()
	packed.resize(MAX_ACTORS)
	var n := 0
	if _walkers.is_valid():
		for w in _walkers.call():
			if n >= MAX_ACTORS:
				break
			if not (w is Node2D) or not (w as Node2D).is_visible_in_tree():
				continue
			var p := (w as Node2D).global_position
			if not view.has_point(p):
				continue
			var k := 0.8 if w is CompanionView else 1.0
			packed[n] = Vector4(p.x, p.y + _box.z * k, _box.x * k + _cell.x * 0.5, _box.y * k + _cell.y * 0.5)
			n += 1
	_mat.set_shader_parameter("actors", packed)
	_mat.set_shader_parameter("actor_count", n)
