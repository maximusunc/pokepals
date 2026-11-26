class_name CoinArc
extends Node2D
## LINGERLONG: one coin tossed into the wishing fountain, from the wisher's hand to the basin. A tiny node that
## flies its arc (turning as it goes), tells the fountain where it landed, and frees itself. At most MAX are in
## the air at once (a crowd tossing coins costs nothing past that: the rest just splash and swell).

const MAX := 12
const TIME := 0.75
const HEIGHT := 46.0

static var _live := 0

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _t := 0.0
var _land: Callable
var _counted := false


## Room for one more coin in the air?
static func room() -> bool:
	return _live < MAX


## Fly from `from` (a hand, in world space) to `to` (the basin's water); `land` is called once, on arrival.
func launch(from: Vector2, to: Vector2, land: Callable) -> void:
	_from = from
	_to = to
	_land = land
	position = from
	z_index = 2   # in the air, over everyone
	_live += 1
	_counted = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _counted:
		_counted = false
		_live -= 1


func _process(delta: float) -> void:
	_t += delta / TIME
	if _t >= 1.0:
		if _land.is_valid():
			_land.call(_to)
		set_process(false)
		queue_free()
		return
	var p := _from.lerp(_to, _t)
	p.y -= sin(_t * PI) * HEIGHT
	position = p
	queue_redraw()


func _draw() -> void:
	ItemIcon.draw_coin(self, Vector2.ZERO, 0.42, 1.0, cos(_t * TAU * 2.0))
