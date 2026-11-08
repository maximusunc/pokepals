class_name DreamGate
extends RefCounted
## Dozewood's secret as pure logic (state in, state out): a companion that only falls asleep where it
## feels SAFE, dreams of a place, and the walk to that place. No nodes, nothing drawn: the DozeDirector
## feeds it positions, the companion's mood and bond, and turns its answers into a body at rest, a
## thought bubble and a hint.
##
## What "safe" means (all of it must hold, every number in the world's `reveal` block):
##   * the companion is inside a NAP SPOT (one of a few authored hollows) and you are beside it;
##   * you have petted it lately and it welcomed it (`note_pet`, within `pet_window` seconds): a warm hand
##     is what tells it the place is safe;
##   * you are staying still, close by (`still_speed`, `together_distance`);
##   * its mood is calm: not wound up (`calm_arousal`) and not withdrawn (`calm_valence`).
## While all of that holds DROWSE fills, faster the deeper the bond (`fill_seconds_fresh` down to
## `fill_seconds_bonded`). Anything missing lets it drain gently (`drain_rate`), never all at once, and
## never as a failure: a fidget only slows the nap.
##
## The cycle:
##   AWAKE   drowse below `settle_at`. A "yawn" fires as it crosses `yawn_at`.
##   DROWSY  drowse in [settle_at, 1): it has stopped and lies down ("settle"). If the safety lapses long
##           enough it gets up again ("stir").
##   ASLEEP  drowse full ("asleep"). After `dream_delay` more seconds the dream begins ("dream") and the
##           place it dreams of is remembered for the visit (`dreamt`). It wakes ("wake") if you walk
##           more than `wake_distance` away, or poke it (a pet or a call: `poked`).
##   Then, awake, if you and it stand at the dreamed landmark together ("arrive", once), the secret is there.
##
## Waking leaves a short `wake_cooldown` before it can drift off again, so a call or a step away never
## flickers it straight back to sleep. A call while drowsy ("note_call") just lets the drowse go.
##
## Separate from the cycle: an AMBIENT YAWN. If you stand still anywhere for `yawn_after` seconds your
## companion yawns (a hint, nothing more), then not again for `yawn_every` seconds. Yawns are catching,
## in Dozewood.

enum Phase { AWAKE, DROWSY, ASLEEP }

const DEFAULTS := {
	"spot_radius": 120.0,        # the companion must be this near a nap spot
	"player_radius": 150.0,      # ...and you this near it
	"together_distance": 100.0,  # ...and the two of you this near each other
	"still_speed": 12.0,         # px/s under which you count as staying still
	"pet_window": 40.0,          # seconds a welcomed pet stays "recent"
	"calm_arousal": 0.40,        # arousal (-1..1) at or under this is calm enough
	"calm_valence": -0.05,       # valence at or over this is at ease
	"fill_seconds_fresh": 16.0,  # a fresh companion needs this long to drift off...
	"fill_seconds_bonded": 5.0,  # ...a fully bonded one this long
	"drain_rate": 0.12,          # drowse lost per second while it isn't safe
	"settle_at": 0.30,           # drowse at which it stops and lies down
	"yawn_at": 0.55,             # ...and at which it yawns
	"stir_below": 0.12,          # a drowsy companion gets up when drowse falls under this
	"dream_delay": 2.5,          # asleep this long before the dream begins
	"wake_distance": 170.0,      # you this far from it wakes it
	"wake_cooldown": 6.0,        # seconds after waking before it can doze again
	"arrive_radius": 150.0,      # you within this of the dreamed landmark...
	"companion_radius": 190.0,   # ...and it within this
	"yawn_after": 45.0,          # ambient yawn: seconds of standing still
	"yawn_every": 150.0,         # ...and the quiet between yawns
}

var phase := Phase.AWAKE
## 0..1, how drowsy it is.
var drowse := 0.0
## True once it has dreamed this visit (so the landmark's secret can now be found).
var dreamt := false
## True once you have arrived at the dreamed landmark together (once).
var arrived := false
## Why it isn't dozing, when it isn't: "" (it is, or no spot is near), "spot", "pet", "still", "calm".
var blocker := ""

var _spots: Array = []         # Array[Vector2]
var _landmark := Vector2.ZERO
var _cfg: Dictionary = {}
var _pet_age := INF            # seconds since a welcomed pet
var _asleep_for := 0.0
var _cooldown := 0.0
var _last_player := Vector2.ZERO
var _has_last := false
var _still_for := 0.0
var _yawn_cd := 0.0
var _yawned := false           # this drowse already yawned
var _dreaming := false


## spots: the nap spots (Vector2s, or [x, y] pairs). landmark: the place it dreams of. cfg: the secret's
## reveal block (see DEFAULTS for the keys).
func _init(spots: Array, landmark: Vector2, cfg: Dictionary = {}) -> void:
	for p in spots:
		_spots.append(p if p is Vector2 else Vector2(float(p[0]), float(p[1])))
	_landmark = landmark
	_cfg = DEFAULTS.duplicate()
	for k in cfg:
		if DEFAULTS.has(k):
			_cfg[k] = cfg[k]


func is_asleep() -> bool:
	return phase == Phase.ASLEEP


## Whether it is dreaming right now (asleep, and the dream has begun): the bubble shows.
func is_dreaming() -> bool:
	return _dreaming


