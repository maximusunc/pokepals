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
	fails += _test_interaction_hesitates_then_comes_when_bonded(cfg)
	fails += _test_low_bond_sometimes_declines(cfg)
	fails += _test_bond_raises_approach_rate(cfg)
	fails += _test_appeal_raises_approach_rate(cfg)
	fails += _test_mood_raises_approach_rate(cfg)
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


# A copy of cfg with the appeal/mood nudges zeroed, so the approach decision is purely
# bond-driven and thus deterministic — for pinning the hesitation beat itself.
static func _consider_cfg_bond_only(cfg: Dictionary) -> Dictionary:
	var c := cfg.duplicate(true)
	c["curiosity_consider"]["appeal_weight"] = 0.0
	c["curiosity_consider"]["valence_weight"] = 0.0
	c["curiosity_consider"]["arousal_weight"] = 0.0
	return c


# Trigger a nearby interaction on the first frame, then run a couple of seconds of empty
# frames (companion held in place, so it stays >stop_distance from the thing). Reports whether
# it perked on notice and whether it ever actually set off toward the thing (desired_speed > 0).
static func _notice_then_run(brain: CompanionBrain, cfg: Dictionary, tags: Array = []) -> Dictionary:
	var companion_pos := Vector2(100, 100)
	var target := Vector2(200, 100)  # within curiosity_radius (260), beyond stop_distance (30)
	var event := { "type": "interaction", "position": target, "tags": tags }
	var first := brain.update(_ctx(companion_pos, Vector2(110, 100), [event]))
	var moved := false
	for _i in 140:  # ~2.2s at delta 0.016 — past the longest (fresh) consider delay
		if float(brain.update(_ctx(companion_pos, Vector2(110, 100), []))["desired_speed"]) > 0.0:
			moved = true
			break
	return { "perked": "perk" in first["reactions"], "moved": moved, "first": first }


# Count, over a span of seeds, how many fresh-or-bonded companions actually come over.
static func _approach_rate(cfg: Dictionary, bond: float, tags: Array = []) -> int:
	var approached := 0
	for sv in range(1, 41):
		var s := CompanionSelf.make_default(cfg)
		s.bond = bond
		var brain := CompanionBrain.new(cfg, sv, s)
		if _notice_then_run(brain, cfg, tags)["moved"]:
			approached += 1
	return approached


# Even fully bonded, it pauses a beat before moving (so coming over reads as a live decision),
# but after that brief hesitation it reliably comes. Weights zeroed so the outcome is exact.
static func _test_interaction_hesitates_then_comes_when_bonded(cfg: Dictionary) -> int:
	var c := _consider_cfg_bond_only(cfg)
	var s := CompanionSelf.make_default(c)
	s.bond = 1.0
	var brain := CompanionBrain.new(c, 1, s)
	var r := _notice_then_run(brain, c)
	var first: Dictionary = r["first"]
	var fails := 0
	fails += _ok(first["behavior"] == "curious", "notices the interaction at once (curious)")
	fails += _ok("perk" in first["reactions"], "perks the moment it notices")
	fails += _ok(float(first["desired_speed"]) == 0.0, "pauses to consider before moving — no movement on the notice frame")
	fails += _ok(bool(r["moved"]), "a bonded companion does come over after the brief hesitation")
	return fails


# A fresh companion always NOTICES (perks), but only sometimes decides to come — over many
# seeds we should see both outcomes, never all-or-nothing.
static func _test_low_bond_sometimes_declines(cfg: Dictionary) -> int:
	var approached := 0
	var trials := 40
	var always_perked := true
	for sv in range(1, trials + 1):
		var s := CompanionSelf.make_default(cfg)  # bond 0
		var brain := CompanionBrain.new(cfg, sv, s)
		var r := _notice_then_run(brain, cfg)
		if bool(r["moved"]):
			approached += 1
		if not bool(r["perked"]):
			always_perked = false
	var fails := 0
	fails += _ok(always_perked, "a fresh companion always notices (perks), even when it won't come")
	fails += _ok(approached > 0 and approached < trials, "a fresh companion sometimes comes, sometimes stays put (%d/%d)" % [approached, trials])
	return fails


# Bond is the primary axis: a fully bonded companion comes over far more often than a fresh one.
static func _test_bond_raises_approach_rate(cfg: Dictionary) -> int:
	var fresh := _approach_rate(cfg, 0.0)
	var bonded := _approach_rate(cfg, 1.0)
	return _ok(bonded > fresh, "a bonded companion comes over more often than a fresh one (%d vs %d)" % [bonded, fresh])


# Appeal tips marginal calls: a tempting find draws it over more than a dull one, at equal bond.
static func _test_appeal_raises_approach_rate(cfg: Dictionary) -> int:
	var loved := _approach_rate(cfg, 0.0, ["shiny"])
	var dull := _approach_rate(cfg, 0.0, ["made"])
	return _ok(loved > dull, "a tempting find draws it over more than a dull one (%d vs %d)" % [loved, dull])


# Mood tips marginal calls too: with the random walk silenced to isolate it, a bright/energized
# companion is readier to get up and come than a withdrawn one at the same bond.
static func _test_mood_raises_approach_rate(cfg: Dictionary) -> int:
	var c := cfg.duplicate(true)
	c["mood"]["walk_amp"] = 0.0
	var bright := _approach_rate_mood(c, 0.5, 0.5)
	var low := _approach_rate_mood(c, -0.4, -0.4)
	return _ok(bright > low, "a brighter mood makes it readier to come (%d vs %d)" % [bright, low])


static func _approach_rate_mood(cfg: Dictionary, valence: float, arousal: float) -> int:
	var approached := 0
	for sv in range(1, 41):
		var s := CompanionSelf.make_default(cfg)
		s.bond = 0.0
		s.mood_valence = valence
		s.mood_arousal = arousal
		var brain := CompanionBrain.new(cfg, sv, s)
		if _notice_then_run(brain, cfg)["moved"]:
			approached += 1
	return approached


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


# The anti-jitter fix, now expressed as graded commitment: a paused wander carries only the
# base nudge, but once it sets off on a roam its commitment jumps by committed_inertia, so the
# arbiter won't let same-band Follow out-bid it mid-excursion (the wander<->follow limit
# cycle). The arbiter honouring commitment is covered in TestArbiter; here we pin that
# WanderAction's commitment actually rises when it commits to a roam.
static func _test_roam_is_a_committed_beat(cfg: Dictionary) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var wander := CompanionActions.WanderAction.new(cfg, rng, 1)
	var s := CompanionSelf.make_default(cfg)
	var fails := 0
	var paused_commitment := wander.commitment(cfg)
	# Elapse the opening pause, then score with the player close enough to roam: it sets off.
	wander.tick(10.0)
	var perception := {
		"dist_to_player": 50.0,
		"player_pos": Vector2(100, 100),
		"has_poi": true,
		"nearest_poi": Vector2(160, 100),
	}
	wander.score(perception, s, cfg, rng)
	var roaming_commitment := wander.commitment(cfg)
	fails += _ok(is_equal_approx(paused_commitment, float(cfg["arbiter"]["commit_bonus"])), "a paused wander carries only the base commit nudge")
	fails += _ok(roaming_commitment > paused_commitment + 1.0, "setting off on a roam raises commitment well above the base (a committed beat)")
	return fails
