class_name RodView
extends Node2D
## The fishing rod in a player's hand, drawn on their avatar (a child node of the PlayerView, so it moves
## with them): the rod itself, and while fishing the cast flying out, the line, the bobber bobbing on the
## water, the bite (it dips, ripples, and a "!" over your head), and a catch popping up out of the water.
## For YOUR avatar it also draws the timing ring round the bobber (FishingRing).
##
## Used for friends too (U-13): PresenceDirector feeds their relayed activity in through apply_remote, so a
## friend fishing beside you is seen casting, waiting and landing their catch. Pure presentation; what
## happens is decided elsewhere (FishingDirector for you, the friend's own game for them).

const CAST_SECONDS := 0.45
const POP_SECONDS := 1.6
const RING_RADIUS := 40.0
const BOBBER_RED := Color(0.86, 0.26, 0.22)
const BOBBER_WHITE := Color(0.97, 0.95, 0.90)
const LINE := Color(0.95, 0.95, 0.92, 0.75)

var _held := false
var _phase := ""            # "", "cast", "wait", "bite", "caught", "escaped"
var _bobber := Vector2.ZERO # in WORLD space (the water doesn't move with you)
var _cast_t := 1.0          # 0..1 through the cast's flight
var _ring: FishingRing = null
var _pop_t := -1.0          # seconds into a catch popping up, or -1
var _pop_color := Color.WHITE
var _pop_key := ""
var _pop_kind := ""
var _pop_from := Vector2.ZERO
var _remote_n := -1         # the last catch number a friend's identity showed (so each pops once)
var _t := 0.0


func _ready() -> void:
	z_index = 1


## Whether the rod is in hand at all.
func set_held(on: bool) -> void:
	if on != _held:
		_held = on
		if not on:
			clear_fishing()
		queue_redraw()


func is_held() -> bool:
	return _held


## Fishing at `bobber` (world space) in `phase`. Going from not fishing to fishing plays the cast.
func set_fishing(phase: String, bobber: Vector2) -> void:
	if _phase in ["", "escaped", "caught"] and phase in ["cast", "wait", "bite"]:
		_cast_t = 0.0
	_phase = phase
	_bobber = bobber
	queue_redraw()


## Reel the line in (nothing on the water any more).
func clear_fishing() -> void:
	_phase = ""
	_ring = null
	queue_redraw()


## The timing ring to draw round the bobber (yours only), or null.
func set_ring(ring: FishingRing) -> void:
	_ring = ring


## A catch comes up out of the water and rises over your head. `key` / `kind` say what it is (the server's
## item key and category: a fish, a rare fish, an old boot).
func show_catch(key: String, kind: String, color: Color) -> void:
	_pop_t = 0.0
	_pop_color = color
	_pop_key = key
	_pop_kind = kind
	_pop_from = _bobber
	_phase = "caught"
	_ring = null


## A friend's relayed activity (their identity's `held` + `fishing`): mirror it.
func apply_remote(held: String, fishing: Variant) -> void:
	set_held(held == "rod")
	if not (fishing is Dictionary) or not _held:
		clear_fishing()
		return
	var f: Dictionary = fishing
	var b: Variant = f.get("b")
	var bob := Vector2(float(b[0]), float(b[1])) if b is Array and (b as Array).size() == 2 else _bobber
	var ph := String(f.get("ph", ""))
	var n := int(f.get("n", 0))
	if ph == "caught":
		_bobber = bob
		if n != _remote_n and _remote_n >= 0:
			var c: Variant = f.get("c")
			var col := Color(float(c[0]), float(c[1]), float(c[2])) if c is Array and (c as Array).size() == 3 else Color(0.8, 0.84, 0.88)
			show_catch(String(f.get("k", "")), String(f.get("r", "fish")), col)
		_remote_n = n
	elif ph in ["cast", "wait", "bite"]:
		if _remote_n < 0:
			_remote_n = n
		set_fishing(ph, bob)
	else:
		if _remote_n < 0:
			_remote_n = n
		clear_fishing()


func _process(delta: float) -> void:
	_t += delta
	var busy := false
	if _cast_t < 1.0:
		_cast_t = minf(_cast_t + delta / CAST_SECONDS, 1.0)
		busy = true
	if _pop_t >= 0.0:
		_pop_t += delta
		if _pop_t >= POP_SECONDS:
			_pop_t = -1.0
			if _phase == "caught":
				_phase = ""
		busy = true
	if busy or _phase in ["cast", "wait", "bite"]:
		queue_redraw()
	# Hold the rod behind you while you face away.
	var parent := get_parent()
	if parent is PlayerView:
		show_behind_parent = (parent as PlayerView).facing().y < -0.5


func _facing() -> Vector2:
	var parent := get_parent()
	if parent is PlayerView:
		return (parent as PlayerView).facing()
	return Vector2.DOWN


