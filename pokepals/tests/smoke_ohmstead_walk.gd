extends SceneTree
## Headless WALKING test for Ohmstead's ribbon boards. smoke_ohmstead.gd sets the companion down on each node;
## this one lets it WALK there on its own legs, in real time, which is what found the bug it guards against (a
## hint glance that froze the body: tap a node while the companion was glancing and it never moved again).
##
## Each situation does its mischief on a fresh board (after three nodes are lit), then the board must still be
## closable by plain tapping, so nothing a player does can leave the companion standing:
##   plain, a tap during a glance, the board changing during a glance, tapping ahead along a line, tapping ahead
##   round a corner (refused, then fine), winding back mid-run, a Call mid-run, a Pet mid-run, standing on the
##   very node it has to reach, walking far away and back, and a tap as a bird followed by one as a fox.
## It takes about three and a half minutes (the companion really walks every board). Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_ohmstead_walk.gd
var _world: Node
var _frames := 0
var _sol: Array = [10, 11, 6, 5, 0, 1, 2, 7, 12, 13, 8, 3, 4, 9, 14, 19, 18, 17]
var _scenarios := ["plain", "glance", "glance_then_change", "tap_ahead_straight", "tap_ahead_corner", "wind_mid_run", "call_mid_run", "pet_mid_run", "player_on_node", "walk_away_and_back", "bird_then_fox"]
var _si := -1
var _k := 0
var _t0 := 0
var _state := "boot"
var _did := false
var _fails := 0

func _cd(): return _world._circuit_dir
func _b() -> Dictionary: return _cd().board("sector")
func _m() -> CircuitBoard: return _b()["model"]
func _pos(n: int) -> Vector2: return _m().pos_of(n, _b()["origin"], 64.0)
func _tap(n: int) -> void: _cd().on_tap(_pos(n))
func _since() -> int: return Time.get_ticks_msec() - _t0

func _next_scenario() -> bool:
	_si += 1
	if _si >= _scenarios.size():
		print("ALL OHMSTEAD WALK CHECKS PASSED" if _fails == 0 else "OHMSTEAD WALK FAILED: %d" % _fails)
		quit(0 if _fails == 0 else 1)
		return true
	_cd()._release()
	_m().clear()
	_b()["closed"] = false
	_cd()._local_changed(_b())
	_world._player.position = (_b()["origin"] as Vector2) + Vector2(-50, 130)
	_world._companion.position = _world._player.position + Vector2(16, 0)
	_world._companion._form_species = "fox"
	_k = 0
	_did = false
	_state = "tap"
	_t0 = Time.get_ticks_msec()
	return false

func _process(_d: float) -> bool:
	_frames += 1
	paused = false
	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec("x", WorldData.load_json("res://tests/world_fixtures/ohmstead.json"))
		router.current_world = "x"
		router.arrival_portal_id = ""
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", "x")
		return false
	if _frames < 30:
		return false
	if _state == "boot":
		return _next_scenario()
	var name: String = _scenarios[_si]
	var comp = _world._companion
	var m := _m()
	if _state == "tap":
		if m.is_closed():
			print("  PASS  the board closes after: ", name)
			return _next_scenario()
		# the scenario's mischief, once, after three nodes are lit
		if name == "tap_ahead_straight" and _k == 5 and not _did:
			_did = true
			_tap(1); _tap(2)                # 2 is straight on past 1: the second tap takes the run on to it
			_k = 7; _state = "wait_for"; _t0 = Time.get_ticks_msec(); return false
		if _k == 3 and not _did and name != "tap_ahead_straight":
			_did = true
			match name:
				"glance":
					_cd()._idle = 100.0
					_state = "pause"; _t0 = Time.get_ticks_msec(); return false
				"glance_then_change":
					_cd()._idle = 100.0
					_state = "pause_change"; _t0 = Time.get_ticks_msec(); return false
				"tap_ahead_straight":
					_tap(5); _tap(0)            # 0 is straight on past 5: one run through both
					_k = 5; _state = "wait_for"; _t0 = Time.get_ticks_msec(); return false
				"tap_ahead_corner":
					_tap(5); _tap(0); _tap(1)   # 1 is round a corner from 0: refused until 0 is lit
				"wind_mid_run":
					_tap(5)
					_state = "mid_wind"; _t0 = Time.get_ticks_msec(); return false
				"call_mid_run":
					_tap(5)
					_state = "mid_call"; _t0 = Time.get_ticks_msec(); return false
				"pet_mid_run":
					_tap(5)
					_state = "mid_pet"; _t0 = Time.get_ticks_msec(); return false
				"player_on_node":
					_world._player.position = _pos(5)     # you stand exactly where it has to go
				"walk_away_and_back":
					_world._player.position = (_b()["origin"] as Vector2) + Vector2(-700, 130)
					_state = "away"; _t0 = Time.get_ticks_msec(); return false
				"bird_then_fox":
					comp._form_species = "bird"
					_tap(5)
					comp._form_species = "fox"
		var want := -1
		for n in _sol:
			if not m.is_lit(int(n)):
				want = int(n)
				break
		_tap(want)
		_k = m.path.size()
		_t0 = Time.get_ticks_msec()
		_state = "wait"
		return false
	if _state == "pause":
		if _since() > 600:
			_state = "tap"
		return false
	if _state == "pause_change":
		if _since() > 600:
			m.wind_to(m.head())              # the board changes under the glance (as a friend's move would)
			_cd()._local_changed(_b())
			_state = "tap"
		return false
	if _state == "mid_wind":
		if _since() > 300:
			_tap(11)                         # wind back while it is on its way
			_state = "tap"
		return false
	if _state == "mid_call":
		if _since() > 300:
			comp.issue_command("come", _world._player.position)
			_state = "settle"; _t0 = Time.get_ticks_msec()
		return false
	if _state == "mid_pet":
		if _since() > 300:
			comp.issue_command("pet", _world._player.position)
			_state = "settle"; _t0 = Time.get_ticks_msec()
		return false
	if _state == "away":
		if _since() > 1500:
			_world._player.position = (_b()["origin"] as Vector2) + Vector2(-50, 130)
			_state = "settle"; _t0 = Time.get_ticks_msec()
		return false
	if _state == "settle":
		if _since() > 1200:
			_state = "tap"
		return false
	if _state == "wait_for":
		if m.path.size() >= _k:
			_state = "tap"
		elif _since() > 9000:
			_stuck(name); return _next_scenario()
		return false
	if _state == "wait":
		if m.path.size() > _k or m.is_closed():
			_k = m.path.size()
			_state = "tap"
		elif _since() > 9000:
			_stuck(name); return _next_scenario()
	return false

func _stuck(name: String) -> void:
	var comp = _world._companion
	_fails += 1
	print("  FAIL  the companion was left standing after: ", name, " (path=", _m().path, " target=", _cd()._target, " hold=", _cd()._hold, " engaged=", _cd().engaged_board(),
		" point_t=", comp._point_t, " pending=", comp.pending_command(), " form=", comp.current_form_species(),
		" comp-target dist=", ("%.1f" % comp.position.distance_to(_pos(_cd()._target))) if _cd()._target >= 0 else "-",
		" player-comp=", "%.0f" % comp.position.distance_to(_world._player.position), ")")
