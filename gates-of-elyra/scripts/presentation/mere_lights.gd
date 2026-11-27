class_name MereLights
extends Node2D
## The lily-lights gathering over the Mere while you keep still (W-2, StillnessGate). At rest they're a
## loose, dim scatter drifting on the water; as stillness builds they drift together into a slow ring and
## brighten; when it completes the ring holds, glowing, around where the mere-pearl rises. Pure
## presentation: the SecretDirector feeds it a 0..1 `progress`, eased so a pause visibly loosens it.

const COUNT := 9

var center := Vector2.ZERO
var ring_radius := 80.0
var color := Color(0.62, 0.92, 1.0)

var _target := 0.0
var _shown := 0.0
var _time := 0.0
var _scatter: Array = []  # each light's loose resting offset from the centre


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7351
	for i in COUNT:
		_scatter.append(Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.0, 1.0)) * ring_radius)


func set_progress(p: float) -> void:
	_target = clampf(p, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	# Ease toward the target, so the ring loosens and gathers smoothly rather than jumping.
	_shown += (_target - _shown) * (1.0 - exp(-2.5 * delta))
	queue_redraw()


func _draw() -> void:
	var gather := smoothstep(0.0, 1.0, _shown)
	for i in COUNT:
		var ang := TAU * float(i) / float(COUNT) + _time * 0.15
		var on_ring := center + Vector2(cos(ang), sin(ang) * 0.55) * ring_radius
		var drift := Vector2(sin(_time * 0.4 + i), cos(_time * 0.33 + i * 1.7)) * 10.0
		var loose: Vector2 = center + _scatter[i] + drift
		var p := loose.lerp(on_ring, gather)
		var a := 0.18 + 0.62 * gather
		SoftGlow.draw(self, p, 10.0 + 8.0 * gather, Color(color.r, color.g, color.b, a * 0.5), 0.6)
		draw_circle(p, 2.2 + 1.2 * gather, Color(1, 1, 1, a))
	if gather > 0.6:
		# The ring's own soft heart, once it has mostly gathered.
		SoftGlow.draw(self, center, ring_radius * 0.8, Color(color.r, color.g, color.b, (gather - 0.6) * 0.35), 0.55)
