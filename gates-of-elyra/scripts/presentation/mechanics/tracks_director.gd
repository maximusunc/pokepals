class_name TracksDirector
extends Node
## The snow-hare's TRACKS (Drifthallow's secret): a trail only a fox can read. This is the presentation
## half; the decisions live in the pure TrailGuide (scripts/world). Each frame it hands the guide where
## you and your companion are and which animal the companion wears, and turns the answer into:
##   * a "guide" command for the companion's brain (walk to the next stop, or stand and wait for you);
##   * a bright paw-print on the ground wherever the fox walks (GlowTrail.add_scent), so you can see the
##     line it is following, which fades after a long while;
##   * the few words of hint that go with the moments (nose down, waiting, the scent slipping away);
##   * `trail_done` when it reaches the den, which the SecretDirector turns into the frost-flower rising.
## As you come near the scent spot (in any shape) the companion NOTICES it: it stops and points toward
## the spot for a moment, further off and more often the deeper the bond (TrailGuide.notice, the same
## shape as the Riverbank's salamander points). With a fox, once you're close it trots over to the spot
## by itself and puts its nose down; you only have to be near, it doesn't have to be standing on it.
## In any OTHER shape the companion near the scent spot just plays in the snow (a small cue, no trail,
## and a hint that a different nose might know). Everything is personal and display-only: a friend
## standing beside you sees your fox lead you, but not the tracks, and nothing here is networked.
##
## The numbers all come from the secret's `reveal` block in the world spec, so the next world to hide a
## trail is data only. The decision of WHETHER the player may take what's at the den stays the server's
## (it checks "this world, standing at it" on the claim).

signal trail_done

## How long (seconds) to hold off the companion's autonomous shape-shifting each frame it's on the trail.
const DEFAULT_DRIFT_HOLD := 30.0

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _guide: TrailGuide
var _reveal: Dictionary = {}
var _lines: Dictionary = {}
var _start := Vector2.ZERO
var _trail_pts: Array = []
var _printer: GlowTrail
var _rng := RandomNumberGenerator.new()
var _play_cooldown := 0.0
var _said := {}                 # which one-time hints have been given this visit
var _pointing := false          # holding a notice-point this frame


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


## Lay out this world's trail from the secret's reveal block ({ start, trail, species, ... }).
func configure(secret: Dictionary) -> void:
	_reveal = secret.get("reveal", {})
	_lines = _reveal.get("lines", {})
	_start = WorldData.to_vec2(_reveal.get("start", secret.get("position", [0, 0])))
	_trail_pts = []
	for p in _reveal.get("trail", []):
		_trail_pts.append(WorldData.to_vec2(p))
	_guide = TrailGuide.new(_start, _trail_pts, _reveal)
	_rng.seed = hash(String(secret.get("id", "tracks")))
	_play_cooldown = 0.0
	_said = {}


func guide() -> TrailGuide:
	return _guide


## Per frame (SecretDirector.update drives it).
func update(delta: float) -> void:
	if _guide == null or _guide.is_done() or _player == null or _companion == null:
		return
	var form := _companion.current_form_species()
	var was := _guide.phase
	var r := _guide.update(delta, _companion.position, _player.position, form)

	if String(r["command"]) == "guide":
		_companion.issue_command("guide", r["target"], { "hold": bool(r["hold"]) })
	if _guide.phase != TrailGuide.Phase.IDLE:
		# A fox leading you shouldn't drift into a hare-scared cat halfway along.
		_companion.postpone_form_drift(float(_reveal.get("drift_hold", DEFAULT_DRIFT_HOLD)))

	for pos in r["prints"]:
		_lay_print(pos)
	for e in r["events"]:
		_on_event(String(e), was)

	_update_notice(delta)
	if _guide.phase == TrailGuide.Phase.IDLE:
		_update_play(delta, form)


## The companion noticing the scent spot as you come near: a held point toward it (the body's
## point_at pose), released when the notice ends or the trail begins.
func _update_notice(delta: float) -> void:
	var n := _guide.notice(delta, _player.position, _companion.bond_value())
	if n["point"]:
		_companion.point_at(n["target"], 1.0)
		_pointing = true
		if n["started"]:
			_say_once("notice")
	elif _pointing:
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false


func _on_event(event: String, was_phase: int) -> void:
	match event:
		"sniff":
			_say_once("sniff")
		"set_off":
			_say_once("set_off")
		"wait":
			_say_once("wait")
		"resume":
			pass
		"lost":
			# Only worth a word if it was properly under way (not just a sniff that never began).
			if was_phase == TrailGuide.Phase.LEAD or was_phase == TrailGuide.Phase.WAIT:
				_say_once("lost")
		"done":
			trail_done.emit()


func _say_once(key: String) -> void:
	if _said.has(key):
		return
	_said[key] = true
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)


## One bright paw-print where the fox's feet are, its toes pointing the way the trail runs.
func _lay_print(pos: Vector2) -> void:
	if _printer == null or not is_instance_valid(_printer):
		_printer = _world_art.get_node_or_null("GlowTrail") as GlowTrail
		if _printer == null:
			# A world whose atmosphere sets no footprints still needs a node to hold the scent-prints.
			_printer = GlowTrail.new()
			_printer.name = "GlowTrail"
			_world_art.add_child(_printer)
			_printer.setup(_reveal.get("scent", {}), Callable(self, "_no_walkers"))
	var ahead: Vector2 = _guide_heading(pos)
	_printer.add_scent(pos + Vector2(0, 6), ahead)


func _no_walkers() -> Array:
	return []


## The direction the trail runs from `pos`: toward the waypoint the guide is heading for.
func _guide_heading(pos: Vector2) -> Vector2:
	var i := mini(_guide.next_index, _trail_pts.size() - 1)
	return (_trail_pts[i] as Vector2) - pos


## In any shape but the trail's own, the companion near the scent spot plays in the snow: every so often
## it bounds off to a spot nearby and tumbles about. A cue, nothing more (no trail, no prints).
func _update_play(delta: float, form: String) -> void:
	_play_cooldown = maxf(0.0, _play_cooldown - delta)
	if _play_cooldown > 0.0 or form == _guide.species() or form == "":
		return
	var anchor := _guide.resume_point()
	if _companion.position.distance_to(anchor) > float(_reveal.get("scent_radius", 150.0)) \
			or _player.position.distance_to(anchor) > float(_reveal.get("player_radius", 260.0)):
		return
	_play_cooldown = float(_reveal.get("play_interval", 16.0))
	var ang := _rng.randf_range(0.0, TAU)
	var spot := anchor + Vector2(cos(ang), sin(ang)) * _rng.randf_range(20.0, float(_reveal.get("play_radius", 70.0)))
	_companion.issue_command("visit", spot)
	_say_once("play")
