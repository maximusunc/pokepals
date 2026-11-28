class_name SkyDirector
extends Node
## Loftreach's SECRET: borrowing your companion's eyes. This is the presentation half; the decisions (the flight,
## what the bird has seen, the noticing) live in the pure SkyView and the island geometry in SkyRealm
## (scripts/world). It:
##   * answers the radial's "Go up": in bird form the companion lifts off (a SkyBird puppet flying over the
##     ground, the real body hidden and held where it stands), the camera RISES with it (CameraRig.hold_view:
##     zoomed out, following the bird to the vantage over the middle of the picture), and SkyAir fades the
##     high-cloud picture in as it climbs. In any other shape the companion looks up and a hint says only a
##     bird can climb that high (the radial offers Go up in every shape so it is discoverable);
##   * ends the flight on a tap, on the first step you take, or a Call; pressing Go up again while it is up
##     HOLDS it a little longer. The camera ALWAYS comes back, and the body always reappears: on landing, when the
##     world is left mid-flight (_exit_tree), and when the secret is taken (finish);
##   * when the bird has looked at the islet and the head of the way (SkyView "seen"), brings the hidden bridge
##     down: SkyLayer unspools it from its head while the camera is still up, and the host rebuilds the barriers
##     and routing with it open (reveal_sky_bridge), so after landing it is simply walkable;
##   * makes the companion NOTICE the unreachable islet as you come near, in any shape, and look toward it (a
##     point, like the Riverbank's), scaled by bond; and after a flight that showed it the way, look at the
##     bridge's head for a moment;
##   * says the first-time hint lines (notice, launch, picture, seen, hold, landed, ended).
## The nest itself is the secret's prop (laid out from the start by SecretDirector, visible but out of reach);
## examining it claims, as ever. Everything is personal and display-only; the numbers all come from the secret's
## `reveal` block in the world spec.

## Seconds the camera takes to settle after a landing is the CameraRig's own follow; this is only the look back.
const MOVE_EPS := 0.25

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _view: SkyView
var _reveal: Dictionary = {}
var _lines: Dictionary = {}
var _bridge_id := ""
var _head := Vector2.ZERO
var _bird: SkyBird = null
var _said := {}
var _found := false
var _pointing := false
var _reveal_t := -1.0              # -1 not begun; 0..1 the bridge unspooling
var _look_back := 0.0              # seconds left of the companion looking at the bridge's head after a landing
var _last_pos := Vector2.ZERO
var _flown_seen := false           # this flight is the one that saw the way
var _cooldown := 0.0


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


## From the secret's reveal block. `found`: the secret was found on an earlier visit, so the bridge is simply
## down and Go up stays a quiet toy.
func configure(secret: Dictionary, found: bool = false) -> void:
	_reveal = secret.get("reveal", {})
	_lines = _reveal.get("lines", {})
	_bridge_id = String(_reveal.get("bridge", ""))
	_head = WorldData.to_vec2(_reveal.get("head", [0, 0]))
	var targets: Array = []
	for t in _reveal.get("targets", []):
		targets.append(WorldData.to_vec2(t))
	_view = SkyView.new(WorldData.to_vec2(_reveal.get("vantage", [0, 0])), targets, _reveal)
	_found = found
	_said = {}
	_reveal_t = -1.0
	if found:
		_view.mark_seen()
		_reveal_t = 1.0


## Found on another device (the discovery list arrived late): the bridge is simply down.
func set_found() -> void:
	if _view == null or _view.is_seen():
		return
	_view.mark_seen()
	_reveal_t = 1.0
	var layer := _layer()
	if layer != null:
		layer.set_bridge_reveal(_bridge_id, 1.0)
	if _host != null and _host.has_method("reveal_sky_bridge"):
		_host.reveal_sky_bridge(_bridge_id)


func view() -> SkyView:
	return _view


func is_flying() -> bool:
	return _view != null and _view.is_flying()


func bridge_open() -> bool:
	return _view != null and _view.is_seen()


func _layer() -> SkyLayer:
	return _world_art.sky_layer() if _world_art != null else null


func _camera() -> CameraRig:
	var cam: Variant = _host.get("_camera") if _host != null and is_instance_valid(_host) else null
	return cam as CameraRig


## The radial's Go up. A bird climbs; pressing it again while up holds the bird there a little longer; any other
## shape cannot, and the hint says why.
func try_go_up() -> void:
	if _view == null or _player == null or _companion == null:
		return
	if _view.is_flying():
		if _view.hold():
			_say("hold", false)
		return
	if _companion.current_form_species() != String(_reveal.get("species", "bird")):
		_companion.glance_toward(_companion.position + Vector2(0.0, -220.0))
		_say("not_bird", false)
		return
	if _cooldown > 0.0 or _companion.is_resting():
		return
	if not _view.launch(_companion.position, _companion.bond_value()):
		return
	_flown_seen = false
	_last_pos = _companion.position
	_ensure_bird()
	_bird.lift = 0.0
	_bird.position = _companion.position
	_bird.visible = true
	_companion.visible = false
	_say("launch", true)


## A tap on the world while the eyes are up: bring the bird home. True when a flight was under way (the tap is
## used up); false otherwise, so the controller carries on with an ordinary order.
func on_world_tap() -> bool:
	if not is_flying():
		return false
	_view.request_end()
	return true


