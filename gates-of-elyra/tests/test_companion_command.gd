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
	fails += _test_seek_sweeps_then_settles(cfg)
	fails += _test_seek_times_out_when_fruitless(cfg)
	fails += _test_call_breaks_off_a_search(cfg)
	fails += _test_seek_repicks_a_walled_waypoint(cfg)
	fails += _test_brain_routes_seek(cfg)
	fails += _test_visit_goes_acknowledges_then_releases(cfg)
	fails += _test_visit_cancelled_by_call(cfg)
	fails += _test_brain_routes_visit(cfg)
	fails += _test_visit_performs_verb_on_arrival(cfg)
	fails += _test_brain_routes_visit_verb(cfg)
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


# A perception dict the SeekAction reads: the order (and a point for "settle"), plus positions.
static func _seek_percept(command: String, companion_pos: Vector2, player_pos: Vector2, point = null) -> Dictionary:
	return {
		"command": command,
		"command_point": point,
		"companion_pos": companion_pos,
		"player_pos": player_pos,
	}


# "Go look": the command latches a SEARCH that sweeps the area; when the controller then points the
# companion at the revealed plate ("settle"), it goes, gives the "found it" beat, holds a moment,
# then releases so its own life (Follow) can resume.
static func _test_seek_sweeps_then_settles(cfg: Dictionary) -> int:
	var seek := CompanionActions.SeekAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.5
	var rng := _rng()
	var fails := 0
	fails += _ok(seek.score(_seek_percept("seek", Vector2.ZERO, Vector2.ZERO), s, cfg, rng) == 1.0, "issuing 'seek' latches the search")
	# Sweeping: it ranges out to a waypoint away from where it stands (so it wants to move).
	var moved := false
	for _i in 30:
		if float(seek.act(_seek_percept("", Vector2.ZERO, Vector2.ZERO), s, cfg, rng, 0.05)["desired_speed"]) > 0.0:
			moved = true
			break
	fails += _ok(moved, "a 'seek' search sweeps the area — the companion ranges out to look")
	# The controller found the plate and points the companion at it (here, right where it stands).
	seek.score(_seek_percept("settle", Vector2.ZERO, Vector2.ZERO, Vector2.ZERO), s, cfg, rng)
	var arrival := seek.act(_seek_percept("", Vector2.ZERO, Vector2.ZERO), s, cfg, rng, 0.05)
	fails += _ok("love" in arrival["reactions"], "settling onto the revealed plate gives the 'found it' beat")
	# It holds a beat on the plate, then releases (score drops to 0 — Follow can take back over).
	var hold := float(cfg.get("seek", {}).get("hold_seconds", 3.0))
	for _i in int(hold / 0.05) + 5:
		seek.act(_seek_percept("", Vector2.ZERO, Vector2.ZERO), s, cfg, rng, 0.05)
	fails += _ok(seek.score(_seek_percept("", Vector2.ZERO, Vector2.ZERO), s, cfg, rng) == 0.0, "after holding on the plate the search releases")
	return fails


# A search that never finds anything doesn't get stuck: the sweep TIMES OUT (seek.search_seconds)
# and releases, so its own life (Follow) can resume. We hold the companion in place away from its
# target so it always "wants to move" and never dwells — the fruitless-forever case from the report.
static func _test_seek_times_out_when_fruitless(cfg: Dictionary) -> int:
	var seek := CompanionActions.SeekAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.5
	var rng := _rng()
	seek.score(_seek_percept("seek", Vector2.ZERO, Vector2(400, 0)), s, cfg, rng)
	var timeout := float(cfg.get("seek", {}).get("search_seconds", 14.0))
	var released := false
	for _i in int(timeout / 0.05) + 20:
		seek.act(_seek_percept("", Vector2.ZERO, Vector2(400, 0)), s, cfg, rng, 0.05)
		if seek.score(_seek_percept("", Vector2.ZERO, Vector2(400, 0)), s, cfg, rng) == 0.0:
			released = true
			break
	return _ok(released, "a fruitless search gives up (times out) instead of ranging forever")


