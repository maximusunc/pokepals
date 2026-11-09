class_name FetchDirector
extends Node
## The SILVER THIMBLE (Thimblewick's secret), behind a gap in the garden fence much too small for you. You ask
## your companion to "Go look"; in a shape small enough (a rabbit) it squeezes through the nearest gap, is gone a few
## seconds, and comes back carrying something and sets it down at your feet. What it brings depends on the gap and
## on how well you know each other (a pebble, then a button, then the thimble). This is the presentation half; the
## decisions live in the pure FetchTrip (scripts/world). It:
##   * on the ask, picks the nearest gap to YOU (in range) and starts the trip; says so, gently, when there is no gap
##     near enough, or when it is already off on an errand;
##   * each frame turns the trip's answer into a "guide" command for the companion's brain (trot to the gap's mouth,
##     later bring the find to you), reusing the Drifthallow lead and the NavAgent routing: no new movement;
##   * while the trip controls the body (squeeze, away, emerge) PLACES it itself: the companion shrinks into the gap and
##     is hidden, its mind paused exactly as the first meeting's does, and walks the far side unseen (so a friend, who
##     is sent its position as usual, sees it scamper about behind the fence); then it slips out and the brain resumes;
##   * shows what happens: a rustle in the grass behind the fence while it is away (FetchFx), a burst when it has
##     found something, the find held over its head while it is carried (FetchFx), a first-time hint for each phase;
##   * sets the find down: an ordinary small find becomes a plain examinable prop at your feet (a few may lie about,
##     the oldest is taken away); the THIMBLE is handed to the SecretDirector, which turns it into the secret's prop
##     (and the usual claim on examine). Each trip warms the bond a little (tapering, so it cannot be farmed);
##   * as you come near a gap the companion NOTICES it and points toward it (FetchTrip.notice), further off the deeper
##     the bond.
## Natural player actions never silently reset it: a Call ends the trip on its way out (or brings the companion back
## early while it is away); a Pet is enjoyed and the trip carries on; walking off is fine, it finds you; changing its
## shape before it squeezes just makes the gap too small (and says so). Everything is personal: nothing is networked
## but the companion's ordinary position, which a friend sees move behind the fence.
## All numbers and every line come from the secret's `reveal` block, so the next world to hide something behind a
## fence is data only.

signal thimble_dropped(pos: Vector2, line: String)

const MAX_LYING := 3        # ordinary finds lying about; the oldest is taken away when another is set down

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _trip: FetchTrip
var _reveal: Dictionary = {}
var _lines: Dictionary = {}
var _items: Dictionary = {}
var _interactables: Array = []
var _found := false             # the secret is already ours: the thimble is an ordinary find now
var _said := {}
var _controlling := false       # the trip is placing the companion's body (its mind paused)
var _pointing := false
var _rustle: FetchFx = null
var _carry: FetchFx = null
var _lying: Array = []          # [{ entry, render_index }] ordinary finds on the ground
var _drops := 0
var _more_cd := 0
var _next_id := 0
var _lift := 0.0                # the camera's eased upward look (px) while the companion is behind the fence


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


## Lay out this world's gaps from the secret ({ reveal: { gaps, items, lines, ... } }). `interactables` is the
## controller's examine list (ordinary finds are added to it).
func configure(secret: Dictionary, found: bool, interactables: Array) -> void:
	_reveal = secret.get("reveal", {})
	_lines = _reveal.get("lines", {})
	_items = _reveal.get("items", {})
	_interactables = interactables
	_found = found
	_said = {}
	var gaps: Array = []
	for g in _reveal.get("gaps", []):
		gaps.append({
			"id": String(g["id"]),
			"mouth": WorldData.to_vec2(g["mouth"]),
			"inside": WorldData.to_vec2(g["inside"]),
			"cache": WorldData.to_vec2(g["cache"]),
			"finds": g.get("finds", []),
		})
	_trip = FetchTrip.new(gaps, _reveal)
	if _carry == null and _companion != null:
		_carry = FetchFx.new()
		_carry.mode = "carry"
		_carry.name = "FetchCarry"
		_carry.lift = float(_reveal.get("carry_lift", 26.0))
		_companion.add_child(_carry)


func trip() -> FetchTrip:
	return _trip


## The secret is ours (claimed here or elsewhere): the thimble is just another find from now on.
func set_found() -> void:
	_found = true


