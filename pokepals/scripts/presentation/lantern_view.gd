class_name LanternView
extends Node2D
## The LANTERN in a player's hand (usable items, the second item; docs/usable-items-design.md): a child of
## the PlayerView, so it moves with them. It hangs from the hand, sways a little as you walk, and throws a
## soft warm glow round you, with the firefly inside breathing brighter and dimmer. Shown while the lantern
## is the selected hotbar item (FishingDirector), and for friends carrying one (PresenceDirector).
##
## In the dark worlds (Underroot, Steamhollow's fog) the real light is a pocket of clear air in the mist
## (world_controller hands MistVeil a big warm pocket round each lantern); this draws the lantern and its
## glow everywhere.

const GLOW_RADIUS := 46.0

var _t := 0.0
var _swing := 0.0


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	_t += delta
	var parent := get_parent()
	if parent is PlayerView:
		var p := parent as PlayerView
		var target := clampf(p.velocity.x / 120.0, -1.0, 1.0) * 0.35
		_swing = lerpf(_swing, target, 1.0 - exp(-5.0 * delta))
		show_behind_parent = p.facing().y < -0.5
	queue_redraw()


func _draw() -> void:
	var f := Vector2.DOWN
	var parent := get_parent()
	if parent is PlayerView:
		f = (parent as PlayerView).facing()
	var side := 1.0
	if absf(f.x) > 0.35:
		side = signf(f.x)
	var hand := Vector2(6.0 * side, -8.0)
	if f.y < -0.5:
		hand = Vector2(-6.0, -10.0)
	var breathe := 0.75 + 0.25 * sin(_t * 2.2)
	# the warm pool of light on the ground round you (two soft rings, faint, so it reads as light not paint)
	draw_circle(Vector2(0, -2), GLOW_RADIUS, Color(1.0, 0.82, 0.46, 0.06 * breathe))
	draw_circle(Vector2(0, -2), GLOW_RADIUS * 0.6, Color(1.0, 0.86, 0.52, 0.08 * breathe))
	# the lantern hanging from your hand on a short loop, swinging as you walk
	var hang := hand + Vector2(sin(_swing + sin(_t * 1.6) * 0.06) * 6.0, 7.0)
	draw_line(hand, hang + Vector2(0, -5), Color(0.40, 0.30, 0.20), 1.0, true)
	ItemIcon.draw_lantern(self, hang, 0.62, 1.0, breathe)
