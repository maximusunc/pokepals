class_name HowlDirector
extends Node
## The HOWL (Hollowsong's secret): in wolf form your companion howls on command, the canyon howls back, and
## one echo comes from where there is no wall: a hidden cave. This is the presentation half; the decisions
## live in the pure EchoField / EchoGuide (scripts/world). It:
##   * answers the radial's "Howl": in wolf form the companion stands and howls (a gaze up, stilled body,
##     small arcs off its head), the guide works out the answer, and EchoRipples draws it;
##   * in any OTHER form says, kindly, that a wolf's voice would carry here (the radial offers Howl in every
##     form so it is discoverable; only a wolf can);
##   * tells friends: Net.send_howl() (the server stamps where), and a friend's howl arriving
##     (Net.howl_heard) draws the same ripples here, including the wrong one, so two players howling from
##     two places find the cave much sooner;
##   * says the first-time hint lines (the canyon answers, the wrong answer, silence, the cave);
##   * makes the companion NOTICE the cave as you come near, in any shape, and when you walk up to it opens
##     the crack in the cliff (CliffView.open_cave) and tells the SecretDirector (`cave_opened`), which
##     brings up the answering stone. Once found, howling stays a quiet toy; only the stone is gone.
## Everything is personal and display-only apart from the relayed howl itself. The numbers all come from the
## secret's `reveal` block in the world spec.

signal cave_opened

## Seconds the companion stays still and holds its pose for a howl.
const HOWL_POSE := 1.5

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _guide: EchoGuide
var _ripples: EchoRipples
var _reveal: Dictionary = {}
var _lines: Dictionary = {}
var _cliff: CliffView = null
var _said := {}
var _howl_t := 0.0                 # seconds left on the howl pose
var _react: Array = []             # [{ left: float, pos: Vector2 }]: the companion glancing at a wrong answer as it arrives
var _later: Array = []             # [{ left: float, key: String }]: hint lines held until the thing they describe arrives
var _pointing := false
var _found := false
var _last_cd_hint := -100.0
var _clock := 0.0


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


## Lay out this world's canyon from the secret's reveal block (walls, cave, numbers). `found`: the secret was
## found on an earlier visit, so the cave is simply open and only the toy is left.
func configure(secret: Dictionary, found: bool = false) -> void:
	_reveal = secret.get("reveal", {})
	_lines = _reveal.get("lines", {})
	var cave: Dictionary = _reveal.get("cave", {})
	var mouth := WorldData.to_vec2(cave.get("mouth", secret.get("position", [0, 0])))
	var origin := WorldData.to_vec2(cave.get("origin", cave.get("mouth", secret.get("position", [0, 0]))))
	_guide = EchoGuide.new(_reveal.get("walls", []), origin, mouth, _reveal)
	_said = {}
	_howl_t = 0.0
	_react = []
	_later = []
	_found = found
	_clock = 0.0
	if is_instance_valid(_ripples):
		_ripples.queue_free()
	_ripples = EchoRipples.new()
	_ripples.name = "EchoRipples"
	_host.add_child(_ripples)
	_ripples.configure(_reveal)
	if not Net.howl_heard.is_connected(_on_howl_heard):
		Net.howl_heard.connect(_on_howl_heard)
	if found:
		_guide.update(0.0, mouth, 0.0)   # already open
		_found_open()


func guide() -> EchoGuide:
	return _guide


func ripples() -> EchoRipples:
	return _ripples


## The cliff whose face holds the cave (Scenery's building view), so it can open when the time comes.
func bind_cliff(cliff: CliffView) -> void:
	_cliff = cliff
	if _found or (_guide != null and _guide.is_revealed()):
		_found_open()


func _found_open() -> void:
	if _cliff != null:
		_cliff.snap_open()


func cave_is_open() -> bool:
	return _guide != null and _guide.is_revealed()


## The radial's Howl. A wolf howls; any other shape cannot, and the hint says why.
func try_howl() -> void:
	if _guide == null or _player == null or _companion == null:
		return
	if _companion.current_form_species() != "wolf":
		_companion.glance_toward(_nearest_wall_point())
		_say("not_wolf", false)
		return
	var bond := _companion.bond_value()
	var r := _guide.howl(_companion.position, _player.position, bond)
	if not bool(r["ok"]):
		if _clock - _last_cd_hint > 6.0:
			_last_cd_hint = _clock
			_say("cooldown", false)
		return
	_howl_t = HOWL_POSE
	_ripples.add_howl(_companion.position, _player.position, r, false)
	Net.send_howl()
	var wrong: Dictionary = r["wrong"]
	for e in r["events"]:
		# the first wrong answer is told when it ARRIVES, not when the howl leaves
		if String(e) == "wrong" and not wrong.is_empty():
			_later.append({ "left": float(wrong["arrive"]), "key": "wrong" })
		else:
			_on_event(String(e))
	if not wrong.is_empty():
		# the companion turns its head to the wrong answer as it arrives
		_react.append({ "left": float(wrong["arrive"]) - 0.2, "pos": wrong["origin"] })


## A friend's howl, heard here: the same ripples, fainter.
func _on_howl_heard(x: float, y: float) -> void:
	if _guide == null:
		return
	var at := Vector2(x, y)
	var r := _guide.hear(at, 0.5)
	_ripples.add_howl(at, at, r, true)
	for e in r["events"]:
		if String(e) == "wrong" and not (r["wrong"] as Dictionary).is_empty():
			_later.append({ "left": float(r["wrong"]["arrive"]), "key": "wrong" })
		else:
			_on_event(String(e))


func _nearest_wall_point() -> Vector2:
	var best := _companion.position + Vector2(0.0, -120.0)
	var best_d := INF
	for w in _guide.walls():
		var p := Geometry2D.get_closest_point_to_segment(_companion.position, w[0], w[1])
		var d := p.distance_to(_companion.position)
		if d < best_d:
			best_d = d
			best = p
	return best


func update(delta: float) -> void:
	if _guide == null or _player == null or _companion == null or delta <= 0.0:
		return
	_clock += delta
	var u := _guide.update(delta, _player.position, _companion.bond_value())
	for e in u["events"]:
		_on_event(String(e))
	if bool(u["point"]):
		_companion.point_at(u["target"], 1.0)
		_pointing = true
	elif _pointing:
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false
	# the howl pose: stand still and lift the head (a gaze up, ears and body perked; held while it lasts)
	if _howl_t > 0.0:
		_howl_t -= delta
		_companion.issue_command("guide", _companion.position, { "hold": true })
		_companion.listen_toward(_companion.position + Vector2(0.0, -180.0), 1.0)
	var due: Array = []
	for l in _later:
		l["left"] = float(l["left"]) - delta
		if float(l["left"]) <= 0.0:
			_on_event(String(l["key"]))
		else:
			due.append(l)
	_later = due
	var keep: Array = []
	for rc in _react:
		rc["left"] = float(rc["left"]) - delta
		if float(rc["left"]) <= 0.0:
			_companion.glance_toward(rc["pos"])
		else:
			keep.append(rc)
	_react = keep


func _on_event(event: String) -> void:
	match event:
		"first_echo", "wrong", "silence", "notice":
			_say(event, true)
		"reveal":
			# the SecretDirector says the reveal line when it brings the stone up
			if _cliff != null:
				_cliff.open_cave()
			cave_opened.emit()


func _say(key: String, once: bool) -> void:
	if once:
		if _said.has(key):
			return
		_said[key] = true
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)
