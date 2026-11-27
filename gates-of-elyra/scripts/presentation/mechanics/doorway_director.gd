class_name DoorwayDirector
extends Node
## The LATE ARCH (Lingerlong's secret way): one arch out in the pool shows an evening sky in its doorway, and it
## only opens for your companion. This is the presentation half; the decisions live in the pure DoorwayGate
## (scripts/world). It:
##   * takes the order: a tap on the arch (a direct order, from anywhere it is on screen) or the radial's "Go look"
##     while you are near it (SecretDirector.can_go_look asks `can_go_look`);
##   * each frame turns the gate's answer into a "guide" command for the companion's brain (trot to the threshold,
##     then stand there looking in, ears up), reusing the Drifthallow lead and the NavAgent routing;
##   * while the gate owns the body (under the arch, in the picture, back out) PLACES it itself: its mind paused
##     exactly as Thimblewick's fetch does, the body hidden once it is in the picture and put on the evening
##     terrace, so a friend sees it walk to the arch and vanish (and, if they are on the terrace, sees it waiting
##     there). On your own screen it is drawn SMALL IN THE DOORWAY, between the picture and the frame
##     (ArchView.set_between): walking up into the painted evening, then turned to look back at you;
##   * glows the doorway softly while it is open, a pool of evening light spilling onto the water in front;
##   * the crossings: step into the open doorway from the front and you are both on the terrace (a short soft fade,
##     the sky goes to evening, the camera is put there, not slid); step into the terrace arch's doorway, from either
##     side, any time, and you are both back in the pool in the afternoon. The way back is never closed;
##   * as you come near the Late Arch the companion NOTICES it and points at it (DoorwayGate.notice, by bond).
## A Call ends the trip on the way there, or brings it back out of the picture early; a Pet on the way there is
## enjoyed and the trip carries on. Nothing here is networked but the ordinary positions (your real position IS
## on the terrace when you are there). All numbers and every line come from the spec's `doorway` block.
## It idles cheaply: far from both arches it does a couple of comparisons a frame, and the arch only redraws
## every frame while the companion is in the picture.

const VEIL_IN := 0.28            # seconds to the soft colour on a crossing...
const VEIL_OUT := 0.5            # ...and back out of it on the other side
const EVENING_VEIL := Color(0.78, 0.60, 0.80)
const AFTERNOON_VEIL := Color(1.0, 0.86, 0.72)
const GLOW := Color(1.0, 0.76, 0.54)
const HALO := Color(1.0, 0.70, 0.66)   # the rose of the picture's horizon, round the arch

var _host: Node
var _companion: CompanionView
var _player: PlayerView
var _world_art: WorldArt

var _gate: DoorwayGate
var _cfg: Dictionary = {}
var _lines: Dictionary = {}
var _late: ArchView = null
var _back: ArchView = null
var _through := Vector2.ZERO
var _back_to := Vector2.ZERO
var _beside := Vector2(-22, 14)
var _inside_at := Vector2(-7, -12)
var _inside_scale := 0.5
var _secret_id := ""
var _secret_line := ""

var _prev := Vector2.INF        # the player's feet last frame (INF: no last frame, e.g. just landed)
var _said := {}
var _controlling := false
var _pointing := false
var _crossing := false          # a fade is carrying us across; the gate waits
var _figure: Dictionary = {}    # what to draw in the doorway this frame ({} = nothing)
var _open := false
var _glow := 0.0                # the doorway's glow, eased 0..1
var _time := 0.0
var _hooked := false
var _veil: ColorRect = null


func setup(host: Node, companion: CompanionView, player: PlayerView, world_art: WorldArt) -> void:
	_host = host
	_companion = companion
	_player = player
	_world_art = world_art


## Lay the doorway out from the spec: its `doorway` block, the two arches, and the world's secret (for the line on
## a first arrival).
func configure(doorway: Dictionary, late: ArchView, back: ArchView, secret: Dictionary = {}) -> void:
	_cfg = doorway
	_lines = doorway.get("lines", {})
	_late = late
	_back = back
	_through = WorldData.to_vec2(doorway.get("through", [0, 0]))
	_back_to = WorldData.to_vec2(doorway.get("back_to", [0, 0]))
	_beside = WorldData.to_vec2(doorway.get("beside", [-22, 14]))
	_inside_at = WorldData.to_vec2(doorway.get("inside_at", [-7, -12]))
	_inside_scale = float(doorway.get("inside_scale", 0.5))
	_secret_id = String(secret.get("id", ""))
	_secret_line = String((secret.get("reveal", {}) as Dictionary).get("reveal_line", ""))
	_gate = DoorwayGate.new(WorldData.to_vec2(doorway.get("at", [0, 0])), WorldData.to_vec2(doorway.get("back_at", [0, 0])), doorway)
	_said = {}
	_prev = Vector2.INF


func gate() -> DoorwayGate:
	return _gate


## Whether "Go look" is on offer: the companion is yours, and you are near the Late Arch (or it is already off on
## its errand, so asking again says so instead of the button vanishing).
func can_go_look() -> bool:
	if _gate == null or _companion == null or _player == null or not _companion.is_met():
		return false
	return _gate.is_busy() or _gate.in_ask_range(_player.position)


