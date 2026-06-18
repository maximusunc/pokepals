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
	fails += _test_fresh_roams_free_when_player_is_far(cfg)
	fails += _test_low_bond_lingers_when_player_drifts(cfg)
	fails += _test_high_bond_follows_instead_of_wandering(cfg)
	fails += _test_bonded_still_takes_excursions(cfg)
	fails += _test_low_bond_checks_in_when_player_far(cfg)
	fails += _test_high_bond_does_not_check_in(cfg)
	fails += _test_curiosity_biases_poi_choice(cfg)
	fails += _test_bond_grows_with_time_together(cfg)
	fails += _test_roam_is_a_committed_beat(cfg)
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


# A brain whose companion is already fully bonded — for the at-your-side beats.
static func _bonded_brain(cfg: Dictionary) -> CompanionBrain:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 1.0
	return CompanionBrain.new(cfg, 1, s)


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


# A fresh companion's comfort distance is map-wide, so following is a BONDED beat:
# once bonded it trails a short step behind a player who has moved away.
static func _test_follows_when_far(cfg: Dictionary) -> int:
	var brain := _bonded_brain(cfg)
	# Just past the snug comfort distance but within run_distance -> walk.
	var intent: Dictionary = brain.update(_ctx(Vector2(0, 0), Vector2(70, 0)))
	var fails := 0
	fails += _ok(intent["behavior"] == "follow", "a bonded companion follows when the player steps away")
	fails += _ok(intent["desired_speed"] == float(cfg["walk_speed"]), "walks while trailing")
	# Target should sit between companion and player (trailing behind player).
	var target: Vector2 = intent["move_target"]
	fails += _ok(target.x < 70.0 and target.x > 0.0, "follow target trails behind the player")
	return fails


static func _test_runs_when_very_far(cfg: Dictionary) -> int:
	var brain := _bonded_brain(cfg)
	var intent: Dictionary = brain.update(_ctx(Vector2(0, 0), Vector2(400, 0)))
	return _ok(intent["desired_speed"] == float(cfg["run_speed"]), "a bonded companion runs to catch up when it falls far behind")


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


# The heart of the new range: a fresh companion's territory is the whole map, so even
# with the player far across it the companion keeps living its own life rather than
# being yanked to heel. (The leash backstop returns only as the bond deepens — see the
# high-bond follow test.)
static func _test_fresh_roams_free_when_player_is_far(cfg: Dictionary) -> int:
	var brain := CompanionBrain.new(cfg, 7)
	var poi := Vector2(110, 100)
	var ever_wandered := false
	for i in 2000:
		var ctx := {
			"companion_pos": Vector2(100, 100),
			"player_pos": Vector2(900, 100),  # far across the map, still within its range
			"player_velocity": Vector2.ZERO,
			"delta": 0.05,
			"events": [],
			"time": i * 0.05,
			"points_of_interest": [poi],
		}
		if brain.update(ctx)["behavior"] == "wander":
			ever_wandered = true
			break
	return _ok(ever_wandered, "a fresh companion roams free even when the player is far across the map")


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
	# The player now drifts a little — but a fresh companion's comfort range is wide, so
	# this is still well within it. It keeps its own agenda and potters on.
	var behavior: String = brain.update(_ctx_poi(Vector2(100, 100), Vector2(160, 100), poi, 9999.0))["behavior"]
	var fails := 0
	fails += _ok(started, "low-bond companion sets off to potter about on its own")
	fails += _ok(behavior == "wander", "low-bond companion keeps wandering when the player only drifts a little")
	return fails