## The landmark it dreams of.
func landmark() -> Vector2:
	return _landmark


## The nap spot nearest to `pos` within `spot_radius`, or -1.
func spot_at(pos: Vector2) -> int:
	var best := -1
	var best_d := float(_cfg["spot_radius"])
	for i in _spots.size():
		var d := pos.distance_to(_spots[i])
		if d <= best_d:
			best_d = d
			best = i
	return best


## A welcomed pet: the companion feels a warm hand, and the place feels a little safer.
func note_pet() -> void:
	_pet_age = 0.0


## You called it: whatever it was drifting into, it comes to you instead. Lets the drowse go (and the
## memory of the pet), but never fails anything.
func note_call() -> void:
	if phase != Phase.ASLEEP:
		drowse = 0.0
		phase = Phase.AWAKE
		_pet_age = INF
		_yawned = false


## Seconds it takes a companion of this bond to drift off (useful for hints and tests).
func fill_seconds(bond: float) -> float:
	return lerpf(float(_cfg["fill_seconds_fresh"]), float(_cfg["fill_seconds_bonded"]), clampf(bond, 0.0, 1.0))


## Whether the safety conditions hold right now. Sets `blocker` to the first thing missing (or "").
func _is_safe(companion_pos: Vector2, player_pos: Vector2, mood: Vector2, player_speed: float) -> bool:
	var s := spot_at(companion_pos)
	if s < 0 or player_pos.distance_to(_spots[s]) > float(_cfg["player_radius"]) \
			or companion_pos.distance_to(player_pos) > float(_cfg["together_distance"]):
		blocker = "spot"
		return false
	if _pet_age > float(_cfg["pet_window"]):
		blocker = "pet"
		return false
	if player_speed > float(_cfg["still_speed"]):
		blocker = "still"
		return false
	if mood.y > float(_cfg["calm_arousal"]) or mood.x < float(_cfg["calm_valence"]):
		blocker = "calm"
		return false
	blocker = ""
	return true


## Advance by `delta`. mood: Vector2(valence, arousal). bond: 0..1. poked: you pet or called it this
## frame (only matters while it sleeps). Returns:
##   events:  [String] one-shot moments: "yawn", "settle", "stir", "asleep", "dream", "wake", "arrive",
##            "yawn_ambient"
##   rest:    true while it should lie still (drowsy or asleep)
##   dream:   true while the dream shows
func update(delta: float, companion_pos: Vector2, player_pos: Vector2, mood: Vector2, bond: float, poked := false) -> Dictionary:
	var events: Array = []
	var speed := 0.0
	if _has_last and delta > 0.0:
		speed = player_pos.distance_to(_last_player) / delta
	_last_player = player_pos
	_has_last = true
	_pet_age += delta
	_cooldown = maxf(0.0, _cooldown - delta)

	match phase:
		Phase.AWAKE, Phase.DROWSY:
			var safe := _is_safe(companion_pos, player_pos, mood, speed)
			if safe and _cooldown <= 0.0:
				drowse = minf(1.0, drowse + delta / maxf(0.1, fill_seconds(bond)))
			else:
				drowse = maxf(0.0, drowse - delta * float(_cfg["drain_rate"]))
			if phase == Phase.AWAKE and drowse >= float(_cfg["settle_at"]):
				phase = Phase.DROWSY
				events.append("settle")
			elif phase == Phase.DROWSY and drowse < float(_cfg["stir_below"]):
				phase = Phase.AWAKE
				_yawned = false
				events.append("stir")
			if phase != Phase.ASLEEP and not _yawned and drowse >= float(_cfg["yawn_at"]):
				_yawned = true
				events.append("yawn")
			if drowse >= 1.0:
				phase = Phase.ASLEEP
				_asleep_for = 0.0
				events.append("asleep")
		Phase.ASLEEP:
			_asleep_for += delta
			if not _dreaming and _asleep_for >= float(_cfg["dream_delay"]):
				_dreaming = true
				dreamt = true
				events.append("dream")
			if poked or companion_pos.distance_to(player_pos) > float(_cfg["wake_distance"]):
				_wake()
				events.append("wake")

	# Together at the dreamed place: the secret is there.
	if dreamt and not arrived and phase != Phase.ASLEEP \
			and player_pos.distance_to(_landmark) <= float(_cfg["arrive_radius"]) \
			and companion_pos.distance_to(_landmark) <= float(_cfg["companion_radius"]):
		arrived = true
		events.append("arrive")

	# An ambient yawn, anywhere: standing still a good while is catching.
	_yawn_cd = maxf(0.0, _yawn_cd - delta)
	if speed <= float(_cfg["still_speed"]) and phase == Phase.AWAKE:
		_still_for += delta
		if _still_for >= float(_cfg["yawn_after"]) and _yawn_cd <= 0.0:
			_yawn_cd = float(_cfg["yawn_every"])
			_still_for = 0.0
			events.append("yawn_ambient")
	else:
		_still_for = 0.0

	return { "events": events, "rest": phase != Phase.AWAKE, "dream": _dreaming }


func _wake() -> void:
	phase = Phase.AWAKE
	drowse = 0.0
	_dreaming = false
	_asleep_for = 0.0
	_pet_age = INF
	_cooldown = float(_cfg["wake_cooldown"])
	_yawned = false
