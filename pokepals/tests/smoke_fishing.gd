extends SceneTree
## Headless smoke test for FISHING (usable items, step 1; docs/usable-items-design.md): loads the real
## World scene in the Vale, plays the server's side by hand through Net (there's no server here), and walks
## through a whole catch: the rod on its post, taking it onto the hotbar, the use button dimmed away from
## water and ready beside it, a cast, the bite, the timing ring landed, the catch coming up, a miss, walking
## off, switching slots, and a friend's rod and catch. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_fishing.gd

var _world: Node
var _net: Node
# Untyped on purpose: naming the director's class here would compile it before the Net autoload exists.
var _fish
var _player: Node2D
var _frames := 0
var _step := 0
var _step_frame := 0
var _fails := 0
var _rod_post: Dictionary = {}


func _ok(cond: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fails += 1


func _build() -> void:
	var router := root.get_node("/root/WorldRouter")
	_net = root.get_node("/root/Net")
	_net.prime_world_spec(router.VALE_ID, WorldData.load_json("res://tests/world_fixtures/vale.json"))
	var scene: PackedScene = load("res://scenes/world.tscn")
	_world = scene.instantiate()
	root.add_child(_world)
	_net.emit_signal("world_spec_unchanged", router.VALE_ID)
	paused = false


## Play the server: hand Net a frame as if it had come down the socket.
func _server(event: String, payload: Dictionary) -> void:
	_net._dispatch(event, payload)


func _next() -> void:
	_step += 1
	_step_frame = _frames


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		_build()
		return false
	if _frames < 4:
		return false
	if _frames > 3000:
		print("FISHING SMOKE FAILED: timed out at step %d" % _step)
		quit(1)
		return true
	var since := _frames - _step_frame
	match _step:
		0:
			print("SmokeFishing")
			_fish = _world._fishing_dir
			_player = _world.get_node("Scenery/Player")
			_player.set_process(false)   # we place the player by hand
			for e in _world._interactables:
				if String(e.get("gives", "")) == "rod":
					_rod_post = e
			_ok(not _rod_post.is_empty(), "the Vale has the rod's post, examinable")
			_ok(_fish._water != null and _fish._water.has_water(), "the Vale's water is known")
			_ok(not _world._hotbar.visible and not _world._use_button.visible, "no hotbar or use button before you have anything")
			_server("inventory", { "items": [] })
			_server("hotbar", { "slots": [null, null, null, null, null] })
			_next()
		1:
			_ok(_fish._rest != null and _fish._rest.visible, "the rod rests on its post while it's still there for you")
			# Examine the post: offline, Net.take_rod is a quiet no-op; then the server's answer.
			_player.position = _rod_post["pos"] + Vector2(0, 20)
			_world._invalidate_nearest()
			_world._try_interact()
			_server("rod_taken", { "ok": true, "new": true })
			_server("inventory", { "items": [{ "item_def_id": 10, "name": "Fishing Rod", "category": "tool", "key": "rod", "quantity": 1 }] })
			_server("hotbar", { "slots": [10, null, null, null, null] })
			_next()
		2:
			_ok(not _fish._rest.visible, "taken: the post is empty (for you)")
			_ok(_world._hotbar.visible and _world._use_button.visible, "the hotbar and the use button appear")
			_ok(_fish._rod.is_held(), "the rod is in your hand")
			_ok(_world._presence_dir._held == "rod", "friends are told you hold a rod")
			_ok(_world.hint_text().contains("hotbar"), "a hint says where it went")
			# Away from any water (where you arrive): the use button dims and a tap explains.
			_player.position = Vector2(560, -50)
			_next()
		3:
			_ok(not _world._use_button._ready_now, "away from water the use button is dim")
			_fish.use_item()
			_ok(_fish._phase == "" and _world.hint_text().contains("water"), "a tap there says to find some water")
			# Beside the little pond, facing it.
			_player.position = Vector2(600, 40)
			_player.look_toward(Vector2(640, 110) - _player.position)
			_next()
		4:
			_ok(_world._use_button._ready_now, "beside the pond the use button is ready")
			_fish.use_item()
			_ok(_fish._phase == "cast", "tap: the line flies out")
			_ok(_fish._water.is_water(_fish._bobber), "the bobber lands in the pond")
			_ok(_world._presence_dir._fishing.get("ph") == "cast", "friends see the cast")
			_server("fish_hooked", { "wait_ms": 150, "window": 0.2, "speed": 1.0 })
			_ok(_fish._phase == "wait", "the server hooks it: wait for a bite")
			_next()
		5:
			if _fish._phase == "wait" and since < 240:
				return false
			_ok(_fish._phase == "bite", "a bite")
			_ok(_world._use_button._alert, "the use button pulses")
			_ok(_fish._rod._ring != null, "the timing ring is drawn round the bobber")
			_next()
		6:
			# Tap as the ring meets the circle.
			if _fish._phase == "bite" and not _fish._ring.in_window() and since < 240:
				return false
			_fish.use_item()
			_ok(_fish._phase == "reel", "tapped in the window: landed, the server is told")
			_server("fish_caught", { "item_def_id": 220, "key": "koi", "name": "Moonscale Koi", "kind": "rare_fish", "color": [0.96, 0.94, 0.88], "count": 1 })
			_ok(_fish._phase == "caught", "the catch comes up")
			_ok(_fish._rod._pop_t >= 0.0, "it rises out of the water over your head")
			_ok(_world.hint_text().contains("Moonscale Koi") and _world.hint_text().contains("rare"), "a rare one, and it says so")
			var f: Dictionary = _world._presence_dir._fishing
			_ok(f.get("k") == "koi" and f.get("r") == "rare_fish" and int(f.get("n", 0)) == 1, "friends are told what you caught")
			_next()
		7:
			if _fish._phase != "" and since < 240:
				return false
			_ok(_fish._phase == "", "then the line is in, ready to cast again")
			# A miss: tap far too early.
			_fish.use_item()
			_server("fish_hooked", { "wait_ms": 0, "window": 0.2, "speed": 1.0 })
			_next()
		8:
			if _fish._phase == "wait" and since < 60:
				return false
			_fish.use_item()   # straight away: the ring is wide open, nowhere near the circle
			_ok(_fish._phase == "escaped" and _world.hint_text().contains("Next time"), "a miss: it slips away, next time")
			_next()
		9:
			if _fish._phase != "" and since < 240:
				return false
			# Walking off reels the line in.
			_fish.use_item()
			_server("fish_hooked", { "wait_ms": 5000, "window": 0.2, "speed": 1.0 })
			_player.position += Vector2(-60, 0)
			_next()
		10:
			_ok(_fish._phase == "", "walking away reels the line in")
			# Switching to an empty slot puts the rod away.
			_fish.select_slot(1)
			_ok(not _fish._rod.is_held() and _world._presence_dir._held == "", "an empty slot: nothing in hand")
			_fish.select_slot(0)
			_ok(_fish._rod.is_held(), "back to the rod")
			# A friend fishing beside us.
			_net.emit_signal("peer_joined", "friend")
			_net.emit_signal("identity_received", "friend", { "held": "rod", "fishing": { "b": [640, 100], "ph": "wait", "n": 0 } })
			_next()
		11:
			var pair: Dictionary = _world._presence_dir._remote_pairs.get("friend", {})
			var rod = pair.get("rod")
			_ok(rod != null and rod.is_held() and rod._phase == "wait", "a friend's rod and line are drawn")
			_net.emit_signal("identity_received", "friend", { "held": "rod", "fishing": { "b": [640, 100], "ph": "caught", "n": 1, "k": "minnow", "r": "fish", "c": [0.8, 0.8, 0.9] } })
			_ok(rod != null and rod._pop_t >= 0.0 and rod._pop_key == "minnow", "and their catch comes up")
			_net.emit_signal("identity_received", "friend", { "held": "", "fishing": null })
			_ok(rod != null and not rod.is_held(), "they put it away")
			_next()
		12:
			print("")
			if _fails == 0:
				print("ALL FISHING SMOKE CHECKS PASSED")
				quit(0)
			else:
				print("FISHING SMOKE FAILED: %d" % _fails)
				quit(1)
			return true
	return false
