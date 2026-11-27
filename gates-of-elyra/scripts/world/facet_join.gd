class_name FacetJoin
extends RefCounted
## Glintwold's secret, as pure logic (no nodes; state in, state out): THE UNFINISHED, a great stone hanging in
## loose pieces on the Turning Floor, which only looks whole from two places at once. Half of its shards answer
## to whoever stands nearest one unmarked spot (the "you" mark), the other half to whoever stands nearest the
## other (the "companion" mark). The HeartstoneView draws it; the FacetsDirector feeds this where everyone is.
##
## HOW A HALF SLIDES. For each half, `d` is its viewer's offset from its mark. The half's OPENNESS is
##     s = ease_out((|d| - tolerance) / (open_dist - tolerance)), clamped 0..1
## so it is exactly 0 (home) inside `tolerance` of the mark (the magnet: a little off still clicks shut) and
## grows to 1 by `open_dist`. Where the viewer stands is read the way you look round a real thing: by its ANGLE
## round the stone compared with the mark's (`lat`, -1..1 over the whole circle, eased so the first steps show)
## and its DISTANCE from the stone compared with the mark's (`rad`, -1..1 over `rad_open`). Each shard then sits
## off its home by
##     parallax:  -(side * lat + out * rad * 0.4) * slide * depth
##                (side: the way round the stone at the mark, out: away from the stone; near shards, depth > 0,
##                slide against the way you stepped round, far ones, depth < 0, with it)
##     spread:    radial * s * spread                 (and the whole half eases apart from its middle)
## clamped to `max_offset`, so every step round the Turning Floor slides the pieces, not just the ones near a mark. Further than `reach - reach_band` from the stone's centre the parallax fades out, and
## beyond `reach` the half simply hangs at its resting spread (radial * spread), so from afar it is a stone
## loosely apart and nothing moves as you walk.
##
## WHO IS A VIEWER. Every actor in the world (you, your companion, friends and theirs) is a candidate. Each mark
## is served by the actor nearest to it, and one actor never serves both while another is there (the mark with
## the nearer candidate picks first), so two friends close it without directing a companion at all.
##
## DONE. Both halves home (each viewer inside `tolerance` of its mark) and held there `hold_s` in a row: it is
## done, once, and stays whole. Leaving a mark lets the hold go back to zero (no penalty, nothing lost).
##
## THE COMPANION'S PART (bond 0..1): "Go look" lands it `go_look_error(bond)` px off its mark (far off fresh,
## nearly true when deep), and as you come within `glance_range(bond)` of the stone it glances at its mark now
## and then (more often the deeper the bond), until that half is home.
##
## EVENTS (one-shot strings on rising edges, for the director's lines):
##   "near"  you came within reach the first time     "you_home" / "companion_home"  a half closed
##   "half"  exactly one half is home                  "both"     both are home and the hold has begun
##   "complete"  it is whole

const DEFAULTS := {
	"reach": 320.0,           # the sliding only happens within this of the centre
	"reach_band": 90.0,       # ...fading out over this last stretch
	"tolerance": 16.0,        # within this of a mark, that half is exactly home
	"hold_s": 2.0,            # both home this long and it is whole
	"floor_radius": 230.0,    # the Turning Floor (taps inside it stand the companion there)
	"open_dist": 150.0,       # how far from its mark a viewer must be for its half to be fully open
	"slide": 22.0,            # px a depth-1 shard slides at its furthest (the parallax)
	"spread": 8.0,            # px a shard eases out from its half's middle at full openness (and at rest)
	"max_offset": 30.0,       # no shard ever strays further than this
	"rad_open": 140.0,        # how far nearer or further than the mark from the stone reads as "all the way"
	"settle_radius": 34.0,    # a companion told to stand this near its mark is put on it
	"go_look_error_low": 70.0,   # px off its mark "Go look" lands, fresh...
	"go_look_error_high": 6.0,   # ...and deeply bonded
	"glance_range_low": 230.0,   # how near the stone you must be before it glances at its mark, fresh...
	"glance_range_high": 470.0,  # ...and deeply bonded
	"glance_cooldown_low": 14.0,
	"glance_cooldown_high": 5.0,
}

var center := Vector2.ZERO
var marks := { "you": Vector2.ZERO, "companion": Vector2.ZERO }
var shards: Array = []        # [{ home: Vector2, depth: float, owner: "you"|"companion", radial: Vector2 }]
var held := 0.0
var done := false
var _cfg: Dictionary
var _was := { "near": false, "you": false, "companion": false, "half": false, "both": false }
var _glance_cd := 0.0


