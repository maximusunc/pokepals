class_name DreamBubble
extends Node2D
## What a dozing companion shows above its head (Dozewood): slow "z"s drifting up while it sleeps, and,
## once it dreams, a thought bubble holding a small picture of a place. Pure presentation: the
## DozeDirector tells it how asleep (`set_sleep`, 0..1) and how far into the dream (`set_dream`, 0..1) the
## companion is, and hands it the picture; every value eases, so the bubble swells and the z's thin out
## rather than popping.
##
## It is a child of the companion, drawn above everything (absolute z), in the companion's local space:
## three small circles trail up from the head to the bubble, which bobs very slowly. Inside the bubble the
## picture sits under a soft sheen, with a few pale motes turning round the rim. Dream pictures are baked
## little vignettes (tools/gen_dozewood.py), already hazed and round-edged, so they read as remembered.

const BUBBLE_R := 27.0
const BUBBLE_AT := Vector2(14.0, -78.0)
const TRAIL := [Vector2(3.0, -30.0), Vector2(7.0, -41.0), Vector2(10.0, -53.0)]
const TRAIL_R := [2.0, 3.0, 4.4]

var _sleep_target := 0.0
var _dream_target := 0.0
var _sleep := 0.0
var _dream := 0.0
var _picture: Texture2D = null
var _time := 0.0
var _wisps: Array = []     # [{ age, life, x }] one-off z's (a yawn)


func _ready() -> void:
	z_as_relative = false
	z_index = 40
	set_process(true)


func set_picture(tex: Texture2D) -> void:
	_picture = tex


func set_sleep(v: float) -> void:
	_sleep_target = clampf(v, 0.0, 1.0)


func set_dream(v: float) -> void:
	_dream_target = clampf(v, 0.0, 1.0)


## A single z drifting up (an ambient yawn, or the yawn before a nap).
func puff() -> void:
	_wisps.append({ "age": 0.0, "life": 3.2, "x": 6.0 })


func is_showing_dream() -> bool:
	return _dream > 0.05


func _process(delta: float) -> void:
	_time += delta
	_sleep += (_sleep_target - _sleep) * (1.0 - exp(-1.6 * delta))
	# The bubble swells slowly in, and pops down a little quicker than it grew.
	var rate := 1.3 if _dream_target > _dream else 3.2
	_dream += (_dream_target - _dream) * (1.0 - exp(-rate * delta))
	for w in _wisps:
		w["age"] = float(w["age"]) + delta
	_wisps = _wisps.filter(func(w: Dictionary) -> bool: return float(w["age"]) < float(w["life"]))
	visible = _sleep > 0.01 or _dream > 0.01 or not _wisps.is_empty()
	if visible:
		queue_redraw()


func _draw() -> void:
	# Drifting z's: three in a stream, each a little bigger as it rises, while it sleeps.
	if _sleep > 0.02:
		for k in 3:
			var t := fposmod(_time * 0.22 + float(k) / 3.0, 1.0)
			var a := sin(t * PI) * _sleep * 0.9
			_draw_z(Vector2(8.0 + t * 12.0 + sin(_time * 0.8 + k) * 2.0, -22.0 - t * 30.0), 2.4 + 2.6 * t, a)
	for w in _wisps:
		var t := float(w["age"]) / float(w["life"])
		_draw_z(Vector2(float(w["x"]) + t * 8.0, -20.0 - t * 34.0), 2.6 + 2.2 * t, sin(t * PI) * 0.85)
	if _dream < 0.02:
		return
	var d := smoothstep(0.0, 1.0, _dream)
	var bob := Vector2(0.0, sin(_time * 0.9) * 1.6)
	# the little trail of thought-circles, appearing one after another
	for i in TRAIL.size():
		var f := clampf(d * 3.0 - float(i) * 0.7, 0.0, 1.0)
		if f > 0.0:
			_disc(TRAIL[i] + bob * 0.4, float(TRAIL_R[i]) * f, Color(1, 1, 1, 0.5 * f))
	var c := BUBBLE_AT + bob
	var r := BUBBLE_R * d * (1.0 + 0.03 * sin(_time * 1.7))
	SoftGlow.draw(self, c, r * 1.7, Color(0.78, 0.82, 1.0, 0.22 * d), 1.0)
	draw_circle(c, r, Color(0.96, 0.95, 1.0, 0.62 * d), true, -1.0, true)
	if _picture != null:
		var sz := _picture.get_size() * (r / BUBBLE_R)
		draw_texture_rect(_picture, Rect2(c - sz * 0.5, sz), false, Color(1, 1, 1, 0.92 * d))
	# a pale sheen on the upper left, and the rim
	draw_arc(c, r - 1.0, PI * 1.05, PI * 1.55, 10, Color(1, 1, 1, 0.85 * d), 1.6, true)
	draw_arc(c, r, 0.0, TAU, 40, Color(0.85, 0.88, 1.0, 0.8 * d), 1.2, true)
	# motes turning slowly round the rim
	for k in 4:
		var ang := _time * 0.35 + float(k) * TAU / 4.0
		var mp := c + Vector2(cos(ang), sin(ang)) * (r + 4.0)
		draw_circle(mp, 1.1, Color(1, 1, 0.9, 0.75 * d), true, -1.0, true)


func _disc(p: Vector2, r: float, col: Color) -> void:
	draw_circle(p, r, col, true, -1.0, true)
	draw_arc(p, r, 0.0, TAU, 14, Color(0.85, 0.88, 1.0, col.a * 0.9), 1.0, true)


## A "z": a top bar, a diagonal, a bottom bar, in the same flat language as the other emotes.
func _draw_z(p: Vector2, s: float, alpha: float) -> void:
	if alpha <= 0.01:
		return
	var col := Color(0.92, 0.94, 1.0, alpha)
	var shade := Color(0.30, 0.34, 0.60, alpha * 0.8)
	var shade_pts := PackedVector2Array([p + Vector2(0, 0) + Vector2(-s + 1, -s + 1), p + Vector2(s + 1, -s + 1), p + Vector2(-s + 1, s + 1), p + Vector2(s + 1, s + 1)])
	var pts := PackedVector2Array([p + Vector2(-s, -s), p + Vector2(s, -s), p + Vector2(-s, s), p + Vector2(s, s)])
	draw_polyline(shade_pts, shade, 2.2, true)
	draw_polyline(pts, col, 1.6, true)
