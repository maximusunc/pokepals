class_name FishingDirector
extends Node
## FISHING, the pilot usable item (docs/usable-items-design.md): the starter rod on its post in the Vale,
## the hotbar and use button, and a cast from rod to catch. Created by world_controller in every world
## (you can fish anywhere there is water, U-6) and freed with it on a world hop.
##
## A cast, from your side (the server judges every step; Server.Fishing):
##   1. Tap Use (or F) with the rod selected and water in reach: the line flies out (FishingWater picks where
##      the bobber lands) and we ask the server to cast.
##   2. The server answers with how long until a bite and how hard the timing ring is (never what's on the
##      line). The bobber sits on the water; your companion keeps you company, watching it.
##   3. A bite: the bobber dips, a "!" pops over your head, the use button pulses and the timing ring closes in
##      round the bobber (FishingRing). Tap as it meets the target circle.
##   4. In time, we tell the server and it grants the catch into your inventory; it comes up out of the water
##      and over your head, and your companion is delighted. A miss, or no tap, and it slips away: never a
##      loss, just "next time".
## Walking away reels the line in. Friends see all of it (U-13): what we hold and our fishing go out with
## our identity (PresenceDirector.set_activity).

const SLOTS := 5
const WALK_OFF := 24.0        # px you can shuffle while fishing before the line reels in
const ESCAPED_HOLD := 0.9     # s the line lingers after a fish gets away, before it reels in
const ANSWER_WAIT := 6.0      # s to wait for the server to answer a cast or a reel before giving up
const ROD_KEY := "rod"

var _host: Node
var _player: PlayerView
var _companion: CompanionView
var _presence: PresenceDirector
var _hotbar: Hotbar
var _use: UseButton
var _scenery: Node2D

var _water: FishingWater
var _allowed := true          # this world lets you fish (a spec opts out with "fishing": false)
var _items: Dictionary = {}   # item_def_id -> { key, name, category, color, quantity }
var _slots: Array = []        # item def id or null, per slot
var _selected := 0
var _known := false           # whether the server has told us what we carry yet

var _rod: RodView             # the rod in our own hand
var _post_pos := Vector2.ZERO # the starter rod's post in this world (if it has one)
var _rest: RodRest = null     # the rod resting on the post, while it's still there for us

# The cast in hand: "" (not fishing), "cast" (asked the server), "wait", "bite", "reel" (told the server
# we landed it), "caught", "escaped".
var _phase := ""
var _bobber := Vector2.ZERO
var _anchor := Vector2.ZERO   # where we stood to cast
var _wait_left := 0.0
var _ring: FishingRing = null
var _hold := 0.0              # how long "caught" / "escaped" lingers
var _answer_wait := 0.0       # how long we've waited on the server's answer to a cast / reel
var _catches := 0             # catches this session (so a friend's screen pops each one once)
var _last_catch: Dictionary = {}


func setup(host: Node, player: PlayerView, companion: CompanionView, presence: PresenceDirector, scenery: Node2D, hotbar: Hotbar, use: UseButton) -> void:
	_host = host
	_player = player
	_companion = companion
	_presence = presence
	_scenery = scenery
	_hotbar = hotbar
	_use = use
	_rod = RodView.new()
	_rod.name = "Rod"
	_player.add_child(_rod)
	_hotbar.slot_selected.connect(select_slot)
	_use.used.connect(use_item)
	Net.inventory_received.connect(_on_inventory)
	Net.hotbar_received.connect(_on_hotbar)
	Net.rod_taken.connect(_on_rod_taken)
	Net.fish_hooked.connect(_on_fish_hooked)
	Net.fish_caught.connect(_on_fish_caught)
	Net.fish_escaped.connect(_on_fish_escaped)
	Net.fish_refused.connect(_on_fish_refused)
	# What the server already told us before this world was built (a world hop), so the bar shows at once.
	if Net.has_inventory():
		_on_inventory(Net.inventory())
	_on_hotbar(Net.hotbar_slots())


## Read this world's water and whether it allows fishing, and find the starter rod's post (if any).
func configure(data: Dictionary) -> void:
	_water = FishingWater.from_world(data)
	_allowed = data.get("fishing", true) != false
	for it in data.get("props", []):
		if it is Dictionary and String((it as Dictionary).get("gives", "")) == ROD_KEY:
			_post_pos = WorldData.to_vec2(it["position"])
			_rest = RodRest.new()
			_rest.name = "RodRest"
			_rest.position = _post_pos
			_rest.visible = false   # until we know whether the rod is still there for us
			_scenery.add_child(_rest)
	_refresh_rest()


## Water a world adds that isn't in its spec's shapes (Ebbmere: wherever the tide covers right now).
func add_water(is_water_at: Callable) -> void:
	if _water != null:
		_water.set_extra(is_water_at)


