class_name ListenDirector
extends Node
## The FAINT BELL (Steamhollow's secret): a little bronze bell somewhere in the fog, ringing too softly
## for you to hear. Your companion hears it. This is the presentation half; the decisions live in the pure
## ListenGuide (scripts/world). Each frame it hands the guide how you and your companion are moving, and
## how deep the bond is, and turns the answer into the companion's BODY LANGUAGE and nothing else:
##   * its gaze turns toward the sound, its ears prick, its body stills a little and perks up
##     (CompanionView.listen_toward), more clearly the longer you stand easy together and the deeper the
##     bond; walk on and it loses the sound again, gently;
##   * there is no arrow, no marker and no HUD: that body language is the only compass;
##   * when you stop and it is beside you, it is asked to stand easy too (a hold), so its own wandering does
##     not keep it from settling; it is never moved;
##   * close to the bell, the tell grows stronger, and the bell shows through the fog: a small warm pocket
##     where the mist thins (mist_pockets, read by the MistVeil);
##   * a few hints at the moments (it hears, it loses it, you are close), each said once.
## Examining the bell is the ordinary claim flow; SecretDirector lays the prop out and owns that.
## Everything is personal and display-only: a friend beside you sees your companion turn, and nothing
## here is networked. The numbers all come from the secret's `reveal` block in the world spec.

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _guide: ListenGuide
var _reveal: Dictionary = {}
var _lines: Dictionary = {}
var _bell := Vector2.ZERO
var _said := {}                  # which one-time hints have been given this visit
var _visible := 0.0              # how much of the bell shows through the fog right now
var _pocket_radius := 46.0
var _active := true


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


## Lay out this world's bell from the secret ({ position, reveal: { ... } }).
func configure(secret: Dictionary) -> void:
	_reveal = secret.get("reveal", {})
	_lines = _reveal.get("lines", {})
	_bell = WorldData.to_vec2(secret.get("position", [0, 0]))
	_guide = ListenGuide.new(_bell, _reveal)
	_pocket_radius = float(_reveal.get("pocket_radius", 46.0))
	_said = {}
	_visible = 0.0
	_active = true


func guide() -> ListenGuide:
	return _guide


## The secret has been found: stop listening and let the companion relax.
func finish() -> void:
	_active = false
	_visible = 0.0
	if _companion != null:
		_companion.listen_toward(Vector2.ZERO, 0.0)


## The moving pocket in the mist where the bell shows (for MistVeil): empty until you are close.
func mist_pockets() -> Array:
	if not _active or _visible <= 0.01:
		return []
	return [{ "pos": _bell + Vector2(0.0, -10.0), "radius": _pocket_radius * _visible, "warm": 0.9 * _visible }]


## How much of the bell shows right now (0..1), for tests and the world art.
func visible_amount() -> float:
	return _visible


## Per frame (SecretDirector.update drives it).
func update(delta: float) -> void:
	if not _active or _guide == null or _player == null or _companion == null or delta <= 0.0:
		return
	var r := _guide.update(delta, _player.position, _player.velocity.length(), _companion.position,
		_companion.velocity.length(), _companion.bond_value())
	_visible = float(r["visible"])
	# You have gone still and it is beside you: invite it to stand easy too (a guide "hold", which lapses by
	# itself a moment after we stop asking, and which a whistle or a pet cancels), or its own wandering
	# would never let it settle. It never moves it, and never when you are walking.
	if bool(r["calm"]):
		_companion.issue_command("guide", _companion.position, { "hold": true })
	_companion.listen_toward(r["target"], float(r["tell"]))
	for e in r["events"]:
		_on_event(String(e))


func _on_event(event: String) -> void:
	match event:
		"hear":
			_say_once("hear")
		"lost":
			_say_once("lost")
		"near":
			_say_once("near")
		"close":
			_say_once("close")


func _say_once(key: String) -> void:
	if _said.has(key):
		return
	_said[key] = true
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)
