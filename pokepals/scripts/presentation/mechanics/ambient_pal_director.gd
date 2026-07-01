class_name AmbientPalDirector
extends Node
## Ambient pals — server-authoritative set-dressing creatures that make the world feel inhabited even
## when few players are online (the SVG's "ambient pals — not yours"). Each pal is a BRAINLESS
## CompanionView puppet: flagged remote (no brain, no save, no local collision), parented into the
## y-sorted Scenery so it depth-sorts with everything else, and eased toward the transforms the SERVER
## simulates and broadcasts. This is the exact puppet path a remote peer's companion uses — only the
## source differs: the world's ambient sim rather than another player.
##
## It owns nothing but presentation: it spawns one puppet per pal in the world spec's "ambient_pals"
## and, on each Net.ambient_state_received, hands every puppet its latest authoritative spot. As a child
## of the world controller, its Net connection is auto-dropped when the scene reloads on a world hop.
## No-op in worlds without an "ambient_pals" block.

const COMPANION_SCENE := preload("res://scenes/companion.tscn")

var _scenery: Node2D
var _style: ArtStyle
var _bounds := Rect2()
var _pals: Dictionary = {}  # id (String) -> CompanionView puppet


## Wire up scene refs and start listening for the server's ambient-pal ticks.
func setup(scenery: Node2D, style: ArtStyle) -> void:
	_scenery = scenery
	_style = style
	Net.ambient_state_received.connect(_on_ambient_state)


## The walkable bounds, so an untrusted/garbled server position can't fling a puppet off the map
## (mirrors the presence director's clamp of remote peers).
func set_bounds(bounds: Rect2) -> void:
	_bounds = bounds


## Spawn one stationary puppet per pal in the spec, pinned at its home until the server's sim drives it.
func spawn_pals(data: Dictionary) -> void:
	for d in data.get("ambient_pals", []):
		if not (d is Dictionary):
			continue
		var id := String(d.get("id", ""))
		if id == "" or _pals.has(id):
			continue
		var home := WorldData.to_vec2(d.get("home", [0, 0]))
		var rc := COMPANION_SCENE.instantiate() as CompanionView
		rc.set_remote()  # before add_child: builds no brain, reads no save, never self-collides
		rc.name = "AmbientPal_%s" % id
		rc.set_style(_style)
		_scenery.add_child(rc)
		rc.position = home
		rc.set_remote_state(home, Vector2.DOWN)  # pin here; a remote eases toward its target
		var look: Variant = d.get("look", {})
		if look is Dictionary:
			rc.apply_remote_look(look)
		_pals[id] = rc


## A batch of authoritative pal transforms from the server: ease each known puppet toward its new spot.
## Unknown ids (a spec/sim mismatch) are ignored — harmless.
func _on_ambient_state(pals: Array) -> void:
	for p in pals:
		if not (p is Dictionary):
			continue
		var rc: CompanionView = _pals.get(String(p.get("id", "")))
		if rc == null:
			continue
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		if _bounds.has_area():
			pos = Vector2(
				clampf(pos.x, _bounds.position.x, _bounds.end.x),
				clampf(pos.y, _bounds.position.y, _bounds.end.y))
		rc.set_remote_state(pos, p.get("look", Vector2.DOWN))