## Examining the rod's post: take the rod if it's still there for us, else read the post.
func examine_post(entry: Dictionary) -> void:
	if _owns_rod():
		_host.show_hint(String(entry.get("lore", "")) if String(entry.get("lore", "")) != "" else "An empty post by the water.")
		return
	_companion.notify_interaction(entry["pos"], String(entry["id"]), entry["tags"])
	Net.take_rod()


## Select a hotbar slot (tapped, or keys 1-5). Switching away from the rod reels the line in.
func select_slot(index: int) -> void:
	if index < 0 or index >= SLOTS:
		return
	if index != _selected and _phase != "":
		_reel_in_quietly()
	_selected = index
	# The selection decides what's in your hand and what the use button shows, so redo all of it.
	_refresh_bar()
	_refresh_use()


## The use button (or F): use whatever is selected. Only the rod does anything yet.
func use_item() -> void:
	var item := _selected_item()
	if item.is_empty():
		return
	if String(item.get("key", "")) != ROD_KEY:
		return
	match _phase:
		"":
			_try_cast()
		"wait", "cast":
			_reel_in_quietly()
			_host.show_hint("You reel the line back in.")
		"bite":
			_tap_ring()


## Whether the hotbar has anything on it (so the controller knows the keys 1-5 / F mean something).
func has_items() -> bool:
	for s in _slots:
		if s != null:
			return true
	return false


func update(delta: float) -> void:
	_refresh_use()
	match _phase:
		"cast", "reel":
			# Waiting on the server. If its answer never comes (the link dropped), let the moment go.
			_answer_wait += delta
			if _answer_wait > ANSWER_WAIT:
				_let_go("The line went slack.")
		"wait":
			_wait_left -= delta
			# Your companion keeps you company: settled beside you, its eyes on the bobber.
			_companion.listen_toward(_bobber, 0.6)
			if _wait_left <= 0.0:
				_bite()
		"bite":
			_companion.listen_toward(_bobber, 1.0)
			_ring.update(delta)
			if _ring.result() == "timeout":
				Net.reel(false)
				_let_go("It got away. Next time!")
		"caught", "escaped":
			_hold -= delta
			if _hold <= 0.0:
				_phase = ""
				_rod.clear_fishing()
				_publish()
	# Walking off reels the line in.
	if _phase in ["cast", "wait", "bite"] and _player.position.distance_to(_anchor) > WALK_OFF:
		_reel_in_quietly()
		_host.show_hint("You reel the line in as you walk away.")


# ── the cast ──

func _try_cast() -> void:
	if not _allowed:
		_host.show_hint("There's no fishing here.")
		return
	var p: Variant = _water.cast_point(_player.position, _player.facing()) if _water != null else null
	if p == null:
		_host.show_hint("Find some water to fish in.")
		return
	_bobber = p
	_anchor = _player.position
	_player.look_toward(_bobber - _player.position)
	_phase = "cast"
	_answer_wait = 0.0
	_rod.set_fishing("cast", _bobber)
	_companion.glance_toward(_bobber)
	Net.cast_line()
	_publish()


func _on_fish_hooked(wait_ms: int, window: float, speed: float) -> void:
	if _phase != "cast":
		return
	_phase = "wait"
	_wait_left = float(wait_ms) / 1000.0
	_ring = FishingRing.new(window, speed)
	_rod.set_fishing("wait", _bobber)
	_publish()


func _bite() -> void:
	_phase = "bite"
	_rod.set_fishing("bite", _bobber)
	_rod.set_ring(_ring)
	_companion.glance_toward(_bobber)
	_use.set_alert(true)
	_host.show_hint("Something's biting! Tap as the ring meets the circle.")
	_publish()


func _tap_ring() -> void:
	var result := _ring.tap()
	_use.set_alert(false)
	if result == "landed":
		_phase = "reel"
		_answer_wait = 0.0
		Net.reel(true)
	else:
		Net.reel(false)
		_let_go("It slipped off the hook. Next time!")


func _on_fish_caught(item: Dictionary) -> void:
	if _phase != "reel":
		return
	_catches += 1
	var kind := String(item.get("kind", "fish"))
	var color := color_of(item.get("color"))
	_last_catch = { "k": String(item.get("key", "")), "r": kind, "c": [color.r, color.g, color.b] }
	_phase = "caught"
	_hold = RodView.POP_SECONDS
	_rod.show_catch(String(item.get("key", "")), kind, color)
	_companion.delight_at(_player.position)
	var what := String(item.get("name", "something"))
	match kind:
		"rare_fish":
			_host.show_hint("A %s! A rare one. It would look lovely in a tank at home." % what)
		"material":
			_host.show_hint("You reel up %s %s." % [_article(what), what])
		_:
			_host.show_hint("You caught %s %s!" % [_article(what), what])
	_publish()


func _on_fish_escaped() -> void:
	if _phase == "reel":
		_let_go("It slipped off the hook. Next time!")


