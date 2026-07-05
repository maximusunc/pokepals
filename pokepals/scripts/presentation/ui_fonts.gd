class_name UiFonts
extends RefCounted
## The game's two typefaces, loaded once and handed out as cached Font variants:
##   • Space Grotesk — the UI text face (a variable font; ask for a weight 300..700).
##   • Silkscreen    — the chunky pixel face for tiny ALL-CAPS labels (WARDROBE, badges).
## Both are OFL-licensed (license files sit beside the .ttf files in assets/fonts).
##
## Loading degrades gracefully: if a font file is missing or not yet imported, the
## getters return null and callers simply keep whatever font they already had (the
## engine default), so a fresh checkout never crashes over typography.

const GROTESK_PATH := "res://assets/fonts/SpaceGrotesk.ttf"
const PIXEL_PATH := "res://assets/fonts/Silkscreen-Regular.ttf"
const PIXEL_BOLD_PATH := "res://assets/fonts/Silkscreen-Bold.ttf"

## The OpenType 'wght' axis tag ('w'<<24|'g'<<16|'h'<<8|'t') — the key FontVariation
## expects in variation_opentype for a variable font's weight.
const WGHT_TAG := 2003265652

static var _base_cache := {}      # path -> Font (or null if unavailable)
static var _variant_cache := {}   # "path|weight|spacing" -> FontVariation


## Space Grotesk at a given weight (400 regular, 500 medium, 600 semibold, 700 bold).
## Optional spacing adds per-glyph letter-spacing in pixels (for tracked-out caps).
static func grotesk(weight := 400, spacing := 0) -> Font:
	return _variant(GROTESK_PATH, weight, spacing)


## Silkscreen — the pixel caps face. No weight axis; pass bold=true for the bold cut.
static func pixel(bold := false, spacing := 0) -> Font:
	return _variant(PIXEL_BOLD_PATH if bold else PIXEL_PATH, 0, spacing)


static func _variant(path: String, weight: int, spacing: int) -> Font:
	var key := "%s|%d|%d" % [path, weight, spacing]
	if _variant_cache.has(key):
		return _variant_cache[key]
	var base := _base(path)
	if base == null:
		return null
	var v := FontVariation.new()
	v.base_font = base
	if weight > 0:
		v.variation_opentype = { WGHT_TAG: float(weight) }
	if spacing != 0:
		v.spacing_glyph = spacing
	_variant_cache[key] = v
	return v


## Load a base font file, preferring the imported resource; fall back to reading the
## .ttf directly (works headless / before the editor has imported it). Null if absent.
static func _base(path: String) -> Font:
	if _base_cache.has(path):
		return _base_cache[path]
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path) as Font
	if f == null and FileAccess.file_exists(path):
		var ff := FontFile.new()
		if ff.load_dynamic_font(path) == OK:
			f = ff
	_base_cache[path] = f
	return f
