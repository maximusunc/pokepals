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


## The seeded, jittered border-ring tree positions. Shared by the renderer (world_art)
## and the collision builder so the drawn treeline and its barriers always agree.
static func border_positions(bounds: Rect2, cfg: Dictionary) -> Array:
	var out: Array = []
	if cfg.is_empty() or not bool(cfg.get("ring", true)):
		return out
	var spacing := float(cfg.get("spacing", 130.0))
	var inset := float(cfg.get("inset", 20.0))
	var jitter := float(cfg.get("jitter", 34.0))
	var rows := int(cfg.get("rows", 2))
	var row_gap := float(cfg.get("row_gap", 64.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xBEEF
	for row in rows:
		var pad := inset + float(row) * row_gap
		var rect := Rect2(bounds.position + Vector2(pad, pad), bounds.size - Vector2(pad * 2.0, pad * 2.0))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var x := rect.position.x
		while x <= rect.end.x:
			out.append(_jitter(Vector2(x, rect.position.y), jitter, rng))
			out.append(_jitter(Vector2(x, rect.end.y), jitter, rng))
			x += spacing
		var y := rect.position.y + spacing
		while y < rect.end.y:
			out.append(_jitter(Vector2(rect.position.x, y), jitter, rng))
			out.append(_jitter(Vector2(rect.end.x, y), jitter, rng))
			y += spacing
	return out


static func _jitter(base: Vector2, jitter: float, rng: RandomNumberGenerator) -> Vector2:
	return base + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))


## Build the full list of solid circles [{ center: Vector2, radius: float }] from the
## world data: hand-placed trees + the border ring, great-tree landmarks, the tall
## props, and (optionally) ponds. cfg is the world spec's "collision" block.
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
	for it in world_data.get("interactables", []):
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
	return solids


static func _pond_solid(pond: Dictionary) -> Dictionary:
	return { "center": WorldData.to_vec2(pond["center"]), "radius": float(pond["radius"]) }


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
			var center: Vector2 = s["center"]
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