func _on_fish_refused(reason: String) -> void:
	if _phase != "cast":
		return
	_reel_in_quietly(false)
	match reason:
		"no_fishing":
			_host.show_hint("There's no fishing here.")
		"no_rod":
			_host.show_hint("You'll need a rod. There's one on a post by the little pond in the Vale.")
		_:
			pass  # cast too soon after the last: nothing to say, it just doesn't go


func _let_go(line: String) -> void:
	_phase = "escaped"
	_hold = ESCAPED_HOLD
	_use.set_alert(false)
	_rod.set_ring(null)
	_rod.set_fishing("wait", _bobber)
	_host.show_hint(line)
	_publish()


## Reel the line in with nothing to show for it. If a fish was hooked, tell the server it's let go.
func _reel_in_quietly(tell_server := true) -> void:
	if tell_server and _phase in ["wait", "bite"]:
		Net.reel(false)
	_phase = ""
	_ring = null
	_use.set_alert(false)
	_rod.clear_fishing()
	_publish()


# ── the rod's post ──

func _on_rod_taken(ok: bool, is_new: bool) -> void:
	if not ok:
		_host.show_hint("Step a little closer to the post.")
	elif is_new:
		_companion.delight_at(_post_pos)
		_host.show_hint("You take the fishing rod. It's on your hotbar: find some water and tap Use.")
	else:
		_host.show_hint("You already have a rod.")


# ── what we carry ──

func _on_inventory(items: Array) -> void:
	_items.clear()
	for it in items:
		if not (it is Dictionary):
			continue
		var d: Dictionary = it
		_items[int(d.get("item_def_id", 0))] = {
			"key": String(d.get("key", "")),
			"name": String(d.get("name", "")),
			"kind": String(d.get("category", "")),
			"color": color_of(d.get("color")),
			"quantity": int(d.get("quantity", 0)),
		}
	_known = true
	_refresh_bar()
	_refresh_rest()


func _on_hotbar(slots: Array) -> void:
	_slots = []
	for i in SLOTS:
		var v: Variant = slots[i] if i < slots.size() else null
		if (v is int or v is float) and int(v) > 0:
			_slots.append(int(v))
		else:
			_slots.append(null)
	_refresh_bar()


func _refresh_bar() -> void:
	var shown: Array = []
	for s in _slots:
		if s != null and _items.has(int(s)):
			shown.append(_items[int(s)])
		else:
			shown.append({})
	_hotbar.set_slots(shown)
	_hotbar.set_selected(_selected)
	var item := _selected_item()
	_use.set_item(String(item.get("key", "")), String(item.get("kind", "")), item.get("color", Color(0.8, 0.84, 0.88)))
	# The rod is in your hand while it's the selected item.
	_rod.set_held(String(item.get("key", "")) == ROD_KEY)
	_publish()


## The rod rests on its post until it's ours (each player sees their own post).
func _refresh_rest() -> void:
	if _rest != null:
		_rest.visible = _known and not _owns_rod()


func _refresh_use() -> void:
	var item := _selected_item()
	if String(item.get("key", "")) != ROD_KEY:
		_use.set_ready(not item.is_empty())
		return
	if _phase != "":
		_use.set_ready(_phase in ["wait", "bite", "cast"])
		return
	_use.set_ready(_allowed and _water != null and _water.cast_point(_player.position, _player.facing()) != null)


func _selected_item() -> Dictionary:
	if _selected < 0 or _selected >= _slots.size():
		return {}
	var s: Variant = _slots[_selected]
	if s == null or not _items.has(int(s)):
		return {}
	return _items[int(s)]


func _owns_rod() -> bool:
	for it in _items.values():
		if String((it as Dictionary).get("key", "")) == ROD_KEY:
			return true
	return false


## Tell friends what we hold and what our line is doing (only sent when it changes).
func _publish() -> void:
	if _presence == null:
		return
	var held := ROD_KEY if _rod.is_held() else ""
	var fishing: Dictionary = {}
	var ph := _phase
	if ph == "reel":
		ph = "bite"
	if ph in ["cast", "wait", "bite", "caught", "escaped"]:
		fishing = { "b": [_bobber.x, _bobber.y], "ph": ph, "n": _catches }
		if ph == "caught":
			fishing.merge(_last_catch)
	_presence.set_activity(held, fishing)


static func color_of(v: Variant) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return Color(0.8, 0.84, 0.88)


static func _article(word: String) -> String:
	return "an" if word.length() > 0 and "AEIOUaeiou".contains(word[0]) else "a"


## The starter rod lying across its post, for as long as it's still there for you. A small y-sorted node in
## the Scenery (so you can stand in front of or behind it), drawn over the post WorldArt draws.
class RodRest extends Node2D:
	func _draw() -> void:
		ItemIcon.draw(self, "rod", "tool", Vector2(2, -16), 22.0)
