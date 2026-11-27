class_name TideDirector
extends Node
## EBBMERE's tide and what it uncovers: the presentation half. The decisions live in the pure TideClock (the
## shared tide), TideField (the seabed), DigPlan (what is buried where, this tide) and DigSense (the companion
## sniffing it out), all in scripts/world and tested; the drawing is TideLayer (the sea), DigSites (signs, holes
## and finds), TideGauge (the tide pole) and LampGlow (the lighthouse). This node ties them together each frame:
##   * it reads the shared clock, hands the water level to the layer, and says (once, kindly) what the tide is
##     doing: going out, lowest tide coming, lowest tide, coming back, high water;
##   * while spots are uncovered it lets your companion SNIFF them out: stop, nose down, point (scaled by
##     bond); a spot it has pointed at, or that you or it walk right up to, shows a ring of bubbles;
##   * it takes the player's tap on such a spot as a DIRECT ORDER through the companion's form: a form that can
##     dig (the spec's `dig.affordances`: fox, rabbit, wolf) goes and digs; one that cannot (a bird, a cat) goes
##     and pats at the sand and says so; the order is the same `visit` command the Vale's mounds use, so a Pet
##     or a Call still takes over and nothing is ever lost (a spot stays buried until the tide takes it);
##   * a dig brings up a shell, sea-glass or a crab that scuttles off, and on the far bar, in the lowest window,
##     the sand-dollar (`dollar_unearthed`, which the SecretDirector turns into the usual examine-and-claim).
## The tide is the shared clock; the dig spots' state is personal and display-only (a friend sees the same
## water and the same spots alive, but not your holes). Nothing is networked. Whether you may take the
## sand-dollar stays the server's call: it checks the clock too (Server.Tide).
## The numbers come from the spec's `tide` and `dig` blocks.

signal dollar_unearthed

const LOW_SOON_S := 24.0

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _tide: Dictionary = {}
var _dig: Dictionary = {}
var _field: TideField
var _layer: TideLayer
var _sites: DigSites
var _gauge: TideGauge
var _lamp: LampGlow
var _spots: Array = []          # { id, pos, elev }
var _sense: DigSense
var _found := false
var _configured := false
var _built := false

var _cycle := -1000000
var _noticed := {}              # spot id -> true, this tide
var _dug := {}                  # spot id -> { kind, name, age }, this tide
var _order: Dictionary = {}     # { id, pos, t }: the companion is on its way to dig
var _digging: Dictionary = {}   # { id, pos, t }: it is digging
var _pointing := false
var _pet_pause := 0.0
var _call_pause := 0.0
var _said := {}                 # first-time hints, this session
var _cycle_said := {}           # per-tide hints
var _shift_ms := 0              # a test/debug shift of the clock
var _level := 0.5
var _spray_t := 0.0


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


## Lay the world's tide and dig spots out from its spec (the whole spec: `tide` and `dig` blocks).
func configure(data: Dictionary, found: bool) -> void:
	_tide = data.get("tide", {})
	_dig = data.get("dig", {})
	_found = found
	_field = TideField.from_spec(_tide.get("field", {}), float(_tide.get("deep_elev", 0.26)))
	_spots = []
	for s in _dig.get("spots", []):
		var pos := WorldData.to_vec2(s["position"])
		_spots.append({ "id": String(s["id"]), "pos": pos, "elev": _field.elev_at(pos) })
	_sense = DigSense.new(_dig)
	_configured = not _field.is_empty()
	_noticed = {}
	_dug = {}
	_order = {}
	_digging = {}
	_cycle = -1000000


