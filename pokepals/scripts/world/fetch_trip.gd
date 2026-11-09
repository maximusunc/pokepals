class_name FetchTrip
extends RefCounted
## A companion SLIPPING THROUGH A GAP TOO SMALL FOR YOU and coming back with something, as pure logic (state
## in, state out): Thimblewick's lost thimble. The player DELEGATES ("Go look") and the companion goes off
## to the nearest gap in the garden fence, squeezes through, is gone a few seconds, and returns carrying a
## find. This decides, every frame, what the companion should be doing about it. It draws nothing and knows
## no nodes: the FetchDirector feeds it positions, the worn form and the bond, and turns the answer into a
## "guide" command, a hidden/placed/shrinking body, a carried item and a hint.
##
##   IDLE     nothing happening. `ask` (from a gap in range) starts a trip.
##   GO       it trots to the gap's mouth (on the open side of the fence). A pet is enjoyed and the trip
##            carries on afterwards; a Call ends it ("called off"); if it cannot get there it gives up.
##   POKE     (only in a shape that does not fit) it nudges at the gap, cannot, and gives it up: nothing is
##            lost, and the hint says only something small and quick would fit.
##   SQUEEZE  it shrinks into the gap (the director moves the body across to the far side as it goes).
##   AWAY     gone, a few seconds (`away`, shorter as the bond deepens). The body is hidden; the director
##            plays a rustle at the gap. A Call brings it back early (`hurry_seconds`), gracefully.
##   EMERGE   it slips back out of the gap, carrying the find.
##   BRING    it carries the find to you wherever you have gone (a Call just brings it faster), and drops it
##            at your feet. If it cannot reach you in `bring_patience` seconds it simply sets the find down
##            where it stands. Nothing is ever lost.
##
## WHAT IT BRINGS depends on the gap and on the bond. Each gap has an ordered list of `finds`, each with a
## `min_bond`; the trip brings the best find whose min_bond the bond has reached, so a new companion comes
## back with a pebble and a deeply bonded one with the thimble (Thimblewick's one secret gap). The trip
## itself also WARMS the bond a little (`warm`, tapering with every trip to the same gap, so it cannot be
## farmed), which is how a fresh pair reaches the thimble in one visit without grinding.
##
## BOND shapes it (every value is a low..high pair in the data, blended by bond 0..1):
##   * `away`: how long it is gone (a bonded companion is quicker, it knows what you want);
##   * `notice_range` / `notice_cooldown`: from how far off it points at a gap, and how often.
##
## All numbers come from the secret's `reveal` block in the world spec; DEFAULTS are a safety net only.

enum Phase { IDLE, GO, POKE, SQUEEZE, AWAY, EMERGE, BRING }

const DEFAULTS := {
	"ask_range": 420.0,           # the gap must be within this of YOU for "Go look" to pick it
	"species": ["rabbit"],        # the shapes small enough to fit
	"mouth_reach": 10.0,          # arrived at the gap's mouth
	"go_speed": 100.0,
	"go_patience": 16.0,          # seconds without arriving before it gives up the way
	"poke_seconds": 1.8,          # how long it nudges at a gap it cannot fit before giving up
	"squeeze_seconds": 0.8,
	"away_low": 9.0,              # seconds gone at zero bond...
	"away_high": 5.0,             # ...and at full bond
	"hurry_seconds": 1.1,         # a Call during AWAY: this much longer, at most
	"emerge_seconds": 0.6,
	"bring_speed": 128.0,
	"drop_distance": 30.0,        # close enough to you to set the find down
	"bring_patience": 45.0,       # seconds before it sets the find down wherever it stands
	"cooldown": 2.0,              # after a drop, before the next ask
	"pet_pause": 3.0,             # a Pet is enjoyed: leave it alone this long, then carry on
	"warm": 0.045,                # the bond a trip warms (bond units)...
	"warm_decay": 0.8,            # ...times this for every earlier trip to the same gap...
	"warm_min": 0.008,            # ...but never less than this
	"notice_range_low": 240.0,
	"notice_range_high": 560.0,
	"notice_cooldown_low": 18.0,
	"notice_cooldown_high": 7.0,
	"notice_hold": 2.4,
	"rustle_every": 1.1,          # seconds between rustles while it is away
}

