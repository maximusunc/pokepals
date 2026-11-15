class_name HouseDirector
extends Node
## YOUR HOUSE at home (home building; docs/usable-items-design.md "Home building"). Active only in a home whose
## spec has a house (the carpenter in the bazaar has been paid; Server.House / Server.HomeWorld). Created by
## world_controller in every world, and freed with it on a world hop.
##
##   * **Being built:** the carpenter is here (a person dressed as she is in the bazaar), walking between the
##     corners of the frame and hammering away. Examine her for how long is left. The frame rises as the build
##     goes on (HouseView). When the time is up (counted here from the server's own start time and build time),
##     it's **finished** right in front of you: the frame becomes a house, the furniture goes in (its rugs and
##     shelves are WorldArt plates; its pieces wall in through a solids rebuild), your keepsakes move inside onto
##     its display spots and every other find onto its curio shelves, exactly as the server will lay them out
##     next time (Server.HomeWorld). The carpenter waves and heads off.
##   * **Built:** nothing to do: the server already laid it out with everything inside.
##
## Friends visiting see the same: the build is worked out from the same numbers on every client.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const WALK_SPEED := 46.0
const HAMMER_GAP := 0.55

var _host: Node
var _player: PlayerView
var _companion: CompanionView
var _world_art: WorldArt
var _scenery: Node2D
var _style: ArtStyle
var _home_dir: HomeDirector

var _active := false
var _data: Dictionary = {}
var _interactables: Array = []
var _view: HouseView
var _mine := false

var _carpenter: PlayerView
var _hammer: AxeView
var _entry: Dictionary = {}     # the carpenter's examine entry
var _spots: Array = []          # where she works (world)
var _spot := 0
var _work := 0.0                # seconds of hammering left at this spot
var _swing := 0.0
var _leaving := false
# Where she's walking to right now: moved at walking pace and handed to her body as its target, so the body eases
# after it and its walk cycle plays (setting her position directly would leave her gliding, unanimated).
var _walk := Vector2.ZERO


func setup(host: Node, player: PlayerView, companion: CompanionView, world_art: WorldArt, scenery: Node2D, style: ArtStyle, home_dir: HomeDirector) -> void:
	_host = host
	_player = player
	_companion = companion
	_world_art = world_art
	_scenery = scenery
	_style = style
	_home_dir = home_dir


func is_active() -> bool:
	return _active


## The house's view, if this home has one.
func view() -> HouseView:
	return _view


## The world is laid out: find the house among the buildings and, while it's being built, bring the carpenter.
func begin(data: Dictionary, interactables: Array, building_views: Array) -> void:
	_data = data
	_interactables = interactables
	for bv in building_views:
		if bv is HouseView:
			_view = bv
	_active = _view != null
	if not _active:
		return
	var home: Dictionary = data.get("home", {})
	_mine = String(home.get("owner_id", "")) == Net.local_id() and Net.local_id() != ""
	if not _view.built:
		if _view.build_progress() >= 1.0:
			# It finished while we were away (or on the way here): finish it now, quietly.
			_finish(false)
			return
		_spawn_carpenter()
		var mins := int(ceil(_view.seconds_left() / 60.0))
		if _mine:
			_host.show_hint("The carpenter is hard at work on your house, up at the north of the glade. About %d minute%s to go." % [mins, "" if mins == 1 else "s"])


func update(delta: float) -> void:
	if not _active:
		return
	if not _view.built and _view.build_progress() >= 1.0:
		_finish(true)
	_update_carpenter(delta)


## Examining the carpenter while she works: how long is left.
func examine_builder() -> void:
	if _view == null or _view.built:
		_host.show_hint("\"All done. Enjoy it!\"")
		return
	var left := _view.seconds_left()
	var mins := int(ceil(left / 60.0))
	var line := "\"Nearly there, a minute or so.\"" if mins <= 1 else "\"Coming along nicely. About %d minutes more.\"" % mins
	if _view.progress < 0.3:
		line = "\"Just getting the frame up. About %d minutes, and you'll have a roof over your head.\"" % mins
	_companion.notify_interaction(_entry.get("pos", _player.position), "carpenter", ["person"])
	_host.show_hint(line)


# ── finishing ──

