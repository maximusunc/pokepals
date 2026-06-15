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
	fails += _test_wanders_to_poi_on_its_own(cfg)
	fails += _test_follow_overrides_self_wander(cfg)
	fails += _test_low_bond_lingers_when_player_drifts(cfg)
	fails += _test_high_bond_follows_instead_of_wandering(cfg)
	fails += _test_bond_grows_with_time_together(cfg)
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


# Like _ctx but with a standing point of interest the companion can wander to.
static func _ctx_poi(companion_pos: Vector2, player_pos: Vector2, poi: Vector2, time: float) -> Dictionary:
	return {
		"companion_pos": companion_pos,
		"player_pos": player_pos,
		"player_velocity": Vector2.ZERO,
		"delta": 0.05,
		"events": [],
		"time": time,
		"points_of_interest": [poi],
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


# With no input from the player but a prop nearby, the companion should — given
# enough time — decide to wander over and investigate on its own.
static func _test_wanders_to_poi_on_its_own(cfg: Dictionary) -> int:
	var brain := CompanionBrain.new(cfg, 12345)
	var poi := Vector2(120, 100)
	var wandered := false
	for i in 8000:
		var ctx := {
			"companion_pos": Vector2(100, 100),
			"player_pos": Vector2(100, 100),  # player stays put and close -> would otherwise idle
			"player_velocity": Vector2.ZERO,
			"delta": 0.05,
			"events": [],
			"time": i * 0.05,
			"points_of_interest": [poi],
		}
		if brain.update(ctx)["behavior"] == "wander":
			wandered = true
			break
	return _ok(wandered, "wanders off on its own to potter about")


# The distance "leash": even a barely-bonded, independent companion won't let the
# player get truly far. With the player well beyond follow_far, following must win
# over any self-directed wander.
static func _test_follow_overrides_self_wander(cfg: Dictionary) -> int:
	var brain := CompanionBrain.new(cfg, 7)
	var poi := Vector2(110, 100)
	var ever_wandered := false
	for i in 2000:
		var ctx := {
			"companion_pos": Vector2(100, 100),
			"player_pos": Vector2(400, 100),  # well beyond follow_far
			"player_velocity": Vector2.ZERO,
			"delta": 0.05,
			"events": [],
			"time": i * 0.05,
			"points_of_interest": [poi],
		}
		if brain.update(ctx)["behavior"] == "wander":
			ever_wandered = true
			break
	return _ok(not ever_wandered, "follows the player instead of self-wandering when they're far")


# The heart of it: a fresh, barely-bonded companion is its own creature. Once it's
# set off to investigate something, a small drift by the player shouldn't yank it
# to heel — it would rather keep pottering.
static func _test_low_bond_lingers_when_player_drifts(cfg: Dictionary) -> int:
	var brain := CompanionBrain.new(cfg, 12345, CompanionSelf.make_default(cfg))  # bond ~ 0
	var poi := Vector2(120, 100)
	# Settled right beside the player, let a self-directed wander get going.
	var started := false
	for i in 8000:
		if brain.update(_ctx_poi(Vector2(100, 100), Vector2(100, 100), poi, i * 0.05))["behavior"] == "wander":
			started = true
			break
	# The player now drifts to a gentle walking distance (past follow_near, well
	# short of follow_far). A barely-bonded companion keeps its own agenda.
	var behavior: String = brain.update(_ctx_poi(Vector2(100, 100), Vector2(160, 100), poi, 9999.0))["behavior"]
	var fails := 0
	fails += _ok(started, "low-bond companion sets off to potter about on its own")
	fails += _ok(behavior == "wander", "low-bond companion keeps wandering when the player only drifts a little")
	return fails


# The other end of the arc: a deeply bonded companion wants to be at your side. The
# moment the player steps away, following beats any lingering urge to investigate.
static func _test_high_bond_follows_instead_of_wandering(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 1.0
	var brain := CompanionBrain.new(cfg, 1, s)
	# Same modest drift as the low-bond case, with a prop right there to tempt it.
	var behavior: String = brain.update(_ctx_poi(Vector2(100, 100), Vector2(160, 100), Vector2(120, 100), 0.0))["behavior"]
	return _ok(behavior == "follow", "high-bond companion stays with the player instead of wandering off")


# Bond deepens with time spent close together.
static func _test_bond_grows_with_time_together(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var before := s.bond
	var brain := CompanionBrain.new(cfg, 1, s)
	for i in 600:  # ~30s of staying close
		brain.update(_ctx(Vector2(100, 100), Vector2(110, 100)))  # dist 10 -> "near"
	return _ok(brain.get_self().bond > before, "bond grows the longer the player stays near")