func _ensure_bird() -> void:
	if is_instance_valid(_bird):
		var info := _companion.form_sheet_info()
		_bird.set_sheet(info)
		return
	var layer := _layer()
	var parent: Node = layer.air() if layer != null and layer.air() != null else _world_art
	_bird = SkyBird.new()
	_bird.name = "SkyBird"
	parent.add_child(_bird)
	_bird.set_sheet(_companion.form_sheet_info())
	_bird.visible = false


## A step (a key, the stick) is also a way to come home.
func _moving() -> bool:
	var v := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	for pair in [[KEY_A, Vector2(-1, 0)], [KEY_D, Vector2(1, 0)], [KEY_W, Vector2(0, -1)], [KEY_S, Vector2(0, 1)]]:
		if Input.is_physical_key_pressed(pair[0]):
			v += pair[1]
	var joy: Variant = _host.get("_joystick") if _host != null else null
	if joy != null and joy.get("direction") is Vector2:
		v += joy.direction
	return v.length() > MOVE_EPS


func update(delta: float) -> void:
	if _view == null or _player == null or _companion == null or delta <= 0.0:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var bond := _companion.bond_value()
	if not _view.is_flying():
		_notice(delta, bond)
		_look_at_bridge(delta)
		return
	# ---- in flight
	if _pointing:
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false
	_companion.postpone_form_drift(8.0)
	if _moving() or _companion.pending_command() == "call" or _companion.current_form_species() != String(_reveal.get("species", "bird")):
		_view.request_end()
	if _companion.pending_command() == "":
		_companion.issue_command("guide", _companion.position, { "hold": true })
	var vp := _player.get_viewport_rect().size
	var st := _view.update(delta, _companion.position, vp, bond)
	for e in st["events"]:
		_on_event(String(e))
	var alt: float = st["alt"]
	var pos: Vector2 = st["pos"]
	if is_instance_valid(_bird):
		var step := pos - _last_pos
		if step.length() > 0.5:
			_bird.look = step.normalized()
		elif _view.phase == SkyView.Phase.STAY:
			_bird.look = Vector2.RIGHT
		_bird.lift = alt * float(_reveal.get("bird_lift", 220.0))
		_bird.position = pos - Vector2(0.0, _bird.lift)
		_bird.scale = Vector2.ONE * lerpf(1.0, 2.6, alt)
	_last_pos = pos
	var cam := _camera()
	if cam != null:
		cam.hold_view(pos + Vector2(0.0, -alt * 40.0), float(st["zoom"]))
	var layer := _layer()
	if layer != null and layer.air() != null:
		layer.air().set_picture(float(st["picture"]))
	_advance_reveal(delta)
	if not _view.is_flying():
		_land()


func _advance_reveal(delta: float) -> void:
	if _reveal_t < 0.0 or _reveal_t >= 1.0:
		return
	_reveal_t = minf(1.0, _reveal_t + delta / maxf(0.1, float(_reveal.get("reveal_secs", 3.0))))
	var layer := _layer()
	if layer != null:
		layer.set_bridge_reveal(_bridge_id, _reveal_t)


func _on_event(event: String) -> void:
	match event:
		"picture":
			_say("picture", true)
		"seen":
			_flown_seen = true
			_say("seen", false)
			_reveal_t = 0.0
			if _host != null and _host.has_method("reveal_sky_bridge"):
				_host.reveal_sky_bridge(_bridge_id)
		"landed":
			pass


## The bird is home: the real companion is back, the camera is handed back to the player, the picture goes.
func _land() -> void:
	_restore()
	_cooldown = 1.0
	if _flown_seen:
		_look_back = float(_reveal.get("look_back_secs", 3.0))
		_say("landed", true)
	else:
		_say("ended", true)
	_flown_seen = false


## Put everything a flight borrowed back: the camera's follow and zoom, the companion's body, the puppet and the
## picture. Safe to call at any time, any number of times.
func _restore() -> void:
	var cam := _camera()
	if cam != null:
		cam.end_hold()
	if is_instance_valid(_companion):
		_companion.visible = true
	if is_instance_valid(_bird):
		_bird.visible = false
	var layer := _layer()
	if layer != null and layer.air() != null:
		layer.air().set_picture(0.0)


## The secret is taken (or the world is being torn down): drop any flight on the spot.
func finish() -> void:
	if _view != null and _view.is_flying():
		_view.request_end()
	_restore()


func _exit_tree() -> void:
	# Leaving the world mid-flight must never leave a hidden companion or a camera stuck up in the sky.
	if is_instance_valid(_companion):
		_companion.visible = true
	var cam := _camera()
	if cam != null:
		cam.end_hold()


## Noticing the islet: as you come near, the companion stops and looks toward it, in any shape.
func _notice(delta: float, bond: float) -> void:
	var r := _view.notice(delta, _player.position, bond)
	if bool(r["point"]):
		_companion.point_at(r["target"], 1.0)
		_pointing = true
		if bool(r["started"]):
			_say("notice", true)
	elif _pointing:
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false


## After a flight that found the way, the companion looks at the head of the bridge a moment.
func _look_at_bridge(delta: float) -> void:
	if _look_back <= 0.0:
		return
	_look_back -= delta
	_companion.listen_toward(_head, 1.0)
	if _look_back <= 0.0:
		_say("bridge", true)


func _say(key: String, once: bool) -> void:
	if once:
		if _said.has(key):
			return
		_said[key] = true
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)
