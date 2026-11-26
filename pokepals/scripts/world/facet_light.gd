class_name FacetLight
extends RefCounted
## Glintwold's turning light, as plain arithmetic: where the light stands at a given moment.
##
## The lore: a light found the dull stone and began, very slowly, to turn round it, and it is still turning. So
## every flat face (a glint) changes shade slowly as it goes. The angle is a pure function of the shared clock
## (pass Net.server_unix_ms()), so everyone in the world sees the same light, with nothing simulated or sent,
## the way Ebbmere's tide works.
##
## The angle is the direction TOWARD the light on the ground plane, in radians, screen space (x right, y down):
## at `start` (by default the upper left, -3/4 PI) when the turn begins, then a full turn every `period` seconds.
## Anything that wants to agree with the ground's shading (a shard, a tree's lit side) reads the same angle.

const DEFAULT_PERIOD := 600.0      # seconds for one full turn
const DEFAULT_START := -0.75 * PI  # from the upper left


## The light's angle at `unix_ms` (radians, -PI..PI).
static func angle(unix_ms: int, period_s := DEFAULT_PERIOD, start := DEFAULT_START) -> float:
	var p := maxf(1.0, period_s) * 1000.0
	var turn := fposmod(float(unix_ms), p) / p
	return wrapf(start + turn * TAU, -PI, PI)


## A unit vector toward the light on the ground plane.
static func direction(a: float) -> Vector2:
	return Vector2(cos(a), sin(a))


## The period and start from a ground entity's config ("light_period", "light_start" in degrees).
static func from_config(cfg: Dictionary, unix_ms: int) -> float:
	return angle(unix_ms, float(cfg.get("light_period", DEFAULT_PERIOD)), deg_to_rad(float(cfg.get("light_start", -135.0))))
