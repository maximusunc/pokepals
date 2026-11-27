class_name SkyRealm
extends RefCounted
## The geometry of a SKY-ISLAND world (Loftreach), as pure logic: no nodes, no drawing, no physics.
## A sky world is a set of ISLANDS (closed polygons of walkable ground) joined by rope BRIDGES (straight walkable
## strips), and everything else is open sky you must not be able to walk into. From that one description this
## module builds
##   * the SOLIDS that fence it: every island's edge becomes a chain of segment solids (the same dict shape
##     Solids and NavGrid already understand, so collision and routing need nothing new), with a gap cut where
##     an open bridge joins the island, and a rail along each side of every open bridge;
##   * the GROUND test: is this point on an island or on an open bridge? (The companion's walkability grid
##     uses it so a path is never planned through the sky.)
## A bridge may be HIDDEN (`"hidden": true`): until its id is listed in the sky's `revealed` array it has no
## gap, no rails and no ground, so the island it springs from is simply closed there. That is how a bridge
## "appears": the world rebuilds its solids and routing with the id revealed (see Solids.build, which calls
## solids() with the same dictionary).
##
## The `sky` dictionary (from the world spec; every number is authored in data):
##   islands: [{ id, poly: [[x, y], ...] }]            closed outlines, any winding
##   bridges: [{ id, a: [x, y], b: [x, y], width, hidden }]   a and b are the two mouths, on island edges
##   edge_radius  (5.0)   half-thickness of an island's fence      rail_radius  (3.0)   of a bridge's rail
##   revealed: [bridge ids]  (runtime) hidden bridges that are open now

const DEFAULT_EDGE_R := 5.0
const DEFAULT_RAIL_R := 3.0
const DEFAULT_WIDTH := 80.0
## How far a bridge's walkable strip reaches past each mouth, into the island, so there is no seam of
## "sky" in the walkability grid where the two meet.
const MOUTH_OVERLAP := 16.0


static func is_open(bridge: Dictionary, sky: Dictionary) -> bool:
	if not bool(bridge.get("hidden", false)):
		return true
	return (sky.get("revealed", []) as Array).has(String(bridge.get("id", "")))


static func bridge_ends(b: Dictionary) -> Array:
	return [WorldData.to_vec2(b["a"]), WorldData.to_vec2(b["b"])]


static func bridge_width(b: Dictionary) -> float:
	return float(b.get("width", DEFAULT_WIDTH))


static func find_bridge(sky: Dictionary, id: String) -> Dictionary:
	for b in sky.get("bridges", []):
		if String(b.get("id", "")) == id:
			return b
	return {}


static func find_island(sky: Dictionary, id: String) -> Dictionary:
	for i in sky.get("islands", []):
		if String(i.get("id", "")) == id:
			return i
	return {}


