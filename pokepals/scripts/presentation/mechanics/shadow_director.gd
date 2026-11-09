class_name ShadowDirector
extends Node
## The SHADOW MURAL (Lanternfold's secret): a flock of birds crossing a cliff face, one missing, and a door in
## the cliff that opens when the gap is filled. Your companion is the key: pick its FORM, stand it in the great
## lantern's light, and its shadow falls on the screen; only the bird's, from the right place, fits the gap.
## This is the presentation half; the decisions live in the pure ShadowCast / ShadowMask / MuralGuide
## (scripts/world). It:
##   * PLACES the companion: a tap on the lit ground sends it to stand there (Stage taps arrive from the world
##     controller as `on_ground_tap`, only when the tap was empty ground, so props and players are never
##     shadowed by it). It walks over by its own legs (the Drifthallow `guide` order, routed round things by the
##     NavAgent) and stays put, re-issued each frame. A bird told to stand NEAR the right place settles onto it
##     (MuralGuide.settle_target): only the right animal is helped, so the form still matters;
##   * keeps that standing from being broken by what a player naturally does (Underroot's lesson, Dozewood's):
##     a CALL ends it gracefully (it comes to you), a PET is enjoyed and the standing carries on after a few
##     seconds, a form change keeps the place (it re-settles in its new shape), and its autonomous form drift is
##     held off while it stands (the Drifthallow fox);
##   * feeds the guide where the companion stands, what it wears and how still it is, and turns the answer into
##     the screen's glow (`ShadowScreenView.set_fit`), the first-time hint lines, the companion NOTICING the gap
##     and pointing at it as you come near, and, when the gap is filled, `mural_done`;
##   * lifts the camera's gaze toward the mural while you stand on the stage (Camera2D.offset, eased), because the
##     view is only 360 px tall and the mural stands well north of the spot you watch from;
##   * keeps the screen's shadows current: every player and companion in the world (you, and friends' pairs)
##     throws one, which is part of the fun.
## Everything is personal and display-only: a friend sees your companion stand there and sees the screen as it
## is for them; the mural itself is not networked. The numbers all come from the secret's `reveal` block, so
## the next shadow world is data. Whether you may take what is behind the door stays the server's call.

signal mural_done

## How far (px) the player may wander from where the companion stands before it lets go and follows again.
const RELEASE_DISTANCE := 760.0

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _guide: MuralGuide
var _reveal: Dictionary = {}
var _lines: Dictionary = {}
var _screen: ShadowScreenView = null
var _said := {}
var _found := false
var _posing := false
var _pose_want := Vector2.ZERO          # where it was told to stand (before any settle)
var _pet_pause := 0.0
var _pointing := false
var _sync_t := 0.0
var _release_in := -1.0                 # seconds until the standing is let go after the gap is filled
var _last_fit := 0.0
var _lift := 0.0                        # the camera's eased upward offset (px)


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


## Lay out this world's mural from the secret's reveal block. `found`: the gap was filled on an earlier visit, so
## the mural is simply complete and the door open, and the shadows stay a quiet toy.
func configure(secret: Dictionary, found: bool = false) -> void:
	_reveal = secret.get("reveal", {})
	_lines = _reveal.get("lines", {})
	_guide = MuralGuide.new(_reveal)
	_guide.set_masks(_build_masks())
	_said = {}
	_found = found
	_posing = false
	_pet_pause = 0.0
	_release_in = -1.0
	_bind()


func guide() -> MuralGuide:
	return _guide


## The screen's view (Scenery's building), so the shadows can fall on it.
func bind_screen(view: ShadowScreenView) -> void:
	_screen = view
	_bind()


func _bind() -> void:
	if _screen == null or _guide == null:
		return
	var info := PalView.sheet_info(_guide.fill_species(), 0)
	_screen.bind_mural(_guide, info)
	if _found:
		_screen.complete(true)
	_sync_casters()


## The gap was filled on another device (or this visit's join list says so): the mural is simply complete.
func set_found() -> void:
	_found = true
	if _screen != null:
		_screen.complete(true)


func mural_complete() -> bool:
	return _guide != null and (_guide.is_done() or _found)


## Silhouettes of every animal the companion can wear: the right-facing profile (the fill species' flight row,
## every beat of it laid over each other, since its shadow flaps), read off the real sheets.
func _build_masks() -> Dictionary:
	var out := {}
	for f in PalView.available_forms():
		var species := String(f["species"])
		var m := _mask_of(species)
		if m != null:
			out[species] = m
	return out


func _mask_of(species: String) -> ShadowMask:
	var info := PalView.sheet_info(species, 0)
	if info.is_empty():
		return null
	var tex: Texture2D = info["tex"]
	var img: Image = tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var sheet: Dictionary = info["sheet"]
	var frame: Array = sheet.get("frame", [32, 32])
	var fw := int(frame[0])
	var fh := int(frame[1])
	var rows: Dictionary = sheet.get("rows", {})
	var fly_row := int(sheet.get("fly_row", -1))
	var row := fly_row if (species == _guide.fill_species() and fly_row >= 0) else int(rows.get("right", 2))
	var cols := int(sheet.get("cols", 8)) if row == fly_row else 1
	var alpha := PackedByteArray()
	alpha.resize(fw * fh)
	for c in cols:
		for y in fh:
			for x in fw:
				var a := int(img.get_pixel(c * fw + x, row * fh + y).a * 255.0)
				if a > int(alpha[y * fw + x]):
					alpha[y * fw + x] = a
	return ShadowMask.from_alpha(fw, fh, alpha, float(fw) * 0.5, float(fh) - 8.0)