## Whether "Go look" is on the radial: always in a fetch world once the companion is yours (asking while it is away
## says so, in its own words, instead of the button vanishing).
func available() -> bool:
	return _trip != null and _companion != null and _companion.is_met()


func is_busy() -> bool:
	return _trip != null and _trip.is_busy()


## The player's ask ("Go look"): send the companion through the nearest gap.
func ask() -> void:
	if _trip == null or _companion == null or _player == null or not _companion.is_met():
		return
	if _trip.is_busy():
		_say_always("busy")
		return
	if not _trip.can_ask():
		return   # a beat of cooldown just after a drop: nothing to say
	var gap := _trip.nearest_gap(_player.position)
	if gap < 0:
		_say_always("no_gap")
		return
	if _trip.ask(gap, _companion.bond_value()):
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false
		_say("set_off")


## The controller tore the world down, or the secret is no more: hand the companion its body back.
func _exit_tree() -> void:
	var cam: Variant = _host.get("_camera") if _host != null and is_instance_valid(_host) else null
	if cam != null and cam is Camera2D:
		(cam as Camera2D).offset = Vector2.ZERO
	_release()
	if is_instance_valid(_rustle):
		_rustle.queue_free()
	if is_instance_valid(_carry):
		_carry.queue_free()


## Per frame (SecretDirector.update drives it).
func update(delta: float) -> void:
	if _trip == null or _player == null or _companion == null or delta <= 0.0:
		return
	_ensure_rustle()
	var ctx := {
		"companion_pos": _companion.position, "player_pos": _player.position, "bond": _companion.bond_value(),
		"species": _companion.current_form_species(), "pending": _companion.pending_command(),
	}
	var r := _trip.update(delta, ctx)
	if _trip.is_busy():
		# the shape must hold while it works (and, in GO, until it squeezes through)
		_companion.postpone_form_drift(float(_reveal.get("drift_hold", 30.0)))
	if bool(r["control"]):
		_place(r["body"] as Dictionary)
	elif _controlling:
		_release()
	if String(r["command"]) == "guide":
		_companion.issue_command("guide", r["target"], { "hold": bool(r["hold"]), "speed": float(r["speed"]) })
	_carry.item = String(r["carry"]) if _carry != null else ""
	for e in r["events"]:
		_on_event(String(e))
	var drop: Dictionary = r["drop"]
	if not drop.is_empty():
		_on_drop(drop)
	_update_notice(delta)
	_update_camera(delta)


## While the companion is on the far side of the fence the camera looks a little north, so the rustle in the grass
## (and its slipping back out) is in view even when you stand some way off. Camera2D.offset is the framing's free
## knob; ShadowDirector uses it the same way in Lanternfold. It eases back down once the companion is out.
func _update_camera(delta: float) -> void:
	var cam: Variant = _host.get("_camera") if _host != null else null
	if cam == null or not (cam is Camera2D):
		return
	var want := 0.0
	var g := _trip.current_gap()
	if g >= 0 and _controlling:
		# look far enough north that the cache (where the grass shivers hardest) is a little way in from the top of the
		# view, but never so far that the player slips off the bottom of it
		var rise: float = _player.position.y - (_trip.gaps()[g]["cache"] as Vector2).y
		if rise < 520.0:
			want = -clampf(rise - 110.0, 0.0, float(_reveal.get("camera_lift", 120.0)))
	_lift = move_toward(_lift, want, delta * 90.0)
	(cam as Camera2D).offset = Vector2(0.0, _lift)


## While the trip owns the body: its mind is paused, it is put where the trip says, shrunk, and hidden when it is
## properly through. (A friend still sees the position, which keeps moving behind the fence.)
func _place(body: Dictionary) -> void:
	if not _controlling:
		_controlling = true
		_companion.set_process(false)
		_companion.velocity = Vector2.ZERO
		_companion.point_at(Vector2.ZERO, 0.0)
	_companion.position = body["pos"]
	var s := float(body["scale"])
	_companion.scale = Vector2(s, s)
	_companion.visible = not bool(body["hidden"])


func _release() -> void:
	if not _controlling or _companion == null or not is_instance_valid(_companion):
		return
	_controlling = false
	_companion.scale = Vector2.ONE
	_companion.visible = true
	_companion.set_process(true)