## The world is drawn: put the sea, the signs, the tide pole and the lamp into it.
func after_world_drawn() -> void:
	if not _configured or _built:
		return
	_built = true
	_layer = TideLayer.new()
	_layer.name = "TideLayer"
	_world_art.add_child(_layer)
	if not _layer.setup(_tide, _field, Callable(_host, "_walkers")):
		_layer.queue_free()
		_layer = null
	_sites = DigSites.new()
	_sites.name = "DigSites"
	_world_art.add_child(_sites)
	var scenery: Node = _host.get("_scenery")
	if scenery != null:
		if _tide.has("gauge"):
			_gauge = TideGauge.new()
			_gauge.name = "TideGauge"
			_gauge.position = WorldData.to_vec2(_tide["gauge"])
			scenery.add_child(_gauge)
			_gauge.configure(_tide)
		if _tide.has("lamp"):
			_lamp = LampGlow.new()
			_lamp.name = "LampGlow"
			var lamp := WorldData.to_vec2(_tide["lamp"])
			_lamp.lamp_offset = Vector2(0, -121)
			_lamp.position = lamp + Vector2(0, 121 + 2)   # the tower's foot: it sorts in front of the tower
			scenery.add_child(_lamp)


func layer() -> TideLayer:
	return _layer


func field() -> TideField:
	return _field


func sites() -> DigSites:
	return _sites


func spots() -> Array:
	return _spots


func level() -> float:
	return _level


## The secret has been taken: the flats keep their digging, minus the sand-dollar.
func finish() -> void:
	_found = true


## The shared time, in unix ms: the server's clock (as the last join told us) plus a debug shift.
func now_ms() -> int:
	return Net.server_unix_ms() + _shift_ms


## Tests and debugging: make the tide read as though it were `ms` right now (it keeps running from there).
func debug_set_time_ms(ms: int) -> void:
	_shift_ms = 0
	_shift_ms = ms - now_ms()


func _say_once(key: String, line: String) -> void:
	if _said.has(key) or line == "" or _host == null:
		return
	_said[key] = true
	_host.show_hint(line)


func _hint(key: String) -> String:
	return String((_tide.get("hints", {}) as Dictionary).get(key, ""))


func _line(key: String) -> String:
	return String((_dig.get("lines", {}) as Dictionary).get(key, ""))


## The dig spots alive in this tide and uncovered by the water right now.
func visible_spots() -> Array:
	var out: Array = []
	var frac := float(_dig.get("active_fraction", 0.6))
	var margin := float(_tide.get("expose_margin", 0.012))
	var dollar := String(_dig.get("dollar_spot", ""))
	for s in _spots:
		var always: bool = String(s["id"]) == dollar and not _found
		if DigPlan.is_active(_cycle, String(s["id"]), frac, always) and DigPlan.exposed(float(s["elev"]), _level, margin):
			out.append(s)
	return out


## Per frame (SecretDirector.update drives it).
func update(delta: float) -> void:
	if not _configured or _player == null or _companion == null or delta <= 0.0:
		return
	var now := now_ms()
	_level = TideClock.level(_tide, now)
	var cycle := TideClock.cycle(_tide, now)
	if cycle != _cycle:
		# a new tide: the sea has smoothed the sand, so every hole is gone and every spot is buried afresh
		_cycle = cycle
		_noticed = {}
		_dug = {}
		_order = {}
		_digging = {}
		_cycle_said = {}
		_sense.reset()
	var state := TideClock.state(_tide, now)
	if _layer != null:
		_layer.set_level(_level)
	if _gauge != null:
		_gauge.set_state(_level, TideClock.phase(_tide, now) >= 0.5, state == "low")
	if _lamp != null:
		var lo := float(_tide.get("level_low", 0.30))
		var hi := float(_tide.get("level_high", 0.78))
		_lamp.set_low(1.0 - (_level - lo) / maxf(0.001, hi - lo))
	_update_hints(now, state)

	# What a player naturally does must not be swallowed by our own orders (the brain's slot holds ONE).
	var pc := _companion.pending_command()
	if pc == "pet":
		_pet_pause = 3.0
	elif pc == "come":
		_call_pause = 4.0
	_pet_pause = maxf(0.0, _pet_pause - delta)
	_call_pause = maxf(0.0, _call_pause - delta)
	var free := _pet_pause <= 0.0 and _call_pause <= 0.0 and pc != "pet" and pc != "come"

	var vis := visible_spots()
	_update_digging(delta, vis)
	_update_sniffing(delta, vis, free)
	_update_sites(vis)


