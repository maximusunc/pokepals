class_name FetchFx
extends Node2D
## The two small bits of showmanship around Thimblewick's fetch (the logic is FetchTrip, the conductor
## FetchDirector):
##   * mode "carry": a child of the COMPANION, drawing what it is carrying, held up over its head and bobbing as it
##     trots (smaller than it will be on the ground, since a companion carrying a thimble that size would be
##     comic, and this is meant to be sweet);
##   * mode "rustle": a node standing BEHIND the fence at a gap, in the y-sorted scenery layer so the pickets hide
##     part of it, which shivers the grass and sends up a few specks while the companion is away. It is the whole
##     "somebody is busy back there" cue: you cannot see the companion, but you can see where it is.
## Pure presentation, no state worth saving; `set_active` / `burst` / `set_item` are the director's levers.

var mode := "rustle"
var item := ""                 # carry: what is being carried ("" = nothing, draws nothing)
var lift := 26.0               # carry: px above the companion's feet
var _active := false           # rustle: shivering now
var _gain := 0.0               # rustle: eased 0..1 intensity
var _burst := 0.0              # rustle: a quick flare (a find!), decays
var _t := 0.0
var _seed := 0.0


func _ready() -> void:
	_seed = fposmod(position.x * 0.013 + position.y * 0.021, TAU)
	set_process(true)


func set_active(on: bool) -> void:
	_active = on


## A quick bright flare at the rustle: it found something (or it is hurrying back).
func burst() -> void:
	_burst = 1.0


func is_idle() -> bool:
	return not _active and _gain < 0.01 and _burst < 0.01 and item == ""


func _process(delta: float) -> void:
	_t += delta
	_gain = move_toward(_gain, 1.0 if _active else 0.0, delta * 3.0)
	_burst = maxf(0.0, _burst - delta * 1.6)
	if mode == "carry":
		if item != "":
			queue_redraw()
		return
	if _gain > 0.01 or _burst > 0.01:
		queue_redraw()


func _draw() -> void:
	if mode == "carry":
		if item != "":
			var bob := sin(_t * 9.0) * 1.2
			FindDraw.draw(self, item, Vector2(0.0, -lift + bob), 0.62, _t)
		return
	if _gain < 0.01 and _burst < 0.01:
		return
	var g := maxf(_gain, _burst)
	# blades of long grass shivering hard, in two tones (thick enough to read from a screen away)
	for i in 9:
		var x := -18.0 + float(i) * 4.4
		var shake := sin(_t * 17.0 + _seed + float(i) * 1.7) * 4.0 * g
		var h := 24.0 + float((i * 7) % 5) * 4.0
		var col := Color(0.34, 0.62, 0.22) if i % 2 == 0 else Color(0.20, 0.46, 0.18)
		draw_line(Vector2(x, 2.0), Vector2(x + shake, 2.0 - h), col, 3.0)
		draw_line(Vector2(x + 1.8, 2.0), Vector2(x + 1.8 + shake * 0.7, 2.0 - h * 0.7), col.lightened(0.2), 1.8)
	# specks and a petal or two kicked up and drifting
	for j in 6:
		var u := fposmod(_t * 0.9 + float(j) * 0.37 + _seed, 1.0)
		var px := -12.0 + float(j) * 4.8 + sin(_t * 3.0 + float(j)) * 3.0
		var py := 2.0 - u * 30.0
		var a := (1.0 - u) * 0.8 * g
		draw_circle(Vector2(px, py), 1.2 if j % 2 == 0 else 1.7, Color(0.90, 0.80, 0.52, a))
	if _burst > 0.01:
		var r := 8.0 + 16.0 * (1.0 - _burst)
		draw_arc(Vector2(0.0, -10.0), r, 0.0, TAU, 20, Color(1.0, 0.95, 0.7, 0.8 * _burst), 1.5, true)
		for k in 4:
			var a2 := float(k) / 4.0 * TAU + 0.6
			draw_circle(Vector2(0.0, -10.0) + Vector2(cos(a2), sin(a2)) * r * 0.8, 1.4, Color(1, 1, 0.8, _burst))
