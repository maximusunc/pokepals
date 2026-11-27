class_name GlyphNotice
extends RefCounted
## A companion NOTICING a wrong character in a world made of text, as pure logic (state in, state out):
## Glyphfall's stray ampersand, standing in the grass in the grass's own colour. You could walk past it all
## day. The world authors where it is; this decides, every frame, whether your companion is stopped and
## looking at it, and when you have come close enough to see it for yourself. It draws nothing and knows no
## nodes: the MisprintDirector feeds it positions and turns the answer into the companion's body (a held
## look) and the glyph's shine.
##
## WHEN IT NOTICES. When you are within its noticing range of the glyph (`notice_range`, wider with the
## bond) and it is beside you (`companion_radius`): it stops and looks for `notice_hold` seconds, then walks
## on. After a cooldown it stops and looks again: sooner with the bond, and sooner the nearer you are
## (`near_radius`, `near_cooldown_factor`), so the looks come thick and fast as you close in. The looks are
## the only compass: no arrow, no marker.
##
## WHEN YOU SEE IT. Once it has noticed at least once, the glyph begins to catch the light as you approach
## (`glow`, 0 at `glow_radius` rising to 1 at `find_radius`), and inside `find_radius` it is FOUND: it can be
## examined and taken. Until your companion has looked, you can stand on it and it is only grass to you;
## but standing there is well inside its range, so it will look.
##
## Deterministic given its inputs. Every number comes from the secret's `reveal` block in the world spec;
## the defaults are a safety net only.

const DEFAULTS := {
	"notice_range_low": 150.0,       # how far from the glyph you can be for it to notice, at zero bond...
	"notice_range_high": 380.0,      # ...and at full bond
	"notice_cooldown_low": 11.0,     # seconds between looks, at zero bond...
	"notice_cooldown_high": 4.0,     # ...and at full bond
	"notice_hold": 2.6,              # how long one look lasts
	"near_radius": 110.0,            # inside this, the looks come quicker
	"near_cooldown_factor": 0.4,     # ...the cooldown is this fraction, right at the glyph
	"companion_radius": 150.0,       # it must be this close to you to be shown anything
	"find_radius": 30.0,             # you are this close, and it has looked: you see it
	"glow_radius": 90.0,             # where the glyph begins to catch the light
}

var _glyph := Vector2.ZERO
var _cfg: Dictionary = {}
var _hold := 0.0            # seconds left of the current look
var _cooldown := 0.0        # seconds until it may look again
var _looks := 0             # how many looks it has given
var _was_near := false
var _found := false


## glyph: where the wrong character stands. cfg: the secret's reveal block (see DEFAULTS for the keys).
func _init(glyph: Vector2, cfg: Dictionary = {}) -> void:
	_glyph = glyph
	_cfg = DEFAULTS.duplicate()
	for k in cfg:
		if DEFAULTS.has(k):
			_cfg[k] = cfg[k]


func glyph() -> Vector2:
	return _glyph


## How far from the glyph you can be for the companion to notice it, at a bond (0..1).
func notice_range(bond: float) -> float:
	return lerpf(float(_cfg["notice_range_low"]), float(_cfg["notice_range_high"]), clampf(bond, 0.0, 1.0))


## Seconds between looks, at a bond and a distance from the glyph.
func cooldown(bond: float, dist: float) -> float:
	var base := lerpf(float(_cfg["notice_cooldown_low"]), float(_cfg["notice_cooldown_high"]), clampf(bond, 0.0, 1.0))
	var near := clampf(1.0 - dist / maxf(1.0, float(_cfg["near_radius"])), 0.0, 1.0)
	return base * lerpf(1.0, float(_cfg["near_cooldown_factor"]), near)


## 0..1: how much the glyph catches the light from `dist` away (only once it has been noticed).
func glow_at(dist: float) -> float:
	return 1.0 - smoothstep(float(_cfg["find_radius"]), float(_cfg["glow_radius"]), dist)


func has_noticed() -> bool:
	return _looks > 0


func is_found() -> bool:
	return _found


## Advance by `delta`. Returns what the director should do this frame:
##   point:   true while the companion is stopped and looking
##   target:  the world point it looks at (the glyph)
##   glow:    0..1, how much the glyph catches the light
##   found:   true once you have seen it (it stays true)
##   events:  one-shots: "notice" (its first look), "again" (a later look), "near" (you came within
##            near_radius after it had looked), "found" (you saw it)
func update(delta: float, player_pos: Vector2, companion_pos: Vector2, bond: float) -> Dictionary:
	var out := { "point": false, "target": _glyph, "glow": 0.0, "found": _found, "events": [] }
	if _found:
		out["glow"] = 1.0
		return out
	var dist := player_pos.distance_to(_glyph)
	if _hold > 0.0:
		_hold -= delta
		if _hold > 0.0:
			out["point"] = true
		else:
			_cooldown = cooldown(bond, dist)
	elif _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	elif dist <= notice_range(bond) and companion_pos.distance_to(player_pos) <= float(_cfg["companion_radius"]):
		_hold = float(_cfg["notice_hold"])
		_looks += 1
		out["point"] = true
		out["events"].append("notice" if _looks == 1 else "again")
	if _looks > 0:
		out["glow"] = glow_at(dist)
		var near := dist <= float(_cfg["near_radius"])
		if near and not _was_near:
			out["events"].append("near")
		_was_near = near
		if dist <= float(_cfg["find_radius"]):
			_found = true
			_hold = 0.0
			out["point"] = false
			out["found"] = true
			out["glow"] = 1.0
			out["events"].append("found")
	return out
