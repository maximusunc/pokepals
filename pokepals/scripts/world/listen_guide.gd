class_name ListenGuide
extends RefCounted
## A companion LISTENING for something you cannot hear, as pure logic (state in, state out):
## Steamhollow's little bronze bell, ringing somewhere in the fog too faintly for a person. The world
## authors where the bell is; this decides, every frame, how clearly the companion hears it and which
## way it turns. It draws nothing and knows no nodes: the ListenDirector feeds it positions and speeds
## and turns the answer into the companion's body language (gaze, perked ears, a stilled body).
##
## WHEN IT HEARS. Only when it is calm and SETTLED beside you:
##   * you are still or moving slowly (`still_speed`),
##   * it is close (`companion_radius`) and itself standing easy (`companion_still_speed`),
##   * and the bell is within hearing (`hear_range`, which grows with the bond).
## Hold that for a moment (`settle` seconds, shorter the deeper the bond) and its hearing builds from
## nothing to a clear tell. Walk on, or let it wander off, and the sound drains away over `lose_seconds`:
## it is lost, never punished; stand still together and it comes back.
##
## HOW CLEARLY. `tell` (0..1) is the strength of the companion's body language. It builds as hearing
## builds, capped lower for a fresh companion (`tell_cap_low`) than a bonded one (`tell_cap_high`).
## The AIM is rough at first and settles as it listens: it starts off by up to `aim_error` radians
## (wobbling slowly from side to side, more for a fresh companion) and narrows to the truth as the
## sound becomes clear. Close to the bell (`near_radius`) everything sharpens: the tell grows stronger,
## the aim is true, and it takes less stillness to hear. Within `visible_radius` the bell shows in the
## fog (`visible`, 0..1), fully by `found_radius`.
##
## Everything is deterministic given its inputs (the wobble runs off an internal clock) and every
## number comes from the secret's `reveal` block in the world spec; the defaults are a safety net only.

const DEFAULTS := {
	"hear_range_low": 320.0,      # how far away the companion can hear the bell, at zero bond...
	"hear_range_high": 760.0,     # ...and at full bond
	"still_speed": 30.0,          # you are "still or slow" under this many px/s
	"companion_still_speed": 26.0,
	"companion_radius": 95.0,     # it must be this close to you to count as beside you
	"settle_low": 2.4,            # seconds of being settled before it hears clearly, at zero bond...
	"settle_high": 1.0,           # ...and at full bond
	"lose_seconds": 2.2,          # how long a clear sound takes to drain once you are no longer settled
	"tell_cap_low": 0.7,          # the strongest tell a fresh companion gives...
	"tell_cap_high": 1.0,         # ...and a bonded one
	"aim_error_low": 0.62,        # radians the aim can be off at first (~35 degrees), fresh...
	"aim_error_high": 0.22,       # ...and bonded
	"aim_residual": 0.10,         # radians of wobble that never quite goes while far from the bell
	"wobble_rate": 0.7,           # cycles per second of the aim's slow side-to-side
	"near_radius": 240.0,         # inside this, the tell sharpens
	"near_settle_factor": 0.45,   # ...and settling takes this fraction of the time, right at the bell
	"visible_radius": 130.0,      # the bell can be seen through the fog inside this...
	"found_radius": 62.0,         # ...fully visible inside this
	"aim_distance": 120.0,        # how far from the companion the point it looks at is
	"hear_threshold": 0.4,        # the tell passes this: "hear" (a one-shot event); under "lost_threshold": "lost"
	"lost_threshold": 0.05,
}

var _bell := Vector2.ZERO
var _cfg: Dictionary = {}
var _settle := 0.0              # seconds of being settled, 0..need
var _clock := 0.0
var _heard := false             # a clear sound is currently held (for the hear / lost events)
var _was_near := false
var _was_visible := false
var _last_tell := 0.0


## bell: where the bell hangs. cfg: the secret's reveal block (see DEFAULTS for the keys).
func _init(bell: Vector2, cfg: Dictionary = {}) -> void:
	_bell = bell
	_cfg = DEFAULTS.duplicate()
	for k in cfg:
		if DEFAULTS.has(k):
			_cfg[k] = cfg[k]


func bell() -> Vector2:
	return _bell


## How far the companion can hear the bell from, at a bond (0..1).
func hear_range(bond: float) -> float:
	return lerpf(float(_cfg["hear_range_low"]), float(_cfg["hear_range_high"]), clampf(bond, 0.0, 1.0))


