class_name HomeDirector
extends Node
## A player's HOME, in the world (H6/H7, HS-3..HS-6, FR-5; docs/home-world-and-secrets-design.md).
## Active only in a home ("home:<owner>"). What it does depends on whose home it is:
##
##   * **Your own:** your companion looks over everything you've found and chooses its keepsakes
##     (KeepsakeChoice, pure logic). New finds settle into empty spots; now and then a clearly
##     better-loved find replaces one, and you SEE it happen: the companion trots to the old keepsake,
##     carries it off to the journal, and the new one stands in its place. The choice goes to the server
##     so it's stable, along with the spots the bond has opened (the glade widens on the next visit).
##     Then the companion settles by its favourite.
##   * **Someone else's:** if they're away, their companion is here anyway, napping by its favourite
##     keepsake. It peeks up at you, a little shy, when you come near. It's a stand-in drawn from how
##     their companion looks; it vanishes the moment they arrive and their real one walks in with them.
##
## Presentation-coupled (it moves the companion's body and draws keepsakes), so it lives under
## /presentation; the choosing itself is KeepsakeChoice in /world.

const COMPANION_SCENE := preload("res://scenes/companion.tscn")
## How long the companion takes to reach a keepsake before it's carried off (a swap).
const SWAP_DELAY := 2.2
## How near a visitor comes before the napping stand-in peeks up at them.
const GREET_RADIUS := 90.0

var _host: Node
var _companion: CompanionView
var _player: PlayerView
var _world_art: WorldArt
var _presence: PresenceDirector
var _scenery: Node2D
var _style: ArtStyle

var _active := false
var _home: Dictionary = {}
var _owner_id := ""
var _resident: CompanionView
var _greeted := false


func setup(host: Node, companion: CompanionView, player: PlayerView, world_art: WorldArt, presence: PresenceDirector, scenery: Node2D, style: ArtStyle) -> void:
	_host = host
	_companion = companion
	_player = player
	_world_art = world_art
	_presence = presence
	_scenery = scenery
	_style = style


func is_active() -> bool:
	return _active


## Whose home this is ("" outside a home).
func owner_id() -> String:
	return _owner_id


## The world is laid out and everyone placed: start the home's beats. A no-op in any other world.
func begin(data: Dictionary, interactables: Array) -> void:
	_home = data.get("home", {})
	_active = WorldRouter.current_world.begins_with(WorldRouter.HOME_PREFIX) and not _home.is_empty()
	if not _active:
		return
	_owner_id = String(_home.get("owner_id", ""))
	if _owner_id == Net.local_id():
		_arrange_keepsakes(interactables)
	else:
		_spawn_resident(interactables)
		var owner_name := String(_home.get("owner_name", "someone"))
		_host.show_hint("%s's home." % owner_name)


func update(_delta: float) -> void:
	if not _active or _resident == null or not is_instance_valid(_resident):
		return
	# The owner just arrived (or left): their real companion walks with them, so the stand-in steps aside.
	_resident.visible = not _presence.has_peer(_owner_id)
	if not _resident.visible:
		return
	var to_player := _player.position - _resident.position
	if to_player.length() <= GREET_RADIUS:
		_resident.set_remote_state(_resident.position, to_player)
		if not _greeted:
			_greeted = true
			_host.show_hint("%s's companion is napping by its favourite keepsake. It peeks up at you, a little shy." % String(_home.get("owner_name", "Their")))


# --- your own home: the companion chooses ----------------------------------------------------

