class_name TestBattleLogic
## Pure-logic tests for the battle core. No engine/UI involved — just data in,
## data out — which is exactly what makes the core easy to test and safe to retune.
## Run headlessly via tests/run_tests.gd.

static func run_all() -> int:
	var fails := 0
	var defs: Dictionary = DataLoader.load_all("res://data/")
	print("TestBattleLogic")
	fails += _test_type_chart(defs)
	fails += _test_determinism(defs)
	fails += _test_purity(defs)
	fails += _test_effectiveness_feeds_damage(defs)
	fails += _test_battle_reaches_conclusion(defs)
	return fails


# --- helpers -----------------------------------------------------------------

static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1

static func _act(side: String, move_id: String) -> Dictionary:
	return { "side": side, "kind": "move", "move_id": move_id }

static func _find_event(events: Array, type: String, side: String) -> Dictionary:
	for e in events:
		if e["type"] == type and e.get("side", "") == side:
			return e
	return {}


# --- tests -------------------------------------------------------------------

static func _test_type_chart(defs: Dictionary) -> int:
	var chart: Dictionary = defs["types"]["chart"]
	var fails := 0
	fails += _ok(TypeChart.effectiveness("aqua", "ember", chart) == 2.0, "aqua is super effective vs ember")
	fails += _ok(TypeChart.effectiveness("ember", "aqua", chart) == 0.5, "ember is weak vs aqua")
	fails += _ok(TypeChart.effectiveness("ember", "spark", chart) == 1.0, "ember vs spark is neutral")
	return fails

static func _test_determinism(defs: Dictionary) -> int:
	var actions := { "player": _act("player", "ember_claw"), "enemy": _act("enemy", "vine_whip") }
	var a: Dictionary = BattleState.make_initial_state(["emberpup"], ["florafawn"], defs, 42)
	var b: Dictionary = BattleState.make_initial_state(["emberpup"], ["florafawn"], defs, 42)
	# Resolve several turns; same seed + same actions must replay identically.
	for i in range(3):
		a = BattleLogic.resolve_turn(a, actions, defs)
		b = BattleLogic.resolve_turn(b, actions, defs)
	var same := JSON.stringify(a) == JSON.stringify(b)
	var differs_by_seed: bool = JSON.stringify(BattleLogic.resolve_turn(
		BattleState.make_initial_state(["emberpup"], ["florafawn"], defs, 99), actions, defs)
	) != JSON.stringify(BattleLogic.resolve_turn(
		BattleState.make_initial_state(["emberpup"], ["florafawn"], defs, 42), actions, defs))
	var fails := 0
	fails += _ok(same, "same seed + actions replay identically")
	fails += _ok(differs_by_seed, "different seeds diverge")
	return fails

static func _test_purity(defs: Dictionary) -> int:
	var actions := { "player": _act("player", "flame_burst"), "enemy": _act("enemy", "leaf_storm") }
	var state: Dictionary = BattleState.make_initial_state(["emberpup"], ["florafawn"], defs, 7)
	var before := JSON.stringify(state)
	BattleLogic.resolve_turn(state, actions, defs)
	var after := JSON.stringify(state)
	return _ok(before == after, "resolve_turn does not mutate its input state")

static func _test_effectiveness_feeds_damage(defs: Dictionary) -> int:
	# aqua move vs an ember defender should record 2.0; vs a flora defender, 1.0.
	# Scan seeds so we test a turn where the move actually lands.
	var fails := 0
	fails += _ok(_recorded_effectiveness(defs, "florafawn", "water_jet", "emberpup") == 2.0,
		"super-effective hit records effectiveness 2.0")
	fails += _ok(_recorded_effectiveness(defs, "emberpup", "water_jet", "florafawn") == 1.0,
		"neutral hit records effectiveness 1.0")
	return fails

static func _recorded_effectiveness(defs: Dictionary, player_id: String, move_id: String, enemy_id: String) -> float:
	for seed_value in range(30):
		var state: Dictionary = BattleState.make_initial_state([player_id], [enemy_id], defs, seed_value)
		# Player faster-or-equal isn't guaranteed; just resolve and look for a landed hit on the enemy.
		var actions := { "player": _act("player", move_id), "enemy": _act("enemy", "vine_whip") }
		var result: Dictionary = BattleLogic.resolve_turn(state, actions, defs)
		var dmg := _find_event(result["events"], "damage", "enemy")
		if not dmg.is_empty():
			return float(dmg["effectiveness"])
	return -1.0  # no landed hit found -> test will fail visibly

static func _test_battle_reaches_conclusion(defs: Dictionary) -> int:
	var state: Dictionary = BattleState.make_initial_state(["emberpup"], ["florafawn"], defs, 1)
	var actions := { "player": _act("player", "ember_claw"), "enemy": _act("enemy", "vine_whip") }
	var guard := 0
	while not BattleState.is_over(state) and guard < 100:
		state = BattleLogic.resolve_turn(state, actions, defs)
		guard += 1
	var fails := 0
	fails += _ok(BattleState.is_over(state), "battle terminates within 100 turns")
	fails += _ok(BattleState.winner(state) in ["player", "enemy"], "a winner is declared")
	fails += _ok(state["phase"] == "over", "phase becomes 'over'")
	return fails
