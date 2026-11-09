class_name EchoGuide
extends RefCounted
## The state of Hollowsong's howling, as pure logic (state in, state out): the howl's cooldown, which hints
## have been earned, the companion NOTICING the hidden cave as you come near, and the cave revealing
## itself when you walk up to it. The geometry (which wall answers, from where, when) is EchoField; this
## holds what changes from one howl to the next. No nodes: the HowlDirector feeds it positions and turns
## the answers into ripples, hints and the companion's body language.
##
## THE HOWL. `howl` asks for one if the cooldown is over (shorter the deeper the bond) and returns the
## echoes of the canyon's walls plus, if the cave can hear it, the wrong answer. Each howl counts, so the
## wrong answer's small bearing error is different every time (and a friend's howl, `hear`, counts too).
## THE EVENTS. One-shot strings the director turns into the first-time hint lines:
##   "first_echo" the canyon answered for the first time      "silence" a howl nothing answered
##   "wrong" the first time the cave's wrong answer is heard  "reveal" you walked up to the cave
##   "notice" the companion has started pointing at the cave
## THE NOTICE (`update`): inside `notice_range` of the cave mouth (further the deeper the bond), the
## companion stops and points at it for `notice_hold` seconds, then not again for `notice_cooldown`
## seconds (shorter with bond): the same shape as the Riverbank's salamander points and Drifthallow's scent.
## It only happens once the player has not yet found the cave; the point is a hint, never a requirement.
## THE REVEAL: when YOU come within `reveal_radius` of the mouth, in any shape, it opens. Nothing else is
## needed, so no natural thing a player does (petting, calling, switching form) can undo it.

const DEFAULTS := {
	"cooldown_low": 4.0,            # seconds between howls at zero bond...
	"cooldown_high": 2.4,           # ...and at full bond
	"reveal_radius": 210.0,         # walking this close to the cave mouth opens it
	"notice_range_low": 280.0,      # how near you must be for the companion to notice the cave, fresh...
	"notice_range_high": 620.0,     # ...and bonded
	"notice_cooldown_low": 16.0,
	"notice_cooldown_high": 6.0,
	"notice_hold": 2.5,
}

var _walls: Array = []
var _cave_origin := Vector2.ZERO    # where the wrong answer truly comes from
var _cave_mouth := Vector2.ZERO     # where the cave shows (and the player must walk up to)
var _cfg: Dictionary = {}
var _cooldown := 0.0
var _count := 0                     # howls heard so far (seeds the bearing error)
var _said := {}
var _revealed := false
var _notice_cd := 0.0
var _notice_left := 0.0


## walls: the spec's `[ax, ay, bx, by]` list. cave_origin / cave_mouth: points. cfg: the secret's reveal.
func _init(walls: Array, cave_origin: Vector2, cave_mouth: Vector2, cfg: Dictionary = {}) -> void:
	_walls = EchoField.walls_from(walls)
	_cave_origin = cave_origin
	_cave_mouth = cave_mouth
	_cfg = EchoField.DEFAULTS.duplicate()
	for k in DEFAULTS:
		_cfg[k] = DEFAULTS[k]
	for k in cfg:
		_cfg[k] = cfg[k]
	_cfg["_complete"] = true


func walls() -> Array:
	return _walls


func cave_origin() -> Vector2:
	return _cave_origin


func cave_mouth() -> Vector2:
	return _cave_mouth


func speed() -> float:
	return float(_cfg["speed"])


func is_revealed() -> bool:
	return _revealed


func howl_count() -> int:
	return _count


## Seconds between howls at a bond (0..1).
func cooldown_for(bond: float) -> float:
	return lerpf(float(_cfg["cooldown_low"]), float(_cfg["cooldown_high"]), clampf(bond, 0.0, 1.0))


func can_howl() -> bool:
	return _cooldown <= 0.0


## Seconds until the next howl is allowed (0 when ready).
func wait_left() -> float:
	return maxf(0.0, _cooldown)


## Forget what has happened (a world rebuilt).
func reset() -> void:
	_cooldown = 0.0
	_count = 0
	_said = {}
	_revealed = false
	_notice_cd = 0.0
	_notice_left = 0.0


## The player calls out: { ok, echoes, wrong, events } or { ok: false, wait } while the cooldown holds.
## `source` is where the voice leaves (the companion), `listener` where it is heard (you).
func howl(source: Vector2, listener: Vector2, bond: float) -> Dictionary:
	if _cooldown > 0.0:
		return { "ok": false, "wait": _cooldown, "echoes": [], "wrong": {}, "events": [] }
	_cooldown = cooldown_for(bond)
	var r := _answer(source, listener, bond)
	r["ok"] = true
	return r


## A howl somebody ELSE made, heard here (no cooldown, nothing of ours changes but the hint flags). The
## voice and the ears are one point: wherever they stood.
func hear(at: Vector2, bond: float = 0.5) -> Dictionary:
	var r := _answer(at, at, bond)
	r["ok"] = true
	return r


func _answer(source: Vector2, listener: Vector2, bond: float) -> Dictionary:
	_count += 1
	var echoes := EchoField.echoes(source, listener, _walls, _cfg, bond)
	var wrong := EchoField.wrong_echo(source, listener, _cave_origin, _cfg, bond, _count * 7919 + 17)
	var events: Array = []
	if echoes.is_empty() and wrong.is_empty():
		_once(events, "silence")
	if not echoes.is_empty():
		_once(events, "first_echo")
	if not wrong.is_empty():
		_once(events, "wrong")
	return { "echoes": echoes, "wrong": wrong, "events": events }


func _once(events: Array, key: String) -> void:
	if not _said.has(key):
		_said[key] = true
		events.append(key)


## Advance by `delta` with the player at `player_pos`. Returns { "point": bool (hold a point at the cave this
## frame), "target": the cave mouth, "events": [..] } and cools the howl.
func update(delta: float, player_pos: Vector2, bond: float) -> Dictionary:
	_cooldown = maxf(0.0, _cooldown - delta)
	var out := { "point": false, "target": _cave_mouth, "events": [] }
	if _revealed:
		_notice_left = 0.0
		return out
	var b := clampf(bond, 0.0, 1.0)
	var d := player_pos.distance_to(_cave_mouth)
	if d <= float(_cfg["reveal_radius"]):
		_revealed = true
		_notice_left = 0.0
		out["events"] = ["reveal"]
		return out
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left > 0.0:
			out["point"] = true
		else:
			_notice_cd = lerpf(float(_cfg["notice_cooldown_low"]), float(_cfg["notice_cooldown_high"]), b)
		return out
	if _notice_cd > 0.0:
		_notice_cd = maxf(0.0, _notice_cd - delta)
		return out
	var reach := lerpf(float(_cfg["notice_range_low"]), float(_cfg["notice_range_high"]), b)
	if d <= reach:
		_notice_left = float(_cfg["notice_hold"])
		out["point"] = true
		if not _said.has("notice"):
			_said["notice"] = true
			out["events"] = ["notice"]
	return out
