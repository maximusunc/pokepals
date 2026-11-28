class_name WishDirector
extends Node
## THE WISHING FOUNTAIN (Lingerlong): a shared ritual and a very small coin sink. Near the fountain the use
## button offers "Toss a coin" (tapping the fountain does the same); examining it reads its lore and how many
## wishes it holds. The server decides everything (Server.Wishes): where you stand, how soon, whether it costs a
## coin (one if you have one, free if not), and the count, which the world keeps for good.
##
## What everyone near sees when anyone wishes: a small gold coin arcs from the wisher into the basin (CoinArc, one
## tiny node that frees itself, at most CoinArc.MAX in the air), a ring and a few glints on the water
## (FountainView.splash), and the jets swell; wishes close together add up, so a crowd tossing coins makes it rise
## grandly. Only while the fountain is on screen (it hides itself otherwise); a wisher with no puppet here (out
## of sight) gets no arc, just the splash.

const REACH := 90.0          # px past the basin's rim the button offers a toss (the server allows a little more)
const GAP := 1.5             # s between our own wishes (the server's limit too)
const SWELL := 0.55          # how much one wish lifts the jets (FountainView.swell)
const PAID_LINES := [
	"You toss a coin in. The fountain keeps it safe.",
	"A coin, a wish. The water takes both.",
	"Plink. Your wish is in good hands now.",
	"You make a wish. You don't tell anyone what.",
]
const FREE_LINES := [
	"No coins? The fountain doesn't mind. Your wish is in.",
	"You wish without a coin. The fountain doesn't mind at all.",
]

var _host: Node
var _player: PlayerView
var _presence: PresenceDirector
var _scenery: Node2D
var _view: FountainView = null
var _center := Vector2.ZERO
var _radius := 0.0
var _id := ""
var _count := -1             # wishes it holds (-1 until the server says)
var _since := INF            # s since our last wish
var _rng := RandomNumberGenerator.new()


func setup(host: Node, player: PlayerView, presence: PresenceDirector, scenery: Node2D) -> void:
	_host = host
	_player = player
	_presence = presence
	_scenery = scenery
	_rng.randomize()
	Net.wishes_received.connect(_on_count)
	Net.wish_made.connect(_on_wish_made)
	Net.wish_refused.connect(_on_refused)
	Net.wished.connect(_on_wished)


## This world's fountain (its spec's `fountain` block) and the view that draws it; none in most worlds.
func configure(data: Dictionary, view: FountainView) -> void:
	var f: Dictionary = data.get("fountain", {})
	_view = view
	_id = String(f.get("id", ""))
	_radius = float(f.get("radius", 0.0))
	_center = WorldData.to_vec2(f.get("center", [0, 0])) if f.has("center") else Vector2.ZERO
	if f.is_empty():
		_view = null


func active() -> bool:
	return _view != null


func count() -> int:
	return _count


## Close enough to toss a coin in (standing, or sitting on a bench round it).
func in_reach() -> bool:
	return _view != null and _player.position.distance_to(_center) <= _radius + REACH


## PLACE ACTION (FishingDirector.places): "Toss a coin" by the fountain.
func place_action() -> Dictionary:
	return { "verb": "Toss a coin", "icon": "coin", "rank": 1 } if in_reach() else {}


func place_use() -> void:
	toss()


## Toss a coin in (the use button, F, or a tap on the fountain). The server answers wish_made / wish_refused.
func toss() -> void:
	if not in_reach():
		_host.show_hint("Step a little closer to the fountain.")
		return
	if _since < GAP:
		return   # (a coin is still on its way; the fountain likes them one at a time)
	_since = 0.0
	Net.send_wish()


## A tap on the world that snapped to the fountain: toss a coin if we're close enough (true: handled).
func on_tap(entry: Dictionary) -> bool:
	if _view == null or String(entry.get("id", "")) != _id or not in_reach():
		return false
	toss()
	return true


## Examining the fountain: its lore, and how many wishes it holds (true: handled).
func examine(entry: Dictionary) -> bool:
	if _view == null or String(entry.get("id", "")) != _id:
		return false
	var lore := String(entry.get("lore", ""))
	var held := ""
	if _count == 0:
		held = "It holds no wishes yet."
	elif _count == 1:
		held = "It holds one wish."
	elif _count > 1:
		held = "It holds %s wishes." % _grouped(_count)
	_host.show_hint((lore + " " + held).strip_edges())
	return true


func update(delta: float) -> void:
	_since += delta


func _on_count(n: int) -> void:
	_count = n


func _on_wish_made(n: int, paid: bool, balance: int) -> void:
	_count = maxi(_count, n)
	if paid:
		_host.set_wallet_balance(balance)
	var lines: Array = PAID_LINES if paid else FREE_LINES
	_host.show_hint(lines[_rng.randi() % lines.size()])
	_coin_from(_player.position + Vector2(0, -14))


func _on_refused(reason: String) -> void:
	_since = GAP   # (we may try again straight away)
	if reason == "away":
		_host.show_hint("Step a little closer to the fountain.")


## Someone ELSE wished: their coin flies from where their avatar is drawn, if it is.
func _on_wished(by: String, n: int, _paid: bool) -> void:
	_count = maxi(_count, n)
	if _view == null or by == Net.local_id():
		return
	var at: Variant = _presence.peer_position(by) if _presence != null else null
	_coin_from(at + Vector2(0, -14) if at is Vector2 else null)


## A coin goes in: an arc from `from` when there's one to draw (and the fountain is in view), else just the splash.
func _coin_from(from: Variant) -> void:
	if _view == null or not is_instance_valid(_view):
		return
	var to := _view.basin_point(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
	if not _view.visible:
		_view.swell(SWELL)   # (off screen: nothing to draw, but the jets are up when you look)
		return
	if from is Vector2 and CoinArc.room() and (from as Vector2).distance_to(_center) < 600.0:
		var coin := CoinArc.new()
		coin.name = "Coin"
		_scenery.add_child(coin)
		coin.launch(from, to, _land)
	else:
		_land(to)


func _land(at: Vector2) -> void:
	if _view != null and is_instance_valid(_view):
		_view.splash(at)
		_view.swell(SWELL)


## 12345 -> "12,345".
static func _grouped(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
