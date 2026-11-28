class_name MisprintDirector
extends Node
## The WRONG GLYPH (Glyphfall's secret): one character in a world made of text is not the one that belongs
## there, an ampersand among the quote marks of the grass. This is the presentation half; the decisions live
## in the pure GlyphNotice (scripts/world). It does three things and nothing else:
##   * puts the wrong character on the page (GlyphPage.set_wrong_glyph), in the grass's own colour;
##   * each frame hands the notice where you and your companion are and how deep the bond is, and when it
##     says so stops the companion and turns it to look (CompanionView.point_at), for a couple of seconds at a
##     time: the only compass there is;
##   * lets the glyph catch the light as you close in (GlyphPage.set_wrong_glow), and when you are on it,
##     says it is found (`glyph_found`: SecretDirector makes it examinable, the ordinary claim flow).
## When the secret is taken the page is corrected: the ampersand is gone and grass stands there.
## Personal and display-only: a friend beside you sees your companion stop and look, and nothing here is
## networked. The numbers all come from the secret's `reveal` block in the world spec.

signal glyph_found

var _host: Node
var _companion: CompanionView
var _player: PlayerView

var _notice: GlyphNotice
var _reveal: Dictionary = {}
var _lines: Dictionary = {}
var _glyph := Vector2.ZERO
var _said := {}
var _pointing := false
var _active := false
var _glow := -1.0
var _shine := Color(1.0, 0.86, 0.42)


func setup(host: Node, companion: CompanionView, _world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_player = player


## Lay out this world's wrong glyph from the secret ({ position, reveal: { glyph, ... } }).
func configure(secret: Dictionary) -> void:
	_reveal = secret.get("reveal", {})
	_lines = _reveal.get("lines", {})
	_glyph = WorldData.to_vec2(secret.get("position", [0, 0]))
	_shine = WorldData.to_color((secret.get("prop", {}) as Dictionary).get("color", [1.0, 0.86, 0.42]))
	_notice = GlyphNotice.new(_glyph, _reveal)
	_said = {}
	_active = true
	_glow = -1.0
	_place()


func notice() -> GlyphNotice:
	return _notice


## The world's page of text is built after the secret is laid out: put the glyph on it once it is there.
func _place() -> bool:
	var page: GlyphPage = _host.glyph_page() if _host != null and _host.has_method("glyph_page") else null
	if page == null:
		return false
	var index := page.special_index(String(_reveal.get("glyph", "&")))
	page.set_wrong_glyph(_glyph, maxi(index, 0), _active, _shine)
	return true


## The secret has been taken: the page is corrected, and the companion stops looking.
func finish() -> void:
	_active = false
	_release()
	var page: GlyphPage = _host.glyph_page() if _host != null and _host.has_method("glyph_page") else null
	if page != null:
		page.set_wrong_glyph(_glyph, 0, false)
		page.set_wrong_glow(0.0)


func _release() -> void:
	if _pointing and _companion != null:
		_companion.point_at(Vector2.ZERO, 0.0)
	_pointing = false


## Per frame (SecretDirector.update drives it).
func update(delta: float) -> void:
	if not _active or _notice == null or _player == null or _companion == null or delta <= 0.0:
		return
	var page: GlyphPage = _host.glyph_page() if _host.has_method("glyph_page") else null
	if page == null:
		return
	if _glow < 0.0:
		_place()   # the page did not exist yet when the secret was laid out
		_glow = 0.0
	var r := _notice.update(delta, _player.position, _companion.position, _companion.bond_value())
	if bool(r["point"]):
		_companion.point_at(r["target"], 1.0)
		_pointing = true
	else:
		_release()
	var glow := float(r["glow"])
	if not is_equal_approx(glow, _glow):
		_glow = glow
		page.set_wrong_glow(glow)
	for e in r["events"]:
		match String(e):
			"notice":
				_say_once("notice")
			"again":
				_say_once("again")
			"near":
				_say_once("near")
			"found":
				glyph_found.emit()


func _say_once(key: String) -> void:
	if _said.has(key):
		return
	_said[key] = true
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)