## Seconds of being settled before it hears clearly, at a bond and a distance from the bell.
func settle_needed(bond: float, dist: float) -> float:
	var base := lerpf(float(_cfg["settle_low"]), float(_cfg["settle_high"]), clampf(bond, 0.0, 1.0))
	return base * lerpf(1.0, float(_cfg["near_settle_factor"]), near_amount(dist))


## 0..1, how close to the bell (1 at the bell, 0 at or beyond `near_radius`).
func near_amount(dist: float) -> float:
	return clampf(1.0 - dist / maxf(1.0, float(_cfg["near_radius"])), 0.0, 1.0)


## 0..1, how much of the bell shows through the fog from `dist` away.
func visibility(dist: float) -> float:
	return 1.0 - smoothstep(float(_cfg["found_radius"]), float(_cfg["visible_radius"]), dist)


## Whether the companion counts as settled beside you right now (the pure test of "calm and close").
func is_settled(player_speed: float, companion_pos: Vector2, player_pos: Vector2, companion_speed: float) -> bool:
	return player_speed <= float(_cfg["still_speed"]) \
		and companion_speed <= float(_cfg["companion_still_speed"]) \
		and companion_pos.distance_to(player_pos) <= float(_cfg["companion_radius"])


## Forget what it was hearing (a world rebuilt, or a hop).
func reset() -> void:
	_settle = 0.0
	_heard = false
	_last_tell = 0.0


## Advance by `delta`. Returns what the director should do this frame:
##   tell:       0..1, how strongly the companion's body shows it hears something (0: nothing)
##   target:     the world point it should look toward (only meaningful while tell > 0)
##   listening:  true while you are settled and in range (hearing is building or held)
##   hearing:    0..1, how built-up its hearing is (before the bond's cap), for pacing
##   visible:    0..1, how much the bell shows through the fog
##   near:       0..1, how close to the bell you are (0 beyond near_radius)
##   events:     one-shots: "hear" (a clear sound), "lost" (it slipped away), "near" (you came within
##               near_radius), "close" (the bell came into view)
func update(delta: float, player_pos: Vector2, player_speed: float, companion_pos: Vector2, companion_speed: float, bond: float) -> Dictionary:
	_clock += delta
	var b := clampf(bond, 0.0, 1.0)
	var dist := player_pos.distance_to(_bell)
	var in_range := dist <= hear_range(b)
	var near := near_amount(dist)
	var settled := is_settled(player_speed, companion_pos, player_pos, companion_speed)
	var need := maxf(0.05, settle_needed(b, dist))
	var listening := settled and in_range
	if listening:
		_settle = minf(need, _settle + delta)
	else:
		_settle = maxf(0.0, _settle - delta * need / maxf(0.1, float(_cfg["lose_seconds"])))
	var hearing := clampf(_settle / need, 0.0, 1.0)
	var clarity := smoothstep(0.0, 1.0, hearing)
	var cap := lerpf(float(_cfg["tell_cap_low"]), float(_cfg["tell_cap_high"]), b)
	var tell := clarity * lerpf(cap, 1.0, near)

	# The aim narrows as the sound clears, and is true by the bell.
	var err := (lerpf(float(_cfg["aim_error_low"]), float(_cfg["aim_error_high"]), b) * (1.0 - clarity) \
		+ float(_cfg["aim_residual"]) * (1.0 - b)) * (1.0 - near)
	var dir := (_bell - companion_pos)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var aimed := dir.rotated(err * sin(_clock * TAU * float(_cfg["wobble_rate"])))

	var events: Array = []
	if not _heard and tell >= float(_cfg["hear_threshold"]):
		_heard = true
		events.append("hear")
	elif _heard and tell <= float(_cfg["lost_threshold"]):
		_heard = false
		events.append("lost")
	var is_near := dist <= float(_cfg["near_radius"])
	if is_near and not _was_near:
		events.append("near")
	_was_near = is_near
	var vis := visibility(dist)
	var is_visible := vis > 0.0
	if is_visible and not _was_visible:
		events.append("close")
	_was_visible = is_visible
	_last_tell = tell

	return {
		"tell": tell,
		"target": companion_pos + aimed * float(_cfg["aim_distance"]),
		"listening": listening,
		"hearing": hearing,
		"visible": vis,
		"near": near,
		"events": events,
	}
