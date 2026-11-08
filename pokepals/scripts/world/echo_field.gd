class_name EchoField
extends RefCounted
## ECHOES in a canyon, as pure geometry (Hollowsong). Given a voice at a point, the listener's ears, and the
## canyon's authored WALLS (line segments), it works out which walls answer, from where, and when. It draws
## nothing and knows no nodes: the HowlDirector hands the answer to the ripples.
##
## HOW A WALL ANSWERS (the mirror-image method). A sound that bounces off a flat wall reaches you exactly as
## if it came from the source's MIRROR IMAGE behind the wall. So for each wall: reflect the source across
## its line, draw a straight line from that image to the listener, and if it crosses the wall's actual
## extent, that wall answers, at the crossing point. The path is as long as that straight line, so the echo
## arrives `path / speed` seconds after the call, and fainter the longer the path. A wall is only heard if
## the voice can actually reach it and come back: the two legs must not pass through another wall. Because
## the image is a point, the returning wavefront is simply a circle centred on it (that is what the ripples
## draw), cut to the beam the wall's ends allow.
##
## THE WRONG ANSWER. One place in the canyon answers where there is no wall at all: a hidden cave. It
## returns a late, hollow reply from its own position rather than from any face, which is what the player
## is meant to notice and follow. Its apparent origin is seen with a little error that shrinks the closer
## you stand and the deeper the bond (`wrong_echo`), so a single howl gives a rough bearing and two howls
## from two places close in on it.
##
## Everything is deterministic (the error comes from an integer seed), and every number is a plain
## dictionary entry (the secret's `reveal` block), with the DEFAULTS as a safety net only.

const DEFAULTS := {
	"speed": 700.0,               # px/s the sound travels, in the ripples and in the delays
	"path_low": 1500.0,           # the longest there-and-back path still heard, at zero bond...
	"path_high": 2200.0,          # ...and at full bond (a bonded howl carries further)
	"min_strength": 0.10,         # fainter than this and the echo is dropped
	"falloff": 1.15,              # how fast strength drops with path length
	"max_candidates": 28,         # walls considered per howl, nearest first (bounds the cost)
	"min_gap": 8.0,               # the source must be at least this far off a wall to bounce off it
	"hollow": 0.35,               # extra seconds before the wrong answer starts (it answers late, like a hollow)
	"wrong_range_low": 1100.0,    # how far the cave can hear a howl, at zero bond...
	"wrong_range_high": 1700.0,   # ...and at full bond
	"wrong_noise_low": 0.38,      # radians the wrong answer's bearing is off at full range, fresh...
	"wrong_noise_high": 0.10,     # ...and bonded
	"wrong_noise_floor": 0.18,    # up close the error never falls below this fraction of the above
	"wrong_strength_low": 0.70,   # how clearly the wrong answer shows, fresh...
	"wrong_strength_high": 1.0,   # ...and bonded
}


## `[ax, ay, bx, by]` arrays (the spec's wall list) as `[Vector2 a, Vector2 b]` pairs.
static func walls_from(list: Array) -> Array:
	var out: Array = []
	for w in list:
		if w is Array and (w as Array).size() >= 4:
			var a := Vector2(float(w[0]), float(w[1]))
			var b := Vector2(float(w[2]), float(w[3]))
			if a.distance_squared_to(b) > 1.0:
				out.append([a, b])
	return out


