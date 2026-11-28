class_name HarvestDirector
extends Node
## HARVESTING (home building; docs/usable-items-design.md "Home building"): chopping trees with an axe, and
## picking up the loose things lying about (the Riverbank's stones and driftwood). Created by world_controller
## in every world and freed with it on a world hop. The server judges every step (Server.Harvest):
##
##   * **Chop.** With the axe selected, tap Use (or F) beside a tree. You turn to it and swing; one swing fells
##     it (a chop that takes time, `Net.chop_ms()` > 0, is several swings, the crown shivering at each). The
##     server gives you the wood and tells everyone here the tree is down: it topples, and a stump stays until
##     it grows back (the server's regrow time). Not in the Vale or at home (`"chopping": false`), and only
##     trees that are wood (not a fence picket, a crystal, a flower stalk; mirrors Server.Harvest's list).
##   * **Pick up.** A stone or a piece of driftwood is examinable; examining it picks it up. It's gone for
##     everyone until it washes back.
##
## What's down when we arrive comes with the join (Net.harvest_down()); each node grows back on its own timer
## here, from the server's own figure, so nothing more need be sent.

const CHOP_REACH := 40.0        # px from your feet to a trunk to swing at it
const SWING_GAP := 0.5          # s between swings while a chop takes time
const WALK_OFF := 18.0          # px you can shuffle mid-chop before you stop
# Tree kinds that aren't wood (keep in step with Server.Harvest's @not_wood).
const NOT_WOOD := ["picket", "grass", "clover", "daisy", "poppy", "cosmos", "dandelion", "foxglove", "bluebell",
	"crystal_spire", "bell_flower", "spore_stalk", "bubble_stalk", "lolli", "gumdrop", "pillar", "mound", "fungus",
	"gw_spire", "gw_hill", "gw_boulder"]
const PICKUP_NAMES := { "stone": "a river stone", "driftwood": "a piece of driftwood" }

var _host: Node
var _player: PlayerView
var _companion: CompanionView
var _scenery: Scenery
var _axe: AxeView

var _allowed := true
var _trees: Array = []          # [{ index, pos, wood }] (the spec's trees, in order)
var _pickups: Dictionary = {}   # id -> { view: PickupView, entry: Dictionary }
var _regrow: Dictionary = {}    # node id -> seconds until it grows back
var _held := false              # whether the axe is the selected item

# A chop in hand (while chops take time): the tree's index, where we stood, time left, time to the next swing.
var _chop_index := -1
var _chop_anchor := Vector2.ZERO
var _chop_left := 0.0
var _swing_wait := 0.0
var _waiting := false           # a chop sent, waiting for the server's answer

# The last "is there a tree in reach?" answer, and where it was asked (rechecked as you move).
var _ready_pos := Vector2.INF
var _ready_age := INF
var _ready := -1


func setup(host: Node, player: PlayerView, companion: CompanionView, scenery: Scenery) -> void:
	_host = host
	_player = player
	_companion = companion
	_scenery = scenery
	_axe = AxeView.new()
	_axe.name = "Axe"
	_axe.visible = false
	_player.add_child(_axe)
	Net.harvest_received.connect(func(_d: Array, _ms: int) -> void: _apply_down())
	Net.harvested.connect(_on_harvested)
	Net.harvest_got.connect(_on_got)
	Net.harvest_refused.connect(_on_refused)


## Read this world's trees and pickups (folding the pickups into the examine list), then lay out what's
## already down.
func configure(data: Dictionary, interactables: Array) -> void:
	_allowed = data.get("chopping", true) != false
	_trees.clear()
	var trees: Array = data.get("trees", [])
	for i in trees.size():
		var t: Variant = trees[i]
		if not (t is Array) or (t as Array).size() < 2:
			continue
		var kind := String(t[2]) if (t as Array).size() > 2 else "tree"
		_trees.append({ "index": i, "pos": WorldData.to_vec2(t), "wood": not NOT_WOOD.has(kind) })
	for p in data.get("pickups", []):
		if not (p is Dictionary):
			continue
		var kind := String(p.get("kind", ""))
		if not PICKUP_NAMES.has(kind):
			continue
		var id := String(p.get("id", ""))
		var pos := WorldData.to_vec2(p.get("position", [0, 0]))
		var view := PickupView.new()
		view.kind = kind
		view.position = pos
		view.name = "Pickup_%s" % id
		view.set_meta("understory", true)   # cleared with the scenery on a rebuild
		_scenery.add_child(view)
		var entry := {
			"pos": pos, "label": String(PICKUP_NAMES[kind]), "id": id, "tags": ["pickup", kind], "kind": "pickup",
			"render_index": -1, "lore": "", "affordances": {}, "pickup": id,
		}
		interactables.append(entry)
		_pickups[id] = { "view": view, "entry": entry }
	_apply_down()


