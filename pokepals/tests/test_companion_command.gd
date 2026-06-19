class_name TestCompanionCommand
## Tests for player COMMANDS — the call/whistle (and, later, pet). Pure logic: the command
## action is exercised directly with hand-made perception dicts (mirroring how the wander beat
## is unit-tested), plus one end-to-end check that issue_command routes through the brain.
##
## The point being pinned: a whistle is BOND- and DISTANCE-gated, never a guaranteed summon —
## out of earshot it does nothing; in earshot it always acknowledges; whether it then comes
## scales with the bond; and calling never grows bond.

static func run_all() -> int:
	var fails := 0
	var cfg: Dictionary = WorldData.load_json("res://data/companion.json")
	print("TestCompanionCommand")
	fails += _test_out_of_earshot_does_nothing(cfg)
	fails += _test_in_earshot_acknowledges_and_lifts_mood(cfg)
	fails += _test_bonded_comes_after_acknowledging(cfg)
	fails += _test_fresh_acknowledges_but_stays(cfg)
	fails += _test_calling_never_grows_bond(cfg)
	fails += _test_escorts_after_arriving(cfg)
	fails += _test_brain_routes_a_call(cfg)
	fails += _test_brain_ignores_a_call_from_afar(cfg)
	fails += _test_pet_only_when_adjacent(cfg)
	fails += _test_fresh_pet_can_shy_away(cfg)
	fails += _test_bonded_pet_leans_in(cfg)
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 1
	return r


# A perception dict the ComeAction reads: the order, the distance, the pre-rolled die, and the
# positions act() needs. command_roll < come_chance means "will come".
static func _percept(dist: float, command_roll: float) -> Dictionary:
	return {
		"command": "come",
		"dist_to_player": dist,
		"command_roll": command_roll,
		"companion_pos": Vector2(0, 0),
		"player_pos": Vector2(dist, 0),
	}


static func _ctx(companion_pos: Vector2, player_pos: Vector2) -> Dictionary:
	return {
		"companion_pos": companion_pos,
		"player_pos": player_pos,
		"player_velocity": Vector2.ZERO,
		"delta": 0.016,
		"events": [],
		"time": 0.0,
	}


# A whistle from beyond hear_radius can't be heard: the action never latches, even fully bonded.
static func _test_out_of_earshot_does_nothing(cfg: Dictionary) -> int:
	var come := CompanionActions.ComeAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	s.bond = 1.0
	var far := float(cfg["come"]["hear_radius"]) + 500.0
	var score := come.score(_percept(far, 0.0), s, cfg, _rng())
	return _ok(score == 0.0, "a call from beyond hear_radius does nothing (no infinite-range summon)")


# Within earshot it always HEARS: it latches, perks/looks in place without moving, and the mood
# lifts at being called — regardless of whether it will end up coming (here it won't: roll high).
static func _test_in_earshot_acknowledges_and_lifts_mood(cfg: Dictionary) -> int:
	var come := CompanionActions.ComeAction.new(5)
	var s := CompanionSelf.make_default(cfg)  # bond 0
	var v0 := s.mood_valence
	var a0 := s.mood_arousal
	var score := come.score(_percept(300.0, 0.99), s, cfg, _rng())
	var intent := come.act(_percept(300.0, 0.99), s, cfg, _rng(), 0.016)
	var fails := 0
	fails += _ok(score == 1.0, "a call within earshot is heard and latches the command beat")
	fails += _ok(float(intent["desired_speed"]) == 0.0, "acknowledges in place — no movement on the notice frame")
	fails += _ok("perk" in intent["reactions"], "perks to acknowledge the call")
	fails += _ok(s.mood_valence > v0 and s.mood_arousal > a0, "being called lifts the mood")
	return fails


# A fully bonded companion, after the brief acknowledgment, comes running (at run_speed).
static func _test_bonded_comes_after_acknowledging(cfg: Dictionary) -> int:
	var come := CompanionActions.ComeAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	s.bond = 1.0
	var p := _percept(300.0, 0.0)  # roll 0 -> certainly comes
	come.score(p, s, cfg, _rng())
	var moved_at := 0.0
	for _i in 200:  # past the ack_pause, then it should set off
		var intent := come.act(p, s, cfg, _rng(), 0.016)
		if float(intent["desired_speed"]) > 0.0:
			moved_at = float(intent["desired_speed"])
			break
	var fails := 0
	fails += _ok(moved_at > 0.0, "a bonded companion comes over after acknowledging")
	fails += _ok(is_equal_approx(moved_at, float(cfg["run_speed"])), "it runs to you, not strolls")
	return fails