func _arrange_keepsakes(interactables: Array) -> void:
	if not _companion.is_met():
		return
	var finds: Array = _home.get("finds", [])
	var positions: Array = _home.get("spot_positions", [])
	var bond_spots := KeepsakeChoice.spots_for_bond(_companion.bond_value())
	var identity: Dictionary = _companion.self_dict().get("identity", {})
	# Only the spots already open in this glade can be filled now; the bond's new ones open next visit.
	var r := KeepsakeChoice.choose(finds, identity, mini(bond_spots, maxi(positions.size(), KeepsakeChoice.MIN_SPOTS)), _home.get("keepsakes", []))
	var by_id: Dictionary = {}
	for f in finds:
		by_id[String(f.get("id", ""))] = f

	if String(r["swapped_out"]) != "":
		_swap(interactables, String(r["swapped_out"]), by_id.get(String(r["swapped_in"]), {}))
	var labels: Array = []
	for id in r["filled"]:
		var pos: Variant = _free_spot(interactables, positions)
		if pos == null:
			break
		_place(interactables, by_id[id], pos)
		labels.append(String(by_id[id].get("label", "a keepsake")))
	if not labels.is_empty():
		_host.show_hint("Your companion settles %s in a spot of its own." % SecretDirector.names_phrase(labels))

	if bool(r["changed"]) or bond_spots != int(_home.get("spots", 3)):
		Net.set_keepsakes(r["keep"], bond_spots)
	if not (r["keep"] as Array).is_empty():
		_settle_by(interactables, String(r["keep"][0]), 0.6 if String(r["swapped_out"]) == "" else SWAP_DELAY + 1.4)


## The companion trots to the keepsake it's letting go of, carries it off to the journal, and the new
## favourite stands in its place.
func _swap(interactables: Array, out_id: String, new_find: Dictionary) -> void:
	var old := _keepsake_entry(interactables, out_id)
	if old.is_empty() or new_find.is_empty():
		return
	var pos: Vector2 = old["pos"]
	_companion.issue_command("visit", pos)
	get_tree().create_timer(SWAP_DELAY).timeout.connect(func() -> void:
		old["_taken"] = true
		_world_art.take_interactable(int(old["render_index"]))
		_place(interactables, new_find, pos)
		_host.secret_taken()  # (the examine scan's cache is stale either way)
		_host.show_hint("Your companion carries %s off to the journal, and settles %s in its place." % [old["label"], String(new_find.get("label", "a keepsake"))]))


func _place(interactables: Array, find: Dictionary, pos: Vector2) -> void:
	var id := String(find.get("id", ""))
	var render_index := _world_art.add_interactable(pos, WorldData.to_color(find.get("color", [0.7, 0.7, 0.7])), String(find.get("type", "chime_stone")))
	interactables.append({
		"pos": pos, "label": String(find.get("label", "a keepsake")), "id": "keepsake_" + id, "tags": ["keepsake"],
		"kind": "prop", "render_index": render_index, "lore": String(find.get("line", "")), "affordances": {},
		"keepsake": id,
	})


## The companion goes and settles by its favourite keepsake (a moment after arriving, or after a swap).
func _settle_by(interactables: Array, id: String, delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		var e := _keepsake_entry(interactables, id)
		if not e.is_empty():
			_companion.issue_command("visit", e["pos"] + Vector2(16, 8)))


func _keepsake_entry(interactables: Array, id: String) -> Dictionary:
	for e in interactables:
		if String(e.get("keepsake", "")) == id and not bool(e.get("_taken", false)):
			return e
	return {}


## The first open spot no keepsake stands on, or null.
func _free_spot(interactables: Array, positions: Array) -> Variant:
	for p in positions:
		var spot := WorldData.to_vec2(p)
		var taken := false
		for e in interactables:
			if String(e.get("keepsake", "")) != "" and not bool(e.get("_taken", false)) and (e["pos"] as Vector2).distance_to(spot) < 4.0:
				taken = true
		if not taken:
			return spot
	return null


# --- someone else's home: the resident --------------------------------------------------------

func _spawn_resident(interactables: Array) -> void:
	var resident: Dictionary = _home.get("resident", {})
	if resident.is_empty():
		return
	var spot := _player.position + Vector2(120, -60)
	for e in interactables:
		if String(e.get("keepsake", "")) != "":
			spot = e["pos"]
			break
	spot += Vector2(18, 10)
	_resident = COMPANION_SCENE.instantiate() as CompanionView
	_resident.set_remote()
	_resident.name = "ResidentCompanion"
	_resident.set_style(_style)
	_scenery.add_child(_resident)
	var look: Variant = resident.get("companion_look", {})
	if look is Dictionary:
		_resident.apply_remote_look(look)
	var form: Variant = resident.get("companion_form", {})
	if form is Dictionary:
		_resident.apply_remote_form(String((form as Dictionary).get("species", "")), int((form as Dictionary).get("variant", 0)))
	_resident.position = spot
	_resident.set_remote_state(spot, Vector2.LEFT)
