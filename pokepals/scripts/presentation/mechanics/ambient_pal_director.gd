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
const PLAYER_SCENE := preload("res://scenes/player.tscn")

var _scenery: Node2D
var _style: ArtStyle
var _bounds := Rect2()
var _pals: Dictionary = {}  # id (String) -> puppet (CompanionView, PalView for species pals, PlayerView for people)
var _hidden := false        # true while the first-meeting search owns the world's animal life


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
## A pal whose spec names a SPECIES (cat/fox/rabbit/bird/wolf — see data/pals.json) gets the pixelart
## animal sprite (PalView); one without — or with a species we can't draw — keeps the classic
## companion puppet, so older seeds render exactly as before.
func spawn_pals(data: Dictionary) -> void:
	for d in data.get("ambient_pals", []):
		if not (d is Dictionary):
			continue
		var id := String(d.get("id", ""))
		if id == "" or _pals.has(id):
			continue
		var home := WorldData.to_vec2(d.get("home", [0, 0]))
		# A PERSON (the Bazaar's walking traffic): the same remote puppet another player gets, dressed
		# from its 'person' appearance. The server walks it about like any pal.
		var person: Variant = d.get("person", null)
		if person is Dictionary:
			var pp := PLAYER_SCENE.instantiate() as PlayerView
			pp.set_remote()
			pp.name = "AmbientPerson_%s" % id
			pp.set_style(_style)
			_scenery.add_child(pp)
			pp.apply_identity((person as Dictionary).get("appearance", {}))
			pp.position = home
			pp.set_remote_state(home, Vector2.DOWN)
			_pals[id] = pp
			continue
		var species := String(d.get("species", ""))
		var variant := int(d.get("variant", 0))
		if species != "" and PalView.supported(species, variant):
			var pv := PalView.new()
			pv.name = "AmbientPal_%s" % id
			pv.setup_species(species, variant)
			_scenery.add_child(pv)
			pv.position = home
			pv.set_remote_state(home, Vector2.DOWN)
			_pals[id] = pv
			continue
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


## The people who simply STAND somewhere: props carrying a 'person' look (the Bazaar's stallholders).
## Each is the same remote PlayerView the walkers use, dressed from that look, parked at the prop's
## spot and turned to its 'facing' (toward the lane). The server never moves them, so they're
## purely local; the prop itself stays in the world data, so Examining it still reads its line.
func spawn_standing_people(data: Dictionary) -> void:
	for it in data.get("props", []):
		if not (it is Dictionary) or not (it.get("person", null) is Dictionary):
			continue
		var pos := WorldData.to_vec2(it.get("position", [0, 0]))
		var face := WorldData.to_vec2(it.get("facing", [0, 1]))
		if face == Vector2.ZERO:
			face = Vector2.DOWN
		var pp := PLAYER_SCENE.instantiate() as PlayerView
		pp.set_remote()
		pp.name = "StandingPerson_%s" % String(it.get("id", ""))
		pp.set_style(_style)
		_scenery.add_child(pp)
		pp.apply_identity((it["person"] as Dictionary).get("appearance", {}))
		pp.position = pos
		pp.set_remote_state(pos, face)


## Stand the ambient pals aside (or bring them back) while the FIRST-MEETING search runs — so every
## animal the searching player can see belongs to the search, and none of the set dressing reads as
## a candidate that mysteriously won't respond. The server keeps driving positions underneath (the
## sim is shared truth); this is purely local visibility. Un-hiding fades them gently back in, so
## the world seems to breathe back to life around the newly met pair rather than popping.
func set_hidden(hidden: bool) -> void:
	if hidden == _hidden:
		return
	_hidden = hidden
	for rc in _pals.values():
		if rc is PlayerView:
			continue  # people aren't part of the animal flock; they stay out in the world
		var n := rc as Node2D
		if hidden:
			n.visible = false
		else:
			n.visible = true
			n.modulate.a = 0.0
			n.create_tween().tween_property(n, "modulate:a", 1.0, 1.2)


## The world's NATIVE creatures — species pals whose registry entry carries lore (Nocthollow's) — as
## [{ id, view: PalView }], for the controller to make examinable. The meadow animals carry none.
func native_creatures() -> Array:
	var out: Array = []
	for id in _pals:
		var pv := _pals[id] as PalView
		if pv != null and pv.lore() != "":
			out.append({ "id": "creature_%s" % id, "view": pv })
	return out


## Let each native creature notice the nearest person (positions in world space) — presentation-only
## reactions; see PalView.react_to. Cheap: a handful of people times a few dozen creatures.
func update_reactions(people: Array) -> void:
	if people.is_empty():
		return
	for v in _pals.values():
		var pv := v as PalView
		if pv == null or pv.lore() == "":
			continue
		var best: Vector2 = people[0]
		var best_d := pv.position.distance_to(best)
		for i in range(1, people.size()):
			var d := pv.position.distance_to(people[i])
			if d < best_d:
				best_d = d
				best = people[i]
		pv.react_to(best, best_d)


## A batch of authoritative pal transforms from the server: ease each known puppet toward its new spot.
## Unknown ids (a spec/sim mismatch) are ignored — harmless.
func _on_ambient_state(pals: Array) -> void:
	for p in pals:
		if not (p is Dictionary):
			continue
		# Either puppet kind (CompanionView or PalView) — both answer set_remote_state(),
		# so the call stays dynamic rather than typed to one class.
		var rc: Variant = _pals.get(String(p.get("id", "")))
		if rc == null:
			continue
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		if _bounds.has_area():
			pos = Vector2(
				clampf(pos.x, _bounds.position.x, _bounds.end.x),
				clampf(pos.y, _bounds.position.y, _bounds.end.y))
		rc.set_remote_state(pos, p.get("look", Vector2.DOWN))