# --------------------------------------------------------------------------------------------------- hints
func _update_hints(now: int, state: String) -> void:
	var hi := float(_tide.get("level_high", 0.78))
	match state:
		"low":
			if not _cycle_said.has("low"):
				_cycle_said["low"] = true
				if _said.has("low"):
					_host.show_hint(_hint("low_short"))
				else:
					_say_once("low", _hint("low"))
		"ebbing":
			if TideClock.seconds_until_low(_tide, now) <= LOW_SOON_S:
				if not _cycle_said.has("low_soon"):
					_cycle_said["low_soon"] = true
					if _said.has("low_soon"):
						_host.show_hint(_hint("low_soon_short"))
					else:
						_say_once("low_soon", _hint("low_soon"))
			else:
				_say_once("ebbing", _hint("ebbing"))
		_:
			if _level > hi - 0.04:
				_say_once("high", _hint("high"))
			else:
				_say_once("flooding", _hint("flooding"))


# ------------------------------------------------------------------------------------------- sniffing
func _update_sniffing(delta: float, vis: Array, free: bool) -> void:
	var busy := not _order.is_empty() or not _digging.is_empty()
	var cands: Array = []
	for s in vis:
		if not _noticed.has(String(s["id"])) and not _dug.has(String(s["id"])):
			cands.append({ "id": s["id"], "pos": s["pos"] })
	# a spot right by you or your companion is simply seen
	for id in _sense.seen_by_eye(cands, _player.position, _companion.position):
		_notice(String(id))
	var rest: Array = []
	for c in cands:
		if not _noticed.has(String(c["id"])):
			rest.append(c)
	if busy or not free:
		if _pointing:
			_companion.point_at(Vector2.ZERO, 0.0)
			_pointing = false
		return
	var r := _sense.update(delta, _player.position, _companion.bond_value(), rest)
	if r["point"]:
		_companion.point_at((r["target"] as Vector2) + Vector2(0.0, -2.0), 1.0)
		_pointing = true
		if r["started"]:
			_say_once("sniff", _line("sniff"))
	elif _pointing:
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false
	if String(r["noticed"]) != "":
		_notice(String(r["noticed"]))


func _notice(id: String) -> void:
	if _noticed.has(id):
		return
	_noticed[id] = true
	_say_once("sign", _line("sign"))


# ----------------------------------------------------------------------------------------------- the sign
func _can_dig() -> bool:
	return DigPlan.verb_for(_companion.current_form_species(), _dig.get("affordances", {})) != ""


func _update_sites(vis: Array) -> void:
	if _sites == null:
		return
	var color := Color(0.98, 0.92, 0.62)
	var style: Variant = _host.get("_style")
	if style != null:
		color = (style as ArtStyle).form_highlight_color(_companion.current_form_species())
	var can := _can_dig()
	var signs: Array = []
	var holes: Array = []
	for s in vis:
		var id := String(s["id"])
		if _dug.has(id):
			holes.append({ "pos": s["pos"], "kind": String(_dug[id]["kind"]), "name": String(_dug[id].get("name", "")) })
		elif _noticed.has(id):
			signs.append({ "pos": s["pos"], "color": color, "pulse": can })
	_sites.signs = signs
	_sites.holes = holes


