class_name PlazaRealm
extends RefCounted
## The geometry of a FLOATING PLAZA world (Lingerlong), as pure logic: no nodes, no drawing, no physics.
## A plaza is a few axis-aligned marble FLOORS and one shallow POOL, laid edge to edge, and everything else is
## open sky you must not be able to walk into. From the spec's `plaza` block this module builds
##   * the SOLIDS that fence it: the outline of the union of every rectangle, as segment solids (the same dict
##     shape Solids and NavGrid already understand, so collision and routing need nothing new). Where two floors
##     meet there is no fence: an edge only stands where the far side of it is sky;
##   * the GROUND test: is this point on a floor or in the pool? (The companion's walkability grid uses it, so a
##     route is never planned through the sky, and a floor that touches nothing, like the evening terrace, is an
##     island no route reaches.)
## It is the rectangle twin of SkyRealm (whose islands are polygons joined by bridges): a plaza is made of
## rooms that touch, so the fence has to be worked out from the union rather than authored.
##
## The `plaza` dictionary (from the world spec):
##   floors: [{ id, rect: [x0, y0, x1, y1], tile_b: [r, g, b] }]
##   pool:   { rect: [x0, y0, x1, y1] }        (wade-able water: ground too)
##   edge_radius (4.0)   half-thickness of the fence

const DEFAULT_EDGE_R := 4.0


## Every walkable rectangle (the floors, then the pool), as Rect2.
static func ground_rects(plaza: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for f in plaza.get("floors", []):
		out.append(rect_of(f.get("rect", [])))
	if plaza.has("pool"):
		out.append(rect_of((plaza["pool"] as Dictionary).get("rect", [])))
	return out


## [x0, y0, x1, y1] as a Rect2 (an empty one for anything malformed).
static func rect_of(r: Array) -> Rect2:
	if r.size() < 4:
		return Rect2()
	var a := Vector2(float(r[0]), float(r[1]))
	var b := Vector2(float(r[2]), float(r[3]))
	return Rect2(a, b - a).abs()


## The floor (its dictionary) that `p` stands on, or {} (the pool and the sky are no floor).
static func floor_at(plaza: Dictionary, p: Vector2) -> Dictionary:
	for f in plaza.get("floors", []):
		if _holds(rect_of(f.get("rect", [])), p):
			return f
	return {}


static func in_pool(plaza: Dictionary, p: Vector2) -> bool:
	return plaza.has("pool") and _holds(rect_of((plaza["pool"] as Dictionary).get("rect", [])), p)


static func is_ground(rects: Array, p: Vector2) -> bool:
	for r: Rect2 in rects:
		if _holds(r, p):
			return true
	return false


## A Rect2's has_point leaves out its far edges; a floor's edge is floor on every side.
static func _holds(r: Rect2, p: Vector2) -> bool:
	return p.x >= r.position.x and p.x <= r.end.x and p.y >= r.position.y and p.y <= r.end.y


## A Callable(Vector2) -> bool for NavGrid.build, or an invalid Callable when the world has no plaza.
static func ground_test(plaza: Dictionary) -> Callable:
	var rects := ground_rects(plaza)
	if rects.is_empty():
		return Callable()
	return func(p: Vector2) -> bool: return is_ground(rects, p)


## The fence round the union of every walkable rectangle: [{ a, b, radius }] segment capsules (see
## Solids.nearest_point). Each rectangle's four edges are cut wherever another rectangle's corner lines up
## with them, and a piece is kept only if the point just beyond its middle is sky. Collinear pieces that meet
## are joined again, so a long edge is one solid, not dozens.
static func solids(plaza: Dictionary) -> Array:
	var out: Array = []
	var rects := ground_rects(plaza)
	if rects.is_empty():
		return out
	var radius := float(plaza.get("edge_radius", DEFAULT_EDGE_R))
	var xs: Array[float] = []
	var ys: Array[float] = []
	for r in rects:
		xs.append_array([r.position.x, r.end.x])
		ys.append_array([r.position.y, r.end.y])
	for r in rects:
		# [fixed coordinate, from, to, outward normal, horizontal?] for the north, south, west and east edges
		var edges := [
			[r.position.y, r.position.x, r.end.x, Vector2.UP, true],
			[r.end.y, r.position.x, r.end.x, Vector2.DOWN, true],
			[r.position.x, r.position.y, r.end.y, Vector2.LEFT, false],
			[r.end.x, r.position.y, r.end.y, Vector2.RIGHT, false],
		]
		for e in edges:
			var fixed: float = e[0]
			var lo: float = e[1]
			var hi: float = e[2]
			var out_n: Vector2 = e[3]
			var horiz: bool = e[4]
			var cuts: Array[float] = [lo, hi]
			for c in (xs if horiz else ys):
				if c > lo and c < hi:
					cuts.append(c)
			cuts.sort()
			var run_from := NAN
			var run_to := NAN
			for i in cuts.size() - 1:
				var a := cuts[i]
				var b := cuts[i + 1]
				if b - a < 0.5:
					continue
				var mid := (a + b) * 0.5
				var probe := (Vector2(mid, fixed) if horiz else Vector2(fixed, mid)) + out_n
				var open_sky := not is_ground(rects, probe)
				if open_sky and not is_nan(run_from) and is_equal_approx(run_to, a):
					run_to = b
				elif open_sky:
					if not is_nan(run_from):
						out.append(_seg(fixed, run_from, run_to, horiz, radius))
					run_from = a
					run_to = b
			if not is_nan(run_from):
				out.append(_seg(fixed, run_from, run_to, horiz, radius))
	return out


static func _seg(fixed: float, a: float, b: float, horiz: bool, radius: float) -> Dictionary:
	if horiz:
		return { "a": Vector2(a, fixed), "b": Vector2(b, fixed), "radius": radius }
	return { "a": Vector2(fixed, a), "b": Vector2(fixed, b), "radius": radius }