## The axe is (or isn't) the selected item: carried over your shoulder, or put away.
func set_held(held: bool) -> void:
	_held = held
	_axe.visible = held
	if not held:
		_stop_chop()


## The use button with the axe selected: chop the tree you're standing at.
func use_axe() -> void:
	if _chop_index >= 0 or _waiting:
		return
	if not _allowed:
		_host.show_hint("The trees here are for keeping. Try another world.")
		return
	var i := _target()
	if i < 0:
		_host.show_hint("Walk up to a tree and tap Use to chop it.")
		return
	var t: Dictionary = _trees[i]
	if not bool(t["wood"]):
		_host.show_hint("That's not something to take an axe to.")
		return
	_player.look_toward((t["pos"] as Vector2) - _player.position)
	_axe.swing()
	var tv := _scenery.spec_tree(int(t["index"]))
	if tv != null:
		tv.shake()
	var ms := Net.chop_ms()
	if ms <= 0:
		_waiting = true
		Net.chop(int(t["index"]))
		get_tree().create_timer(3.0).timeout.connect(func() -> void: _waiting = false)
		return
	_chop_index = int(t["index"])
	_chop_anchor = _player.position
	_chop_left = float(ms) / 1000.0
	_swing_wait = SWING_GAP
	Net.chop_start(_chop_index)
	_host.show_hint("Chop, chop...")


## Whether the use button should look ready: the axe has a tree to swing at.
func can_chop() -> bool:
	if not _allowed:
		return false
	var pos := _player.position
	if _ready_age < 0.4 and pos.distance_squared_to(_ready_pos) < 9.0:
		return _ready >= 0
	_ready_pos = pos
	_ready_age = 0.0
	_ready = _target()
	return _ready >= 0 and bool(_trees[_ready]["wood"])


## Examining a stone or a piece of driftwood: pick it up.
func examine_pickup(entry: Dictionary) -> void:
	_companion.notify_interaction(entry["pos"], String(entry["id"]), entry["tags"])
	Net.gather(String(entry["pickup"]))


func update(delta: float) -> void:
	_ready_age += delta
	# Everything that's down grows back on its own clock.
	if not _regrow.is_empty():
		for id in _regrow.keys():
			_regrow[id] = float(_regrow[id]) - delta
			if float(_regrow[id]) <= 0.0:
				_regrow.erase(id)
				_grow_back(String(id))
	if _chop_index >= 0:
		if _player.position.distance_to(_chop_anchor) > WALK_OFF:
			_stop_chop()
			_host.show_hint("You lower the axe.")
			return
		_chop_left -= delta
		_swing_wait -= delta
		if _swing_wait <= 0.0:
			_swing_wait = SWING_GAP
			_axe.swing()
			var tv := _scenery.spec_tree(_chop_index)
			if tv != null:
				tv.shake()
		if _chop_left <= 0.0:
			_waiting = true
			Net.chop(_chop_index)
			_chop_index = -1
			get_tree().create_timer(3.0).timeout.connect(func() -> void: _waiting = false)


# ── the shared state ──

## Lay out what's down right now (on arrival, and when the join's push lands after the world was built).
func _apply_down() -> void:
	for d in Net.harvest_down():
		var id := String(d.get("id", ""))
		_regrow[id] = float(d.get("left_ms", 0)) / 1000.0
		_set_down(id, false)


func _on_harvested(node_id: String, left_ms: int, by: String) -> void:
	_regrow[node_id] = float(left_ms) / 1000.0
	_set_down(node_id, true, by)


func _set_down(id: String, animate: bool, by := "") -> void:
	if id.begins_with("t") and id.substr(1).is_valid_int():
		var tv := _scenery.spec_tree(int(id.substr(1)))
		if tv == null or tv.felled:
			return
		if animate:
			# It falls away from whoever chopped it (us, or a friend), or to the right.
			var from := _player.position if by == Net.local_id() or by == "" else tv.position + Vector2(-1, 0)
			tv.fell(1.0 if tv.position.x >= from.x else -1.0)
		else:
			tv.set_felled_now()
		_invalidate_ready()
		return
	if _pickups.has(id):
		var pk: Dictionary = _pickups[id]
		(pk["view"] as PickupView).set_taken(true, animate)
		(pk["entry"] as Dictionary)["_taken"] = true
		_host.secret_taken()   # (the examine scan's cache is stale)


