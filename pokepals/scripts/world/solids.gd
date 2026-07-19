class_name Solids
extends RefCounted
## Barriers as pure logic: the world's solid things as a list of circles, plus a
## resolver that keeps a moving body out of them and inside the map. No nodes, no
## physics engine — just geometry in, geometry out — so it's unit-testable, runs
## headless, and could later enforce the same collision on a server. The presentation
## layer (player/companion) calls resolve() right after its manual move; the companion
## *brain* never sees any of this.

## Built-in "solid" prop types and their blocking radii. Tall things block; flat,
## walk-over things (flowers, mushrooms, chime_stone, basin) are simply absent here.
## A prop can override via "solid"/"collision_radius" in the world spec.
const SOLID_TYPES := {
	"bench": 11.0,
	"signpost": 7.0,
	"lantern": 6.0,
	"crystal": 9.0,
	"log": 13.0,
	"berry_bush": 9.0,
}


## Build the full list of solid circles [{ center: Vector2, radius: float }] from the
## world data: hand-placed trees + the border ring, great-tree landmarks, the tall
## props, and (optionally) ponds. `border_pts` is the world's border treeline, generated
## SERVER-SIDE now (Server.WorldBorder) and shipped in the spec as "border_trees" — the
## client draws and collides against those authoritative points rather than generating them.
## cfg is the world spec's "collision" block.
static func build(world_data: Dictionary, border_pts: Array, cfg: Dictionary) -> Array:
	var solids: Array = []
	var tree_r := float(cfg.get("tree_radius", 7.0))
	var great_r := float(cfg.get("great_tree_radius", 16.0))
	var pond_blocks := bool(cfg.get("pond_blocks", true))

	for t in world_data.get("trees", []):
		solids.append({ "center": WorldData.to_vec2(t), "radius": tree_r })
	for p in border_pts:
		solids.append({ "center": p as Vector2, "radius": tree_r })
	for lm in world_data.get("landmarks", []):
		solids.append({ "center": WorldData.to_vec2(lm["position"]), "radius": great_r })
	for it in world_data.get("props", []):
		var type := String(it.get("type", ""))
		if not bool(it.get("solid", SOLID_TYPES.has(type))):
			continue
		var r := float(it.get("collision_radius", SOLID_TYPES.get(type, 8.0)))
		solids.append({ "center": WorldData.to_vec2(it["position"]), "radius": r })
	if pond_blocks:
		if world_data.has("pond"):
			solids.append(_pond_solid(world_data["pond"]))
		for pd in world_data.get("ponds", []):
			solids.append(_pond_solid(pd))
	# Hedge walls (the maze): each is a SEGMENT solid — a line from "from" to "to" with a
	# half-thickness radius (a capsule). resolve() pushes bodies off the nearest point of the
	# segment, so one entry blocks a whole long hedge run rather than a string of circles.
	for h in world_data.get("hedges", []):
		solids.append({
			"a": WorldData.to_vec2(h["from"]),
			"b": WorldData.to_vec2(h["to"]),
			"radius": float(h.get("thickness", 28.0)) * 0.5,
		})
	return solids


static func _pond_solid(pond: Dictionary) -> Dictionary:
	return { "center": WorldData.to_vec2(pond["center"]), "radius": float(pond["radius"]) }


## The point of solid `s` nearest to `p` — the blocking point a body is pushed away from.
## Circle solids carry a "center"; segment solids (hedges) carry "a"/"b", and for those the
## blocking point is the closest point on the segment. The ONE definition of the solid-dict
## shape, shared by the resolver here and by NavGrid's rasterizer — so a new solid shape
## can't silently mean different things to collision and to routing.
static func nearest_point(s: Dictionary, p: Vector2) -> Vector2:
	return Geometry2D.get_closest_point_to_segment(p, s["a"], s["b"]) if s.has("a") else s["center"]


## Keep a body of the given radius inside `bounds` and out of every solid. Clamps to
## the map edge, then pushes out of any overlapping circle (a couple of passes for
## corner stability). Only the into-the-obstacle component is corrected, so motion
## along a surface survives — i.e. you slide along walls and around trunks.
static func resolve(pos: Vector2, radius: float, solids: Array, bounds: Rect2, margin: float) -> Vector2:
	var r := radius + margin
	var p := pos
	p = _clamp_bounds(p, r, bounds)
	for _pass in 2:
		for s in solids:
			var center := nearest_point(s, p)
			var min_dist := r + float(s["radius"])
			var d := p - center
			var dist := d.length()
			if dist < min_dist:
				if dist < 0.0001:
					d = Vector2.UP
					dist = 0.0001
				p = center + d / dist * min_dist
		p = _clamp_bounds(p, r, bounds)
	return p


static func _clamp_bounds(p: Vector2, r: float, bounds: Rect2) -> Vector2:
	return Vector2(
		clampf(p.x, bounds.position.x + r, bounds.end.x - r),
		clampf(p.y, bounds.position.y + r, bounds.end.y - r))