# The "Call rescues it" path: a whistle mid-search breaks the search off (yields the command band)
# so a stuck "go look" can always be recovered — the exact fix the bug report asked for.
static func _test_call_breaks_off_a_search(cfg: Dictionary) -> int:
	var seek := CompanionActions.SeekAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.5
	var rng := _rng()
	seek.score(_seek_percept("seek", Vector2.ZERO, Vector2.ZERO), s, cfg, rng)
	seek.act(_seek_percept("", Vector2.ZERO, Vector2.ZERO), s, cfg, rng, 0.05)  # searching
	var fails := 0
	fails += _ok(seek.score(_seek_percept("", Vector2.ZERO, Vector2.ZERO), s, cfg, rng) == 1.0,
		"the search is running before the whistle")
	fails += _ok(seek.score(_seek_percept("come", Vector2.ZERO, Vector2(100, 0)), s, cfg, rng) == 0.0,
		"whistling 'come' breaks off the search so Call can take over (yields the command band)")
	return fails


# A swept waypoint can sit behind a maze wall the geometry-blind brain can't see. Pinned at the
# origin (no progress), the search must give up on that waypoint after waypoint_patience and sweep
# elsewhere — rather than grinding against the wall until the whole search times out.
static func _test_seek_repicks_a_walled_waypoint(cfg: Dictionary) -> int:
	var seek := CompanionActions.SeekAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.5
	var rng := _rng()
	seek.score(_seek_percept("seek", Vector2.ZERO, Vector2.ZERO), s, cfg, rng)
	seek.act(_seek_percept("", Vector2.ZERO, Vector2.ZERO), s, cfg, rng, 0.05)  # establish a waypoint
	var target0: Vector2 = seek._target
	var patience := float(cfg.get("seek", {}).get("waypoint_patience", 2.0))
	var repicked := false
	for _i in int(patience / 0.05) + 5:
		seek.act(_seek_percept("", Vector2.ZERO, Vector2.ZERO), s, cfg, rng, 0.05)
		if seek._target != target0:
			repicked = true
			break
	return _ok(repicked, "a walled sweep (no progress toward the waypoint) gives up and sweeps elsewhere")