func _grow_back(id: String) -> void:
	if id.begins_with("t") and id.substr(1).is_valid_int():
		var tv := _scenery.spec_tree(int(id.substr(1)))
		if tv != null and tv.felled:
			tv.regrow()
		_invalidate_ready()
		return
	if _pickups.has(id):
		var pk: Dictionary = _pickups[id]
		(pk["view"] as PickupView).set_taken(false, true)
		(pk["entry"] as Dictionary)["_taken"] = false
		_host.secret_taken()


func _on_got(info: Dictionary) -> void:
	_waiting = false
	var key := String(info.get("key", ""))
	var n := int(info.get("count", 1))
	var total := int(info.get("total", n))
	var name := String(info.get("name", "something")).to_lower()
	_companion.delight_at(_player.position)
	if key == "wood":
		_host.show_hint("Timber! +%d wood (you have %d)." % [n, total])
	else:
		_host.show_hint("You pick up %s %s (you have %d)." % [_article(name), name, total])


func _on_refused(_node_id: String, reason: String) -> void:
	_waiting = false
	match reason:
		"no_axe":
			_host.show_hint("You'll need an axe. The tinker in the bazaar can make you one.")
		"no_chopping":
			_host.show_hint("The trees here are for keeping. Try another world.")
		"not_wood":
			_host.show_hint("That's not something to take an axe to.")
		"too_far":
			_host.show_hint("Step a little closer.")
		_:
			pass   # someone else got there first: it's already falling


# ── helpers ──

## The tree to swing at: the nearest standing one in reach, preferring one in the way you face.
func _target() -> int:
	var pos := _player.position
	var face := _player.facing()
	var best := -1
	var best_score := INF
	for i in _trees.size():
		var t: Dictionary = _trees[i]
		var to: Vector2 = (t["pos"] as Vector2) - pos
		var d := to.length()
		if d > CHOP_REACH:
			continue
		var tv := _scenery.spec_tree(int(t["index"]))
		if tv == null or tv.felled:
			continue
		var score := d - (8.0 * to.normalized().dot(face) if d > 0.01 else 0.0)
		if score < best_score:
			best_score = score
			best = i
	return best


func _stop_chop() -> void:
	_chop_index = -1


func _invalidate_ready() -> void:
	_ready_age = INF


static func _article(word: String) -> String:
	if word.begins_with("a ") or word.begins_with("an ") or word.begins_with("some "):
		return ""
	return "an" if word.length() > 0 and "aeiou".contains(word[0]) else "a"


## A stone or a piece of driftwood lying on the bank: a small y-sorted node in the Scenery. Taken, it lifts
## and fades; back again, it fades in.
class PickupView extends Node2D:
	var kind := "stone"
	var _alpha := 1.0
	var _target := 1.0
	var _lift := 0.0

	func set_taken(taken: bool, animate: bool) -> void:
		_target = 0.0 if taken else 1.0
		if not animate:
			_alpha = _target
		_lift = 0.0
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		if is_equal_approx(_alpha, _target):
			set_process(false)
			return
		_alpha = move_toward(_alpha, _target, delta * 2.5)
		if _target == 0.0:
			_lift += delta * 30.0
		queue_redraw()

	func _draw() -> void:
		if _alpha <= 0.01:
			return
		var a := _alpha
		var up := Vector2(0, -_lift)
		draw_set_transform(Vector2(0, 3), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.16 * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if kind == "driftwood":
			ItemIcon.draw_driftwood(self, up + Vector2(0, -3), 0.9, Color(0.70, 0.60, 0.48), a)
		else:
			# a little heap of river stones
			ItemIcon.draw_stone(self, up + Vector2(-4, -1), 0.55, Color(0.58, 0.60, 0.62), a)
			ItemIcon.draw_stone(self, up + Vector2(4, 0), 0.5, Color(0.66, 0.66, 0.64), a)
			ItemIcon.draw_stone(self, up + Vector2(0, -4), 0.6, Color(0.62, 0.64, 0.68), a)