## The player's ask ("Go look", or a tap on the arch): send the companion to the doorway.
func ask() -> void:
	if _gate == null or _companion == null or not _companion.is_met() or _crossing:
		return
	if _gate.is_busy():
		_say_always("busy")
		return
	if _gate.ask(_companion.bond_value()):
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false
		_say_always("set_off")


## A tap in the world: true (and the order given) when it is on the Late Arch.
func on_tap(world: Vector2) -> bool:
	if _gate == null or not _gate.is_tap_on_arch(world):
		return false
	if _companion == null or not _companion.is_met():
		return false
	ask()
	return true


func is_crossing() -> bool:
	return _crossing


## The controller tore the world down: hand the companion its body back, and leave the arch as it was.
func _exit_tree() -> void:
	_release()
	if is_instance_valid(_late):
		_late.set_between(Callable())
	if is_instance_valid(_veil):
		_veil.get_parent().queue_free()


## Per frame (the controller drives it).
func update(delta: float) -> void:
	if _gate == null or _player == null or _companion == null or delta <= 0.0:
		return
	if _crossing:
		return   # the fade is carrying us; nothing is judged until we have landed
	_time += delta
	var ctx := {
		"companion_pos": _companion.position, "player_pos": _player.position, "player_prev": _prev,
		"bond": _companion.bond_value(), "pending": _companion.pending_command(),
	}
	_prev = _player.position
	var r := _gate.update(delta, ctx)
	if _gate.is_busy():
		_companion.postpone_form_drift(20.0)   # the shape it went in as is the one you see in the picture
	if bool(r["control"]):
		_place(r["body"] as Dictionary)
	if _controlling and not _gate.is_controlled():
		_release()   # (the same frame it steps back out onto the threshold: its own again at once)
	if String(r["command"]) == "guide":
		_companion.issue_command("guide", r["target"], { "hold": bool(r["hold"]), "speed": float(r["speed"]) })
	if (r["look"] as Vector2).is_finite():
		_companion.listen_toward(r["look"], 1.0)
	_figure = r["figure"]
	_open = bool(r["open"])
	for e in r["events"]:
		_on_event(String(e))
	_update_doorway(delta)
	if bool(r["through"]):
		_cross(_through, EVENING_VEIL, true)
	elif bool(r["back"]):
		_cross(_back_to, AFTERNOON_VEIL, false)
	else:
		_update_notice(delta)


## While the gate owns the body: its mind paused, put where the gate says; once it is in the picture, hidden and
## set down on the evening terrace (where a friend's screen, which only knows its position, sees it waiting).
func _place(body: Dictionary) -> void:
	if not _controlling:
		_controlling = true
		_companion.set_process(false)
		_companion.velocity = Vector2.ZERO
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false
	var hidden := bool(body["hidden"])
	_companion.position = (_through + _beside) if hidden else (body["pos"] as Vector2)
	_companion.visible = not hidden
	if not hidden:
		_companion.queue_redraw()


func _release() -> void:
	if not _controlling or _companion == null or not is_instance_valid(_companion):
		return
	_controlling = false
	_companion.visible = true
	_companion.velocity = Vector2.ZERO
	_companion.set_process(true)


## The doorway's look: the small figure and the glow are drawn by the arch itself (between its picture and its
## frame) only while there is something to draw, so the arch is still a still picture the rest of the time.
func _update_doorway(delta: float) -> void:
	_glow = move_toward(_glow, 1.0 if _open else 0.0, delta / 0.6)
	var want := not _figure.is_empty() or _glow > 0.0
	if want != _hooked and is_instance_valid(_late):
		_hooked = want
		_late.set_between(Callable(self, "_draw_between") if want else Callable())


