class_name TankView
extends Node2D
## The fish TANK at home, drawn (usable items, step 3; docs/usable-items-design.md): a small glass tank on a
## wooden stand by the journal, clear water over pale sand with a sprig of weed, the rare fish you've put in
## swimming slowly back and forth behind the glass, and a few bubbles rising. A y-sorted node in the Scenery
## (so you can stand in front of it or behind it), placed at the tank prop's spot. TankDirector tells it which
## fish swim (set_fish); this only draws.

const W := 34.0            # the glass box
const H := 24.0
const STAND_H := 8.0
const WATER := Color(0.46, 0.72, 0.82, 0.55)
const GLASS := Color(0.86, 0.95, 1.0, 0.75)

var _fish: Array = []      # [{ key, color: Color, phase, speed, depth }]
var _t := 0.0


## The fish in the tank: [{ key, color: [r, g, b] }] in the order they went in.
func set_fish(fish: Array) -> void:
	_fish.clear()
	for i in fish.size():
		var f: Dictionary = fish[i] if fish[i] is Dictionary else {}
		_fish.append({
			"key": String(f.get("key", "")),
			"color": FishingDirector.color_of(f.get("color")),
			"phase": float(i) * 2.1 + 0.4,
			"speed": 0.32 + 0.09 * float(i),
			"depth": 0.3 + 0.22 * float(i),   # how far down the water each swims (0 top .. 1 bottom)
		})
	queue_redraw()


func fish_count() -> int:
	return _fish.size()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var top := Vector2(-W * 0.5, -STAND_H - H)
	# shadow and stand
	draw_circle(Vector2(0, 2), W * 0.5, Color(0.08, 0.06, 0.04, 0.22))
	draw_rect(Rect2(Vector2(-W * 0.5 - 2, -STAND_H), Vector2(W + 4, STAND_H)), Color(0.46, 0.32, 0.20))
	draw_rect(Rect2(Vector2(-W * 0.5 - 2, -STAND_H), Vector2(W + 4, 2)), Color(0.58, 0.42, 0.28))
	# water, sand and a sprig of weed
	draw_rect(Rect2(top + Vector2(0, 3), Vector2(W, H - 3)), WATER)
	draw_rect(Rect2(top + Vector2(0, H - 4), Vector2(W, 4)), Color(0.90, 0.82, 0.62, 0.9))
	var sway := sin(_t * 1.3) * 1.5
	for k in 3:
		var base := top + Vector2(6 + k * 3, H - 4)
		draw_line(base, base + Vector2(sway * 0.6 + k - 1, -9 - k * 2), Color(0.36, 0.62, 0.36), 1.4, true)
	# the fish, swimming back and forth (they turn at each end)
	for f in _fish:
		var u: float = sin(_t * float(f["speed"]) + float(f["phase"]))
		var x := lerpf(-W * 0.5 + 7.0, W * 0.5 - 7.0, (u + 1.0) * 0.5)
		var y := top.y + 6.0 + float(f["depth"]) * (H - 13.0) + sin(_t * 1.7 + float(f["phase"])) * 0.8
		var heading := cos(_t * float(f["speed"]) + float(f["phase"]))
		draw_set_transform(Vector2(x, y), 0.0, Vector2(1.0 if heading >= 0.0 else -1.0, 1.0))
		ItemIcon.draw_fish(self, Vector2.ZERO, 0.5, f["color"], false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# bubbles rising
	for b in 3:
		var bu := fposmod(_t * 0.35 + float(b) * 0.33, 1.0)
		var bp := top + Vector2(W - 7.0 - float(b) * 3.0, H - 5.0 - bu * (H - 8.0)) + Vector2(sin(_t * 3.0 + b) * 0.8, 0)
		draw_arc(bp, 0.9 + bu * 0.5, 0.0, TAU, 8, Color(1, 1, 1, 0.7 * (1.0 - bu)), 0.7, true)
	# the glass: rim, edges and a glint
	draw_rect(Rect2(top, Vector2(W, H)), GLASS, false, 1.2)
	draw_line(top + Vector2(0, 3), top + Vector2(W, 3), Color(1, 1, 1, 0.45), 0.8)
	draw_line(top + Vector2(4, 6), top + Vector2(4, H - 7), Color(1, 1, 1, 0.35), 1.0)
