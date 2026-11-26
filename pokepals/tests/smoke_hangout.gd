extends SceneTree
## Headless smoke test for LINGERLONG's hangout: the wishing fountain and sitting together. Loads the real World
## scene from the fixture and checks:
##   * by the fountain the use button offers "Toss a coin"; examining it says how many wishes it holds;
##   * a `wished` from someone else swells the fountain and flies their coin, our own wish says a warm line, and a
##     crowd's wishes never put more than CoinArc.MAX coins in the air;
##   * by a bench the button offers "Sit"; a tap sits you on the seat (drawn sitting), a step gets you up, in front;
##   * anyone else still on a seat's anchor is drawn sitting, and standing again once they move; nobody is anywhere
##     else, and a seat someone's on isn't offered.
## Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_hangout.gd

const LINGERLONG_ID := "18181818-1818-1818-1818-181818181818"
const FIXTURE := "res://tests/world_fixtures/lingerlong.json"

var _world: Node
var _frames := 0
var _step := 0
var _fails := 0
var _peer = null
var _seat_i := -1


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(LINGERLONG_ID, WorldData.load_json(FIXTURE))
		router.current_world = LINGERLONG_ID
		router.arrival_portal_id = ""
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", LINGERLONG_ID)
		paused = false
		return false
	paused = false
	if _frames < 8:
		return false
	_step += 1
	match _step:
		1:
			# stand by the fountain, and let the camera come round to it (it hides itself off screen)
			_world._player.position = Vector2(20, 380)
			_world._camera.position = Vector2(20, 380)
		40:
			_fountain_checks()
		41:
			_seat_checks_begin()
		44:
			_seat_checks_sat()
		45:
			# a step on the stick gets us up
			Input.action_press("ui_down")
		48:
			Input.action_release("ui_down")
			_seat_checks_stood()
		49:
			_remote_begin()
		200:
			_remote_sat()
		201:
			_peer.set_remote_state(_peer.position + Vector2(60, 40), Vector2.DOWN)
		240:
			_check(_peer.seat_index() == -1, "and standing again once they walk off")
			return _finish()
	return false


func _fountain_checks() -> void:
	var net := root.get_node("/root/Net")
	var fv = _world.fountain_view()
	_check(fv != null and _world._wish_dir.active(), "the fountain is wired up")
	# by the fountain, empty-handed: the button tosses a coin
	_world._player.position = Vector2(20, 380)
	_world._fishing_dir._refresh_use()
	var ub = _world._use_button
	_check(ub.visible and ub._verb == "Toss a coin" and ub._key == "coin", "by the fountain the button offers Toss a coin (%s)" % ub._verb)
	# far from it, and from any seat: nothing
	_world._player.position = Vector2(0, -700)
	_world._fishing_dir._refresh_use()
	_check(not ub.visible or ub._verb == "", "out in the pool it offers nothing (%s)" % ub._verb)
	_world._player.position = Vector2(20, 380)
	# the count arrives, and examining says it
	net.emit_signal("wishes_received", 1203)
	var entry := {}
	for e in _world._interactables:
		if String(e.get("id", "")) == "wishing_fountain":
			entry = e
	_check(_world._wish_dir.examine(entry) and _world.hint_text().contains("1,203 wishes"), "examining it says how many wishes it holds (%s)" % _world.hint_text())
	# someone else wishes: the jets swell, the count goes up
	var before: float = fv.swelling()
	net.emit_signal("wished", "someone-else", 1204, true)
	_check(fv.swelling() > before + 0.3 and _world._wish_dir.count() == 1204, "a wish from someone else swells the fountain")
	# our own wish: a warm line, and our coin flies
	net.emit_signal("wish_made", 1205, false, 0)
	_check(_world.hint_text().contains("fountain doesn't mind") and CoinArc._live >= 1, "a free wish of ours says the fountain doesn't mind, and our coin flies")
	# a crowd: a friend's puppet stands by the basin and wishes a great many times; never more than MAX coins in the air
	var pd = _world._presence_dir
	pd._on_peer_joined("crowd")
	# Puppets are built once a position arrives and the drawing budget has run (SC-2): settle it now.
	net.emit_signal("state_received", "crowd", { "p": Vector2(-40, 360), "pf": Vector2.UP, "c": Vector2(-60, 370), "cl": Vector2.UP })
	pd.flush_puppets()
	for k in 40:
		net.emit_signal("wished", "crowd", 1206 + k, true)
	_check(CoinArc._live <= CoinArc.MAX and CoinArc._live >= CoinArc.MAX - 1, "a crowd's wishes keep at most %d coins in the air (%d)" % [CoinArc.MAX, CoinArc._live])
	_check(fv.swelling() >= FountainView.SWELL_MAX - 0.01, "and make the fountain rise as high as it goes")


