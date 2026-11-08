class_name FollowDirector
extends Node
## The ROOT-HEART (Underroot's secret): a seed glowing deep in the tangle of tunnels, which the dark makes
## nearly impossible to steer to yourself. You ask your companion to "Go look" and then FOLLOW. This is the
## presentation half; the decisions live in the pure FollowGuide (scripts/world). It:
##   * on the ask, plans a route from where the companion stands to the heart through the tunnels (the
##     companion body's own NavGrid, CompanionView.plan_route) and hands it to the guide;
##   * each frame turns the guide's answer into a "guide" command for the companion's brain (walk to the next
##     stop at the bond's pace, or stand and wait / hold back), reusing the Drifthallow lead and the NavAgent
##     routing: no new movement;
##   * makes the state READABLE in the dark: the companion's own light swells while it leads, holds steady
##     while it waits for you, and is down while it holds back from your pushing ahead (mist_pockets, read by
##     the MistVeil), plus a hint the first time of each;
##   * as you come near the heart the companion NOTICES it and points toward it (FollowGuide.notice, the same
##     shape as the Riverbank's salamander points), further off the deeper the bond; and the heart itself
##     glimmers faintly through the dark when you are close, so you can tell when you are nearly there;
##   * `heart_reached` when you and the companion have both arrived, which the SecretDirector turns into the
##     root-heart rising (and the usual claim on examine).
## Everything is personal and display-only: a friend beside you sees your companion lead, and nothing here is
## networked. The numbers all come from the secret's `reveal` block in the world spec, so the next world to
## hide something in the dark is data only. Whether you may take the heart stays the server's call (it checks
## "this world, standing at it" on the claim).

signal heart_reached

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _guide: FollowGuide
var _reveal: Dictionary = {}
var _lines: Dictionary = {}
var _heart := Vector2.ZERO
var _said := {}                 # which one-time hints have been given this visit
var _pointing := false          # holding a notice-point this frame
var _light := 0.0               # the companion's light right now, eased (0..1)
var _light_target := 0.0
var _glimmer := 0.0             # how much of the heart's own glow shows through the dark (0..1)
var _revealed := false          # the heart is in the world (arrival), so it shines for itself
var _active := true
var _time := 0.0


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


## Lay out this world's heart from the secret ({ position, reveal: { ... } }).
func configure(secret: Dictionary) -> void:
	_reveal = secret.get("reveal", {})
	_lines = _reveal.get("lines", {})
	_heart = WorldData.to_vec2(secret.get("position", [0, 0]))
	_guide = FollowGuide.new(_heart, _reveal)
	_said = {}
	_light = 0.0
	_light_target = 0.0
	_glimmer = 0.0
	_revealed = false
	_active = true


func guide() -> FollowGuide:
	return _guide


## Whether "Go look" is on offer right now: the heart is still to be found and not yet reached.
func can_ask() -> bool:
	return _active and _guide != null and not _guide.is_done()


## The heart has risen (arrival), so it shines for itself until it is taken.
func mark_revealed() -> void:
	_revealed = true


## The secret has been found: stop leading and let the companion relax.
func finish() -> void:
	_active = false
	_light_target = 0.0
	_light = 0.0
	_glimmer = 0.0
	_revealed = false
	if _companion != null:
		_companion.point_at(Vector2.ZERO, 0.0)


## The player's ask ("Go look"): plan the way and lead. Said once when it can't (nowhere to go from here).
func ask() -> void:
	if not can_ask() or _companion == null or _player == null:
		return
	var route := _companion.plan_route(_heart)
	if route.is_empty() or (route.back() as Vector2).distance_to(_heart) > 140.0:
		# Nothing to lead along (nav off, or boxed in): say so gently rather than do nothing.
		_say("no_way")
		return
	if _guide.begin(route, _companion.bond_value()):
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false
		_host.show_hint(String(_lines.get("ask", "You ask your companion to go look. Stay behind it, and follow its light.")))
		_said["ask_said"] = true


## The moving pockets in the dark that belong to this secret (for MistVeil): the companion's own light,
## swelling while it leads and steady while it waits; and the heart's glimmer, once you are close.
func mist_pockets() -> Array:
	var out: Array = []
	if not _active:
		return out
	if _light > 0.02 and _companion != null:
		var big := float(_reveal.get("lead_light_radius", 132.0))
		out.append({ "pos": _companion.position + Vector2(0.0, -6.0), "radius": big * _light, "warm": 0.9 })
	if _glimmer > 0.02:
		var r := float(_reveal.get("heart_radius", 120.0)) if _revealed else float(_reveal.get("glimmer_radius", 54.0))
		var pulse := 0.88 + 0.12 * sin(_time * 1.6)
		out.append({ "pos": _heart + Vector2(0.0, -8.0), "radius": r * _glimmer * pulse, "warm": 1.0 })
	return out


## Per frame (SecretDirector.update drives it).
func update(delta: float) -> void:
	if not _active or _guide == null or _player == null or _companion == null or delta <= 0.0:
		return
	_time += delta
	var bond := _companion.bond_value()

	var r := _guide.update(delta, _companion.position, _player.position, bond)
	if String(r["command"]) == "guide":
		_companion.issue_command("guide", r["target"], { "hold": bool(r["hold"]), "speed": float(r["speed"]) })
	if _guide.is_leading():
		# A leading companion shouldn't change shape halfway; keep its drift off while it works.
		_companion.postpone_form_drift(float(_reveal.get("drift_hold", 30.0)))
	_light_target = float(r["light"])
	for e in r["events"]:
		_on_event(String(e))
	_light = move_toward(_light, _light_target, delta / maxf(0.05, float(_reveal.get("light_ease", 0.6))))

	_update_notice(delta)
	_update_glimmer(delta)
	if _guide.is_done():
		_light_target = 0.0
		if not _said.has("done_cleared"):
			_said["done_cleared"] = true
			heart_reached.emit()


## The companion noticing the heart as you come near: a held point toward it (the body's point_at pose),
## released when the notice ends or the lead begins.
func _update_notice(delta: float) -> void:
	var n := _guide.notice(delta, _player.position, _companion.bond_value())
	if n["point"]:
		_companion.point_at(n["target"], 1.0)
		_pointing = true
		if n["started"]:
			_say("notice")
	elif _pointing:
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false


## The heart's own faint glow, showing through the dark when you are near (and in full once it has risen).
func _update_glimmer(delta: float) -> void:
	var d := _player.position.distance_to(_heart)
	var want := 0.0
	if _revealed:
		want = 1.0
	elif d <= float(_reveal.get("glimmer_range", 320.0)):
		want = clampf(1.0 - d / float(_reveal.get("glimmer_range", 320.0)), 0.0, 1.0) * 0.9 + 0.1
	_glimmer = move_toward(_glimmer, want, delta * 0.8)


func _on_event(event: String) -> void:
	match event:
		"set_off", "reached":
			pass
		"wait":
			_say("wait")
		"balk":
			_say("balk")
		"let_go":
			# Every time, like scent_lost: it is the cue that the lead has ended and you can ask again.
			_host.show_hint(String(_lines.get("let_go", "")))
		"lost":
			_say("lost")
		"scent_lost":
			# Every time: it is the cue to ask again, and nothing else tells you.
			_host.show_hint(String(_lines.get("scent_lost", "")))
		"at_heart":
			_say("at_heart")
		"arrived":
			pass


## A hint line, once per visit (the lines are the world's; a missing one says nothing).
func _say(key: String) -> void:
	if _said.has(key):
		return
	_said[key] = true
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)