## Drawn by the Late Arch between its picture and its frame (`ci` is the arch; origin at its feet).
func _draw_between(ci: CanvasItem) -> void:
	if _glow > 0.0:
		var breath := 0.5 + 0.5 * sin(_time * 2.2)
		var g := smoothstep(0.0, 1.0, _glow)
		# a soft halo round the whole arch (drawn under the frame, so it shows only round its edges)...
		SoftGlow.draw(ci, Vector2(0, -60), 66.0, Color(HALO.r, HALO.g, HALO.b, (0.55 + 0.15 * breath) * g), 1.2)
		# ...the evening in the doorway brightened, lamps and all (the frame keeps it inside the opening)...
		if ci is ArchView:
			(ci as ArchView).draw_picture_again(Color(1.5, 1.25, 1.1, (0.30 + 0.12 * breath) * g))
		SoftGlow.draw(ci, Vector2(0, -36), 26.0, Color(GLOW.r, GLOW.g, GLOW.b, (0.30 + 0.12 * breath) * g), 1.5)
		# ...and its light spilling out onto the water in front
		SoftGlow.draw(ci, Vector2(0, 8), 52.0, Color(GLOW.r, GLOW.g * 0.88, GLOW.b, (0.60 + 0.12 * breath) * g), 0.32)
	if _figure.is_empty():
		return
	var k := clampf(float(_figure.get("k", 0.0)), 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var feet := Vector2(0, -1).lerp(_inside_at, e)
	var s := lerpf(1.0, _inside_scale, e)
	var tint := Color.WHITE.lerp(Color(0.86, 0.78, 0.96), e)
	# a soft dusk shadow under it, on the painted floor
	SoftGlow.draw(ci, feet + Vector2(0, 0.5), 9.0 * s, Color(0.17, 0.16, 0.36, 0.30), 0.35)
	var look := Vector2.UP if String(_figure.get("facing", "up")) == "up" else Vector2.DOWN
	var walking := bool(_figure.get("walking", false))
	var pose := _companion.reflection_pose()
	if pose.is_empty():
		_draw_plain_figure(ci, feet, s, tint)
		return
	var sheet: Dictionary = (pose["sheet"] as Dictionary).duplicate()
	sheet["scale"] = float(sheet.get("scale", 1.0)) * s
	PalSprite.draw(ci, pose["tex"], {
		"look": look, "speed": 40.0 if walking else 0.0, "time": _time,
		"offset": feet - Vector2(0, PalSprite.FOOT_Y), "modulate": tint,
	}, sheet)


## No animal sheet (the classic rig): a small soft silhouette in the companion's place.
func _draw_plain_figure(ci: CanvasItem, feet: Vector2, s: float, tint: Color) -> void:
	var coat := Color(0.96, 0.90, 0.84) * tint
	ci.draw_circle(feet + Vector2(0, -7.0 * s), 7.0 * s, coat, true, -1.0, true)
	ci.draw_circle(feet + Vector2(0, -16.0 * s), 5.0 * s, coat, true, -1.0, true)


## Carry the player (and the companion, beside them) across: a short soft fade, set down, the camera put there.
func _cross(to: Vector2, veil: Color, to_evening: bool) -> void:
	_crossing = true
	_ensure_veil()
	_veil.color = Color(veil.r, veil.g, veil.b, 0.0)
	var tw := create_tween()
	tw.tween_property(_veil, "color:a", 1.0, VEIL_IN)
	tw.tween_callback(func() -> void: _land(to, to_evening))
	tw.tween_property(_veil, "color:a", 0.0, VEIL_OUT)
	tw.tween_callback(func() -> void: _crossing = false)


## Set both down at `to` (the gate is idle again by now), with everything that follows a place rather than a walk.
func _land(to: Vector2, to_evening: bool) -> void:
	_release()
	_figure = {}
	_open = false
	_glow = 0.0
	_update_doorway(0.0)
	_player.position = to
	_player.velocity = Vector2.ZERO
	_companion.position = to + _beside
	_companion.velocity = Vector2.ZERO
	_companion.visible = true
	var nav: Variant = _companion.get("_nav_agent")
	if nav != null:
		nav.reset()
	_prev = Vector2.INF
	var cam: Variant = _host.get("_camera") if _host != null else null
	if cam is CameraRig:
		(cam as CameraRig).snap_to(to)
	var pg: PlazaGround = _world_art.plaza_ground() if _world_art != null else null
	if pg != null:
		pg.settle_evening()
	if to_evening:
		var fresh := _secret_id != "" and not Net.has_discovery(_secret_id) and _secret_line != ""
		if fresh and not _said.has("secret"):
			_said["secret"] = true
			_host.show_hint(_secret_line)
		else:
			_say_always("through")
		_companion.delight_at(to + Vector2(0, -40))
	else:
		_say_always("back")


## The soft colour a crossing fades through: a full-screen rect of our own, under the HUD and over the world.
func _ensure_veil() -> void:
	if is_instance_valid(_veil):
		return
	var layer := CanvasLayer.new()
	layer.name = "DoorwayVeil"
	layer.layer = 5
	add_child(layer)
	_veil = ColorRect.new()
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.color = Color(1, 1, 1, 0)
	layer.add_child(_veil)


func _on_event(event: String) -> void:
	match event:
		"sniff":
			_say("sniff")
		"inside":
			_companion.delight_at(_gate.door_middle())
			_say("inside")
		"came_out":
			_companion.delight_at(_player.position)
			_say_always("came_out")
		"called_out":
			_say_always("called_out")
		"called_off":
			_say_always("called_off")
		"lost_way":
			_say_always("lost_way")
		"plain_through":
			_say("plain_through")


## The companion noticing the Late Arch as you come near: a held point toward its doorway, released when the
## notice ends or a trip begins.
func _update_notice(delta: float) -> void:
	if not _companion.is_met():
		return
	var n := _gate.notice(delta, _player.position, _companion.bond_value())
	if bool(n["point"]):
		_companion.point_at(n["target"], 1.0)
		_pointing = true
		if bool(n["started"]):
			_say("notice")
	elif _pointing:
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false


## A line, once per visit (a missing line says nothing).
func _say(key: String) -> void:
	if _said.has(key):
		return
	_said[key] = true
	_say_always(key)


func _say_always(key: String) -> void:
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)