# End-to-end: issue_command('seek') routes through the brain to a search beat (command band wins).
static func _test_brain_routes_seek(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.5
	var brain := CompanionBrain.new(cfg, 1, s)
	brain.issue_command("seek")
	var intent := brain.update(_ctx(Vector2(0, 0), Vector2(40, 0)))
	return _ok(intent["behavior"] == "seek", "issue_command('seek') routes through to a search beat")


# A perception dict the VisitAction reads: the order, the target point, and positions.
static func _visit_percept(command: String, companion_pos: Vector2, target = null, verb: String = "") -> Dictionary:
	return {
		"command": command,
		"command_point": target,
		"command_meta": { "verb": verb } if verb != "" else {},
		"companion_pos": companion_pos,
		"player_pos": Vector2.ZERO,
	}


# A directed order (I-1): "visit" sends the companion to a specific point; away from it, it wants to
# move; on arrival it gives the acknowledge perk, dwells a beat, then releases so its own life resumes.
static func _test_visit_goes_acknowledges_then_releases(cfg: Dictionary) -> int:
	var visit := CompanionActions.VisitAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.5
	var rng := _rng()
	var target := Vector2(200, 0)
	var fails := 0
	fails += _ok(visit.score(_visit_percept("visit", Vector2.ZERO, target), s, cfg, rng) == 1.0, "issuing 'visit' latches the order")
	# GO: standing away from the object, it wants to move toward it.
	var moved := false
	for _i in 10:
		if float(visit.act(_visit_percept("", Vector2.ZERO, target), s, cfg, rng, 0.05)["desired_speed"]) > 0.0:
			moved = true
			break
	fails += _ok(moved, "a 'visit' order sends the companion toward the object")
	# Arrival: now standing on the object -> the acknowledge perk.
	var arrival := visit.act(_visit_percept("", target, target), s, cfg, rng, 0.05)
	fails += _ok("perk" in arrival["reactions"], "arriving at the object gives the acknowledge perk")
	# It dwells a beat, then releases (score drops to 0 — autonomous life can resume).
	var dwell := float(cfg.get("visit", {}).get("dwell_seconds", 1.4))
	for _i in int(dwell / 0.05) + 5:
		visit.act(_visit_percept("", target, target), s, cfg, rng, 0.05)
	fails += _ok(visit.score(_visit_percept("", target, target), s, cfg, rng) == 0.0, "after acknowledging it releases back to its own life")
	return fails


# A whistle (or pet) mid-visit CANCELS it (yields the command band) so calling the companion back
# always works — it never resumes the abandoned visit once Come/Pet finish.
static func _test_visit_cancelled_by_call(cfg: Dictionary) -> int:
	var visit := CompanionActions.VisitAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	var rng := _rng()
	visit.score(_visit_percept("visit", Vector2.ZERO, Vector2(200, 0)), s, cfg, rng)
	var fails := 0
	fails += _ok(visit.score(_visit_percept("", Vector2.ZERO, Vector2(200, 0)), s, cfg, rng) == 1.0, "the visit is active before the whistle")
	fails += _ok(visit.score(_visit_percept("come", Vector2.ZERO, Vector2(200, 0)), s, cfg, rng) == 0.0, "whistling 'come' cancels the visit (yields the command band)")
	return fails


# F-2: a visit carrying a VERB (from command_meta) performs it on arrival — a happy "did the thing"
# beat (delight + the verb name) — whereas a bare visit only gives the plain acknowledge perk.
static func _test_visit_performs_verb_on_arrival(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.5
	var rng := _rng()
	var target := Vector2(200, 0)
	var fails := 0
	# A verb-carrying order.
	var perform := CompanionActions.VisitAction.new(5)
	perform.score(_visit_percept("visit", Vector2.ZERO, target, "unearth"), s, cfg, rng)
	var arrival := perform.act(_visit_percept("", target, target, "unearth"), s, cfg, rng, 0.05)
	fails += _ok("delight" in arrival["reactions"], "arriving to perform a verb gives the delight beat")
	fails += _ok("unearth" in arrival["reactions"], "the verb name is emitted for a form-specific animation to hook")
	# A bare visit (no verb) stays the quiet acknowledge — no delight.
	var bare := CompanionActions.VisitAction.new(5)
	bare.score(_visit_percept("visit", Vector2.ZERO, target), s, cfg, rng)
	var bare_arrival := bare.act(_visit_percept("", target, target), s, cfg, rng, 0.05)
	fails += _ok(not ("delight" in bare_arrival["reactions"]), "a bare visit does not celebrate — just the acknowledge perk")
	return fails


# End-to-end: issue_command('visit', point, {verb}) carries the verb through the brain into the beat.
static func _test_brain_routes_visit_verb(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.5
	var brain := CompanionBrain.new(cfg, 1, s)
	# Right on the object so it arrives and performs this same frame.
	brain.issue_command("visit", Vector2(10, 0), { "verb": "unearth" })
	var intent := brain.update(_ctx(Vector2(0, 0), Vector2(200, 0)))
	var fails := 0
	fails += _ok(intent["behavior"] == "visit", "issue_command('visit', point, meta) routes through to a visit beat")
	fails += _ok("delight" in intent["reactions"], "the verb carried in meta drives the perform beat end-to-end")
	return fails


# End-to-end: issue_command('visit', point) routes through the brain to a visit beat (command band wins).
static func _test_brain_routes_visit(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	s.bond = 0.5
	var brain := CompanionBrain.new(cfg, 1, s)
	brain.issue_command("visit", Vector2(40, 0))
	var intent := brain.update(_ctx(Vector2(0, 0), Vector2(200, 0)))
	return _ok(intent["behavior"] == "visit", "issue_command('visit', point) routes through to a visit beat")