## `block`: the spec's `heartstone` block. `shard_list`: [{ home: [x, y] | Vector2, depth: float, owner }], home
## relative to the stone's foot (any origin works: the spread is measured from each half's own middle).
func _init(block: Dictionary, shard_list: Array) -> void:
	_cfg = DEFAULTS.duplicate()
	for k in DEFAULTS:
		if block.has(k):
			_cfg[k] = float(block[k])
	center = _v(block.get("position", [0, 0]))
	var m: Dictionary = block.get("marks", {})
	marks = { "you": _v(m.get("you", [0, 0])), "companion": _v(m.get("companion", [0, 0])) }
	_set_shards(shard_list)


func cfg(key: String) -> float:
	return float(_cfg[key])


static func _v(a: Variant) -> Vector2:
	if a is Vector2:
		return a
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


func _set_shards(list: Array) -> void:
	shards = []
	var mids := { "you": Vector2.ZERO, "companion": Vector2.ZERO }
	var counts := { "you": 0, "companion": 0 }
	for s in list:
		var owner := "companion" if String(s.get("owner", "you")) == "companion" else "you"
		var home := _v(s.get("home", [0, 0]))
		shards.append({ "home": home, "depth": clampf(float(s.get("depth", 0.0)), -1.0, 1.0), "owner": owner, "radial": Vector2.ZERO })
		mids[owner] += home
		counts[owner] += 1
	for i in shards.size():
		var sh: Dictionary = shards[i]
		var owner := String(sh["owner"])
		var mid: Vector2 = mids[owner] / float(maxi(1, int(counts[owner])))
		var r: Vector2 = (sh["home"] as Vector2) - mid
		# a shard right in its half's middle still eases out, each its own way
		sh["radial"] = r.normalized() if r.length() > 0.5 else Vector2.RIGHT.rotated(float(i) * 2.39996)


## Which actor serves each mark: { you: index | -1, companion: index | -1 }. The mark whose nearest actor is
## nearer picks first; the other takes the nearest of the rest (or the same one, if it is the only actor).
func assign_viewers(actors: Array) -> Dictionary:
	var out := { "you": -1, "companion": -1 }
	if actors.is_empty():
		return out
	var ny := _nearest(marks["you"], actors, -1)
	var nc := _nearest(marks["companion"], actors, -1)
	var dy: float = (actors[ny] as Vector2).distance_to(marks["you"])
	var dc: float = (actors[nc] as Vector2).distance_to(marks["companion"])
	if dy <= dc:
		out["you"] = ny
		out["companion"] = _nearest(marks["companion"], actors, ny) if actors.size() > 1 else ny
	else:
		out["companion"] = nc
		out["you"] = _nearest(marks["you"], actors, nc) if actors.size() > 1 else nc
	return out


static func _nearest(p: Vector2, actors: Array, skip: int) -> int:
	var best := -1
	var best_d := INF
	for i in actors.size():
		if i == skip:
			continue
		var d := (actors[i] as Vector2).distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## One half's state for a viewer at `viewer`: { open: 0..1 (s), near: 0..1 (how much the parallax shows),
## closeness: 0..1, home: bool, dir: unit vector from the mark to the viewer }.
func half_state(half: String, viewer: Vector2) -> Dictionary:
	var m: Vector2 = marks[half]
	var d := viewer - m
	var dist := d.length()
	var t := clampf((dist - cfg("tolerance")) / maxf(1.0, cfg("open_dist") - cfg("tolerance")), 0.0, 1.0)
	var s := 1.0 - (1.0 - t) * (1.0 - t)   # eases out: the first steps off a mark already show plainly
	var from_c := viewer.distance_to(center)
	var near := 1.0 - smoothstep(cfg("reach") - cfg("reach_band"), cfg("reach"), from_c)
	var home := dist <= cfg("tolerance") and from_c <= cfg("reach")
	# the angle round the stone and the distance from it, against the mark's
	var mc := m - center
	var out := mc.normalized() if mc.length() > 0.001 else Vector2.DOWN
	var side := Vector2(-out.y, out.x)   # the way round (increasing angle)
	var vc := viewer - center
	var turn := angle_difference(mc.angle(), vc.angle()) / PI if vc.length() > 0.001 else 0.0
	var lat := signf(turn) * pow(absf(turn), 0.6)
	var rad := clampf((vc.length() - mc.length()) / cfg("rad_open"), -1.0, 1.0)
	return {
		"open": s, "near": near, "home": home,
		"closeness": 1.0 if home else near * (1.0 - s),
		"lat": lat, "rad": rad, "side": side, "out": out,
	}


## A half with no viewer at all (an empty world): it hangs at its resting spread.
static func resting_half() -> Dictionary:
	return { "open": 1.0, "near": 0.0, "home": false, "closeness": 0.0, "lat": 0.0, "rad": 0.0, "side": Vector2.RIGHT, "out": Vector2.DOWN }


