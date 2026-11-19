class_name AlignDirector
extends Node
## Farmeadow's secret on screen: the skylark painted across a little farmyard (an old barn wall, a scarecrow, straw
## bales, a dry-stone wall), which only joins up into one picture from one spot looking south. Drives the pure AlignGate each frame, and does what it says:
##   * your companion points at the spot now and then as you come near, then trots over and sits right on it;
##   * standing still there, looking near enough south, the view is drawn exactly onto the spot and heading
##     (PerspectiveView.set_magnet: the picture clicks together);
##   * held for a couple of seconds, the painted lark lifts off the farmyard (LarkFlight) and flutters down at your
##     feet, where it's the secret's prop (`lark_landed`; SecretDirector reveals it).
## Found already, the picture still lines up when you stand there (a toy), but nothing more happens.

signal lark_landed(pos: Vector2, line: String)

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView
var _gate: AlignGate
var _reveal: Dictionary = {}
var _found := false
var _magnet_on := false
var _pointing := false
var _told := {}
var _flight: LarkFlight
var _perched: LarkFlight
var _secret_id := ""


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


func configure(secret: Dictionary, found: bool = false) -> void:
	_reveal = secret.get("reveal", {})
	_secret_id = String(secret.get("id", ""))
	_found = found
	_gate = AlignGate.new(_reveal)
	if found:
		_empty_the_picture()   # the lark flew off it once already: its sky is empty now


func gate() -> AlignGate:
	return _gate


func update(delta: float) -> void:
	if _perched != null and _secret_id != "" and Net.has_discovery(_secret_id):
		_perched.queue_free()   # picked up: it's gone home
		_perched = null
	var pv := PerspectiveView.active
	if pv == null or _gate == null or _player == null or _flight != null:
		return
	var face := _player.facing()
	var heading := atan2(face.x, -face.y)  # the way you face, as a bearing
	var out := _gate.update(delta, _player.position, _player.velocity.length(), heading, pv.eye(), pv.rig.yaw, _companion.bond_value())
	var want: bool = out["capture"]
	if want:
		# the view's focus level with you on the line, its eye on the one point the picture lines up from
		var mv := _gate.magnet_view(_player.position)
		pv.set_magnet(true, mv[0], _gate.facing, mv[1])
	elif _magnet_on:
		pv.set_magnet(false)
	if want != _magnet_on:
		_magnet_on = want
		if want and not _found:
			_tell("settle")
	if _found:
		if out["completed"]:  # a toy now: it lines up, and can line up again
			_gate.done = false
			_gate.held = 0.0
		return
	# your companion's part
	if out["point"] != _pointing:
		_pointing = out["point"]
		_companion.point_at(_gate.spot if _pointing else Vector2.ZERO, 0.8 if _pointing else 0.0)
		if _pointing:
			_tell("notice")
	if out["visit"]:
		_companion.issue_command("visit", _gate.spot)
		_tell("visit")
	if out["completed"]:
		_lift_the_lark(pv)


## The painted lark comes off the farmyard: a little bird starting exactly where the painted one is (on the ray
## through it, at the distance of the wall it's mostly painted on, as big as it's painted) and fluttering down to
## land at your feet.
func _lift_the_lark(pv: PerspectiveView) -> void:
	var proj := pv.proj
	var screen := Vector2(float(_reveal.get("lark_screen_x", -8.0)), float(_reveal.get("lark_screen_y", -9.0)))
	var z := float(_reveal.get("lark_depth", 380.0))
	# The picture was laid out for the camera standing on the spot (focal = eye_back with no tilt). From anywhere
	# else on the line the eye is the same point and only the zoom differs, so the painted lark's place in the
	# world comes out the same: work it out with the spot camera's focal, from the eye.
	var f := _gate.cfg("eye_back") * cos(proj.pitch) + proj.height * sin(proj.pitch)
	var eye := _gate.eye_point()
	var ground := eye + proj.forward() * z + proj.right() * (screen.x * z / f)
	var lift := (proj.shift + f * proj.height / z - screen.y) * z / f
	# it lands beside you (to your right on screen, a step ahead), wherever on the line you stand
	var land := _player.position + proj.right() * 28.0 + proj.forward() * 14.0
	_flight = LarkFlight.new()
	_flight.name = "LarkFlight"
	_flight.start(ground, lift, float(_reveal.get("lark_span", 60.0)) * z / f, land)
	_flight.landed.connect(_on_landed.bind(land))
	_companion.point_at(Vector2.ZERO, 0.0)
	(_player.get_parent() as Node).add_child(_flight)
	_empty_the_picture()   # it comes off the wall and the bales: they're left with just the sun's ring


## Swap the things the lark was painted across for their versions without it (the reveal's `bare`).
func _empty_the_picture() -> void:
	var bare: Dictionary = _reveal.get("bare", {})
	if bare.is_empty() or _player == null:
		return
	for c in (_player.get_parent() as Node).get_children():
		var t := c as TreeView
		if t == null or t.tex == null:
			continue
		var id := t.tex.resource_path.get_file().get_basename()
		if bare.has(id) and ResourceLoader.exists(String(bare[id])):
			t.tex = load(String(bare[id]))
			t.queue_redraw()


func _on_landed(land: Vector2) -> void:
	if PerspectiveView.active != null:
		PerspectiveView.active.set_magnet(false)
	_magnet_on = false
	_perched = _flight   # it stays standing in the grass until it's picked up
	_flight = null
	lark_landed.emit(land, String(_reveal.get("reveal_line", "")))


func _tell(key: String) -> void:
	if _told.has(key):
		return
	_told[key] = true
	var line := String((_reveal.get("lines", {}) as Dictionary).get(key, ""))
	if line != "" and _host != null and _host.has_method("show_hint"):
		_host.show_hint(line)


func _exit_tree() -> void:
	if _magnet_on and PerspectiveView.active != null:
		PerspectiveView.active.set_magnet(false)
