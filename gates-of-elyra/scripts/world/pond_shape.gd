class_name PondShape
extends RefCounted
## THE SHAPE OF A POND'S BANK, as pure logic: the one formula the drawn shoreline (WorldArt), the sandy
## shore band (GroundLayer), collision (Solids, NavGrid), fishing (FishingWater) and the server's pal sim
## (Server.AmbientPals, an Elixir twin) all read, so where you are stopped is where the water is drawn.
##
## A pond is a gently irregular ring round its centre: the radius is nudged in and out by a few INTEGER
## harmonics (integer frequencies are what let the loop close seamlessly at a == TAU) whose phases are
## offset by a seed taken from the pond's position, so every body of water keeps its own stable shape.
## A soft world (one whose art block renders its ground "soft": Bobbledown) has truly round water.

const MAX_WOBBLE := 0.205   # the farthest the bank strays from the nominal radius (the harmonics' amplitudes summed)


## A pond's seed, from its centre (the same stable phase WorldArt gives everything that sways).
static func seed_for(center: Vector2) -> float:
	return fposmod(center.x * 0.013 + center.y * 0.021, TAU)


## The bank's distance from the centre at angle `a`.
static func radius_at(a: float, radius: float, seed: float) -> float:
	var wobble := 0.11 * sin(3.0 * a + seed) + 0.06 * sin(5.0 * a - seed * 1.7) + 0.035 * sin(8.0 * a + seed * 2.3)
	return radius * (1.0 + wobble)


## The bank's distance from the centre in the direction of `p`.
static func radius_toward(p: Vector2, center: Vector2, radius: float, seed: float) -> float:
	var off := p - center
	return radius_at(off.angle(), radius, seed) if off.length_squared() > 0.000001 else radius * (1.0 - MAX_WOBBLE)


## The farthest the bank reaches from the centre.
static func max_radius(radius: float) -> float:
	return radius * (1.0 + MAX_WOBBLE)


## Does this world draw its ponds with the wobbly bank? (Every world but a soft one.)
static func organic_in(world_data: Dictionary) -> bool:
	var art: Variant = world_data.get("art")
	if not (art is Dictionary):
		return true
	var ents: Variant = (art as Dictionary).get("entities")
	if not (ents is Dictionary):
		return true
	var ground: Variant = (ents as Dictionary).get("ground")
	return not (ground is Dictionary and String((ground as Dictionary).get("render", "")) == "soft")
