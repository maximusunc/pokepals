class_name PathShape
extends RefCounted
## Turns a world spec's straight path SEGMENTS into the organic curves the ground draws.
##
## A spec authors a path as from→to segments; a long trail is several segments end to end, and
## a fork is three meeting at one point. Drawn literally that's a set of ruler-straight strokes
## with hard elbows. Here we:
##   1. chain segments that meet end-to-end into one polyline per trail (a fork, or any point
##      where three or more meet, ends a chain, so trails still join at their junctions);
##   2. round every interior elbow off with Chaikin corner-cutting (the ends stay put);
##   3. resample evenly and let it meander a little side to side, the wander fading to zero at
##      both ends so junctions and destinations still line up exactly.
## Pure geometry (no drawing), deterministic from the input: the same spec curves the same way on
## every client. Presentation only: paths never collide, so nothing in the world logic changes.

const JOIN_EPS := 1.5  # endpoints this close count as the same point


## The full pipeline: segments [{from: Vector2, to: Vector2}, …] → smoothed, meandering polylines.
static func curves(segments: Array, meander := 9.0, step := 10.0) -> Array:
	var out: Array = []
	for chain in chains(segments):
		var pts := smooth(chain, 3)
		pts = resample(pts, step)
		out.append(wander(pts, meander))
	return out


## Group segments into polylines that run through every point where exactly two segments meet.
static func chains(segments: Array) -> Array:
	var nodes: Array[Vector2] = []
	var edges: Array = []  # [a_index, b_index]
	for s in segments:
		edges.append([_node(nodes, s["from"]), _node(nodes, s["to"])])
	var degree := PackedInt32Array()
	degree.resize(nodes.size())
	for e in edges:
		degree[e[0]] += 1
		degree[e[1]] += 1
	var used := PackedByteArray()
	used.resize(edges.size())
	var out: Array = []
	# Start a chain at every node that isn't a simple pass-through, walking each unused edge out of it.
	for start in nodes.size():
		if degree[start] == 2:
			continue
		for ei in edges.size():
			if used[ei] == 0 and (edges[ei][0] == start or edges[ei][1] == start):
				out.append(_walk(nodes, edges, degree, used, start, ei))
	# Whatever is left is a closed loop of pass-through nodes.
	for ei in edges.size():
		if used[ei] == 0:
			out.append(_walk(nodes, edges, degree, used, edges[ei][0], ei))
	return out


static func _node(nodes: Array[Vector2], p: Vector2) -> int:
	for i in nodes.size():
		if nodes[i].distance_to(p) <= JOIN_EPS:
			return i
	nodes.append(p)
	return nodes.size() - 1


static func _walk(nodes: Array[Vector2], edges: Array, degree: PackedInt32Array, used: PackedByteArray, start: int, first_edge: int) -> PackedVector2Array:
	var pts := PackedVector2Array([nodes[start]])
	var at := start
	var ei := first_edge
	while ei >= 0:
		used[ei] = 1
		var nxt: int = edges[ei][1] if edges[ei][0] == at else edges[ei][0]
		pts.append(nodes[nxt])
		at = nxt
		ei = -1
		if degree[at] == 2:
			for k in edges.size():
				if used[k] == 0 and (edges[k][0] == at or edges[k][1] == at):
					ei = k
					break
	return pts


## Chaikin corner-cutting: each pass replaces every interior corner with two points a quarter of the
## way along its edges. The first and last points are kept, so a trail still ends where it was put.
static func smooth(pts: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var cur := pts
	for _i in iterations:
		if cur.size() < 3:
			return cur
		var nxt := PackedVector2Array([cur[0]])
		for k in cur.size() - 1:
			var a := cur[k]
			var b := cur[k + 1]
			if k > 0:
				nxt.append(a.lerp(b, 0.25))
			if k < cur.size() - 2:
				nxt.append(a.lerp(b, 0.75))
		nxt.append(cur[cur.size() - 1])
		cur = nxt
	return cur


## Evenly spaced points along a polyline, about `step` apart (both ends kept).
static func resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var out := PackedVector2Array([pts[0]])
	var carry := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var seg := a.distance_to(b)
		var t := step - carry
		while t < seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	# Always finish exactly on the authored end: append it, or, if the last sample already landed within
	# half a pixel of it, snap that sample onto it (so a path never stops a hair short of its end).
	var end := pts[pts.size() - 1]
	if out[out.size() - 1].distance_to(end) > 0.5:
		out.append(end)
	else:
		out[out.size() - 1] = end
	return out


## Push each point sideways by a slow, seeded wave, tapering to nothing at both ends.
static func wander(pts: PackedVector2Array, amp: float) -> PackedVector2Array:
	var n := pts.size()
	if n < 3 or amp <= 0.0:
		return pts
	var seed := fposmod(pts[0].x * 0.0123 + pts[0].y * 0.0311, TAU)
	var out := PackedVector2Array()
	var dist := 0.0
	var total := 0.0
	for k in n - 1:
		total += pts[k].distance_to(pts[k + 1])
	for k in n:
		if k > 0:
			dist += pts[k - 1].distance_to(pts[k])
		var a := pts[maxi(k - 1, 0)]
		var b := pts[mini(k + 1, n - 1)]
		var tangent := (b - a).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var u := dist / maxf(total, 0.001)
		var taper := sin(u * PI)  # 0 at both ends
		var w := sin(dist * 0.021 + seed) * 0.7 + sin(dist * 0.047 - seed * 1.3) * 0.3
		out.append(pts[k] + normal * w * amp * taper)
	return out
