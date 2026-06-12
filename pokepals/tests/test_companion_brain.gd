class_name TestCompanionBrain
## Tests for the companion's pure decision logic. No nodes, no rendering — just
## context in, intent out — which is exactly what the logic/presentation split
## buys us.

static func run_all() -> int:
	var fails := 0
	var cfg: Dictionary = WorldData.load_json("res://data/companion.json")
	print("TestCompanionBrain")
	fails += _test_idle_when_close(cfg)
	fails += _test_follows_when_far(cfg)
	fails += _test_runs_when_very_far(cfg)
	fails += _test_curious_about_nearby_interaction(cfg)
	fails += _test_ignores_distant_interaction(cfg)
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _ctx(companion_pos: Vector2, player_pos: Vector2, events: Array = []) -> Dictionary:
	return {
		"companion_pos": companion_pos,
		"player_pos": player_pos,
		"player_velocity": Vector2.ZERO,
		"delta": 0.016,
		"events": events,
		"time": 0.0,
	}


static func _test_idle_when_close(cfg: Dictionary) -> int:
	var brain := CompanionBrain.new(cfg, 1)
	var intent: Dictionary = brain.update(_ctx(Vector2(100, 100), Vector2(110, 100)))
	var fails := 0
	fails += _ok(intent["behavior"] == "idle", "idles when within follow_near")
	fails += _ok(intent["desired_speed"] == 0.0, "no movement intent while idling")
	return fails


static func _test_follows_when_far(cfg: Dictionary) -> int:
	var brain := CompanionBrain.new(cfg, 1)
	# Just beyond follow_near but within follow_far -> walk.
	var intent: Dictionary = brain.update(_ctx(Vector2(0, 0), Vector2(70, 0)))
	var fails := 0
	fails += _ok(intent["behavior"] == "follow", "follows when beyond follow_near")
	fails += _ok(intent["desired_speed"] == float(cfg["walk_speed"]), "walks while trailing")
	# Target should sit between companion and player (trailing behind player).
	var target: Vector2 = intent["move_target"]
	fails += _ok(target.x < 70.0 and target.x > 0.0, "follow target trails behind the player")
	return fails


static func _test_runs_when_very_far(cfg: Dictionary) -> int:
	var brain := CompanionBrain.new(cfg, 1)
	var intent: Dictionary = brain.update(_ctx(Vector2(0, 0), Vector2(400, 0)))
	return _ok(intent["desired_speed"] == float(cfg["run_speed"]), "runs to catch up when beyond follow_far")


static func _test_curious_about_nearby_interaction(cfg: Dictionary) -> int:
	var brain := CompanionBrain.new(cfg, 1)
	var event := { "type": "interaction", "position": Vector2(120, 100) }
	var intent: Dictionary = brain.update(_ctx(Vector2(100, 100), Vector2(110, 100), [event]))
	var fails := 0
	fails += _ok(intent["behavior"] == "curious", "becomes curious about a nearby interaction")
	fails += _ok(intent["look_at"] == Vector2(120, 100), "attends to the interaction point")
	fails += _ok("perk" in intent["reactions"], "emits a 'perk' reaction when it notices")
	return fails


static func _test_ignores_distant_interaction(cfg: Dictionary) -> int:
	var brain := CompanionBrain.new(cfg, 1)
	var far := float(cfg["curiosity_radius"]) + 200.0
	var event := { "type": "interaction", "position": Vector2(far, 0) }
	var intent: Dictionary = brain.update(_ctx(Vector2(0, 0), Vector2(10, 0), [event]))
	return _ok(intent["behavior"] != "curious", "ignores an interaction beyond curiosity_radius")