static func poly_points(island: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in island.get("poly", []):
		out.append(WorldData.to_vec2(p))
	return out


static func centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(1.0, float(poly.size()))


## The walkable strip of a bridge as a quad, reaching `pad` px past each mouth along its axis.
static func bridge_quad(b: Dictionary, pad: float = 0.0) -> PackedVector2Array:
	var ends := bridge_ends(b)
	var a: Vector2 = ends[0]
	var c: Vector2 = ends[1]
	var u := (c - a).normalized()
	var n := u.orthogonal() * bridge_width(b) * 0.5
	a -= u * pad
	c += u * pad
	return PackedVector2Array([a - n, c - n, c + n, a + n])


## The solids that fence the sky world: [{ a, b, radius }] segment capsules (see Solids.nearest_point).
static func solids(sky: Dictionary) -> Array:
	var out: Array = []
	if sky.is_empty():
		return out
	var edge_r := float(sky.get("edge_radius", DEFAULT_EDGE_R))
	var rail_r := float(sky.get("rail_radius", DEFAULT_RAIL_R))
	var open: Array = []
	for b in sky.get("bridges", []):
		if is_open(b, sky):
			open.append(b)
	for isl in sky.get("islands", []):
		var poly := poly_points(isl)
		var n := poly.size()
		for i in n:
			var p := poly[i]
			var q := poly[(i + 1) % n]
			for iv in _kept_intervals(p, q, open):
				var a: Vector2 = p.lerp(q, iv[0])
				var c: Vector2 = p.lerp(q, iv[1])
				if a.distance_to(c) >= 0.5:
					out.append({ "a": a, "b": c, "radius": edge_r })
	for b in open:
		var ends := bridge_ends(b)
		var a: Vector2 = ends[0]
		var c: Vector2 = ends[1]
		var nrm := (c - a).normalized().orthogonal() * bridge_width(b) * 0.5
		out.append({ "a": a - nrm, "b": c - nrm, "radius": rail_r })
		out.append({ "a": a + nrm, "b": c + nrm, "radius": rail_r })
	return out


## The parts of edge p->q (as [t0, t1] along it) that stay solid once every open bridge's gap is cut out: the
## gap is where the edge passes through the bridge's strip, between the two mouths.
static func _kept_intervals(p: Vector2, q: Vector2, open: Array) -> Array:
	var cuts: Array = []
	var d := q - p
	for b in open:
		var ends := bridge_ends(b)
		var a: Vector2 = ends[0]
		var c: Vector2 = ends[1]
		var len := a.distance_to(c)
		if len < 1.0:
			continue
		var u := (c - a) / len
		var nrm := u.orthogonal()
		var half := bridge_width(b) * 0.5
		# E(t) = p + t d; across-strip s(t) = (E - a).n, along-strip l(t) = (E - a).u; both linear in t.
		var s0 := (p - a).dot(nrm)
		var s1 := d.dot(nrm)
		var l0 := (p - a).dot(u)
		var l1 := d.dot(u)
		var lo := 0.0
		var hi := 1.0
		var iv_s := _slab(s0, s1, -half, half)
		# only the part of the edge inside the strip AND near a mouth (within a few px of either end of the axis)
		var iv_a := _slab(l0, l1, -MOUTH_OVERLAP, 6.0)
		var iv_b := _slab(l0, l1, len - 6.0, len + MOUTH_OVERLAP)
		for iv in [iv_a, iv_b]:
			if iv_s.is_empty() or iv.is_empty():
				continue
			lo = maxf(iv_s[0], iv[0])
			hi = minf(iv_s[1], iv[1])
			if lo < hi:
				cuts.append([maxf(0.0, lo), minf(1.0, hi)])
	if cuts.is_empty():
		return [[0.0, 1.0]]
	cuts.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var kept: Array = []
	var cursor := 0.0
	for c in cuts:
		if c[0] > cursor:
			kept.append([cursor, c[0]])
		cursor = maxf(cursor, c[1])
	if cursor < 1.0:
		kept.append([cursor, 1.0])
	return kept


## The t in [0, 1] where v0 + t * dv lies in [lo, hi], or [] when it never does.
static func _slab(v0: float, dv: float, lo: float, hi: float) -> Array:
	if absf(dv) < 0.00001:
		return [0.0, 1.0] if v0 >= lo and v0 <= hi else []
	var t0 := (lo - v0) / dv
	var t1 := (hi - v0) / dv
	var a := clampf(minf(t0, t1), 0.0, 1.0)
	var b := clampf(maxf(t0, t1), 0.0, 1.0)
	return [a, b] if a < b else []


static func point_in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly)


## A reusable ground test for a sky: `is_ground(p)` is true on an island or on an open bridge. Bounding boxes
## reject almost every polygon before the exact test, so asking for every cell of a walkability grid is cheap.
class Ground extends RefCounted:
	var _polys: Array = []     # [{ poly: PackedVector2Array, box: Rect2 }]

	func _init(sky: Dictionary) -> void:
		for isl in sky.get("islands", []):
			var poly := SkyRealm.poly_points(isl)
			_polys.append({ "poly": poly, "box": _box(poly) })
		for b in sky.get("bridges", []):
			if SkyRealm.is_open(b, sky):
				var quad := SkyRealm.bridge_quad(b, SkyRealm.MOUTH_OVERLAP)
				_polys.append({ "poly": quad, "box": _box(quad) })

	static func _box(poly: PackedVector2Array) -> Rect2:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in poly:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		return Rect2(lo, hi - lo)

	func is_ground(p: Vector2) -> bool:
		for e in _polys:
			if (e["box"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, e["poly"]):
				return true
		return false


## The ground test as a Callable (Vector2) -> bool, or an empty Callable for a world with no sky.
static func ground_test(sky: Dictionary) -> Callable:
	if sky.is_empty() or (sky.get("islands", []) as Array).is_empty():
		return Callable()
	var g := Ground.new(sky)
	return func(p: Vector2) -> bool: return g.is_ground(p)