var phase := Phase.IDLE

var _gaps: Array = []             # [{ id, mouth: Vector2, inside: Vector2, cache: Vector2, finds: [{ item, min_bond }] }]
var _cfg: Dictionary = {}
var _gap := -1                    # the gap this trip is at
var _find: Dictionary = {}        # the find it will bring (decided as it squeezes through)
var _t := 0.0                     # seconds in the current phase
var _go_time := 0.0               # seconds spent heading for the mouth (a pet's pause does not count)
var _away := 0.0
var _hurried := false
var _found_cued := false
var _cooldown := 0.0
var _pet_left := 0.0
var _rustle_cd := 0.0
var _notice_cd := 0.0
var _notice_left := 0.0
var _notice_gap := -1
var _bond := 0.0
var _trips := {}                  # gap id -> trips completed there
var _carry_pos := Vector2.ZERO


## gaps: the world's gaps (see above; positions as Vector2). cfg: the secret's reveal block.
func _init(gaps: Array, cfg: Dictionary = {}) -> void:
	_gaps = gaps
	_cfg = DEFAULTS.duplicate(true)
	for k in cfg:
		if DEFAULTS.has(k):
			_cfg[k] = cfg[k]


func gaps() -> Array:
	return _gaps


func is_busy() -> bool:
	return phase != Phase.IDLE


## Whether a "Go look" can be asked right now (idle and past the cooldown).
func can_ask() -> bool:
	return phase == Phase.IDLE and _cooldown <= 0.0 and not _gaps.is_empty()


## Whether the body is under the director's direct control (it places it, the brain does not): the
## squeeze, the time away, and the slip back out.
func is_controlled() -> bool:
	return phase == Phase.SQUEEZE or phase == Phase.AWAY or phase == Phase.EMERGE


func is_hidden() -> bool:
	return phase == Phase.AWAY


func current_gap() -> int:
	return _gap


func carry_item() -> String:
	if phase == Phase.EMERGE or phase == Phase.BRING:
		return String(_find.get("item", ""))
	return ""


func trips_at(gap_id: String) -> int:
	return int(_trips.get(gap_id, 0))


func cfg(key: String) -> Variant:
	return _cfg[key]


## Whether `species` is small and quick enough to fit through a gap.
func fits(species: String) -> bool:
	return (_cfg["species"] as Array).has(species)


## Blend a low..high pair of the data by bond.
func at_bond(key: String, bond: float) -> float:
	return lerpf(float(_cfg[key + "_low"]), float(_cfg[key + "_high"]), clampf(bond, 0.0, 1.0))


## The gap nearest to `from` within `max_range` (default: `ask_range`), or -1.
func nearest_gap(from: Vector2, max_range: float = -1.0) -> int:
	var limit := float(_cfg["ask_range"]) if max_range < 0.0 else max_range
	var best := -1
	var best_d := limit
	for i in _gaps.size():
		var d: float = from.distance_to(_gaps[i]["mouth"])
		if d <= best_d:
			best_d = d
			best = i
	return best


## The best find a gap gives at this bond: the last entry of its `finds` (ordered by rising min_bond) whose
## min_bond the bond has reached. The first entry should have min_bond 0, so there is always something.
static func find_for(finds: Array, bond: float) -> Dictionary:
	var out: Dictionary = {}
	for f in finds:
		if bond >= float((f as Dictionary).get("min_bond", 0.0)):
			out = f
	return out


## The next find up at this bond (the one a deeper bond would bring), or {} when this is the best.
static func next_find(finds: Array, bond: float) -> Dictionary:
	for f in finds:
		if bond < float((f as Dictionary).get("min_bond", 0.0)):
			return f
	return {}


## The bond a trip to a gap warms, given how many trips it has had there already.
static func warmth(base: float, decay: float, prior_trips: int, floor_value: float) -> float:
	return maxf(floor_value, base * pow(clampf(decay, 0.0, 1.0), float(maxi(0, prior_trips))))


