class_name VisitorBubble
extends Node2D
## "You're just a visitor in this bubble world": on a world whose actor_look carries a `bubble`
## (Bobbledown), every player and companion walks about inside a soap bubble of their own. Pure
## presentation, a pair of child nodes on the actor (OtherworldLook.apply adds them):
##
##   * the BACK half, drawn behind the actor: a faint tint filling the bubble and the far side of its
##     film, seen through it;
##   * the FRONT half, drawn over the actor: the near rim and a window glint, which is what makes it
##     read as you being INSIDE it rather than standing in front of a disc.
##
## It's soft: it stretches a little along the way you're walking and, through a small spring, jiggles
## as you stop. When it first appears it POPS into being (a quick swell, an overshoot, a few wobbles
## settling, and a ring of droplets), so arriving in the world is a little "you've been bubbled" beat.
## Both halves run the same arithmetic on the same parent, so they stay in step without talking.

const STRETCH := 0.10        # how far it stretches along the walk at full speed (fraction of radius)
const FULL_SPEED := 90.0     # px/s that counts as walking flat out
const SPRING := 70.0         # the jiggle's stiffness...
const DAMP := 7.0            # ...and how quickly it settles
const POP_SWELL := 0.32      # seconds to swell from nothing to its overshoot
const POP_DROPS := 8

var front := false
var radius := 19.0
var center_y := -9.0
var tint := Color(1.0, 0.78, 0.92)
var pop_delay := 0.5         # wait a beat after the world appears, so the pop is seen

var _time := 0.0
var _age := -1.0             # < 0 until the pop starts
var _last := Vector2.INF
var _vel := Vector2.ZERO
var _dir := Vector2.RIGHT
var _stretch := 0.0          # current stretch (spring position) ...
var _stretch_v := 0.0        # ... and its velocity


## Give `actor` its bubble: `cfg` is the look's `bubble` block, `size` scales it (a companion's is
## smaller than its person's). Returns the back half.
static func attach(actor: CanvasItem, cfg: Dictionary, size := 1.0) -> VisitorBubble:
	var halves: Array = []
	for is_front in [false, true]:
		var b := VisitorBubble.new()
		b.name = "VisitorBubbleFront" if is_front else "VisitorBubble"
		b.front = is_front
		b.show_behind_parent = not is_front
		b.radius = float(cfg.get("radius", 19.0)) * size
		b.center_y = float(cfg.get("y", -9.0)) * size
		b.tint = WorldData.to_color(cfg.get("tint", [1.0, 0.78, 0.92]))
		b.pop_delay = float(cfg.get("pop_delay", 0.5))
		actor.add_child(b)
		halves.append(b)
	return halves[0]


func _process(delta: float) -> void:
	_time += delta
	if _age < 0.0:
		pop_delay -= delta
		if pop_delay <= 0.0:
			_age = 0.0
	else:
		_age += delta
	# how fast the actor is moving (smoothed), and the spring that turns it into a stretch and a jiggle
	var here := (get_parent() as Node2D).global_position if get_parent() is Node2D else global_position
	if _last != Vector2.INF and delta > 0.0:
		_vel = _vel.lerp((here - _last) / delta, 1.0 - exp(-10.0 * delta))
	_last = here
	var speed := _vel.length()
	if speed > 8.0:
		_dir = _vel / speed
	var want := clampf(speed / FULL_SPEED, 0.0, 1.0)
	_stretch_v += (SPRING * (want - _stretch) - DAMP * _stretch_v) * delta
	_stretch += _stretch_v * delta
	queue_redraw()


## How big it is right now: 0 before it pops, swelling to an overshoot, then settling with a few wobbles.
func _pop_scale() -> float:
	if _age < 0.0:
		return 0.0
	if _age < POP_SWELL:
		var t := _age / POP_SWELL
		return 1.18 * (1.0 - pow(1.0 - t, 3.0))
	var t2 := _age - POP_SWELL
	return 1.0 + 0.18 * exp(-t2 * 6.0) * cos(t2 * 17.0)


func _draw() -> void:
	var s := _pop_scale()
	if s <= 0.01:
		return
	var c := Vector2(0, center_y)
	# Stretch along the walk (and squeeze across it), with a gentle breath on top. Built as a matrix that
	# scales along _dir rather than a rotation, so the glint stays put at the upper left as you turn.
	var k := _stretch * STRETCH
	var breathe := 0.015 * sin(_time * 1.8)
	var along := 1.0 + k + breathe
	var across := 1.0 - k * 0.7 - breathe
	var d := _dir
	var p := Vector2(-d.y, d.x)
	var x_axis := (d * d.x * along + p * p.x * across) * s
	var y_axis := (d * d.y * along + p * p.y * across) * s
	draw_set_transform_matrix(Transform2D(x_axis, y_axis, c))
	if front:
		_draw_front()
	else:
		_draw_back()
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if front and _age >= 0.0 and _age < 0.7:
		_draw_pop_drops(c)


## The far side: a faint tint through the bubble, and the back of the film.
func _draw_back() -> void:
	var r := radius
	draw_circle(Vector2.ZERO, r, Color(tint.r, tint.g, tint.b, 0.12), true, -1.0, true)
	_draw_film(r, 0.32, 1.4)


## The near side: the brighter rim, a curved window glint at the upper left, a small one opposite.
func _draw_front() -> void:
	var r := radius
	_draw_film(r, 0.5, 1.2)
	draw_arc(Vector2.ZERO, r * 0.74, PI * 1.08, PI * 1.42, 12, Color(1, 1, 1, 0.75), maxf(1.2, r * 0.09), true)
	draw_circle(Vector2(-r * 0.36, -r * 0.62), r * 0.06, Color(1, 1, 1, 0.8), true, -1.0, true)
	draw_circle(Vector2(r * 0.52, r * 0.5), r * 0.05, Color(1, 1, 1, 0.55), true, -1.0, true)


## The thin film's colours, sliding slowly round the rim: mostly the bubble's own tint, with a hint of
## rainbow passing through it.
func _draw_film(r: float, alpha: float, width: float) -> void:
	var segs := 28
	for i in segs:
		var a0 := float(i) / float(segs) * TAU
		var hue := fposmod(float(i) / float(segs) + _time * 0.08, 1.0)
		var film := tint.lerp(Color.from_hsv(hue, 0.45, 1.0), 0.35)
		film.a = alpha
		draw_arc(Vector2.ZERO, r, a0, a0 + TAU / float(segs) + 0.01, 3, film, width, true)


## The arrival pop: a ring flung out from the bubble and a few droplets, gone in a moment.
func _draw_pop_drops(c: Vector2) -> void:
	var t := _age / 0.7
	var fade := 1.0 - t
	draw_arc(c, radius * (1.0 + t * 0.9), 0.0, TAU, 32, Color(1, 1, 1, 0.55 * fade), 1.4, true)
	for i in POP_DROPS:
		var a := float(i) / float(POP_DROPS) * TAU + 0.3
		var q := c + Vector2(cos(a), sin(a)) * radius * (1.05 + t * 1.3)
		draw_circle(q, 1.4 * fade + 0.4, Color(tint.r, tint.g, tint.b, 0.9 * fade), true, -1.0, true)