# A fresh companion with an unfavorable roll acknowledges, then declines: it never sets off.
static func _test_fresh_acknowledges_but_stays(cfg: Dictionary) -> int:
	var come := CompanionActions.ComeAction.new(5)
	var s := CompanionSelf.make_default(cfg)  # bond 0
	var p := _percept(300.0, 0.99)  # roll high -> won't come
	come.score(p, s, cfg, _rng())
	var first := come.act(p, s, cfg, _rng(), 0.016)
	var ever_moved := false
	for _i in 200:
		if float(come.act(p, s, cfg, _rng(), 0.016)["desired_speed"]) > 0.0:
			ever_moved = true
			break
	var fails := 0
	fails += _ok("perk" in first["reactions"], "a fresh companion still acknowledges the call")
	fails += _ok(not ever_moved, "a fresh companion that declines never comes over")
	return fails


static func _test_calling_never_grows_bond(cfg: Dictionary) -> int:
	var come := CompanionActions.ComeAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.5
	var b0 := s.bond
	var p := _percept(300.0, 0.0)
	come.score(p, s, cfg, _rng())
	for _i in 200:
		come.act(p, s, cfg, _rng(), 0.016)
	return _ok(is_equal_approx(s.bond, b0), "calling never grows bond (a whistle isn't earned discovery)")


# A mutable escort-phase perception: positions, whether the player is moving, and (so it never
# re-latches) an empty command unless we're issuing the call.
static func _escort_percept(companion_pos: Vector2, player_pos: Vector2, moving: bool, command: String = "") -> Dictionary:
	return {
		"command": command,
		"dist_to_player": companion_pos.distance_to(player_pos),
		"command_roll": 0.0,
		"companion_pos": companion_pos,
		"player_pos": player_pos,
		"player_moving": moving,
		"player_velocity": Vector2(80, 0) if moving else Vector2.ZERO,
	}


# After arriving it ESCORTS: it sticks close and follows a MOVING player (rather than parking at
# the call spot), keeps escorting as long as you move, and only releases a beat after you settle.
static func _test_escorts_after_arriving(cfg: Dictionary) -> int:
	var come := CompanionActions.ComeAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	s.bond = 1.0
	var stay := float(cfg["come"]["stay"])
	var companion_pos := Vector2(0, 0)
	var player_pos := Vector2(10, 0)  # already within stop_distance -> arrives right after ack
	# Latch the call, then drive past the acknowledgment to reach the escort phase.
	come.score(_escort_percept(companion_pos, player_pos, false, "come"), s, cfg, _rng())
	var hopped := false
	for _i in 60:  # ~1s, past ack_pause
		var intent := come.act(_escort_percept(companion_pos, player_pos, false), s, cfg, _rng(), 0.016)
		if "hop" in intent["reactions"]:
			hopped = true

	# Player runs off: the companion should chase to keep close, and NOT release while you move,
	# even well past `stay` seconds (the escort window refreshes while moving).
	player_pos = Vector2(600, 0)
	var chased := false
	var released_while_moving := false
	for _i in int((stay + 3.0) / 0.016):
		var intent := come.act(_escort_percept(companion_pos, player_pos, true), s, cfg, _rng(), 0.016)
		if float(intent["desired_speed"]) > 0.0:
			chased = true
		if come.score(_escort_percept(companion_pos, player_pos, true), s, cfg, _rng()) <= 0.0:
			released_while_moving = true
			break

	# Player stops, companion settled close: it should drift back to its own life after ~stay.
	player_pos = companion_pos + Vector2(10, 0)
	var release_t := -1.0
	for i in int((stay + 2.0) / 0.016):
		come.act(_escort_percept(companion_pos, player_pos, false), s, cfg, _rng(), 0.016)
		if come.score(_escort_percept(companion_pos, player_pos, false), s, cfg, _rng()) <= 0.0:
			release_t = i * 0.016
			break

	var fails := 0
	fails += _ok(hopped, "gives the arrival hop when it reaches you")
	fails += _ok(chased, "escorts a moving player (follows instead of parking at the call spot)")
	fails += _ok(not released_while_moving, "keeps escorting as long as you keep moving")
	fails += _ok(release_t >= stay * 0.8, "after you settle it stays close a beat before resuming its own life")
	return fails