# ---------------------------------------------------------------------------------------------- the order
## A tap on the world: if it lands on an uncovered spot you have seen (or your companion has sniffed out),
## it is an ORDER to the companion through its worn form. Returns whether it took the tap.
func on_spot_tap(world: Vector2) -> bool:
	if not _configured or _companion == null:
		return false
	var best: Dictionary = {}
	var best_d := float(_dig.get("tap_radius", 54.0))
	for s in visible_spots():
		var id := String(s["id"])
		if not (_noticed.has(id) or _dug.has(id)):
			continue
		var d := world.distance_to(s["pos"])
		if d <= best_d:
			best = s
			best_d = d
	if best.is_empty():
		return false
	var id := String(best["id"])
	if _dug.has(id):
		_host.show_hint(_line("dug"))
		return true
	if not _digging.is_empty():
		return true
	var verb := DigPlan.verb_for(_companion.current_form_species(), _dig.get("affordances", {}))
	if verb == "":
		# the cue: it goes and pats at the sand, and the hint says which shapes could
		_order = {}
		_companion.issue_command("visit", best["pos"])
		if _sites != null:
			_sites.flash(best["pos"])
		_host.show_hint(_line("cant_dig"))
		return true
	_companion.issue_command("visit", best["pos"], { "verb": verb, "object_id": id })
	_order = { "id": id, "pos": best["pos"], "t": 0.0 }
	return true


func _update_digging(delta: float, vis: Array) -> void:
	if not _order.is_empty():
		_order["t"] = float(_order["t"]) + delta
		var still := false
		for s in vis:
			still = still or String(s["id"]) == String(_order["id"])
		var pc := _companion.pending_command()
		if not still or pc == "pet" or pc == "come" or float(_order["t"]) > 25.0:
			_order = {}   # the tide took the spot, or you called/petted it: a spot stays buried, tap again
		elif _companion.position.distance_to(_order["pos"]) <= float(_dig.get("arrive_distance", 40.0)):
			_digging = { "id": _order["id"], "pos": _order["pos"], "t": 0.0 }
			_order = {}
	if _digging.is_empty():
		return
	_digging["t"] = float(_digging["t"]) + delta
	var pc2 := _companion.pending_command()
	var moved_off := _companion.position.distance_to(_digging["pos"]) > float(_dig.get("arrive_distance", 40.0)) * 1.8
	if (pc2 == "pet" or pc2 == "come" or moved_off) and float(_digging["t"]) < float(_dig.get("dig_seconds", 1.8)):
		_digging = {}
		return
	_spray_t -= delta
	if _sites != null and _spray_t <= 0.0:
		_spray_t = 0.12
		_sites.add_spray(_digging["pos"], 3)
	if float(_digging["t"]) >= float(_dig.get("dig_seconds", 1.8)):
		var id := String(_digging["id"])
		var pos: Vector2 = _digging["pos"]
		_digging = {}
		_resolve_dig(id, pos)


func _resolve_dig(id: String, pos: Vector2) -> void:
	var now := now_ms()
	var in_window := TideClock.in_low_window(_tide, now, 0.0)
	var is_dollar := id == String(_dig.get("dollar_spot", ""))
	if DigPlan.dollar_ready(is_dollar, _found, in_window):
		_dug[id] = { "kind": "dollar", "name": "sand-dollar" }
		_companion.notify_interaction(pos, "dug_" + id, ["salt", "sand"])
		_companion.delight_at(pos)
		dollar_unearthed.emit()
		return
	var out := DigPlan.pick_outcome(_cycle, id, _dig.get("outcomes", []))
	_dug[id] = out
	_companion.notify_interaction(pos, "dug_" + id, ["salt", "sand"])
	_companion.delight_at(pos)
	match String(out["kind"]):
		"crab":
			# it scuttles for the sea: toward the nearer open water, which is north on these flats
			if _sites != null:
				_sites.add_crab(pos + Vector2(8, 0), Vector2(randf_range(-0.6, 0.6), -1.0))
			_host.show_hint(_line("dig_crab"))
		"glass":
			_host.show_hint(_line("dig_glass"))
		_:
			var name := String(out.get("name", "shell"))
			_host.show_hint(_line("dig_shell") % name)