## Start a trip to gap `index`. False when busy, cooling down, or there is no such gap.
func ask(index: int, bond: float) -> bool:
	if not can_ask() or index < 0 or index >= _gaps.size():
		return false
	_gap = index
	_bond = bond
	phase = Phase.GO
	_t = 0.0
	_go_time = 0.0
	_pet_left = 0.0
	_find = {}
	_hurried = false
	return true


## Drop whatever is happening (the director's cue when the world is torn down, or a Call in GO).
func cancel() -> void:
	phase = Phase.IDLE
	_gap = -1
	_find = {}
	_t = 0.0


## One frame. `ctx`: companion_pos, player_pos (Vector2), bond (0..1), species (the form worn), pending (the
## player's order the brain has not taken yet: "come", "pet" or ""). Returns:
##   command:  "guide" (the director issues the guide order to `target` at `speed`, `hold` = stand still) or ""
##   target, speed, hold
##   control:  the director places the body itself this frame (`body`: position, scale, hidden)
##   body:     { pos: Vector2, scale: float, hidden: bool } while control
##   carry:    the item being carried (or "")
##   drop:     { item, pos, warm, more, gap } on the frame the find is set down, else {}
##   events:   strings for the director to turn into cues and hints
func update(delta: float, ctx: Dictionary) -> Dictionary:
	var out := {
		"command": "", "target": Vector2.ZERO, "speed": 0.0, "hold": false,
		"control": false, "body": {}, "carry": "", "drop": {}, "events": [],
	}
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if phase == Phase.IDLE:
		return out
	_t += delta
	var companion: Vector2 = ctx["companion_pos"]
	var player: Vector2 = ctx["player_pos"]
	var pending := String(ctx.get("pending", ""))
	_bond = float(ctx.get("bond", _bond))
	var gap: Dictionary = _gaps[_gap]
	var mouth: Vector2 = gap["mouth"]
	var inside: Vector2 = gap["inside"]
	var cache: Vector2 = gap["cache"]
	match phase:
		Phase.GO:
			if pending == "come":
				out["events"].append("called_off")
				cancel()
				return out
			if pending == "pet":
				_pet_left = float(_cfg["pet_pause"])
			if _pet_left > 0.0:
				_pet_left -= delta   # enjoying it: no orders, and the patience clock waits
			else:
				_go_time += delta
				out["command"] = "guide"
				out["target"] = mouth
				out["speed"] = float(_cfg["go_speed"])
				if _go_time >= float(_cfg["go_patience"]):
					out["events"].append("lost_way")
					out["command"] = ""
					cancel()
					return out
			if companion.distance_to(mouth) <= float(_cfg["mouth_reach"]):
				if fits(String(ctx.get("species", ""))):
					phase = Phase.SQUEEZE
					_t = 0.0
					_find = find_for(gap["finds"], _bond)
					out["events"].append("squeeze")
				else:
					phase = Phase.POKE
					_t = 0.0
					out["events"].append("too_big")
		Phase.POKE:
			out["command"] = "guide"
			out["target"] = mouth
			out["hold"] = true
			if pending == "come" or _t >= float(_cfg["poke_seconds"]):
				out["command"] = ""
				out["events"].append("gave_up_big")
				cancel()
		Phase.SQUEEZE:
			var dur := maxf(0.05, float(_cfg["squeeze_seconds"]))
			var u := clampf(_t / dur, 0.0, 1.0)
			out["control"] = true
			out["body"] = { "pos": mouth.lerp(inside, u), "scale": lerpf(1.0, 0.22, u), "hidden": false }
			if u >= 1.0:
				phase = Phase.AWAY
				_t = 0.0
				_away = at_bond("away", _bond)
				_hurried = false
				_found_cued = false
				_rustle_cd = 0.0
				out["events"].append("gone")
		Phase.AWAY:
			if pending == "come" and not _hurried:
				_hurried = true
				_away = minf(_away, _t + float(_cfg["hurry_seconds"]))
				out["events"].append("hurry")
			var u := clampf(_t / maxf(0.05, _away), 0.0, 1.0)
			out["control"] = true
			out["body"] = { "pos": _away_pos(u, inside, cache), "scale": 0.22, "hidden": true }
			_rustle_cd -= delta
			if _rustle_cd <= 0.0:
				_rustle_cd = float(_cfg["rustle_every"])
				out["events"].append("rustle")
			if not _found_cued and not _hurried and u >= 0.5 and not _find.is_empty():
				_found_cued = true
				out["events"].append("found")
			if _t >= _away:
				phase = Phase.EMERGE
				_t = 0.0
				out["events"].append("emerge")
		Phase.EMERGE:
			var dur2 := maxf(0.05, float(_cfg["emerge_seconds"]))
			var u2 := clampf(_t / dur2, 0.0, 1.0)
			out["control"] = true
			out["body"] = { "pos": inside.lerp(mouth, u2), "scale": lerpf(0.22, 1.0, u2), "hidden": false }
			out["carry"] = String(_find.get("item", ""))
			if u2 >= 1.0:
				phase = Phase.BRING
				_t = 0.0
				out["events"].append("carrying")
		Phase.BRING:
			out["carry"] = String(_find.get("item", ""))
			if pending == "pet":
				_pet_left = float(_cfg["pet_pause"])
			if _pet_left > 0.0:
				_pet_left -= delta
			elif pending != "come":
				# a Call hands it back to the brain, which brings it to you faster than we would
				out["command"] = "guide"
				out["target"] = player
				out["speed"] = float(_cfg["bring_speed"])
			var near := companion.distance_to(player) <= float(_cfg["drop_distance"])
			if near or _t >= float(_cfg["bring_patience"]):
				var spot := companion
				if near:
					var away_dir := (companion - player)
					spot = player + (away_dir.normalized() if away_dir.length() > 0.5 else Vector2(1, 0.4).normalized()) * 20.0
				out["drop"] = _drop(spot)
				out["carry"] = ""
				out["command"] = ""
				out["events"].append("dropped" if near else "set_down")
				phase = Phase.IDLE
				_cooldown = float(_cfg["cooldown"])
				_gap = -1
				_find = {}
	return out


