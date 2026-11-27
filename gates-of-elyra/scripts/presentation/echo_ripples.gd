class_name EchoRipples
extends Node2D
## The canyon's ANSWERS, drawn (Hollowsong): what comes back after a howl, as soft ripples on the air. The
## decisions (which wall answers, from where, when) are EchoField's; this only paints them, over the world
## and under the UI. Cosmetic and local: nothing here touches game logic.
##
## For each howl:
##   * the CALL: a thin ring leaving the voice, and a few small arcs rising off the howler;
##   * each WALL's answer: a pair of warm gold arcs. The returning wavefront is a circle centred on the
##     voice's mirror image behind the wall, cut to the stretch the wall can reach, so it starts as the
##     wall's own outline lit up and spreads back toward you, arriving when it should;
##   * the WRONG answer: from where there is no wall, late, and unmistakably another kind of thing: violet
##     where the walls are gold, thick where they are thin, and a dashed second ring behind the solid one,
##     a soft bloom where it is born, and, once it reaches you, a long dotted BEARING line toward where it
##     seemed to come from that lingers, so a second howl from somewhere else can cross it.
## A friend's howl draws the same, a little fainter. Only what is near the screen is drawn: the cost follows
## the view, not the number of howls.

const GOLD := Color(1.0, 0.84, 0.50)
const VIOLET := Color(0.62, 0.44, 1.0)
const INK := Color(0.14, 0.05, 0.30)       # the dark edge that keeps the violet readable on warm stone
const CALL_RANGE := 260.0
const FADE := 0.55   # seconds a wavefront lingers after it has reached you

var speed := 700.0
var streak_life := 16.0
var streak_length := 900.0

var _howls: Array = []   # [{ t, source, listener, echoes, wrong, friend, end }]


func configure(cfg: Dictionary) -> void:
	speed = float(cfg.get("speed", 700.0))
	streak_life = float(cfg.get("streak_life", 16.0))
	streak_length = float(cfg.get("streak_length", 900.0))
	z_index = 20


## Start drawing one howl's answer (an EchoGuide result: { echoes, wrong }).
func add_howl(source: Vector2, listener: Vector2, answer: Dictionary, friend: bool) -> void:
	var end := 1.5
	for e in answer.get("echoes", []):
		end = maxf(end, float(e["arrive"]) + 1.0)
	var wrong: Dictionary = answer.get("wrong", {})
	if not wrong.is_empty():
		end = maxf(end, float(wrong["arrive"]) + streak_life + 1.0)
	_howls.append({ "t": 0.0, "source": source, "listener": listener, "echoes": answer.get("echoes", []), "wrong": wrong,
		"friend": friend, "end": end })
	set_process(true)


func active_count() -> int:
	return _howls.size()


## Seconds into the newest howl (for tests), or -1 when none is active.
func newest_age() -> float:
	return float(_howls.back()["t"]) if not _howls.is_empty() else -1.0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	var keep: Array = []
	for h in _howls:
		h["t"] = float(h["t"]) + delta
		if float(h["t"]) < float(h["end"]):
			keep.append(h)
	_howls = keep
	if _howls.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _howls.is_empty():
		return
	var vis := ViewCull.visible_world_rect(self, 60.0)
	var cull := vis.has_area()
	for h in _howls:
		_draw_howl(h, vis, cull)


func _draw_howl(h: Dictionary, vis: Rect2, cull: bool) -> void:
	var t: float = h["t"]
	var k := 0.7 if bool(h["friend"]) else 1.0
	var src: Vector2 = h["source"]
	# the call: a thin ring leaving the voice, and arcs rising off the howler
	var cr := speed * t
	if cr < CALL_RANGE:
		var a := 0.6 * (1.0 - cr / CALL_RANGE) * k
		_arc_ring(vis, cull, src, cr, 0.0, TAU, Color(GOLD.r, GOLD.g, GOLD.b, a), 2.0)
	if t < 0.9:
		for i in 3:
			var f := clampf((t - float(i) * 0.12) / 0.7, 0.0, 1.0)
			if f > 0.0 and f < 1.0:
				_arc_ring(vis, cull, src + Vector2(0.0, -20.0 - 10.0 * f), 7.0 + float(i) * 6.0, -PI * 0.85, -PI * 0.15,
					Color(GOLD.r, GOLD.g, GOLD.b, 1.0 * (1.0 - f) * k), 2.5)
	# each wall's answer
	for e in h["echoes"]:
		var t_hit := float(e["t_hit"])
		var arrive := float(e["arrive"])
		if t < t_hit or t > arrive + FADE:
			continue
		var r := speed * t
		var image: Vector2 = e["image"]
		var a0 := ((e["a"] as Vector2) - image).angle()
		var a1 := ((e["b"] as Vector2) - image).angle()
		var span := angle_difference(a0, a1)
		var fade_in := clampf((t - t_hit) / 0.18, 0.0, 1.0)
		var fade_out := 1.0 - smoothstep(arrive, arrive + FADE, t)
		var al := float(e["strength"]) * fade_in * fade_out * k
		_arc_ring(vis, cull, image, r, a0, a0 + span, Color(GOLD.r, GOLD.g, GOLD.b, 0.22 * al), 9.0)    # a soft body
		_arc_ring(vis, cull, image, r, a0, a0 + span, Color(GOLD.r, GOLD.g, GOLD.b, 0.95 * al), 2.6)
		_arc_ring(vis, cull, image, r - 12.0, a0, a0 + span, Color(GOLD.r, GOLD.g, GOLD.b, 0.55 * al), 1.6)
		_arc_ring(vis, cull, image, r - 24.0, a0, a0 + span, Color(GOLD.r, GOLD.g, GOLD.b, 0.25 * al), 1.2)
	# the wrong answer
	var wrong: Dictionary = h["wrong"]
	if not wrong.is_empty():
		_draw_wrong(h, wrong, t, vis, cull, k)


