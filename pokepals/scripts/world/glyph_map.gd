class_name GlyphMap
extends RefCounted
## The PAGE of a world made of text, as pure data (state in, state out): for every character cell of
## Glyphfall, what the ground is there (grass, water, shore, path) and, where a thing stands, which character
## it shows and in what colours. It is built once from the world spec and never reads the picture, so a tree
## is the same characters on every frame and on every screen. It draws nothing and knows no nodes: GlyphPage
## turns its byte arrays into two small textures for the shader.
##
## A THING is a small picture made of characters, a "stamp": a few rows of text, set with its bottom row on
## the thing's own cell and centred across it. A space in a stamp is a gap (whatever is behind shows). Each
## stamp has an ink colour (`fg`), optionally other inks for particular characters (`map`), and optionally a
## tint laid in the cell behind each character (`fill`, with `fillmap` per character). Stamps are laid north
## to south, so a nearer thing overlaps a farther one, as it would if you stood in front of it.
##
## Cells are `cell` world px (8 x 12), pinned to the world: cell (i, j) covers x in [i*8, i*8+8), y in
## [j*12, j*12+12). The map covers the world's bounds plus a margin; outside it everything is grass.

const GRASS := 0
const WATER := 1
const SHORE := 2
const PATH := 3

var cell := Vector2(8.0, 12.0)
var origin := Vector2i.ZERO     # the cell coordinates of the map's first cell
var width := 0
var height := 0
var ground := PackedByteArray()  # one of GRASS / WATER / SHORE / PATH per cell
var glyph := PackedByteArray()   # the atlas place of the character a thing shows there (0: none)
var ink := PackedByteArray()     # palette place of that character's colour
var fill := PackedByteArray()    # palette place of the tint behind it (0: none)
var palette: Array[Color] = [Color(0, 0, 0)]   # place 0 is "none"

var _places := {}                # character -> atlas place
var _colors := {}                # html colour -> palette place
var _stamps: Array = []          # [{ pos: Vector2, look: Dictionary, down: Dictionary or {}, key: Vector2i }]
var _down := {}                  # key -> true: things currently shown by their `down` look (a felled tree)


## cell_size: one character in world px. lo, hi: the world's bounds. margin: extra cells all round.
## places: character -> its place in the atlas (data/gf_glyphs.json's `chars`).
func _init(cell_size: Vector2, lo: Vector2, hi: Vector2, places: Dictionary, margin := 12) -> void:
	cell = cell_size
	_places = places
	origin = Vector2i(floori(lo.x / cell.x) - margin, floori(lo.y / cell.y) - margin)
	width = maxi(1, ceili(hi.x / cell.x) + margin - origin.x)
	height = maxi(1, ceili(hi.y / cell.y) + margin - origin.y)
	var n := width * height
	ground.resize(n)
	glyph.resize(n)
	ink.resize(n)
	fill.resize(n)


## The cell (in cell coordinates) holding a world point.
func cell_of(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / cell.x), floori(world.y / cell.y))


## The middle of a cell, in world px.
func centre_of(c: Vector2i) -> Vector2:
	return Vector2((float(c.x) + 0.5) * cell.x, (float(c.y) + 0.5) * cell.y)


func _index(c: Vector2i) -> int:
	var x := c.x - origin.x
	var y := c.y - origin.y
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return y * width + x


func ground_at(world: Vector2) -> int:
	var i := _index(cell_of(world))
	return GRASS if i < 0 else int(ground[i])


## The character a thing shows in the cell holding `world`, or "" if none stands there.
func char_at(world: Vector2) -> String:
	var i := _index(cell_of(world))
	if i < 0 or glyph[i] == 0:
		return ""
	for ch in _places:
		if int(_places[ch]) == int(glyph[i]):
			return String(ch)
	return ""


## The ink of the thing in the cell holding `world` (black if none).
func ink_at(world: Vector2) -> Color:
	var i := _index(cell_of(world))
	return Color(0, 0, 0) if i < 0 else palette[int(ink[i])]


## The tint behind the thing in the cell holding `world`, or null-like transparent if none.
func fill_at(world: Vector2) -> Color:
	var i := _index(cell_of(world))
	return Color(0, 0, 0, 0) if i < 0 or fill[i] == 0 else palette[int(fill[i])]


## A round pond: water inside `radius`, a band of shore `shore` px wide round it. A cell is judged by its
## middle. Water is never painted over by a later pond's shore.
func paint_pond(center: Vector2, radius: float, shore: float) -> void:
	var reach := radius + shore
	var c0 := cell_of(center - Vector2(reach, reach))
	var c1 := cell_of(center + Vector2(reach, reach))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var i := _index(Vector2i(cx, cy))
			if i < 0:
				continue
			var d := centre_of(Vector2i(cx, cy)).distance_to(center)
			if d <= radius:
				ground[i] = WATER
			elif d <= reach and ground[i] != WATER:
				ground[i] = SHORE


## A straight stretch of path from a to b, `half` px to each side. Paths lie over shore, never over water.
func paint_path(a: Vector2, b: Vector2, half: float) -> void:
	var lo := Vector2(minf(a.x, b.x) - half, minf(a.y, b.y) - half)
	var hi := Vector2(maxf(a.x, b.x) + half, maxf(a.y, b.y) + half)
	var c0 := cell_of(lo)
	var c1 := cell_of(hi)
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 0.0001)
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var i := _index(Vector2i(cx, cy))
			if i < 0 or ground[i] == WATER:
				continue
			var p := centre_of(Vector2i(cx, cy))
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			if p.distance_to(a + ab * t) <= half:
				ground[i] = PATH


