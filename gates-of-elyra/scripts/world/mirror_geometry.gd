class_name MirrorGeometry
extends RefCounted
## The geometry of a reflection, as pure functions (Stillglass's mirror lake). The camera looks at the
## world from above and a little in front, so the mirror image of something standing on a bank hangs
## straight DOWN the screen from its feet into the water: the water's edge is the axis, and the image
## is the thing flipped top to bottom about it. That makes a reflection a function of three things only:
## where the thing stands, where the waterline is directly below it, and how far it stands from that
## line. No nodes, no rendering; the presentation layer owns the sprites and the clip.

## The y of the water's surface straight below `foot`, or NAN. `is_water` is a Callable(Vector2) -> bool.
## `foot` must be on dry ground (something standing IN the water has no reflection of its own to show),
## and the water must start within `reach` px below it. Found by stepping down, then bisecting the last
## step so the answer is exact to well under a pixel.
static func waterline_below(foot: Vector2, is_water: Callable, reach: float, step: float = 3.0) -> float:
	if is_water.call(foot):
		return NAN
	var y := 0.0
	while y < reach:
		var ny := minf(reach, y + step)
		if is_water.call(Vector2(foot.x, foot.y + ny)):
			var lo := y
			var hi := ny
			for _i in 5:
				var mid := (lo + hi) * 0.5
				if is_water.call(Vector2(foot.x, foot.y + mid)):
					hi = mid
				else:
					lo = mid
			return foot.y + hi
		y = ny
	return NAN


## The mirror image of a world point about the horizontal line y = axis_y.
static func reflect_point(p: Vector2, axis_y: float) -> Vector2:
	return Vector2(p.x, 2.0 * axis_y - p.y)


## How much of a reflection shows given how far the thing stands from the waterline: full at the edge,
## fading to nothing by `reach` (smoothly, so something walking away from the lake lets go of its image
## instead of losing it with a pop).
static func strength(gap: float, reach: float) -> float:
	if reach <= 0.0 or gap >= reach:
		return 0.0
	var t := clampf(gap / reach, 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


## The animal the lake shows INSTEAD of `current`: one of `pool`, never the one worn, picked by `seed`
## alone (so the same companion shape meets the same other animal every time: deterministic and testable).
## "" when the pool offers nothing else.
static func pick_species(current: String, pool: Array, seed: int) -> String:
	var others: Array = []
	for s in pool:
		if String(s) != current and not others.has(String(s)):
			others.append(String(s))
	if others.is_empty():
		return ""
	return String(others[posmod(seed, others.size())])


## A stable small integer from a string (a secret's id): the seed the lake's choices are made from.
static func seed_of(text: String) -> int:
	var h := 0
	for i in text.length():
		h = (h * 31 + text.unicode_at(i)) & 0x7fffffff
	return h
