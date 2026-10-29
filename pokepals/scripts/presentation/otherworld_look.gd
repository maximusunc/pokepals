class_name OtherworldLook
extends Node2D
## How the people in a re-skinned world are LIT — "you, on another planet". On a world whose art
## override carries an `actor_look` (Nocthollow), every player avatar and companion (our own pair and
## every remote pair) gets two things, and nothing else about it changes:
##
##   * a palette shift — a ShaderMaterial (assets/otherworld_actor.gdshader) on the actor node, which
##     recolours whatever it draws (any outfit, any daemon form) into the planet's light, and lights
##     up its outline;
##   * a glow — this node, added as a child drawn BEHIND the actor: a soft breathing aura, a pool of
##     light on the ground beneath it, and a few motes of light orbiting it.
##
## Pure presentation: the actor's logic, look and save are untouched, and a world without an
## actor_look never calls this, so the meadow worlds look exactly as before.

const SHADER := preload("res://assets/otherworld_actor.gdshader")
const COLOR_KEYS := ["shadow_mult", "light_mult", "cast", "line_glow"]
const FLOAT_KEYS := ["shadow_boost", "light_boost", "cast_amount", "saturation", "line_amount", "line_cut", "pulse_speed"]

var color := Color(0.5, 0.95, 1.0)
var radius := 26.0
var motes := 3
var _time := 0.0


## Re-light `actor` per the world's `look` (ArtStyle.actor_look()). `size` sizes the aura (a companion
## is smaller than its person). A no-op for an empty look.
static func apply(actor: CanvasItem, look: Dictionary, size := 1.0) -> void:
	if look.is_empty() or actor == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	for key in COLOR_KEYS:
		if look.has(key):
			mat.set_shader_parameter(key, WorldData.to_color(look[key]))
	for key in FLOAT_KEYS:
		if look.has(key):
			mat.set_shader_parameter(key, float(look[key]))
	actor.material = mat
	var aura := OtherworldLook.new()
	aura.name = "OtherworldAura"
	aura.show_behind_parent = true
	aura.color = WorldData.to_color(look.get("aura", [0.5, 0.95, 1.0]))
	aura.radius = float(look.get("aura_radius", 26.0)) * size
	aura.motes = int(look.get("motes", 3))
	actor.add_child(aura)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var breathe := 0.86 + 0.14 * sin(_time * 1.4)
	# a pool of light on the ground under the feet, then the aura around the body
	SoftGlow.draw(self, Vector2(0, 6), radius * 0.8, Color(color.r, color.g, color.b, 0.32 * breathe), 0.4)
	SoftGlow.draw(self, Vector2(0, -radius * 0.4), radius * breathe, Color(color.r, color.g, color.b, 0.20))
	# a few motes circling lazily, bobbing as they go
	for k in motes:
		var a := _time * (0.9 + 0.15 * float(k)) + float(k) * TAU / float(maxi(1, motes))
		var p := Vector2(cos(a) * radius * 0.55, -radius * 0.4 + sin(a * 1.7) * radius * 0.25)
		draw_circle(p, 1.4, Color(color.r, color.g, color.b, 0.75))
		draw_circle(p, 0.7, Color(1, 1, 1, 0.9))
