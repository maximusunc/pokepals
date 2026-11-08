class_name DozeDirector
extends Node
## Dozewood's secret, the presentation half: a place your companion dreams of. The decisions live in the
## pure DreamGate (scripts/world); each frame this hands it where you and your companion are, how calm
## the companion is and how bonded, and whether you've poked it, and turns the answers into:
##   * the companion lying down and staying put (CompanionView.set_resting) while it is drowsy or asleep;
##   * z's drifting up, and, once it dreams, a thought bubble holding a picture of the landmark it dreams
##     of (DreamBubble);
##   * the few words of hint that go with the moments (it yawns, lies down, sleeps, dreams, wakes);
##   * `place_found` when you and it stand together at the landmark it dreamed of, which the SecretDirector
##     turns into the secret rising there.
## What counts as "safe" enough to fall asleep (a nap spot, a pet it welcomed, you still and close, a calm
## mood) is the gate's, and is data in the secret's `reveal` block. Wake it by walking away, or with a pet
## or a call: the brain's behaviour tells us ("pet"/"come"), the same way the Ruin watches a search end.
## A welcomed pet is the companion's own "love" reaction while it is petting.
##
## Everything is personal and display-only: a friend beside you sees your companion lie still, but not the
## bubble, and nothing here is networked. The decision of WHETHER you may take what's at the landmark stays
## the server's ("this world, standing at it" on the claim).

signal place_found

## How long (seconds) to hold off the companion's autonomous shape-shifting each frame it's dozing.
const DRIFT_HOLD := 30.0
## Ignore a call for this long after it falls asleep.
const POKE_GRACE := 1.3

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _gate: DreamGate
var _bubble: DreamBubble
var _reveal: Dictionary = {}
var _lines: Dictionary = {}
var _spots: Array = []
var _said := {}                 # one-time hints given this visit
var _since_asleep := 0.0
var _prev_behavior := ""
var _hollow_hint_cd := 0.0
var _last_blocker := ""


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


## Lay out this world's nap spots and dream from the secret's reveal block.
func configure(secret: Dictionary) -> void:
	_reveal = secret.get("reveal", {})
	_lines = _reveal.get("lines", {})
	_spots = []
	for p in _reveal.get("spots", []):
		_spots.append(WorldData.to_vec2(p))
	var landmark := WorldData.to_vec2(_reveal.get("landmark_position", secret.get("position", [0, 0])))
	_gate = DreamGate.new(_spots, landmark, _reveal)
	_said = {}
	if is_instance_valid(_bubble):
		_bubble.queue_free()
	_bubble = DreamBubble.new()
	_bubble.name = "DreamBubble"
	_companion.add_child(_bubble)
	var path := String(_reveal.get("picture", ""))
	if path != "" and ResourceLoader.exists(path):
		_bubble.set_picture(load(path) as Texture2D)
	if not _companion.reacted.is_connected(_on_reacted):
		_companion.reacted.connect(_on_reacted)


func gate() -> DreamGate:
	return _gate


func _exit_tree() -> void:
	if is_instance_valid(_companion):
		_companion.set_resting(false)
		if _companion.reacted.is_connected(_on_reacted):
			_companion.reacted.disconnect(_on_reacted)
	if is_instance_valid(_bubble):
		_bubble.queue_free()


## A pet it welcomed ("love" while petting) is what tells the place it is safe.
func _on_reacted(kind: String) -> void:
	if kind == "love" and _gate != null and _companion.behavior() == "pet":
		_gate.note_pet()


## Per frame (SecretDirector.update drives it).
func update(delta: float) -> void:
	if _gate == null or _player == null or _companion == null or not _companion.is_met():
		return
	var behavior := _companion.behavior()
	var poked := false
	if _gate.is_asleep():
		_since_asleep += delta
		# Only a CALL wakes it. Petting a sleeping companion is the natural thing to do (playtest: players
		# kept petting while waiting, and every pet woke it before the dream could begin), so a pet just
		# gets a sleepy sigh and it sleeps on.
		poked = _since_asleep > POKE_GRACE and behavior == "come"
		if behavior == "pet" and _prev_behavior != "pet" and _since_asleep > POKE_GRACE:
			_say("pet_asleep")
	elif behavior == "come" and _prev_behavior != "come":
		_gate.note_call()
	_prev_behavior = behavior
	_hollow_hint_cd = maxf(0.0, _hollow_hint_cd - delta)

	var was_asleep := _gate.is_asleep()
	var r := _gate.update(delta, _companion.position, _player.position, _companion.mood_snapshot(), _companion.bond_value(), poked)
	_companion.set_resting(bool(r["rest"]))
	if bool(r["rest"]):
		_companion.postpone_form_drift(DRIFT_HOLD)
	_bubble.set_sleep(1.0 if _gate.is_asleep() else 0.0)
	_bubble.set_dream(1.0 if bool(r["dream"]) else 0.0)
	for e in r["events"]:
		_on_event(String(e), poked, was_asleep)
	_hint_the_hollow()


func _on_event(event: String, poked: bool, was_asleep: bool) -> void:
	match event:
		"settle":
			_say_once("settle")
		"yawn":
			_bubble.puff()
			_say_once("yawn")
		"stir":
			_said.erase("settle")   # it can lie down for the first time again, as it were
		"asleep":
			_since_asleep = 0.0
			_say_once("asleep")
		"dream":
			_say_once("dream")
		"wake":
			if was_asleep:
				_say("wake_poked" if poked else "wake_left")
		"yawn_ambient":
			_bubble.puff()
			_say_once("yawn_ambient")
		"arrive":
			place_found.emit()


## Gentle nudges, once each, when you are in a hollow with your companion but it isn't dozing yet: the
## first tells you the hollow is a place for it, the second that it is too wound up to settle.
func _hint_the_hollow() -> void:
	var b := _gate.blocker
	if _hollow_hint_cd > 0.0 or _gate.phase != DreamGate.Phase.AWAKE:
		return
	if _gate.spot_at(_companion.position) < 0 or _player.position.distance_to(_companion.position) > float(_reveal.get("together_distance", 100.0)) * 1.5:
		return
	if b == "pet" and not _said.has("hollow"):
		_say_once("hollow")
		_hollow_hint_cd = 20.0
	elif b == "calm" and b != _last_blocker and not _said.has("calm"):
		_say_once("calm")
		_hollow_hint_cd = 20.0
	_last_blocker = b


func _say_once(key: String) -> void:
	if _said.has(key):
		return
	_said[key] = true
	_say(key)


func _say(key: String) -> void:
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)