func _draw() -> void:
	if _held:
		_draw_rod_and_line()
	if _pop_t >= 0.0:
		_draw_pop()


func _draw_rod_and_line() -> void:
	var f := _facing()
	var side := 1.0
	if absf(f.x) > 0.35:
		side = signf(f.x)
	var hand := Vector2(5.0 * side, -9.0)
	if f.y < -0.5:
		hand = Vector2(-6.0, -11.0)
	var fishing := _phase in ["cast", "wait", "bite"]
	var bob_local := to_local(_bobber)
	var tip: Vector2
	if fishing:
		var dir := (bob_local - hand).normalized() if bob_local.distance_to(hand) > 1.0 else Vector2(side, 0)
		tip = hand + dir * 11.0 + Vector2(0, -15)
	else:
		tip = hand + Vector2(8.0 * side, -17.0)
	# the rod: a cane with a darker grip
	draw_line(hand + (hand - tip).normalized() * 4.0, tip, Color(0.46, 0.32, 0.18), 1.6, true)
	draw_line(hand + (hand - tip).normalized() * 4.0, hand + (tip - hand) * 0.25, Color(0.30, 0.20, 0.12), 2.2, true)
	if not fishing:
		return
	# the line and the bobber
	var target := bob_local
	var bob := target
	if _cast_t < 1.0:
		var e := ease(_cast_t, 0.6)
		bob = tip.lerp(target, e) + Vector2(0, -26.0 * sin(PI * e))
	var dip := 0.0
	if _phase == "bite" and _cast_t >= 1.0:
		dip = 2.4 + 1.2 * sin(_t * 26.0)
	elif _cast_t >= 1.0:
		dip = 0.7 * sin(_t * 2.6)
	bob += Vector2(0, dip)
	var sag := Vector2(0, 8.0 if _cast_t >= 1.0 else 0.0)
	var mid := tip.lerp(bob, 0.5) + sag
	var pts := PackedVector2Array()
	for k in 9:
		var u := float(k) / 8.0
		pts.append(tip.lerp(mid, u).lerp(mid.lerp(bob, u), u))
	draw_polyline(pts, LINE, 0.8, true)
	if _cast_t >= 1.0:
		# rings on the water round the bobber; quick and many when something's biting
		var rate := 2.4 if _phase == "bite" else 0.6
		for k in 2:
			var ph := fposmod(_t * rate + float(k) * 0.5, 1.0)
			draw_arc(target + Vector2(0, 1.5), 3.0 + ph * 9.0, 0.0, TAU, 20, Color(0.9, 0.96, 1.0, 0.45 * (1.0 - ph)), 1.0, true)
	draw_circle(bob, 2.6, BOBBER_WHITE)
	draw_circle(bob + Vector2(0, 0.9), 2.0, BOBBER_RED)
	if _phase == "bite" and _cast_t >= 1.0:
		_draw_alert()
		if _ring != null and not _ring.is_over():
			_draw_ring(target)


## A "!" over your head: something's biting.
func _draw_alert() -> void:
	var p := Vector2(0, -34 + 1.5 * sin(_t * 10.0))
	draw_circle(p, 5.5, Color(UiStyle.GEM_GOLD, 0.95))
	draw_line(p + Vector2(0, -3), p + Vector2(0, 0.8), UiStyle.INK, 1.6)
	draw_circle(p + Vector2(0, 2.6), 0.9, UiStyle.INK)


## The timing ring: a fixed target circle round the bobber, and a ring closing in on it that warms gold as
## it nears. Tap as they meet.
func _draw_ring(center: Vector2) -> void:
	var target_r := RING_RADIUS * FishingRing.target_scale()
	var warm := _ring.closeness()
	draw_arc(center, target_r, 0.0, TAU, 32, Color(1.0, 0.98, 0.9, 0.85), 1.6, true)
	var r := RING_RADIUS * _ring.ring_scale()
	if r > 0.5:
		var col := Color(1.0, 0.98, 0.9).lerp(UiStyle.GEM_GOLD, warm)
		draw_arc(center, r, 0.0, TAU, 40, Color(col, 0.55 + 0.45 * warm), 2.0 + warm, true)


## The catch rising out of the water to over your head, then fading.
func _draw_pop() -> void:
	var u := clampf(_pop_t / POP_SECONDS, 0.0, 1.0)
	var rise := ease(minf(u * 1.6, 1.0), 0.5)
	var from := to_local(_pop_from)
	var to := Vector2(0, -40)
	var p := from.lerp(to, rise) + Vector2(0, -14.0 * sin(PI * minf(u * 1.6, 1.0)))
	var alpha := 1.0 if u < 0.7 else 1.0 - (u - 0.7) / 0.3
	ItemIcon.draw(self, _pop_key, _pop_kind, p, 25.0, _pop_color, alpha)
