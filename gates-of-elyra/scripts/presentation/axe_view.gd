class_name AxeView
extends Node2D
## The AXE in a player's hand (home building; docs/usable-items-design.md "Home building"): a child of the
## PlayerView, so it moves with them. Carried over the shoulder while it's the selected hotbar item
## (FishingDirector), and for friends carrying one (PresenceDirector). `swing()` brings it down in an arc, with
## a few chips of wood flying where it bites; HarvestDirector swings it at a tree (several times while a chop
## takes time).
##
## It sits at the avatar's own depth (y-sorted with it), so a tree you walk behind hides the axe too.

const SWING_TIME := 0.32

## "axe", or "hammer" (the carpenter's, at work on your house).
var tool := "axe"

var _t := 0.0
var _swing := -1.0          # 0..1 through a swing; < 0 when resting
var _chips: Array = []      # [{ p, v, life }] in local space


## One chop: the axe comes down and bites.
func swing() -> void:
	_swing = 0.0


func is_swinging() -> bool:
	return _swing >= 0.0


func _process(delta: float) -> void:
	_t += delta
	if _swing >= 0.0:
		var before := _swing
		_swing += delta / SWING_TIME
		if before < 0.55 and _swing >= 0.55:
			_spray()
		if _swing >= 1.0:
			_swing = -1.0
	for c in _chips:
		c["life"] -= delta
		c["v"] += Vector2(0, 260.0) * delta
		c["p"] += c["v"] * delta
	_chips = _chips.filter(func(c: Dictionary) -> bool: return float(c["life"]) > 0.0)
	var parent := get_parent()
	if parent is PlayerView:
		show_behind_parent = (parent as PlayerView).facing().y < -0.5 and _swing < 0.0
	queue_redraw()


func _side() -> float:
	var parent := get_parent()
	if parent is PlayerView:
		var f := (parent as PlayerView).facing()
		if absf(f.x) > 0.35:
			return signf(f.x)
		if f.y < -0.5:
			return -1.0
	return 1.0


func _spray() -> void:
	var side := _side()
	var at := Vector2(14.0 * side, -8.0)
	for k in 5:
		var a := -PI * 0.5 + side * (0.4 + 0.25 * float(k))
		_chips.append({ "p": at, "v": Vector2(cos(a), sin(a)) * (60.0 + 18.0 * float(k)), "life": 0.45 })


func _draw() -> void:
	var side := _side()
	var hand := Vector2(5.0 * side, -9.0)
	# Resting: over the shoulder, head up behind you. Swinging: raised, then down in front, then back.
	var rest := -0.9 * side
	var angle := rest
	if _swing >= 0.0:
		var k := _swing
		if k < 0.35:
			angle = lerpf(rest, -1.9 * side, k / 0.35)                      # wind up
		elif k < 0.55:
			angle = lerpf(-1.9 * side, 1.25 * side, (k - 0.35) / 0.2)      # down it comes
		else:
			angle = lerpf(1.25 * side, rest, (k - 0.55) / 0.45)            # and back
	var dir := Vector2(sin(angle), -cos(angle))
	var top := hand + dir * 15.0
	draw_line(hand - dir * 3.0, top, Color(0.52, 0.38, 0.24), 2.0, true)
	var across := Vector2(-dir.y, dir.x) * side
	if tool == "hammer":
		draw_line(top - across * 3.0, top + across * 4.0, Color(0.40, 0.40, 0.44), 3.0, true)
	else:
		var head := PackedVector2Array([top - dir * 3.0, top + dir * 1.0, top + across * 6.0 + dir * 2.0, top + across * 7.0 - dir * 4.0])
		draw_colored_polygon(head, Color(0.62, 0.64, 0.68))
		draw_line(top + across * 6.0 + dir * 2.0, top + across * 7.0 - dir * 4.0, Color(0.90, 0.92, 0.95), 1.0, true)
	for c in _chips:
		var a := clampf(float(c["life"]) / 0.45, 0.0, 1.0)
		draw_rect(Rect2(c["p"] - Vector2(1, 1), Vector2(2, 2)), Color(0.86, 0.70, 0.46, a))
