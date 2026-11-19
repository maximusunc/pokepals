class_name GroundShadows
extends Node2D
## Shadows for the perspective view, drawn ON THE GROUND. Top-down, every tree and actor draws its own little
## oval shadow inside its sprite, squashed for a view from above. In perspective the ground is squashed far flatter
## than that (more so the farther away), so a sprite's own shadow comes out too tall and too low and the thing
## above it seems to hover. Instead, PerspectiveView puts two of these in the flat layer (the top-down world it
## renders into the ground textures), where a shadow is drawn as it lies on the ground: the perspective then
## foreshortens it exactly like the ground under it. TreeView skips its own shadow while a perspective view is up.
##
## Each is an afternoon shadow: a dark pool right at the foot (the contact), and a softer tongue cast away from the
## sun along the ground, longer for taller things. That shadow running off from the foot is what pins a thing to
## the ground.
##
## One holds the things that never move (trees, windmills, the keep, haystacks), drawn once; the other the actors
## (you, your companion, friends, pals), redrawn every frame (a handful of circles).

const CONTACT_ALPHA := 0.42
const CAST_ALPHA := 0.2
const AWAY := Vector2(0.62, -0.78)  # the way shadows fall across the ground (the sun low in the south-west)
const CAST_STEPS := 5

var _shadow_color := Color(0.1, 0.12, 0.08)
var _spots: Array = []     # static: [pos, radius, cast length]
var _actors: Array = []    # live: [node, radius, cast length]
var _live := false


func setup_static(spots: Array, shadow: Color) -> void:
	_spots = spots
	_shadow_color = shadow
	_live = false
	queue_redraw()


func setup_actors(actors: Array, shadow: Color) -> void:
	_actors = actors
	_shadow_color = shadow
	_live = true


func _process(_delta: float) -> void:
	if _live:
		queue_redraw()


func _draw() -> void:
	if _live:
		for a in _actors:
			var n := a[0] as Node2D
			if is_instance_valid(n) and n.visible:
				_shadow(n.global_position, float(a[1]), float(a[2]))
	else:
		for s in _spots:
			_shadow(s[0], float(s[1]), float(s[2]))


func _shadow(p: Vector2, r: float, cast: float) -> void:
	var sc := _shadow_color
	# the cast: a run of overlapping discs off along the ground, thinning and fading
	for i in range(CAST_STEPS, 0, -1):
		var t := float(i) / CAST_STEPS
		draw_circle(p + AWAY * cast * t, r * (1.0 - 0.45 * t), Color(sc.r, sc.g, sc.b, CAST_ALPHA * (1.0 - 0.6 * t)))
	# the contact: darkest right under it
	draw_circle(p, r * 1.2, Color(sc.r, sc.g, sc.b, CONTACT_ALPHA * 0.5))
	draw_circle(p, r * 0.8, Color(sc.r, sc.g, sc.b, CONTACT_ALPHA))
