class_name SeatDirector
extends Node
## SITTING TOGETHER (Lingerlong): the local half. Near a free seat the use button offers "Sit"; a tap sets you
## on it, and a step on the stick gets you up again. While you sit your companion settles beside you and rests
## (CompanionView.set_resting), and gets up when you do.
##
## Nothing here is networked. Being seated is a pure function of position and stillness (SeatLogic): you sit on
## the seat's anchor and keep still, so everyone else's screen draws you sitting from your ordinary state packets,
## and theirs draws you standing the moment you move. Remote avatars need nothing from here at all (PlayerView
## looks its seat up as it stops).
##
## Cost: the "is a free seat in reach?" answer is cached and asked again only when you've moved a few px or every
## RECHECK s (others may have sat down); a grid lookup, and only then a pass over who's nearby.

const REACH := 30.0          # px from a seat's anchor you can sit down from
const MOVE := 4.0            # px you move before the answer is asked again
const RECHECK := 0.5         # s before it's asked again regardless
const SETTLE_R := 48.0       # your companion rests once it's this close to you, and slow
const SETTLE_SPEED := 14.0
const SIT_LINES := [
	"You sit down. Nobody here is in a hurry.",
	"You sit for a while. Your companion settles beside you.",
	"A good seat. The afternoon carries on without you.",
	"You sit. The marble is warm from the sun.",
]

var _host: Node
var _player: PlayerView
var _companion: CompanionView
var _presence: PresenceDirector
var _seats: SeatLogic = null

var _free := -1               # the free seat in reach, last time we asked
var _asked_at := Vector2.INF
var _age := INF
var _rested := false          # we laid the companion down (so we're the one to get it up)
var _lines := 0
var _rng := RandomNumberGenerator.new()


func setup(host: Node, player: PlayerView, companion: CompanionView, presence: PresenceDirector) -> void:
	_host = host
	_player = player
	_companion = companion
	_presence = presence
	_player.stood_up.connect(_on_stood_up)
	_rng.randomize()


## Read this world's seats. Every avatar in it learns them too (PlayerView.seats), so anyone still on an anchor
## is drawn sitting.
func configure(data: Dictionary) -> void:
	var s := SeatLogic.from_spec(data.get("seats", []))
	_seats = null if s.is_empty() else s
	PlayerView.seats = _seats
	_free = -1
	_age = INF


func active() -> bool:
	return _seats != null


## PLACE ACTION (FishingDirector.places): "Sit" by a free seat, "Stand up" while sitting. Cached.
func place_action() -> Dictionary:
	if _seats == null:
		return {}
	if _player.is_sitting():
		return { "verb": "Stand up", "icon": "seat", "rank": 0 }
	return { "verb": "Sit", "icon": "seat", "rank": 2 } if _free >= 0 else {}


func place_use() -> void:
	if _seats == null:
		return
	if _player.is_sitting():
		_player.stand_up()
		return
	_ask(true)
	if _free < 0:
		return
	sit_on(_free)


## Sit on seat `i` (the use button, or a test).
func sit_on(i: int) -> void:
	_player.sit(_seats.seat(i)["at"], _seats.stand_point(i))
	_companion.issue_command("come")   # it comes to you, then settles down beside the seat (update)
	_rested = false
	_free = -1
	_age = INF
	if _lines < 2:   # a word the first couple of times, then just the sitting
		_lines += 1
		_host.show_hint(SIT_LINES[_rng.randi() % SIT_LINES.size()])


func update(delta: float) -> void:
	if _seats == null:
		return
	_age += delta
	if _player.is_sitting():
		# Your companion comes to you as it always does; once it's close and has slowed, it lies down to rest.
		if not _rested and _companion.position.distance_to(_player.position) < SETTLE_R \
				and _companion.velocity.length() < SETTLE_SPEED:
			_companion.set_resting(true)
			_rested = true
		return
	if _rested:
		_get_companion_up()
	_ask(false)


## Look for a free seat in reach of where we stand, unless we asked from about here a moment ago.
func _ask(force: bool) -> void:
	var p := _player.position
	if not force and _age < RECHECK and p.distance_squared_to(_asked_at) < MOVE * MOVE:
		return
	_asked_at = p
	_age = 0.0
	_free = _seats.nearest_free(p, REACH)
	if _free >= 0 and _presence != null:
		# only now, with a seat in reach, look at who else is about (someone may be sitting on it)
		_free = _seats.nearest_free(p, REACH, _presence.remote_player_positions())


func _on_stood_up() -> void:
	_get_companion_up()
	_age = INF


func _get_companion_up() -> void:
	if _rested:
		_companion.set_resting(false)
		_rested = false
