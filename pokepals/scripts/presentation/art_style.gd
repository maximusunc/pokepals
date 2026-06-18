class_name ArtStyle
extends RefCounted
## Presentation-only art direction: one shared palette and one light direction the
## whole scene draws from, so the world and the characters read as a single cohesive,
## intentional flat-vector look. Edit data/art.json to re-skin everything. Holds no
## game logic — it just answers "what color?" and "where's the light?" and offers a
## couple of drawing helpers that bake the light direction in.

## Built-in defaults so a missing or partial art.json never breaks rendering (or the
## headless smoke test). Anything art.json provides overrides the matching key.
const DEFAULTS := {
	"palette": {
		"ground_top": [0.49, 0.63, 0.40],
		"ground_bottom": [0.37, 0.51, 0.31],
		"foliage_dark": [0.20, 0.36, 0.24],
		"foliage_mid": [0.28, 0.46, 0.30],
		"foliage_light": [0.42, 0.60, 0.40],
		"bark": [0.41, 0.30, 0.21],
		"water": [0.34, 0.52, 0.62],
		"rim": [1.00, 0.96, 0.82],
		"shadow": [0.05, 0.07, 0.10],
	},
	"light": { "dir": [-0.45, -0.89], "rim_strength": 0.22, "shadow_alpha": 0.20 },
	"characters": {
		"player": { "render": "procedural", "sprite": "", "body": [0.86, 0.52, 0.40], "accent": [0.96, 0.81, 0.67] },
		"companion": { "render": "procedural", "sprite": "", "body": [0.56, 0.62, 0.86], "accent": [0.34, 0.37, 0.54] },
	},
}

var _palette: Dictionary
var _light: Dictionary
var _characters: Dictionary
var _entities: Dictionary


## Load the style from art.json, falling back entirely to DEFAULTS if it's missing.
static func load_style(path := "res://data/art.json") -> ArtStyle:
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		data = WorldData.load_json(path)
	return from_data(data)


## Build a style from an already-parsed dict (used by tests too). Shallow-merges each
## section over the defaults so a partial file only overrides what it names.
static func from_data(data: Dictionary) -> ArtStyle:
	var s := ArtStyle.new()
	s._palette = _merge(DEFAULTS["palette"], data.get("palette", {}))
	s._light = _merge(DEFAULTS["light"], data.get("light", {}))
	s._characters = {}
	for key in DEFAULTS["characters"]:
		s._characters[key] = _merge(DEFAULTS["characters"][key], {})
	for key in data.get("characters", {}):
		s._characters[key] = _merge(s._characters.get(key, {}), data["characters"][key])
	s._entities = (data.get("entities", {}) as Dictionary).duplicate(true)
	return s


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in over:
		out[k] = over[k]
	return out


func color(key: String) -> Color:
	if _palette.has(key):
		return WorldData.to_color(_palette[key])
	return Color(1.0, 0.0, 1.0)  # magenta: a missing palette key should be obvious


func light_dir() -> Vector2:
	return WorldData.to_vec2(_light.get("dir", [-0.45, -0.89])).normalized()


func rim_strength() -> float:
	return float(_light.get("rim_strength", 0.22))


func shadow_alpha() -> float:
	return float(_light.get("shadow_alpha", 0.20))


## A character's art config (render/sprite/body/accent), or an empty dict if unknown.
func character(key: String) -> Dictionary:
	return _characters.get(key, {})


## A world entity's art config (render/sprite), or an empty dict if unknown.
func entity(key: String) -> Dictionary:
	return _entities.get(key, {})


## Draw a "lit blob": a filled base, a lightened cap shifted toward the light, and a
## bright rim cap on the very lit edge. This is the core flat-vector volume cue —
## the same light direction on every blob is what makes the scene feel of-a-piece.
func draw_blob(ci: CanvasItem, center: Vector2, radius: float, base: Color) -> void:
	var ld := light_dir()
	ci.draw_circle(center, radius, base)
	ci.draw_circle(center + ld * radius * 0.40, radius * 0.66, base.lightened(0.22))
	var rim := color("rim")
	ci.draw_circle(center + ld * radius * 0.62, radius * 0.30, Color(rim.r, rim.g, rim.b, rim_strength()))


## Fill a polygon with a vertical top→bottom gradient via per-vertex colors (Gouraud).
## No shader/material needed — robust under GL Compatibility and headless.
func gradient_polygon(ci: CanvasItem, points: PackedVector2Array, top: Color, bottom: Color) -> void:
	if points.is_empty():
		return
	var ymin := points[0].y
	var ymax := points[0].y
	for p in points:
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
	var span := maxf(1.0, ymax - ymin)
	var cols := PackedColorArray()
	for p in points:
		cols.append(top.lerp(bottom, (p.y - ymin) / span))
	ci.draw_polygon(points, cols)


## Bake a vertical top→bottom gradient texture once (for large fills like the ground).
func make_vertical_gradient_texture(top: Color, bottom: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 8
	tex.height = 256
	return tex