## Where the body is along its time away (0..1): in from the gap to the cache, a moment there, and back.
func _away_pos(u: float, inside: Vector2, cache: Vector2) -> Vector2:
	if u < 0.35:
		return inside.lerp(cache, u / 0.35)
	if u < 0.65:
		return cache + Vector2(sin(u * 40.0) * 3.0, cos(u * 31.0) * 1.5)
	return cache.lerp(inside, (u - 0.65) / 0.35)


func _drop(spot: Vector2) -> Dictionary:
	var gap: Dictionary = _gaps[_gap]
	var id := String(gap["id"])
	var prior := trips_at(id)
	var better: Dictionary = next_find(gap["finds"], _bond)
	_trips[id] = prior + 1
	return {
		"item": String(_find.get("item", "")),
		"pos": spot,
		"warm": warmth(float(_cfg["warm"]), float(_cfg["warm_decay"]), prior, float(_cfg["warm_min"])),
		"more": not better.is_empty(),
		"gap": id,
	}


## The companion NOTICING the gaps as you come near: a held point toward the nearest one in range, then a
## cooldown (the Riverbank's pointing, by bond). Only while idle. Returns { point, target, gap, started }.
func notice(delta: float, player_pos: Vector2, bond: float) -> Dictionary:
	var out := { "point": false, "target": Vector2.ZERO, "gap": -1, "started": false }
	if phase != Phase.IDLE or _gaps.is_empty():
		_notice_left = 0.0
		return out
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left > 0.0 and _notice_gap >= 0:
			out["point"] = true
			out["gap"] = _notice_gap
			out["target"] = _gaps[_notice_gap]["mouth"]
		else:
			_notice_cd = at_bond("notice_cooldown", bond)
		return out
	if _notice_cd > 0.0:
		_notice_cd = maxf(0.0, _notice_cd - delta)
		return out
	var near := nearest_gap(player_pos, at_bond("notice_range", bond))
	if near >= 0:
		_notice_gap = near
		_notice_left = float(_cfg["notice_hold"])
		out["point"] = true
		out["started"] = true
		out["gap"] = near
		out["target"] = _gaps[near]["mouth"]
	return out
