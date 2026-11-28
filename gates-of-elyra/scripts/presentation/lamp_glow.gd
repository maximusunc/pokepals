class_name LampGlow
extends Node2D
## The lighthouse lamp's halo at EBBMERE. A node in the y-sorted Scenery standing just in front of the tower
## (so it draws over the lamp room), at the lamp's height. It burns brighter the lower the tide is, so a glance
## at the lighthouse says "the water is nearly out". Purely presentation; the TideDirector hands it
## `set_low(0..1)` (1 = lowest water).

var _low := 0.0
var _time := 0.0
var _radius := 64.0
var lamp_offset := Vector2(0, -121)   # where the lamp sits, from the node (which stands at the tower base, so it sorts in front)


func set_low(k: float) -> void:
	_low = clampf(k, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var breathe := 0.9 + 0.1 * sin(_time * 1.3)
	var a := (0.16 + 0.34 * _low) * breathe
	SoftGlow.draw(self, lamp_offset, _radius * (0.8 + 0.5 * _low), Color(1.0, 0.86, 0.46, a))
	SoftGlow.draw(self, lamp_offset, 18.0, Color(1.0, 0.96, 0.78, 0.35 + 0.35 * _low))
