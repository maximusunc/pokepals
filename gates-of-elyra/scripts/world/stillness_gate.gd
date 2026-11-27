class_name StillnessGate
extends RefCounted
## Nocthollow's secret asks you to be still (W-2): stay quietly by the Mere with your companion settled
## beside you, and after a while the lily-lights drift into a ring and a mere-pearl rises. This is that
## "a while", as pure logic (state in, state out): progress fills while you're still and in the place,
## and moving only PAUSES it, letting it drift back a little rather than wiping it, so a fidget isn't
## punished. Node-free, so it's unit-tested and could run anywhere.

## Seconds of stillness needed.
var seconds := 20.0
## While you're moving in the place (or have wandered off), progress drifts back this many seconds per
## second: a little, never all at once.
var drift_back := 0.5

var _progress := 0.0
var _done := false


func _init(need_seconds := 20.0, drift_back_rate := 0.5) -> void:
	seconds = maxf(0.1, need_seconds)
	drift_back = maxf(0.0, drift_back_rate)


## Advance by `delta` seconds. `in_place`: you're where it counts. `still`: you're not moving and your
## companion is settled beside you. Returns true on the frame it completes (once).
func update(delta: float, in_place: bool, still: bool) -> bool:
	if _done:
		return false
	if in_place and still:
		_progress += delta
	else:
		_progress = maxf(0.0, _progress - delta * drift_back)
	if _progress >= seconds:
		_progress = seconds
		_done = true
		return true
	return false


## How far along it is, 0..1 (drives how gathered and bright the lights are).
func fraction() -> float:
	return _progress / seconds


func is_done() -> bool:
	return _done