# The other end of the arc: when the player genuinely leaves (beyond the bonded
# companion's comfort bubble), following dominates over any urge to wander or
# investigate — it commits to staying with you. (Stepping past the bubble, not the
# old tiny step, since the bubble is exactly what lets a bonded companion still
# potter near you — see _test_bonded_still_takes_excursions.)
static func _test_high_bond_follows_instead_of_wandering(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 1.0
	var brain := CompanionBrain.new(cfg, 1, s)
	var poi := Vector2(120, 100)
	var followed_throughout := true
	# Player a clear stride beyond the comfort bubble; over a stretch of time the
	# companion should keep following and never peel off to wander/investigate.
	for i in 400:
		var behavior: String = brain.update(_ctx_poi(Vector2(100, 100), Vector2(450, 100), poi, i * 0.05))["behavior"]
		if behavior == "wander" or behavior == "checkin":
			followed_throughout = false
			break
	return _ok(followed_throughout, "high-bond companion stays with the player when they genuinely leave")


# The heart of "never leashed": even fully bonded, the companion still takes its own
# little excursions rather than gluing to your side. With the player right there, it
# should still set off to potter about on its own at least sometimes.
static func _test_bonded_still_takes_excursions(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 1.0
	var brain := CompanionBrain.new(cfg, 1, s)
	var poi := Vector2(180, 100)
	var wandered := false
	for i in 8000:
		if brain.update(_ctx_poi(Vector2(100, 100), Vector2(100, 100), poi, i * 0.05))["behavior"] == "wander":
			wandered = true
			break
	return _ok(wandered, "a fully bonded companion still takes little excursions on its own")


# During the independent phase, a companion that's off on its own should come over to
# check in on the player by itself now and then.
static func _test_low_bond_checks_in_when_player_far(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.1
	s.traits["clinginess"] = 1.0  # a sociable companion, to keep the test snappy
	var brain := CompanionBrain.new(cfg, 1, s)
	var checked_in := false
	# Player well beyond the comfort distance but within reach (follow_far).
	for i in 12000:
		var ctx := {
			"companion_pos": Vector2(100, 100),
			"player_pos": Vector2(2600, 100),
			"player_velocity": Vector2.ZERO,
			"delta": 0.05,
			"events": [],
			"time": i * 0.05,
			"points_of_interest": [],
		}
		if brain.update(ctx)["behavior"] == "checkin":
			checked_in = true
			break
	return _ok(checked_in, "a low-bond companion comes over to check in on its own")


# Once fully bonded it's already at your side, so deliberate check-ins fade away: it
# just follows when you're far, never trekking back for a separate "visit".
static func _test_high_bond_does_not_check_in(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 1.0
	s.traits["clinginess"] = 1.0
	var brain := CompanionBrain.new(cfg, 1, s)
	var ever_checked_in := false
	for i in 4000:
		var ctx := {
			"companion_pos": Vector2(100, 100),
			"player_pos": Vector2(2600, 100),
			"player_velocity": Vector2.ZERO,
			"delta": 0.05,
			"events": [],
			"time": i * 0.05,
			"points_of_interest": [],
		}
		if brain.update(ctx)["behavior"] == "checkin":
			ever_checked_in = true
			break
	return _ok(not ever_checked_in, "a fully bonded companion does not do separate check-ins")


# The "interactable-inclined" dimension: a curious companion heads for a nearby prop
# when it wanders; an incurious one ambles to open ground instead.
static func _test_curiosity_biases_poi_choice(cfg: Dictionary) -> int:
	var poi := Vector2(180, 100)
	var curious := _count_poi_targets(cfg, 1.0, poi)
	var incurious := _count_poi_targets(cfg, 0.0, poi)
	var fails := 0
	fails += _ok(curious > 0, "a curious companion heads for the prop when wandering")
	fails += _ok(curious > incurious, "a curious companion targets props more than an incurious one")
	return fails


# Count frames where a wandering companion (with the given curiosity) is heading for
# the prop, over a fixed seeded run.
static func _count_poi_targets(cfg: Dictionary, curiosity: float, poi: Vector2) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.traits["curiosity"] = curiosity
	var brain := CompanionBrain.new(cfg, 4242, s)
	var count := 0
	for i in 4000:
		var intent := brain.update(_ctx_poi(Vector2(100, 100), Vector2(100, 100), poi, i * 0.05))
		if intent["behavior"] == "wander" and (intent["look_at"] as Vector2).is_equal_approx(poi):
			count += 1
	return count


# Bond deepens with time spent close together.
static func _test_bond_grows_with_time_together(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var before := s.bond
	var brain := CompanionBrain.new(cfg, 1, s)
	for i in 600:  # ~30s of staying close
		brain.update(_ctx(Vector2(100, 100), Vector2(110, 100)))  # dist 10 -> "near"
	return _ok(brain.get_self().bond > before, "bond grows the longer the player stays near")


# The anti-jitter fix: a roam must be a COMMITTED beat. While paused the wander is freely
# interruptible; once it sets off on a roam it declares itself non-interruptible, so the
# arbiter won't let same-band Follow unseat it mid-excursion (which is what caused the
# wander<->follow limit cycle). The arbiter honouring this is covered in TestArbiter; here
# we pin the contract WanderAction itself exposes.
static func _test_roam_is_a_committed_beat(cfg: Dictionary) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var wander := CompanionActions.WanderAction.new(cfg, rng, 1)
	var s := CompanionSelf.make_default(cfg)
	var fails := 0
	fails += _ok(wander.interruptible(), "a paused wander is freely interruptible")
	# Elapse the opening pause, then score with the player close enough to roam: it sets off.
	wander.tick(10.0)
	var perception := {
		"dist_to_player": 50.0,
		"player_pos": Vector2(100, 100),
		"has_poi": true,
		"nearest_poi": Vector2(160, 100),
	}
	wander.score(perception, s, cfg, rng)
	fails += _ok(not wander.interruptible(), "once set off on a roam, a wander is a committed (non-interruptible) beat")
	return fails
