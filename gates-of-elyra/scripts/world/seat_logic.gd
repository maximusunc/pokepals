class_name SeatLogic
extends RefCounted
## Somewhere to sit (Lingerlong's benches, loungers, the pool's edge, the terrace chair and cushion): the pure
## half of SITTING TOGETHER. A world's spec lists its seats (`seats: [{ id, at: [x, y], face: [fx, fy] }]`):
## `at` is where a sitter's body stands (their node's position), `face` the way they look, and `off` (optional)
## where they step to when they get up (else a step in front of the seat, the way it faces).
##
## Being seated needs no message of its own: it is a pure function of WHERE an avatar is and WHETHER it is
## standing still. Anyone, local or remote, who is still within SIT_TOL of a seat's anchor is drawn sitting
## on it, facing its way (`seat_at`). Bench and lounger anchors sit inside the furniture's collision, so nobody
## stands there by walking; only sitting puts you there (the pool's edge is open: stop exactly on it and you
## sit down, which is fine).
##
## Lookups go through a coarse grid, so asking "is there a seat here?" costs one dictionary read whatever the
## number of seats, and it is only asked when an avatar stops or starts (PlayerView), not every frame.
## No node references: positions in, indices and plain data out.

const CELL := 64.0
const SIT_TOL := 3.0       # px from an anchor that counts as sitting on it
const TAKEN_R := 8.0       # someone this close to an anchor has that seat
const STAND_OUT := 22.0    # px in front of a seat where you step off to (the furniture's collision ends there)
## How the seated pose is drawn (SpriteActor): the figure is lifted by `lift` px and its lowest `clip` rows
## (the legs, below the seat's edge) are left out. A seat in the spec may give its own.
const LIFT := 6.0
const CLIP := 6

var _seats: Array = []          # [{ id, at: Vector2, face: Vector2, lift, clip }]
var _grid: Dictionary = {}      # Vector2i cell -> Array[int] of seat indices


## The seats of a world's spec (its `seats` list; malformed entries are skipped). Empty if it has none.
static func from_spec(list: Variant) -> SeatLogic:
	var out := SeatLogic.new()
	if list is Array:
		for s in list:
			if s is Dictionary:
				out._add(s)
	return out


func _add(s: Dictionary) -> void:
	var at: Variant = s.get("at", null)
	if not (at is Array) or (at as Array).size() < 2:
		return
	var p := Vector2(float(at[0]), float(at[1]))
	var f := Vector2(0, 1)
	var fv: Variant = s.get("face", null)
	if fv is Array and (fv as Array).size() >= 2:
		f = Vector2(float(fv[0]), float(fv[1]))
	f = f.normalized() if f.length() > 0.01 else Vector2(0, 1)
	var off := p + f * STAND_OUT
	var ov: Variant = s.get("off", null)
	if ov is Array and (ov as Array).size() >= 2:
		off = Vector2(float(ov[0]), float(ov[1]))
	var i := _seats.size()
	_seats.append({
		"id": String(s.get("id", "seat_%d" % i)), "at": p, "face": f, "off": off,
		"lift": float(s.get("lift", LIFT)), "clip": int(s.get("clip", CLIP)),
	})
	var c := _cell(p)
	if not _grid.has(c):
		_grid[c] = []
	(_grid[c] as Array).append(i)


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func size() -> int:
	return _seats.size()


func is_empty() -> bool:
	return _seats.is_empty()


## Seat `i`: { id, at, face, lift, clip }.
func seat(i: int) -> Dictionary:
	return _seats[i]


## The seat whose anchor is within `tol` px of `pos`, or -1.
func seat_at(pos: Vector2, tol := SIT_TOL) -> int:
	var best := -1
	var best_d := tol * tol
	for i in _near(pos, tol):
		var d: float = pos.distance_squared_to(_seats[i]["at"])
		if d <= best_d:
			best = i
			best_d = d
	return best


## Whether an avatar at `pos` is sitting: still, and on a seat's anchor. The seat's index, or -1.
func seated(pos: Vector2, still: bool) -> int:
	return seat_at(pos) if still else -1


## The nearest seat whose anchor is within `reach` of `point` and that nobody in `others` (positions of other
## avatars) is already on (within TAKEN_R of it). -1 if none.
func nearest_free(point: Vector2, reach: float, others: Array = []) -> int:
	var best := -1
	var best_d := reach * reach
	for i in _near(point, reach):
		var at: Vector2 = _seats[i]["at"]
		var d := point.distance_squared_to(at)
		if d > best_d or _taken(at, others):
			continue
		best = i
		best_d = d
	return best


## Where you stand when you get up from seat `i`: its `off`, or a step in front of it, the way it faces.
func stand_point(i: int) -> Vector2:
	return _seats[i]["off"]


static func _taken(at: Vector2, others: Array) -> bool:
	for o in others:
		if o is Vector2 and at.distance_squared_to(o) <= TAKEN_R * TAKEN_R:
			return true
	return false


## Every seat index in the grid cells a circle of `r` round `p` touches.
func _near(p: Vector2, r: float) -> Array:
	var out: Array = []
	var lo := _cell(p - Vector2(r, r))
	var hi := _cell(p + Vector2(r, r))
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var bucket: Variant = _grid.get(Vector2i(cx, cy), null)
			if bucket != null:
				out.append_array(bucket)
	return out
