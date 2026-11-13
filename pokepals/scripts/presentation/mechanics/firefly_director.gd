class_name FireflyDirector
extends Node
## FIREFLY GLADES (usable items, crafting; docs/usable-items-design.md): in a world whose spec has
## `firefly_glades` (Dozewood's three), a slow drift of fireflies hangs over each one (FireflyGlade). Stand
## in a glade with an EMPTY hand (an empty hotbar slot selected) and the use button becomes an open jar; tap
## it and a firefly comes along (the server checks you're in a glade, and allows one every few seconds). The
## tinker in the bazaar makes a lantern with one. No-op in every other world.
##
## FishingDirector (which owns the hotbar and the use button) asks `can_invite()` to show the jar, and calls
## `invite()` when it's tapped.

var _host: Node
var _player: PlayerView
var _companion: CompanionView
var _scenery: Node2D
var _glades: Array = []     # [{ pos: Vector2, radius: float, view: FireflyGlade }]
var _told := false          # the first time you walk into a glade, a hint says what to do
var _waiting := false       # asked the server; waiting for its answer
var _last_glade: Dictionary = {}


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


## The glade you're standing in, or {}.
func _glade_here() -> Dictionary:
	for g in _glades:
		if _player.position.distance_to(g["pos"]) <= float(g["radius"]) + 20.0:
			return g
	return {}


## Whether a firefly could be invited right now (you're in a glade, not already asking).
func can_invite() -> bool:
	return not _waiting and not _glade_here().is_empty()


## The use button was tapped with an empty hand in a glade: ask a firefly along.
func invite() -> void:
	var g := _glade_here()
	if g.is_empty() or _waiting:
		return
	_waiting = true
	_last_glade = g
	Net.catch_firefly()


func update(_delta: float) -> void:
	if _glades.is_empty():
		return
	var g := _glade_here()
	if not g.is_empty() and not _told:
		_told = true
		_host.show_hint("Fireflies! With an empty hand (pick an empty hotbar slot), tap Use to invite one along.")
		_companion.glance_toward(g["pos"])


func _on_caught(count: int) -> void:
	_waiting = false
	if not _last_glade.is_empty():
		(_last_glade["view"] as FireflyGlade).send_one_to(_player)
	_companion.delight_at(_player.position)
	if count <= 1:
		_host.show_hint("A firefly drifts into your jar. It seems happy to come along.")
	else:
		_host.show_hint("Another firefly comes along. (%d in your jar)" % count)


func _on_refused(reason: String) -> void:
	_waiting = false
	if reason == "no_glade":
		_host.show_hint("The fireflies are over there, in the glade.")
	# too soon: nothing to say; it just doesn't go


## A slow drift of fireflies over one glade: a dozen soft lights wandering on their own little loops, pulsing
## in and out. When one comes along with you it flies from the glade to your hand.
class FireflyGlade extends Node2D:
	const COUNT := 12
	var radius := 70.0
	var _t := 0.0
	var _seeds: Array = []
	var _flights: Array = []   # [{ from: Vector2 (local), to: Node2D, t: float }]

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

	func send_one_to(target: Node2D) -> void:
		var s: Dictionary = _seeds[randi() % _seeds.size()]
		_flights.append({ "from": s["c"] + Vector2(0, -float(s["h"])), "to": target, "t": 0.0 })

	func _process(delta: float) -> void:
		_t += delta
		for f in _flights:
			f["t"] = float(f["t"]) + delta / 0.9
		_flights = _flights.filter(func(f: Dictionary) -> bool: return float(f["t"]) < 1.0 and is_instance_valid(f["to"]))
		queue_redraw()

	func _draw() -> void:
		for s in _seeds:
			var a: float = _t * float(s["sp"]) + float(s["ph"])
			var p: Vector2 = s["c"] + Vector2(cos(a), sin(a * 1.3) * 0.6) * float(s["r"]) + Vector2(0, -float(s["h"]))
			var glow := 0.35 + 0.65 * maxf(0.0, sin(_t * float(s["pulse"]) + float(s["ph"])))
			ItemIcon.draw_firefly(self, p, 0.45, glow)
		for f in _flights:
			var to := to_local((f["to"] as Node2D).global_position + Vector2(6, -14))
			var u := ease(float(f["t"]), -2.0)
			var p: Vector2 = (f["from"] as Vector2).lerp(to, u) + Vector2(0, -18.0 * sin(PI * u))
			ItemIcon.draw_firefly(self, p, 0.5, 1.0)
