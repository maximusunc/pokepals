class_name FishingRing
extends RefCounted
## The TIMING RING that lands a fish (usable items, U-4 in docs/usable-items-design.md): when a fish bites,
## a ring closes in on the bobber, and you tap as it meets the small target circle. Pure logic, no drawing:
## FishingDirector ticks it and asks it what happened, RodView draws it.
##
## One PASS is the ring closing from wide open to nothing. It meets the target `TARGET` of the way through a
## pass, and the tap counts within `window` (a share of a pass) around that moment. Rarer catches come with a
## narrower window and a quicker ring (the server says how hard, Server.Fishing). The ring runs `PASSES`
## times; a tap anywhere outside the window, or no tap at all, lets the fish go. That is never a loss, just
## "next time": nothing you have is taken away.

const PASS_SECONDS := 1.4   # one pass at speed 1.0
const TARGET := 0.7         # where in a pass the closing ring meets the target circle
const PASSES := 2

var window := 0.2           # how wide the tap window is, as a share of one pass
var speed := 1.0            # passes per PASS_SECONDS

var _t := 0.0
var _result := ""           # "" while running, then "landed", "missed" or "timeout"


func _init(window_share: float = 0.2, ring_speed: float = 1.0) -> void:
	window = clampf(window_share, 0.02, 0.9)
	speed = maxf(ring_speed, 0.1)


## How long one pass takes, in seconds.
func pass_seconds() -> float:
	return PASS_SECONDS / speed


## Advance the ring. Once it has run all its passes untapped, it times out.
func update(delta: float) -> void:
	if _result != "":
		return
	_t += maxf(delta, 0.0)
	if _t >= pass_seconds() * PASSES:
		_result = "timeout"


## How far through the current pass the ring is, 0 (wide open) to 1 (closed to nothing).
func progress() -> float:
	var ps := pass_seconds()
	return fposmod(_t, ps) / ps


## The ring's size as a share of its widest, 1 (wide open) down to 0. It equals target_scale() at the
## moment it meets the target circle.
func ring_scale() -> float:
	return 1.0 - progress()


## The target circle's size as a share of the ring's widest.
static func target_scale() -> float:
	return 1.0 - TARGET


## Whether a tap right now would land the fish.
func in_window() -> bool:
	return absf(progress() - TARGET) <= window * 0.5


## How close the ring is to the target, 0 (far) to 1 (right on it): for the ring to warm as it nears.
func closeness() -> float:
	var off := absf(progress() - TARGET)
	return clampf(1.0 - off / maxf(window * 2.0, 0.001), 0.0, 1.0)


## The player tapped. The first tap decides: in the window it lands, outside it the fish slips away.
## Returns the result ("landed" / "missed"), or the existing result if the ring has already finished.
func tap() -> String:
	if _result == "":
		_result = "landed" if in_window() else "missed"
	return _result


## "" while the ring is still running, else "landed", "missed" or "timeout".
func result() -> String:
	return _result


func is_over() -> bool:
	return _result != ""