## `p` reflected across the infinite line through a and b.
static func mirror(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	var t := (p - a).dot(d) / maxf(0.000001, d.length_squared())
	var foot := a + d * t
	return foot * 2.0 - p


## Which side of the line a->b the point is on (positive, negative, or ~0 on it), in px of distance.
static func side_of(p: Vector2, a: Vector2, b: Vector2) -> float:
	var d := b - a
	return d.cross(p - a) / maxf(0.000001, d.length())


## Whether the segment p->q is blocked by any wall in `walls` (indices in `only`, or all when empty),
## except the wall `skip`. The ends are pulled in by `trim` px so a leg that merely touches its own
## reflecting wall, or a corner it turns at, is not counted as passing through.
static func blocked(p: Vector2, q: Vector2, walls: Array, skip: int, trim: float = 2.0, only: Array = []) -> bool:
	var d := q - p
	var len := d.length()
	if len <= trim * 2.0:
		return false
	var u := d / len
	var p2 := p + u * trim
	var q2 := q - u * trim
	if only.is_empty():
		for i in walls.size():
			if i != skip and Geometry2D.segment_intersects_segment(p2, q2, walls[i][0], walls[i][1]) != null:
				return true
	else:
		for i in only:
			if i != skip and Geometry2D.segment_intersects_segment(p2, q2, walls[i][0], walls[i][1]) != null:
				return true
	return false


## The longest there-and-back path still heard, at a bond (0..1).
static func reach(cfg: Dictionary, bond: float) -> float:
	return _bond_lerp(cfg, "path_low", "path_high", bond)


## How far the hidden cave can hear a howl from, at a bond.
static func wrong_range(cfg: Dictionary, bond: float) -> float:
	return _bond_lerp(cfg, "wrong_range_low", "wrong_range_high", bond)


## The echoes that come back to `listener` from a voice at `source`, one per answering wall, nearest to
## sound first. Each: { point (where it bounces), image (the mirror image: the centre of the returning
## circle), a, b (the wall's ends), wall (index), t_hit (seconds until the call reaches the wall),
## arrive (seconds until it is back), path (px), strength (0..1) }.
static func echoes(source: Vector2, listener: Vector2, walls: Array, cfg: Dictionary, bond: float = 0.0) -> Array:
	var c := _cfg(cfg)
	var speed := maxf(1.0, float(c["speed"]))
	var max_path := reach(c, bond)
	var min_gap := float(c["min_gap"])
	# the walls near enough to matter, nearest first (this also bounds the occlusion test below)
	var near: Array = []
	for i in walls.size():
		var d := _dist_to_segment(source, walls[i][0], walls[i][1])
		if d <= max_path * 0.5:
			near.append([d, i])
	near.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var cap := int(c["max_candidates"])
	var cand: Array = []
	for k in mini(near.size(), cap):
		cand.append(int(near[k][1]))
	var out: Array = []
	for i in cand:
		var a: Vector2 = walls[i][0]
		var b: Vector2 = walls[i][1]
		var ss := side_of(source, a, b)
		var sl := side_of(listener, a, b)
		if ss * sl <= 0.0 or absf(ss) < min_gap:
			continue   # opposite sides of the wall, or standing on it: no bounce
		var image := mirror(source, a, b)
		var path := image.distance_to(listener)
		if path > max_path:
			continue
		var hit: Variant = Geometry2D.segment_intersects_segment(image, listener, a, b)
		if hit == null:
			continue
		var p: Vector2 = hit
		if blocked(source, p, walls, i, 2.0, cand) or blocked(p, listener, walls, i, 2.0, cand):
			continue
		var strength := pow(clampf(1.0 - path / max_path, 0.0, 1.0), float(c["falloff"]))
		if strength < float(c["min_strength"]):
			continue
		out.append({ "point": p, "image": image, "a": a, "b": b, "wall": i, "t_hit": source.distance_to(p) / speed,
			"arrive": path / speed, "path": path, "strength": strength })
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["arrive"]) < float(y["arrive"]))
	return out


## The cave's wrong answer to a howl, or {} when it is out of earshot. `cave` is where the answer truly
## comes from; the reply starts there `hollow` seconds after the call reaches it, and reaches `listener` a
## travel-time later. { origin (where it seems to come from: the cave seen with some bearing error),
## truth, t_birth, arrive, strength, error (radians, signed), dist }. `seed` makes the error repeatable.
static func wrong_echo(source: Vector2, listener: Vector2, cave: Vector2, cfg: Dictionary, bond: float, seed: int) -> Dictionary:
	var c := _cfg(cfg)
	var range_px := wrong_range(c, bond)
	var dist := listener.distance_to(cave)
	var out_dist := source.distance_to(cave)
	if dist > range_px or out_dist > range_px:
		return {}
	var speed := maxf(1.0, float(c["speed"]))
	var full := _bond_lerp(c, "wrong_noise_low", "wrong_noise_high", bond)
	var near_factor := clampf(dist / maxf(1.0, range_px), float(c["wrong_noise_floor"]), 1.0)
	var err := full * near_factor * unit(seed)
	var origin := listener + (cave - listener).rotated(err)
	var t_birth := out_dist / speed + float(c["hollow"])
	var strength := _bond_lerp(c, "wrong_strength_low", "wrong_strength_high", bond) * (1.0 - 0.45 * clampf(dist / range_px, 0.0, 1.0))
	return { "origin": origin, "truth": cave, "t_birth": t_birth, "arrive": t_birth + dist / speed,
		"strength": clampf(strength, 0.0, 1.0), "error": err, "dist": dist }


## A repeatable pseudo-random number in [-1, 1] from an integer seed (an integer hash, so the same on every
## platform; the same seed always gives the same number).
static func unit(seed: int) -> float:
	var h := (seed * 1103515245 + 12345) & 0x7fffffff
	h = (h ^ (h >> 13)) & 0x7fffffff
	h = (h * 1103515245 + 12345) & 0x7fffffff
	return float(h % 20001) / 10000.0 - 1.0


static func _bond_lerp(cfg: Dictionary, low: String, high: String, bond: float) -> float:
	var c := _cfg(cfg)
	return lerpf(float(c[low]), float(c[high]), clampf(bond, 0.0, 1.0))


static func _cfg(cfg: Dictionary) -> Dictionary:
	if cfg.has("_complete"):
		return cfg   # already merged over the defaults (EchoGuide does it once): no copy
	var c := DEFAULTS.duplicate()
	for k in cfg:
		c[k] = cfg[k]
	return c


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
