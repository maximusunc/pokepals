class_name BattleRNG
## Deterministic pseudo-random number generator, modelled as PURE DATA.
##
## The whole battle core must be deterministic and portable to a server later,
## so we never touch Godot's global RNG. Instead the generator's state is a plain
## Dictionary that is threaded through the battle state and advanced functionally:
## every draw returns BOTH a value AND a new rng dict. Same seed in -> same
## sequence out, every time, on any machine.
##
## Algorithm: a classic 64-bit linear congruential generator (LCG). The exact
## constants are part of the contract — keep them identical if/when this logic is
## reimplemented on the server so battles replay bit-for-bit.

const _MULT: int = 6364136223846793005
const _INCR: int = 1442695040888963407
const _RANGE: int = 0x7fffffff       # 2^31 - 1, used to clamp draws to a non-negative int
const _RANGE_F: float = 2147483648.0 # 2^31, divisor that maps a draw into [0.0, 1.0)


## Create a fresh generator from a seed.
static func make(seed_value: int) -> Dictionary:
	return { "seed": seed_value, "state": seed_value }


## Advance the generator once. Returns { "raw": int in [0, 2^31), "rng": new_rng }.
## This is the single primitive; next_int / next_float build on it.
static func _next_raw(rng: Dictionary) -> Dictionary:
	var s: int = rng["state"] * _MULT + _INCR  # int64; overflow wraps, which is intended
	var raw: int = (s >> 33) & _RANGE          # mask guarantees a non-negative 31-bit result
	return { "raw": raw, "rng": { "seed": rng["seed"], "state": s } }


## Draw an integer in [0, max_exclusive). Returns { "value": int, "rng": new_rng }.
static func next_int(rng: Dictionary, max_exclusive: int) -> Dictionary:
	assert(max_exclusive > 0, "next_int requires max_exclusive > 0")
	var step: Dictionary = _next_raw(rng)
	return { "value": step["raw"] % max_exclusive, "rng": step["rng"] }


## Draw a float in [0.0, 1.0). Returns { "value": float, "rng": new_rng }.
static func next_float(rng: Dictionary) -> Dictionary:
	var step: Dictionary = _next_raw(rng)
	return { "value": float(step["raw"]) / _RANGE_F, "rng": step["rng"] }


## Convenience: returns { "value": bool, "rng": new_rng }, true with probability p.
static func chance(rng: Dictionary, p: float) -> Dictionary:
	var step: Dictionary = next_float(rng)
	return { "value": step["value"] < p, "rng": step["rng"] }
