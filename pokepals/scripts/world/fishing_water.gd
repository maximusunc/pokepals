class_name FishingWater
extends RefCounted
## WHERE YOU CAN FISH (usable items, U-6 in docs/usable-items-design.md): anywhere there is water, in any
## world. Pure logic, no drawing: it reads a world spec's water (round `ponds` / a single `pond`, the
## Riverbank's `river` band) and answers "is this point water?" and "where would a cast from here land?".
## Water that changes with time (Ebbmere's tide) is added through `set_extra`, a test the world supplies.
##
## A pond's drawn outline wobbles a little around its radius, so a point only counts as water a little way
## inside it (`POND_INSET`): a bobber never lands on the bank.

const POND_INSET := 0.86    # a pond is water within this share of its radius
const REACH_MIN := 18.0     # the nearest a cast lands from your feet
const REACH_MAX := 96.0     # the farthest
const STEP := 6.0           # how finely a cast's line is searched
const SETTLE := 12.0        # how much further in the bobber settles past the first water it finds
const SWEEP_DIRS := 16      # directions tried when there's no water straight ahead

var _circles: Array = []    # [{ "c": Vector2, "r": float }]
var _rects: Array = []      # [Rect2]
var _extra := Callable()    # optional (Vector2) -> bool, for water that comes and goes


## The water in a world spec's core (its `pond`, `ponds` and `river`).
static func from_world(data: Dictionary) -> FishingWater:
	var w := FishingWater.new()
	if data.get("pond") is Dictionary:
		w._add_pond(data["pond"])
	for pd in data.get("ponds", []):
		if pd is Dictionary:
			w._add_pond(pd)
	var river: Variant = data.get("river")
	if river is Dictionary and (river as Dictionary).get("rect") is Array and ((river as Dictionary)["rect"] as Array).size() == 4:
		var r: Array = (river as Dictionary)["rect"]
		w._rects.append(Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	return w


func _add_pond(pd: Dictionary) -> void:
	var c: Variant = pd.get("center")
	if not (c is Array) or (c as Array).size() != 2:
		return
	_circles.append({ "c": Vector2(float(c[0]), float(c[1])), "r": float(pd.get("radius", 0.0)) * POND_INSET })


## Add a test for water that isn't in the spec's shapes (Ebbmere: wherever the tide covers right now).
func set_extra(is_water_at: Callable) -> void:
	_extra = is_water_at


## Whether this world has any water at all to fish in.
func has_water() -> bool:
	return not _circles.is_empty() or not _rects.is_empty() or _extra.is_valid()


## Whether a point is water.
func is_water(p: Vector2) -> bool:
	for c in _circles:
		if p.distance_squared_to(c["c"]) <= float(c["r"]) * float(c["r"]):
			return true
	for r: Rect2 in _rects:
		if r.has_point(p):
			return true
	if _extra.is_valid() and bool(_extra.call(p)):
		return true
	return false


## Where a cast from `origin` would land, or null if there's no water in reach. It goes the way you face
## first; if there's no water that way it looks all around and takes the nearest water within reach, so on
## a phone you needn't line up exactly. The bobber settles a little way into the water, not on its edge.
func cast_point(origin: Vector2, facing: Vector2) -> Variant:
	var ahead := facing.normalized() if facing.length() > 0.01 else Vector2.DOWN
	var hit: Variant = _first_water_along(origin, ahead)
	if hit != null:
		return hit
	var best: Variant = null
	var best_d := INF
	for i in SWEEP_DIRS:
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / float(SWEEP_DIRS))
		var p: Variant = _first_water_along(origin, dir)
		if p != null and origin.distance_to(p) < best_d:
			best = p
			best_d = origin.distance_to(p)
	return best


func _first_water_along(origin: Vector2, dir: Vector2) -> Variant:
	var d := REACH_MIN
	while d <= REACH_MAX:
		var p := origin + dir * d
		if is_water(p):
			var settled := origin + dir * minf(d + SETTLE, REACH_MAX)
			return settled if is_water(settled) else p
		d += STEP
	return null