func _finish(seen: bool) -> void:
	_view.finish()
	var house: Dictionary = _view.house
	# The rugs, plinths and shelves go down.
	var plates: Array = _data.get("plates", [])
	for p in house.get("built_plates", []):
		plates.append(p)
	_data["plates"] = plates
	_world_art.refresh_plates(_data)
	# The furniture walls in.
	for b in _data.get("buildings", []):
		if String(b.get("view", "")) == "house":
			var solids: Array = b.get("solid_rects", [])
			for r in house.get("furniture_solids", []):
				solids.append(r)
			b["solid_rects"] = solids
	if _host.has_method("rebuild_world_solids"):
		_host.rebuild_world_solids()
	# Your finds move in.
	_move_finds_inside(house)
	if seen:
		_host.show_hint("Your house is finished! Step inside: everything you've found has moved in with you." if _mine else "The house is finished!")
		_companion.delight_at(_view.position + Vector2(0, 20))
	if _carpenter != null:
		_leaving = true


## The keepsakes onto the display spots (in the order of the glade's spots, so the favourite is by the fire),
## every other find onto the curio shelves, as Server.HomeWorld lays out a built house.
func _move_finds_inside(house: Dictionary) -> void:
	var display: Array = house.get("display_spots", [])
	if _home_dir != null:
		_home_dir.move_into_house(display)
	var shown := {}
	for e in _interactables:
		if String(e.get("keepsake", "")) != "" and not bool(e.get("_taken", false)):
			shown[String(e["keepsake"])] = true
		if String(e.get("curio", "")) != "":
			shown[String(e["curio"])] = true
	var curio_spots: Array = house.get("curio_spots", [])
	var k := 0
	for f in (_data.get("home", {}) as Dictionary).get("finds", []):
		var id := String(f.get("id", ""))
		if shown.has(id) or k >= curio_spots.size():
			continue
		var pos := WorldData.to_vec2(curio_spots[k])
		k += 1
		var ri := _world_art.add_interactable(pos, WorldData.to_color(f.get("color", [0.7, 0.7, 0.7])), String(f.get("type", "chime_stone")))
		_interactables.append({
			"pos": pos, "label": String(f.get("label", "something you found")), "id": "curio_" + id, "tags": ["keepsake"],
			"kind": "prop", "render_index": ri, "lore": String(f.get("line", "")), "affordances": {}, "curio": id,
		})
	_host.secret_taken()   # (the examine scan's cache is stale)


# ── the carpenter ──

func _spawn_carpenter() -> void:
	var cfg: Dictionary = _view.house.get("carpenter", {})
	for s in cfg.get("work_spots", []):
		_spots.append(WorldData.to_vec2(s))
	if _spots.is_empty():
		_spots.append(_view.position + Vector2(0, 24))
	_carpenter = PLAYER_SCENE.instantiate() as PlayerView
	_carpenter.set_remote()
	_carpenter.name = "Carpenter"
	_carpenter.set_style(_style)
	_scenery.add_child(_carpenter)
	_carpenter.apply_identity(cfg.get("appearance", {}))
	_carpenter.position = _spots[0]
	_walk = _spots[0]
	_carpenter.set_remote_state(_spots[0], Vector2.UP)
	_hammer = AxeView.new()
	_hammer.tool = "hammer"
	_hammer.name = "Hammer"
	_carpenter.add_child(_hammer)
	_work = 3.0
	_entry = {
		"pos": _spots[0], "label": "the carpenter", "id": "house_carpenter", "tags": ["person"], "kind": "prop",
		"render_index": -1, "lore": "", "affordances": {}, "house_builder": true,
	}
	_interactables.append(_entry)


func _update_carpenter(delta: float) -> void:
	if _carpenter == null or not is_instance_valid(_carpenter):
		return
	if _leaving:
		# She heads off down the path and is gone.
		var away := _view.position + Vector2(0, 160)
		var before := _walk
		_walk = _walk.move_toward(away, WALK_SPEED * delta)
		_carpenter.set_remote_state(_walk, _walk - before)
		_entry["pos"] = _carpenter.position
		_carpenter.modulate.a = clampf(_carpenter.position.distance_to(away) / 80.0, 0.0, 1.0)
		if _carpenter.position.distance_to(away) < 3.0:
			_entry["_taken"] = true
			_carpenter.queue_free()
			_carpenter = null
		return
	var target: Vector2 = _spots[_spot]
	if _walk.distance_to(target) > 0.5:
		var before := _walk
		_walk = _walk.move_toward(target, WALK_SPEED * delta)
		_carpenter.set_remote_state(_walk, _walk - before)
	elif _carpenter.position.distance_to(target) < 2.0:
		# Hammering, facing the house.
		_carpenter.set_remote_state(target, (_view.position + Vector2(0, -_view.depth * 0.5)) - target)
		_swing -= delta
		if _swing <= 0.0:
			_swing = HAMMER_GAP
			_hammer.swing()
		_work -= delta
		if _work <= 0.0:
			_spot = (_spot + 1) % _spots.size()
			_work = randf_range(3.0, 6.0)
	_entry["pos"] = _carpenter.position
