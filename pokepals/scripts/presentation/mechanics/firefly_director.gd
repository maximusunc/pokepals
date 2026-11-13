class_name FireflyDirector
extends Node
## FIREFLY GLADES (usable items, crafting; docs/usable-items-design.md): in a world whose spec has
## `firefly_glades` (one beside the secret at the end of each dark world, Steamhollow and Underroot, so a lantern
## is the reward for having found your way through once), a slow drift of fireflies hangs over each one (FireflyGlade), and a
## glass jar stands on a little table in each (a prop with `"firefly_jar": true`). EXAMINE the jar and a short
## cutscene plays: your steering rests a moment, a firefly drifts down out of the glade and into the jar, the
## jar glows, and the firefly is in your bag. The tinker in the bazaar makes a lantern with one.
##
## You carry ONE firefly at a time (the server enforces it; we check first so the cutscene never plays for
## nothing): once it has gone into a lantern, another will come. No-op in every other world.

const FLIGHT := 1.5        # s for the firefly to drift down into the jar
const GLOW := 1.0          # s the jar glows with it inside, before it's in your bag
const JAR_TOP := Vector2(0, -30)   # where the jar's mouth is, from the table's spot (world_art draws the jar)

var _host: Node
var _player: PlayerView
var _companion: CompanionView
var _scenery: Node2D
var _glades: Array = []     # [{ pos: Vector2, radius: float, view: FireflyGlade }]
var _told := false          # the first time you walk into a glade, a hint points at the jar

# The cutscene in progress: { jar: Vector2, t: float, answered: bool, ok: bool } or {}.
var _scene: Dictionary = {}


func setup(host: Node, player: PlayerView, companion: CompanionView, scenery: Node2D) -> void:
	_host = host
	_player = player
	_companion = companion
	_scenery = scenery
	Net.firefly_caught.connect(_on_caught)
	Net.firefly_refused.connect(_on_refused)


func configure(data: Dictionary) -> void:
	for g in data.get("firefly_glades", []):
		if not (g is Dictionary):
			continue
		var view := FireflyGlade.new()
		view.name = "FireflyGlade_%s" % String((g as Dictionary).get("id", str(_glades.size())))
		var pos := WorldData.to_vec2(g.get("position", [0, 0]))
		view.position = pos
		view.radius = float(g.get("radius", 70.0))
		_scenery.add_child(view)
		_glades.append({ "pos": pos, "radius": view.radius, "view": view })


func has_glades() -> bool:
	return not _glades.is_empty()


func is_playing() -> bool:
	return not _scene.is_empty()


## Whether we're already carrying a firefly (one at a time).
static func carrying_one() -> bool:
	for it in Net.inventory():
		if it is Dictionary and String((it as Dictionary).get("key", "")) == "firefly" and int((it as Dictionary).get("quantity", 0)) > 0:
			return true
	return false


## The jar was examined: if there's room for a firefly, ask the server and play the cutscene.
func examine_jar(entry: Dictionary) -> void:
	if is_playing():
		return
	if carrying_one():
		_host.show_hint("You already have a firefly with you. Once it's in a lantern, another will come.")
		return
	var jar: Vector2 = entry["pos"]
	var glade := _nearest_glade(jar)
	if glade.is_empty():
		return
	_scene = { "jar": jar, "glade": glade, "t": 0.0, "answered": false, "ok": false }
	_player.input_enabled = false
	_player.look_toward(jar - _player.position)
	_companion.glance_toward(jar)
	_host.show_hint("One of the fireflies drifts down toward the jar...")
	(glade["view"] as FireflyGlade).fly_one_into(jar + JAR_TOP, FLIGHT, GLOW)
	Net.catch_firefly()


