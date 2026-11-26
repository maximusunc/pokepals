class_name FacetsDirector
extends Node
## THE UNFINISHED (Glintwold's secret) in play: a great stone in loose shards over the Turning Floor, which only
## looks whole from two places at once. Half of its shards answer to whoever stands nearest one unmarked spot,
## half to whoever stands nearest the other; both halves home and held, it closes, and the offcut drops at its
## foot. This is the presentation half; the decisions live in the pure FacetJoin (scripts/world). It:
##   * stands the HeartstoneView up in the Scenery layer at the stone's foot and feeds it, each frame you are
##     near, the shards' offsets and each half's closeness, worked out from where you, your companion and every
##     friend's pair stand (so friends can close it together without directing anyone);
##   * PLACES the companion (Lanternfold's tap-to-stand): a tap on empty ground inside the Turning Floor sends it
##     to stand there (taps arrive already mapped to the ground, see world_controller._on_world_tap); a tap close
##     to its mark settles it right onto it. Or you DELEGATE: "Go look" near the stone sends it to find its mark
##     by itself, landing well off with a fresh bond and nearly true with a deep one (then nudge it with a tap);
##   * keeps that standing from being broken by what a player naturally does: a CALL ends it (it comes to you), a
##     PET is enjoyed and it stays, its autonomous form drift is held off, and wandering far lets it go;
##   * as you come near, by bond, your companion glances at its mark now and then;
##   * says a few short lines at the right moments (the world's `reveal.lines` first, these defaults after);
##   * on completion closes the view (snap, flash, light across the faces) and, the first time, `offcut_fell`
##     when the chip has dropped, which the SecretDirector turns into the offcut, claimed the usual way.
## Found already (a return visit): the stone hangs apart again and can still be closed, a quiet toy, but nothing
## falls (Farmeadow's lark and Hollowsong's howl are the precedent). Closed once, it stays whole for the visit.
## Everything is personal and display-only: nothing here is networked; the server checks "this world, standing
## at it" when the offcut is claimed.

signal offcut_fell(pos: Vector2, line: String)

const RELEASE_DISTANCE := 560.0
const DEFAULT_LINES := {
	"near": "The pieces of the stone shift a little as you move, as if you were walking round something real.",
	"notice": "Your companion stops and looks across the Turning Floor, at one particular spot, as if it can see the stone from there.",
	"half": "Half of it has closed. The other half is waiting on someone else.",
	"closing": "The pieces slide together. Hold still.",
	"stand": "Your companion stands where you showed it, and looks up at the stone.",
	"go_look": "Your companion trots round the Turning Floor, looking up at the stone, and settles somewhere on the far side.",
	"called": "Your companion leaves its place on the floor and comes to you.",
	"let_go": "Your companion stops waiting on the floor and follows you.",
	"again": "The pieces close again for a moment, just for the two of you. Nothing falls this time; the offcut is already at home.",
	"far": "Go look works best from nearer the stone.",
}

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _join: FacetJoin
var _view: HeartstoneView
var _block: Dictionary = {}
var _reveal: Dictionary = {}
var _lines: Dictionary = {}
var _chip_at := Vector2.ZERO
var _found := false
var _said := {}
var _posing := false
var _pose_at := Vector2.ZERO
var _pet_pause := 0.0
var _release_in := -1.0
var _remote_t := 0.0
var _remote: Array = []         # friends' players and companions, refreshed twice a second
var _idle := false
var _frame := Vector2.ZERO      # the camera's eased offset toward the stone (px)


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


## Lay the stone out from the spec's `heartstone` block and the secret. `found`: the offcut is already at home.
func configure(heartstone: Dictionary, secret: Dictionary, found: bool) -> void:
	_block = heartstone
	_reveal = secret.get("reveal", {})
	_lines = _reveal.get("lines", {})
	_chip_at = WorldData.to_vec2(secret.get("position", heartstone.get("position", [0, 0])))
	_found = found
	_said = {}
	_posing = false
	_release_in = -1.0
	if _view == null:
		_view = HeartstoneView.new()
		_view.name = "Heartstone"
		_view.chip_landed.connect(_on_chip_landed)
		if _player != null and _player.get_parent() != null:
			_player.get_parent().add_child(_view)   # the Scenery layer: y-sorted with everyone else
	_view.position = WorldData.to_vec2(heartstone.get("position", [0, 0]))
	_join = FacetJoin.new(heartstone, _view.build())
	_view.set_rest(_join.offsets({}))


func join() -> FacetJoin:
	return _join


func view() -> HeartstoneView:
	return _view


func _exit_tree() -> void:
	if is_instance_valid(_view):
		_view.queue_free()
	var cam := _camera()
	if cam != null:
		cam.offset = Vector2.ZERO


## The offcut has been found (here, or on another device): from now on closing it drops nothing.
func set_found() -> void:
	_found = true


## The offcut has been taken: let the companion go.
func finish() -> void:
	_posing = false


func is_posing() -> bool:
	return _posing