func _seat_checks_begin() -> void:
	var seats: SeatLogic = PlayerView.seats
	_check(seats != null and seats.size() == 34, "the world's seats are known to every avatar")
	_seat_i = _index("fountain_bench_6_a")
	# walk up to the bench's front
	_world._player.position = seats.stand_point(_seat_i)
	_world._seat_dir._age = INF
	_world._seat_dir.update(0.016)
	_world._fishing_dir._refresh_use()
	var ub = _world._use_button
	_check(ub._verb == "Sit", "in front of a bench the button offers Sit (%s)" % ub._verb)
	_world._fishing_dir.use_item()


func _seat_checks_sat() -> void:
	var p = _world._player
	var seats: SeatLogic = PlayerView.seats
	_check(p.is_sitting() and p.position == seats.seat(_seat_i)["at"], "a tap sits you on the bench")
	_check(p.seat_index() == _seat_i, "and you're drawn sitting on it")
	_world._fishing_dir._refresh_use()
	_check(_world._use_button._verb == "Toss a coin", "sitting by the fountain you can still toss a coin (%s)" % _world._use_button._verb)


func _seat_checks_stood() -> void:
	var p = _world._player
	_check(not p.is_sitting() and p.seat_index() == -1, "a step on the stick gets you up")
	_check(p.position.distance_to(PlayerView.seats.stand_point(_seat_i)) < 30.0, "in front of the bench (%s)" % p.position)
	_check(not _world._companion.is_resting(), "and your companion gets up with you")


func _remote_begin() -> void:
	var pd = _world._presence_dir
	pd._on_peer_joined("sitter")
	var at: Vector2 = PlayerView.seats.seat(_index("fountain_bench_3_a"))["at"]
	var net2 := _world.get_node("/root/Net")
	net2.emit_signal("state_received", "sitter", { "p": at + Vector2(-30, 10), "pf": Vector2.DOWN, "c": at + Vector2(-50, 20), "cl": Vector2.DOWN })
	pd.flush_puppets()
	_peer = pd._remote_pairs["sitter"]["player"]
	net2.emit_signal("state_received", "sitter", { "p": at, "pf": Vector2.DOWN, "c": at + Vector2(-20, 10), "cl": Vector2.DOWN })


func _remote_sat() -> void:
	_check(_peer.seat_index() == _index("fountain_bench_3_a"), "a friend still on a bench's anchor is drawn sitting on it (%s %s %s)" % [_peer.position, _peer.velocity, _peer.seat_index()])
	# that lounger isn't offered to us
	var seats: SeatLogic = PlayerView.seats
	var near: Vector2 = seats.seat(_index("fountain_bench_3_a"))["at"] + Vector2(0, 20)
	_check(seats.nearest_free(near, 30.0, _world._presence_dir.remote_player_positions()) == -1, "and the seat they're on isn't offered to anyone else")


func _index(id: String) -> int:
	var seats: SeatLogic = PlayerView.seats
	for i in seats.size():
		if String(seats.seat(i)["id"]) == id:
			return i
	return -1


func _finish() -> bool:
	if _fails == 0:
		print("ALL HANGOUT SMOKE CHECKS PASSED")
		quit(0)
	else:
		print("HANGOUT SMOKE FAILED: %d" % _fails)
		quit(1)
	return true


func _check(cond: bool, label: String) -> void:
	print("  %s  %s" % [("PASS" if cond else "FAIL"), label])
	if not cond:
		_fails += 1