func _nearest_glade(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for g in _glades:
		var d := p.distance_to(g["pos"])
		if d < best_d:
			best = g
			best_d = d
	return best


func update(delta: float) -> void:
	if _glades.is_empty():
		return
	if not _told:
		for g in _glades:
			if _player.position.distance_to(g["pos"]) <= float(g["radius"]) + 20.0:
				_told = true
				_host.show_hint("Fireflies, and a glass jar on a little table. Examine the jar.")
				_companion.glance_toward(g["pos"])
				break
	if _scene.is_empty():
		return
	_scene["t"] = float(_scene["t"]) + delta
	# The scene ends once it has played through AND the server has answered (or, if the answer is lost, a
	# little after: steering never stays away).
	var played := float(_scene["t"]) >= FLIGHT + GLOW
	if (played and bool(_scene["answered"])) or float(_scene["t"]) > FLIGHT + GLOW + 5.0:
		_finish()


func _finish() -> void:
	var ok := bool(_scene.get("ok", false))
	var glade: Dictionary = _scene.get("glade", {})
	if not glade.is_empty():
		(glade["view"] as FireflyGlade).end_jar(ok)
	_scene = {}
	_player.input_enabled = true
	if ok:
		_companion.delight_at(_player.position)
		_host.show_hint("A firefly settles into the jar, glowing softly. It's in your bag now. The tinker in the bazaar could make a lantern with it.")


func _on_caught(_count: int) -> void:
	if not _scene.is_empty():
		_scene["answered"] = true
		_scene["ok"] = true


func _on_refused(reason: String) -> void:
	if _scene.is_empty():
		return
	_scene["answered"] = true
	_scene["ok"] = false
	_finish()
	match reason:
		"have_one":
			_host.show_hint("You already have a firefly with you. Once it's in a lantern, another will come.")
		_:
			_host.show_hint("The fireflies drift up again. Step up to the jar.")


## A slow drift of fireflies over one glade: a dozen soft lights wandering on their own little loops, pulsing in
## and out. In the cutscene one leaves the drift, floats down into the jar, and glows there.
class FireflyGlade extends Node2D:
	const COUNT := 12
	var radius := 70.0
	var _t := 0.0
	var _seeds: Array = []
	# The firefly coming down to the jar: { from: Vector2, to: Vector2 (both local), t, flight, glow } or {}.
	var _diver: Dictionary = {}
	var _fade := 0.0           # the jar's glow fading after the firefly is in your bag

	func _ready() -> void:
		z_index = 2
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(name)
		for i in COUNT:
			_seeds.append({
				"c": Vector2(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6)) * radius * 0.8,
				"r": rng.randf_range(6.0, 18.0),
				"sp": rng.randf_range(0.3, 0.8) * (1.0 if rng.randf() < 0.5 else -1.0),
				"ph": rng.randf() * TAU,
				"pulse": rng.randf_range(1.2, 2.6),
				"h": rng.randf_range(10.0, 26.0),
			})

	## One firefly drifts down from the glade into the jar (world point `jar_mouth`).
	func fly_one_into(jar_mouth: Vector2, flight: float, glow: float) -> void:
		var s: Dictionary = _seeds[randi() % _seeds.size()]
		_diver = { "from": s["c"] + Vector2(0, -float(s["h"]) - 20.0), "to": to_local(jar_mouth), "t": 0.0,
			"flight": flight, "glow": glow }

	## The scene's over: the firefly has gone into your bag (its glow fades), or it drifted back up.
	func end_jar(_ok: bool) -> void:
		if not _diver.is_empty():
			_fade = 0.6
			_diver["t"] = float(_diver["flight"]) + float(_diver["glow"])
			_diver["ending"] = true

	func _process(delta: float) -> void:
		_t += delta
		if not _diver.is_empty():
			_diver["t"] = float(_diver["t"]) + delta
			if bool(_diver.get("ending", false)):
				_fade -= delta
				if _fade <= 0.0:
					_diver = {}
		queue_redraw()

	func _draw() -> void:
		for s in _seeds:
			var a: float = _t * float(s["sp"]) + float(s["ph"])
			var p: Vector2 = s["c"] + Vector2(cos(a), sin(a * 1.3) * 0.6) * float(s["r"]) + Vector2(0, -float(s["h"]))
			var glow := 0.35 + 0.65 * maxf(0.0, sin(_t * float(s["pulse"]) + float(s["ph"])))
			ItemIcon.draw_firefly(self, p, 0.7, glow)
		if _diver.is_empty():
			return
		var flight: float = _diver["flight"]
		var to: Vector2 = _diver["to"]
		var t: float = _diver["t"]
		if t < flight:
			# a slow, wandering descent: it eases in, loops a little, and settles at the jar's mouth, leaving a
			# short trail of light behind it so the eye can follow it down
			for k in range(6, 0, -1):
				var tu := ease(clampf((t - float(k) * 0.05) / flight, 0.0, 1.0), -1.6)
				var tp: Vector2 = (_diver["from"] as Vector2).lerp(to, tu) + Vector2(sin(tu * TAU * 1.5) * 12.0 * (1.0 - tu), 0)
				draw_circle(tp, 2.2 - float(k) * 0.25, Color(1.0, 0.93, 0.6, 0.35 - float(k) * 0.05))
			var u := ease(t / flight, -1.6)
			var p: Vector2 = (_diver["from"] as Vector2).lerp(to, u) + Vector2(sin(u * TAU * 1.5) * 12.0 * (1.0 - u), 0)
			ItemIcon.draw_firefly(self, p, 1.0, 1.0)
		else:
			# inside the jar: the whole jar lights up warm and breathes, fading once it's in your bag
			var a := 1.0
			if bool(_diver.get("ending", false)):
				a = clampf(_fade / 0.6, 0.0, 1.0)
			var breathe := 0.75 + 0.25 * sin(_t * 4.0)
			var inside := to + Vector2(0, 10)
			draw_circle(inside, 26.0, Color(1.0, 0.88, 0.48, 0.16 * a * breathe))
			draw_circle(inside, 14.0, Color(1.0, 0.90, 0.52, 0.30 * a * breathe))
			draw_rect(Rect2(to + Vector2(-5, 2), Vector2(10, 15)), Color(1.0, 0.92, 0.6, 0.35 * a * breathe))
			ItemIcon.draw_firefly(self, inside, 0.9, a)