func release() -> void:
	_posing = false


## Whether "Go look" is on offer: the stone still in pieces, and you near enough to it.
func can_ask() -> bool:
	return _join != null and not _join.done and _player != null \
		and _player.position.distance_to(_join.center) <= _join.cfg("reach") * 1.6


## "Go look": your companion goes to find its own mark, as true as the bond lets it.
func ask() -> void:
	if _join == null or _companion == null or _join.done:
		return
	if not can_ask():
		_say("far", false)
		return
	_stand(_join.go_look_target(_companion.bond_value(), randf() * TAU))
	_say("go_look", false)


## A tap on empty ground: inside the Turning Floor it stands your companion there. Returns whether it did.
func on_ground_tap(world: Vector2) -> bool:
	if _join == null or _companion == null or _join.done or not _join.on_floor(world):
		return false
	_stand(_join.settle_target(world))
	_say("stand", true)
	return true


func _stand(at: Vector2) -> void:
	_posing = true
	_pose_at = at
	_pet_pause = 0.0
	_release_in = -1.0
	_companion.issue_command("guide", at, { "hold": false })


func update(delta: float) -> void:
	if _join == null or _companion == null or _player == null or delta <= 0.0:
		return
	_update_standing(delta)
	# Far from the stone nothing slides (it hangs at its resting spread): leave it be.
	_update_camera(delta)
	var far := _player.position.distance_to(_join.center) > _join.cfg("reach") + 360.0
	if far and not _posing:
		if not _idle:
			_idle = true
			_view.set_idle()
		return
	_idle = false
	_remote_t -= delta
	if _remote_t <= 0.0:
		_remote_t = 0.5
		_refresh_remote()
	var actors: Array = [_player.position, _companion.position]
	for a in _remote:
		if is_instance_valid(a):
			actors.append((a as Node2D).position)
	var r := _join.update(delta, actors, _companion.bond_value())
	_view.set_state(r["offsets"], r["closeness"], r["home"])
	for e in r["events"]:
		_on_event(String(e))
	if r["glance"]:
		_companion.glance_toward(_join.marks["companion"])
		_say("notice", true)


## The view is only 360 px tall and the marks stand well off the stone, so while you are near it the camera leans
## toward the stone's middle (Camera2D.offset, eased), enough to keep both you and the whole stone in sight.
func _update_camera(delta: float) -> void:
	var cam := _camera()
	if cam == null:
		return
	var mid := _join.center + Vector2(0, float(_block.get("camera_mid", -80.0)))
	var d := _player.position.distance_to(_join.center)
	var k := 1.0 - smoothstep(_join.cfg("reach"), _join.cfg("reach") + 160.0, d)
	var want := ((mid - _player.position) * 0.5).limit_length(float(_block.get("camera_lean", 130.0))) * k
	if want == Vector2.ZERO and _frame == Vector2.ZERO:
		return
	_frame = _frame.move_toward(want, delta * 160.0)
	cam.offset = _frame


func _camera() -> Camera2D:
	var cam: Variant = _host.get("_camera") if _host != null and is_instance_valid(_host) else null
	return cam as Camera2D if cam is Camera2D else null


func _update_standing(delta: float) -> void:
	var pc := _companion.pending_command()
	if _posing and pc == "come":
		_posing = false
		_say("called", false)
	elif pc == "pet":
		_pet_pause = float(_reveal.get("pet_pause", 3.0))
	_pet_pause = maxf(0.0, _pet_pause - delta)
	if _posing and _player.position.distance_to(_companion.position) > RELEASE_DISTANCE:
		_posing = false
		_say("let_go", false)
	if _posing:
		_companion.postpone_form_drift(30.0)
		if _pet_pause <= 0.0 and pc != "come" and pc != "pet":
			_companion.issue_command("guide", _pose_at, { "hold": false })
	if _release_in > 0.0:
		_release_in -= delta
		if _release_in <= 0.0:
			_posing = false


func _refresh_remote() -> void:
	_remote = []
	var presence: Variant = _host.get("_presence_dir") if _host != null else null
	if presence != null and presence is Object and (presence as Object).has_method("remote_actors"):
		_remote = presence.remote_actors()


func _on_event(event: String) -> void:
	match event:
		"near":
			_say("near", true)
		"half":
			_say("half", true)
		"both":
			_say("closing", true)
		"complete":
			_view.complete(not _found, _chip_at)
			if _found:
				_say("again", true)
			if _posing:
				_release_in = 3.0


func _on_chip_landed(pos: Vector2) -> void:
	if not _found:
		offcut_fell.emit(pos, String(_reveal.get("reveal_line", "")))


## A line, once per visit when `once` (the world's lines first, then ours).
func _say(key: String, once: bool) -> void:
	if once:
		if _said.has(key):
			return
		_said[key] = true
	var line := String(_lines.get(key, DEFAULT_LINES.get(key, "")))
	if line != "" and _host != null and _host.has_method("show_hint"):
		_host.show_hint(line)