## Whether a tap on empty ground at `world` stands the companion on the stage: true when it did (the caller then
## treats the tap as spent). Only ground the lantern lights counts, and only south of the screen's foot.
func on_ground_tap(world: Vector2) -> bool:
	if _guide == null or _companion == null or _screen == null:
		return false
	var face := _guide.face()
	if world.y < float(face["base_y"]) + 18.0 or not ShadowCast.in_cone(face, _guide.lantern(), world):
		return false
	_posing = true
	_pose_want = world
	_pet_pause = 0.0
	_release_in = -1.0
	_issue(_stand_at())
	_say("stage", true)
	return true


## Where it stands now: the tapped place, settled onto the spot if it is the right animal near enough.
func _stand_at() -> Vector2:
	return _guide.settle_target(_companion.current_form_species(), _pose_want)


func _issue(at: Vector2) -> void:
	_companion.issue_command("guide", at, { "hold": false })


func is_posing() -> bool:
	return _posing


## Let the standing go (the companion follows you again).
func release() -> void:
	_posing = false


func update(delta: float) -> void:
	if _guide == null or _companion == null or _player == null or delta <= 0.0:
		return
	# What a player naturally does must not be swallowed by our own per-frame order (the brain's command slot
	# holds ONE order): a Call ends the standing, a Pet is enjoyed and the standing resumes a few seconds later.
	var pc := _companion.pending_command()
	if _posing and pc == "come":
		_posing = false
		_say("called", false)
	elif pc == "pet":
		_pet_pause = float(_reveal.get("pet_pause", 3.0))
	_pet_pause = maxf(0.0, _pet_pause - delta)
	if _posing and _player.position.distance_to(_companion.position) > float(_reveal.get("release_distance", RELEASE_DISTANCE)):
		_posing = false
		_say("let_go", false)
	if _posing:
		_companion.postpone_form_drift(float(_reveal.get("drift_hold", 30.0)))
		if _pet_pause <= 0.0 and pc != "come" and pc != "pet":
			_issue(_stand_at())

	var species := _companion.current_form_species()
	var r := _guide.update(delta, species, _companion.position, _companion.velocity.length(), _player.position, _companion.bond_value())
	_last_fit = float(r["fit"])
	if _screen != null:
		_screen.set_fit(float(r["fit"]), float(r["filling"]))
	for e in r["events"]:
		_on_event(String(e))
	if bool(r["point"]):
		_companion.point_at(r["target"], 1.0)
		_pointing = true
	elif _pointing:
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false
	if _release_in > 0.0:
		_release_in -= delta
		if _release_in <= 0.0:
			_posing = false
	_update_camera(delta)
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.5
		_sync_casters()


## Lift the camera toward the mural while you are on the stage (in the lantern's light or just short of it),
## and let it back down when you leave. Camera2D.offset is the framing's own free knob; nothing else uses it.
func _update_camera(delta: float) -> void:
	var cam: Variant = _host.get("_camera") if _host != null else null
	if cam == null or not (cam is Camera2D):
		return
	var face := _guide.face()
	var p := _player.position
	var on_stage: bool = p.y > float(face["base_y"]) and p.y < _guide.lantern().y + 50.0 and absf(p.x - _guide.lantern().x) < 260.0
	var want := -float(_reveal.get("camera_lift", 60.0)) if on_stage else 0.0
	_lift = move_toward(_lift, want, delta * 70.0)
	(cam as Camera2D).offset = Vector2(0.0, _lift)


func _exit_tree() -> void:
	var cam: Variant = _host.get("_camera") if _host != null and is_instance_valid(_host) else null
	if cam != null and cam is Camera2D:
		(cam as Camera2D).offset = Vector2.ZERO


func _on_event(event: String) -> void:
	match event:
		"arrive", "shadow", "close", "wrong", "holding", "notice":
			_say(event, true)
		"complete":
			if _screen != null:
				_screen.complete()
			if _posing:
				_release_in = float(_reveal.get("release_after", 3.0))
			if not _found:
				mural_done.emit()


## The shadows on the screen: you and your companion, and every friend's pair in the world.
func _sync_casters() -> void:
	if _screen == null or not is_instance_valid(_screen):
		return
	var list: Array = [{ "node": _player, "kind": "player" }, { "node": _companion, "kind": "companion" }]
	var presence: Variant = _host.get("_presence_dir") if _host != null else null
	if presence != null and presence is Object and presence.has_method("remote_actors"):
		for a in presence.remote_actors():
			if a is PlayerView:
				list.append({ "node": a, "kind": "player" })
			elif a is CompanionView:
				list.append({ "node": a, "kind": "companion" })
	_screen.sync_casters(list)


## The secret has been taken: stop pointing, and let the companion go.
func finish() -> void:
	_posing = false
	if _companion != null:
		_companion.point_at(Vector2.ZERO, 0.0)


## A hint line, once per visit when `once` (the lines are the world's; a missing one says nothing).
func _say(key: String, once: bool) -> void:
	if once:
		if _said.has(key):
			return
		_said[key] = true
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)