## Register a thing at `pos` drawn with `look` ({ rows, fg, map, fill, fillmap }; colours as [r, g, b]).
## `down` is the look it has while it is down (a felled tree's stump), or {} if it never is. Nothing is
## drawn until restamp().
func add_thing(pos: Vector2, look: Dictionary, down: Dictionary = {}) -> void:
	if look.is_empty() or (look.get("rows", []) as Array).is_empty():
		return
	_stamps.append({ "pos": pos, "look": look, "down": down, "key": Vector2i(roundi(pos.x), roundi(pos.y)) })


func thing_count() -> int:
	return _stamps.size()


## Mark the thing registered at `pos` as down (true) or standing. Returns whether that changed anything;
## the caller restamps when it did.
func set_down(pos: Vector2, is_down: bool) -> bool:
	var key := Vector2i(roundi(pos.x), roundi(pos.y))
	if is_down == _down.has(key):
		return false
	if is_down:
		_down[key] = true
	else:
		_down.erase(key)
	return true


## Lay every thing onto the page afresh, north to south.
func restamp() -> void:
	glyph.fill(0)
	ink.fill(0)
	fill.fill(0)
	_stamps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector2 = a["pos"]
		var pb: Vector2 = b["pos"]
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x))
	for s in _stamps:
		var look: Dictionary = s["look"]
		if _down.has(s["key"]) and not (s["down"] as Dictionary).is_empty():
			look = s["down"]
		_lay(s["pos"], look)


func _lay(pos: Vector2, look: Dictionary) -> void:
	var rows: Array = look.get("rows", [])
	var n := rows.size()
	var at := cell_of(pos)
	var fg := _color(look.get("fg", [1, 1, 1]))
	var map: Dictionary = look.get("map", {})
	var has_fill := look.has("fill")
	var base_fill := _color(look["fill"]) if has_fill else 0
	var fillmap: Dictionary = look.get("fillmap", {})
	for r in n:
		var text := String(rows[r])
		var x0 := at.x - text.length() / 2
		var cy := at.y - (n - 1) + r
		for k in text.length():
			var ch := text[k]
			if ch == " ":
				continue
			var i := _index(Vector2i(x0 + k, cy))
			if i < 0:
				continue
			glyph[i] = int(_places.get(ch, 0))
			ink[i] = _color(map[ch]) if map.has(ch) else fg
			fill[i] = _color(fillmap[ch]) if fillmap.has(ch) else base_fill


## The palette place of a colour given as [r, g, b] (added if new; 255 colours at most, then the last).
func _color(rgb: Variant) -> int:
	var c := Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	var key := c.to_html(false)
	if _colors.has(key):
		return int(_colors[key])
	if palette.size() >= 256:
		return 255
	palette.append(c)
	_colors[key] = palette.size() - 1
	return palette.size() - 1


## Build a world's page from its spec. cfg is the spec's `atmosphere.glyphs`: `stamps` maps a tree kind
## ("tree", "pine", ...), "great_tree", "portal", "stump" or a prop type to its look (a look with
## `use_color` takes each prop's own colour as its ink); `shore` and
## `path_half` size the ground. Things with no look are simply not drawn.
static func from_spec(data: Dictionary, cfg: Dictionary, places: Dictionary) -> GlyphMap:
	var bounds: Dictionary = data.get("bounds", {})
	var m := GlyphMap.new(WorldData.to_vec2(cfg.get("cell", [8, 12])), WorldData.to_vec2(bounds.get("min", [0, 0])),
		WorldData.to_vec2(bounds.get("max", [0, 0])), places)
	var shore := float(cfg.get("shore", 14.0))
	for pd in data.get("ponds", []):
		m.paint_pond(WorldData.to_vec2(pd["center"]), float(pd["radius"]), shore)
	var half := float(cfg.get("path_half", 9.0))
	for p in data.get("paths", []):
		m.paint_path(WorldData.to_vec2(p["from"]), WorldData.to_vec2(p["to"]), half)
	var stamps: Dictionary = cfg.get("stamps", {})
	var stump: Dictionary = stamps.get("stump", {})
	for t in data.get("trees", []) + data.get("border_trees", []):
		var kind := String(t[2]) if (t as Array).size() > 2 else "tree"
		m.add_thing(Vector2(float(t[0]), float(t[1])), stamps.get(kind, stamps.get("tree", {})), stump)
	for lm in data.get("landmarks", []):
		m.add_thing(WorldData.to_vec2(lm["position"]), stamps.get(String(lm.get("type", "")), {}))
	for p in data.get("props", []):
		var look: Dictionary = stamps.get(String(p.get("type", "")), {})
		if bool(look.get("use_color", false)) and p.has("color"):
			look = look.duplicate()
			look["fg"] = p["color"]   # this kind of thing is inked in each one's own colour (flowers)
		m.add_thing(WorldData.to_vec2(p["position"]), look)
	for p in data.get("portals", []):
		m.add_thing(WorldData.to_vec2(p["position"]), stamps.get("portal", {}))
	m.restamp()
	return m