func _draw_wrong(h: Dictionary, w: Dictionary, t: float, vis: Rect2, cull: bool, k: float) -> void:
	var origin: Vector2 = w["origin"]
	var listener: Vector2 = h["listener"]
	var t_birth := float(w["birth"]) if w.has("birth") else float(w["t_birth"])
	var arrive := float(w["arrive"])
	var s := float(w["strength"]) * k
	var age := t - t_birth
	if age >= 0.0 and age < 1.0 and (not cull or vis.has_point(origin)):
		SoftGlow.draw(self, origin, 60.0, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.5 * s * (1.0 - age)), 0.8)
	if age >= 0.0 and t < arrive + FADE:
		var r := speed * age
		var face := (listener - origin).angle()
		var half := 0.62
		var fade_in := clampf(age / 0.25, 0.0, 1.0)
		var fade_out := 1.0 - smoothstep(arrive, arrive + FADE, t)
		var al := s * fade_in * fade_out
		# thick, with a dark edge, and a dashed second ring behind it: nothing like a wall's thin gold arc
		_arc_ring(vis, cull, origin, r, face - half, face + half, Color(INK.r, INK.g, INK.b, 0.55 * al), 9.0)
		_arc_ring(vis, cull, origin, r, face - half, face + half, Color(VIOLET.r, VIOLET.g, VIOLET.b, 1.0 * al), 5.0)
		_arc_ring(vis, cull, origin, r - 34.0, face - half, face + half, Color(INK.r, INK.g, INK.b, 0.45 * al), 6.0, true)
		_arc_ring(vis, cull, origin, r - 34.0, face - half, face + half, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.85 * al), 3.0, true)
	if t >= arrive and t < arrive + streak_life:
		_draw_bearing(listener, origin, (t - arrive) / streak_life, s, vis, cull)


## The bearing line: dots from where the answer reached you toward where it seemed to come from, fading over
## its life; a small chevron at its near end points the way.
func _draw_bearing(from: Vector2, toward: Vector2, f: float, s: float, vis: Rect2, cull: bool) -> void:
	var dir := (toward - from).normalized()
	var length := minf(from.distance_to(toward), streak_length)
	var a := minf(1.0, s * 1.25) * (1.0 - f * f)
	var step := 26.0
	var n := int(length / step)
	for i in range(1, n + 1):
		var p := from + dir * (float(i) * step)
		if cull and not vis.has_point(p):
			continue
		var fall := 1.0 - 0.55 * float(i) / float(maxi(n, 1))
		draw_circle(p, 4.5, Color(INK.r, INK.g, INK.b, 0.5 * a * fall))
		draw_circle(p, 3.0, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.95 * a * fall))
	if cull and not vis.has_point(from + dir * 40.0):
		return
	var c := from + dir * 40.0
	var side := dir.orthogonal()
	var chev := PackedVector2Array([c - dir * 12.0 + side * 11.0, c, c - dir * 12.0 - side * 11.0])
	draw_polyline(chev, Color(INK.r, INK.g, INK.b, 0.6 * a), 6.0, true)
	draw_polyline(chev, Color(VIOLET.r, VIOLET.g, VIOLET.b, 1.0 * a), 3.5, true)


## An arc of a circle (centre, radius, from angle to angle), only when the circle can cross the view, and
## only the segments that are in it. `dashed` draws every other segment.
func _arc_ring(vis: Rect2, cull: bool, c: Vector2, r: float, a0: float, a1: float, col: Color, width: float, dashed: bool = false) -> void:
	if r <= 1.0 or col.a <= 0.01:
		return
	if cull:
		var near := Vector2(clampf(c.x, vis.position.x, vis.end.x), clampf(c.y, vis.position.y, vis.end.y)).distance_to(c)
		var far := maxf(maxf(c.distance_to(vis.position), c.distance_to(vis.end)),
			maxf(c.distance_to(Vector2(vis.position.x, vis.end.y)), c.distance_to(Vector2(vis.end.x, vis.position.y))))
		if r < near - 8.0 or r > far + 8.0:
			return
	var span := a1 - a0
	var n := clampi(int(absf(span) * r / 22.0), 6, 48)
	var prev := c + Vector2(cos(a0), sin(a0)) * r
	for i in range(1, n + 1):
		var a := a0 + span * float(i) / float(n)
		var p := c + Vector2(cos(a), sin(a)) * r
		if (not dashed or i % 2 == 1) and (not cull or vis.has_point(p) or vis.has_point(prev)):
			draw_line(prev, p, col, width, true)
		prev = p
