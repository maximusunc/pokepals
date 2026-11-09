class_name TideClock
extends RefCounted
## EBBMERE's tide, as a pure function of shared time. Nothing is simulated or broadcast: every client and
## the server compute the same level from the same wall-clock UTC time, an authored period and an
## authored low-water band, so the whole world sees one tide. No nodes, no rendering. The server has a
## twin of this in Elixir (Server.Tide); both are held to the same vectors (tests/world_fixtures/tide_vectors.json).
##
## The shape is one cosine per period: PHASE 0 is high water, PHASE 0.5 the lowest, and the level is
##   level = level_low + (level_high - level_low) * (0.5 + 0.5 * cos(TAU * phase))
## so the water goes out for half a period (phase 0..0.5, "ebbing"), then comes back (0.5..1, "flooding").
## The LOW WINDOW is the stretch around phase 0.5 where the level is at or under `yield_level`: that is the
## "lowest tide" in which the secret's sand-dollar will rise. Everything is in integer milliseconds on the
## way in (so the cycle index and the phase never drift with float error), floats on the way out.
##
## Params (a Dictionary, the spec's `tide` block): period_s, epoch_s, level_low, level_high, yield_level.

const DEFAULTS := { "period_s": 360.0, "epoch_s": 0.0, "level_low": 0.30, "level_high": 0.78, "yield_level": 0.345 }


static func _f(p: Dictionary, key: String) -> float:
	return float(p.get(key, DEFAULTS[key]))


static func period_ms(p: Dictionary) -> int:
	return maxi(1, int(round(_f(p, "period_s") * 1000.0)))


static func epoch_ms(p: Dictionary) -> int:
	return int(round(_f(p, "epoch_s") * 1000.0))


## Where `now_ms` (unix milliseconds) falls in the cycle: 0..1, 0 = high water, 0.5 = lowest.
static func phase(p: Dictionary, now_ms: int) -> float:
	var per := period_ms(p)
	return float(posmod(now_ms - epoch_ms(p), per)) / float(per)


## Which tide this is: an integer that steps up at every high water. Everything per-tide (which dig spots
## are alive, what they hold) is keyed by it, so all clients agree.
@warning_ignore("integer_division")
static func cycle(p: Dictionary, now_ms: int) -> int:
	var per := period_ms(p)
	var d := now_ms - epoch_ms(p)
	return (d - posmod(d, per)) / per


## The water level, level_low .. level_high.
static func level(p: Dictionary, now_ms: int) -> float:
	var lo := _f(p, "level_low")
	var hi := _f(p, "level_high")
	return lo + (hi - lo) * (0.5 + 0.5 * cos(TAU * phase(p, now_ms)))


## Half the width, in seconds, of the low window (the stretch where the level is at or under yield_level).
## 0 if the yield level is at or under the lowest water ever reached; half a period if it is never above it.
static func low_half_s(p: Dictionary) -> float:
	var lo := _f(p, "level_low")
	var hi := _f(p, "level_high")
	var span := hi - lo
	if span <= 0.0:
		return 0.0
	var c := 2.0 * (_f(p, "yield_level") - lo) / span - 1.0   # cos(TAU * phase) at the window's edge, on the ebb
	var arg := -c
	if arg >= 1.0:
		return 0.0
	if arg <= -1.0:
		return _f(p, "period_s") * 0.5
	return acos(arg) / TAU * _f(p, "period_s")


## Seconds from the exact middle of the lowest water.
static func seconds_from_lowest(p: Dictionary, now_ms: int) -> float:
	return absf(phase(p, now_ms) - 0.5) * _f(p, "period_s")


## Whether it is lowest tide: the level is at or under yield_level. `grace_s` widens the window on both
## sides (clock skew, a slow claim).
static func in_low_window(p: Dictionary, now_ms: int, grace_s: float = 0.0) -> bool:
	return seconds_from_lowest(p, now_ms) <= low_half_s(p) + grace_s


## "low" inside the low window; otherwise "ebbing" (the water going out) or "flooding" (coming back).
static func state(p: Dictionary, now_ms: int) -> String:
	if in_low_window(p, now_ms):
		return "low"
	return "ebbing" if phase(p, now_ms) < 0.5 else "flooding"


## Seconds until the low window opens (0 when it is open now). Counted forward, wrapping past high water.
static func seconds_until_low(p: Dictionary, now_ms: int) -> float:
	var half := low_half_s(p)
	var per := _f(p, "period_s")
	var from_lowest := phase(p, now_ms) * per - per * 0.5   # negative before the lowest point, positive after
	if absf(from_lowest) <= half:
		return 0.0
	var open_at := -half
	return (open_at - from_lowest) if from_lowest < 0.0 else (per + open_at - from_lowest)


## Seconds until the low window closes (0 when it is not open).
static func seconds_until_low_ends(p: Dictionary, now_ms: int) -> float:
	var half := low_half_s(p)
	var from_lowest := phase(p, now_ms) * _f(p, "period_s") - _f(p, "period_s") * 0.5
	if absf(from_lowest) > half:
		return 0.0
	return half - from_lowest