# End-to-end: issue_command routes through the brain to a "come" beat when within earshot.
static func _test_brain_routes_a_call(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 1.0
	var brain := CompanionBrain.new(cfg, 1, s)
	brain.issue_command("come")
	var intent := brain.update(_ctx(Vector2(0, 0), Vector2(200, 0)))  # dist 200 < hear_radius
	return _ok(intent["behavior"] == "come", "issue_command('come') routes through to a come beat")


# The same call, but with the player far past hear_radius, is ignored by the brain.
static func _test_brain_ignores_a_call_from_afar(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 1.0
	var brain := CompanionBrain.new(cfg, 1, s)
	brain.issue_command("come")
	var far := float(cfg["come"]["hear_radius"]) + 1000.0
	var intent := brain.update(_ctx(Vector2(0, 0), Vector2(far, 0)))
	return _ok(intent["behavior"] != "come", "a call from beyond earshot is ignored by the brain")


# A pet dict the PetAction reads: the order, distance, the accept/shy die, and positions.
static func _pet_percept(dist: float, pet_roll: float) -> Dictionary:
	return {
		"command": "pet",
		"dist_to_player": dist,
		"pet_roll": pet_roll,
		"companion_pos": Vector2(0, 0),
		"player_pos": Vector2(dist, 0),
	}


# A pet only lands when you're adjacent; out of range the order silently no-ops.
static func _test_pet_only_when_adjacent(cfg: Dictionary) -> int:
	var pet := CompanionActions.PetAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	s.bond = 1.0
	var far := float(cfg["pet"]["range"]) + 50.0
	return _ok(pet.score(_pet_percept(far, 0.0), s, cfg, _rng()) == 0.0, "a pet out of range does nothing")


# A fresh, wary companion can refuse a pet: with an unfavorable roll it shies a step AWAY
# (no heart, no bond), the small mood dip and all.
static func _test_fresh_pet_can_shy_away(cfg: Dictionary) -> int:
	var pet := CompanionActions.PetAction.new(5)
	var s := CompanionSelf.make_default(cfg)  # bond 0 -> accept_chance ~ accept_low
	var b0 := s.bond
	var p := _pet_percept(40.0, 0.99)  # high roll -> shies away
	var score := pet.score(p, s, cfg, _rng())
	var intent := pet.act(p, s, cfg, _rng(), 0.016)
	var step_x := float((intent["move_target"] as Vector2).x)
	var fails := 0
	fails += _ok(score == 1.0, "an adjacent pet latches even when it will be refused")
	fails += _ok(not ("love" in intent["reactions"]), "a refused pet shows no heart")
	fails += _ok(step_x < 0.0, "a refused pet makes it shy a step away from the player")
	fails += _ok(is_equal_approx(s.bond, b0), "a refused pet grows no bond")
	return fails


# A bonded companion welcomes a pet: it leans a step TOWARD you, shows a heart, and bond rises.
static func _test_bonded_pet_leans_in(cfg: Dictionary) -> int:
	var pet := CompanionActions.PetAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.6  # accept_chance ~0.7, with headroom below bond.max to grow
	s.observations["play_seconds"] = 100.0  # past any pet cooldown
	var b0 := s.bond
	var p := _pet_percept(40.0, 0.0)  # low roll -> welcomed
	pet.score(p, s, cfg, _rng())
	var intent := pet.act(p, s, cfg, _rng(), 0.016)
	var step_x := float((intent["move_target"] as Vector2).x)
	var fails := 0
	fails += _ok("love" in intent["reactions"], "a welcomed pet shows a heart")
	fails += _ok(step_x > 0.0, "a welcomed pet makes it lean a step toward the player")
	fails += _ok(s.bond > b0, "a welcomed pet grows bond")
	return fails
