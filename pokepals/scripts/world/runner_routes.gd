class_name RunnerRoutes
extends RefCounted
## Where Ohmstead's RUNNERS are. Each follows a closed route of straight legs (along the grid's bright lines)
## at a steady pace, and where it is, is a pure function of TIME: every client works out the same place from the
## shared clock, so the runners are in the same spots for everyone with nothing simulated or sent (the way
## Ebbmere's tide is shared).
##
## Pure logic: no nodes, no drawing. A route is an Array of Vector2 corners; the last joins back to the first.


## The route's whole length.
static func length(route: Array) -> float:
	var total := 0.0
	for i in route.size():
		total += (route[(i + 1) % route.size()] as Vector2).distance_to(route[i])
	return total


## The point `dist` along the route from its first corner (wrapping), and the way it is heading there:
## { pos: Vector2, dir: Vector2 }.
static func at(route: Array, dist: float) -> Dictionary:
	if route.is_empty():
		return { "pos": Vector2.ZERO, "dir": Vector2.RIGHT }
	var total := length(route)
	if total <= 0.0:
		return { "pos": route[0], "dir": Vector2.RIGHT }
	var d := fposmod(dist, total)
	for i in route.size():
		var a: Vector2 = route[i]
		var b: Vector2 = route[(i + 1) % route.size()]
		var leg := a.distance_to(b)
		if d <= leg and leg > 0.0:
			return { "pos": a.lerp(b, d / leg), "dir": (b - a) / leg }
		d -= leg
	return { "pos": route[0], "dir": Vector2.RIGHT }


## Runner `index` of `count` on this route at time `t` (seconds on the shared clock): the runners are spread
## evenly round it, and every other route runs the other way round (`reverse`), so they don't all circle alike.
static func runner(route: Array, index: int, count: int, speed: float, t: float, reverse := false) -> Dictionary:
	var total := length(route)
	var along := t * speed + total * float(index) / float(maxi(1, count))
	if not reverse:
		return at(route, along)
	var r := at(route, -along)
	r["dir"] = -(r["dir"] as Vector2)
	return r


## Step aside from someone standing at `who`: how far (a Vector2) a runner at `pos` heading `dir` leans off its
## line, within `radius` of them. Sideways only, away from them, and gone by the edge of the radius.
static func sidestep(pos: Vector2, dir: Vector2, who: Vector2, radius: float, amount: float) -> Vector2:
	var d := pos.distance_to(who)
	if d >= radius or radius <= 0.0:
		return Vector2.ZERO
	var side := dir.orthogonal()
	var away := signf(side.dot(pos - who))
	if away == 0.0:
		away = 1.0
	var k := 1.0 - d / radius
	return side * away * amount * k * k * (3.0 - 2.0 * k)