## The rustle stands behind the fence at the gap the trip is at, in the companion's own (y-sorted) layer.
func _ensure_rustle() -> void:
	if _rustle == null or not is_instance_valid(_rustle):
		var parent := _companion.get_parent()
		if parent == null:
			return
		_rustle = FetchFx.new()
		_rustle.mode = "rustle"
		_rustle.name = "FetchRustle"
		parent.add_child(_rustle)
	var g := _trip.current_gap()
	if g >= 0:
		# the grass shivers wherever the hidden companion is (it scampers in from the gap and back), so you can
		# follow it behind the fence; at the gap's inside while it squeezes through
		var spot: Vector2 = _companion.position if _trip.is_hidden() else (_trip.gaps()[g]["inside"] as Vector2)
		_rustle.position = spot + Vector2(0.0, 6.0)
	_rustle.set_active(_trip.is_hidden())


func _on_event(event: String) -> void:
	match event:
		"squeeze":
			_companion.delight_at(_companion.position)
		"gone":
			_say("gone")
		"found":
			if _rustle != null:
				_rustle.burst()
		"missing":
			_say("missing")
		"hurry":
			if _rustle != null:
				_rustle.burst()
			_say_always("hurry")
		"carrying":
			_say("carrying")
		"too_big":
			_say_always("too_big")
		"gave_up_big":
			_say("gave_up_big")
		"lost_way":
			_say_always("lost_way")
		"called_off":
			_say_always("called_off")
		"set_down":
			_say_always("set_down")


## The find is set down at the player's feet: warm the bond, and show it.
func _on_drop(drop: Dictionary) -> void:
	_drops += 1
	_companion.warm_bond(float(drop["warm"]))
	var item_id := String(drop["item"])
	var item: Dictionary = _items.get(item_id, {})
	var pos: Vector2 = drop["pos"]
	var line := String(item.get("drop", ""))
	# an unmet hint that a deeper bond finds more, now and then (the first time, then every third trip)
	if bool(drop["more"]):
		if _more_cd <= 0:
			var more := String(_lines.get("more", ""))
			if more != "":
				line = (line + " " + more).strip_edges()
			_more_cd = 3
		_more_cd -= 1
	if item_id == "thimble" and not _found:
		# the secret: hand it to the SecretDirector (its prop, its claim on examine, its own reveal line)
		_companion.delight_at(pos)
		thimble_dropped.emit(pos, String(_reveal.get("reveal_line", line)) if line == "" else line)
		return
	_lay(item_id, item, pos)
	_companion.delight_at(pos)
	if line != "" and _host != null:
		_host.show_hint(line)


## An ordinary find: a plain examinable prop on the ground (a few may lie about, the oldest is taken away).
func _lay(item_id: String, item: Dictionary, pos: Vector2) -> void:
	var color := WorldData.to_color(item.get("color", [0.7, 0.7, 0.7]))
	var render_index := _world_art.add_interactable(pos, color, String(item.get("type", "find_pebble")))
	_next_id += 1
	var tags: Array = ["small", "found", item_id]
	var entry := {
		"pos": pos, "label": String(item.get("label", "a small find")), "id": "fetched_%d" % _next_id, "tags": tags,
		"kind": "prop", "render_index": render_index, "lore": String(item.get("lore", "")),
		"affordances": {}, "form_effects": {}, "flare": false,
	}
	_interactables.append(entry)
	_lying.append({ "entry": entry, "render_index": render_index })
	while _lying.size() > MAX_LYING:
		var old: Dictionary = _lying.pop_front()
		(old["entry"] as Dictionary)["_taken"] = true
		_world_art.take_interactable(int(old["render_index"]))
	if _host != null:
		_host.secret_taken()   # the examine scan's cached nearest is stale


## The companion noticing a gap as you come near: a held point toward it, released when the notice ends or a trip begins.
func _update_notice(delta: float) -> void:
	if not _companion.is_met():
		return
	var n := _trip.notice(delta, _player.position, _companion.bond_value())
	if bool(n["point"]):
		_companion.point_at(n["target"], 1.0)
		_pointing = true
		if bool(n["started"]):
			_say("notice")
	elif _pointing:
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false


## A hint line, once per visit (a missing line says nothing).
func _say(key: String) -> void:
	if _said.has(key):
		return
	_said[key] = true
	_say_always(key)


func _say_always(key: String) -> void:
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)