## Every shard's offset from its home, for the two halves' states.
func offsets(states: Dictionary) -> Array:
	var out: Array = []
	var slide := cfg("slide")
	var spread := cfg("spread")
	var cap := cfg("max_offset")
	for sh in shards:
		var st: Dictionary = states.get(String(sh["owner"]), resting_half())
		var s := float(st["open"])
		var near := float(st["near"])
		var look: Vector2 = (st["side"] as Vector2) * float(st["lat"]) + (st["out"] as Vector2) * float(st["rad"]) * 0.4
		var parallax: Vector2 = -look * slide * float(sh["depth"])
		var open: Vector2 = (sh["radial"] as Vector2) * spread * s
		var resting: Vector2 = (sh["radial"] as Vector2) * spread
		var o := (parallax + open) * near + resting * (1.0 - near)
		if bool(st["home"]) or done:
			o = Vector2.ZERO
		out.append(o.limit_length(cap))
	return out


## One frame. `actors`: every actor's position (put yours first and your companion's second). Returns
## { offsets: Array[Vector2], closeness: { you, companion }, home: { you, companion }, viewers: { you, companion }
##   (actor indices), hold: 0..1, completed: bool (true once), events: Array[String], glance: bool }.
func update(delta: float, actors: Array, bond: float) -> Dictionary:
	var v := assign_viewers(actors)
	var states := {}
	for half in ["you", "companion"]:
		var i := int(v[half])
		states[half] = half_state(half, actors[i]) if i >= 0 else resting_half()
	var out := {
		"offsets": [], "closeness": {}, "home": {}, "viewers": v, "hold": 0.0,
		"completed": false, "events": [], "glance": false,
	}
	var events: Array = out["events"]
	var hy := bool(states["you"]["home"])
	var hc := bool(states["companion"]["home"])
	if not done:
		var both := hy and hc and int(v["you"]) != int(v["companion"])
		held = held + delta if both else 0.0
		if both and held >= cfg("hold_s"):
			done = true
			out["completed"] = true
			events.append("complete")
		_edge(events, "near", not actors.is_empty() and (actors[0] as Vector2).distance_to(center) <= cfg("reach"))
		_edge(events, "you", hy, "you_home")
		_edge(events, "companion", hc, "companion_home")
		_edge(events, "half", hy != hc)
		_edge(events, "both", both and not done)
	out["hold"] = 1.0 if done else clampf(held / cfg("hold_s"), 0.0, 1.0)
	out["offsets"] = offsets(states)
	for half in ["you", "companion"]:
		out["closeness"][half] = 1.0 if done else float(states[half]["closeness"])
		out["home"][half] = done or bool(states[half]["home"])
	# the companion glances at its mark now and then as you come near (not once its half is home)
	_glance_cd = maxf(0.0, _glance_cd - delta)
	if not done and not hc and not actors.is_empty() and _glance_cd <= 0.0 \
			and (actors[0] as Vector2).distance_to(center) <= glance_range(bond):
		_glance_cd = lerpf(cfg("glance_cooldown_low"), cfg("glance_cooldown_high"), clampf(bond, 0.0, 1.0))
		out["glance"] = true
	return out


func _edge(events: Array, key: String, now: bool, name: String = "") -> void:
	if now and not bool(_was[key]):
		events.append(name if name != "" else key)
	_was[key] = now


## Back to loose pieces (a toy again: found already, and closed once this visit).
func reopen() -> void:
	done = false
	held = 0.0
	for k in _was:
		if k != "near":
			_was[k] = false


## How near the stone you must be for your companion to glance at its mark, by bond.
func glance_range(bond: float) -> float:
	return lerpf(cfg("glance_range_low"), cfg("glance_range_high"), clampf(bond, 0.0, 1.0))


## How far off its mark "Go look" lands your companion, by bond.
func go_look_error(bond: float) -> float:
	return lerpf(cfg("go_look_error_low"), cfg("go_look_error_high"), clampf(bond, 0.0, 1.0))


## Where "Go look" sends your companion: its mark, `go_look_error(bond)` off in the direction `angle` (the
## caller picks it; a random one in play, a fixed one in tests), kept on the Turning Floor.
func go_look_target(bond: float, angle: float) -> Vector2:
	var p: Vector2 = marks["companion"] + Vector2.RIGHT.rotated(angle) * go_look_error(bond)
	var r := cfg("floor_radius") - 8.0
	if p.distance_to(center) > r:
		p = center + (p - center).normalized() * r
	return p


## Whether a tap at `p` is on the Turning Floor.
func on_floor(p: Vector2) -> bool:
	return p.distance_to(center) <= cfg("floor_radius")


## Where a companion told to stand at `p` stands: on its mark if `p` is within `settle_radius` of it (it shuffles
## onto the right spot), else right there.
func settle_target(p: Vector2) -> Vector2:
	var m: Vector2 = marks["companion"]
	return m if p.distance_to(m) <= cfg("settle_radius") else p
