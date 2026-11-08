class_name TestCompanionGuide
## Tests for GuideAction (the command-band "lead the way" order Drifthallow's tracks use) and the
## CompanionForm.postpone_drift that keeps a fox a fox while it does. Pure logic, hand-made perception.

static func run_all() -> int:
	var fails := 0
	var cfg: Dictionary = WorldData.load_json("res://data/companion.json")
	print("TestCompanionGuide")
	fails += _test_guide_walks_to_the_point(cfg)
	fails += _test_guide_hold_stands_and_faces_the_player(cfg)
	fails += _test_guide_lapses_when_not_refreshed(cfg)
	fails += _test_guide_cancelled_by_call(cfg)
	fails += _test_guide_glances_back(cfg)
	fails += _test_brain_routes_guide(cfg)
	fails += _test_postpone_drift()
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


static func _percept(command: String, companion_pos: Vector2, target = null, hold := false) -> Dictionary:
	return {
		"command": command,
		"command_point": target,
		"command_meta": { "hold": hold } if command == "guide" else {},
		"companion_pos": companion_pos,
		"player_pos": Vector2(-200, 0),
	}


static func _test_guide_walks_to_the_point(cfg: Dictionary) -> int:
	var g := CompanionActions.GuideAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	var fails := 0
	fails += _ok(g.score(_percept("guide", Vector2.ZERO, Vector2(200, 0)), s, cfg, _rng()) == 1.0, "issuing 'guide' latches the order")
	var out := g.act(_percept("", Vector2.ZERO, Vector2(200, 0)), s, cfg, _rng(), 0.05)
	fails += _ok(float(out["desired_speed"]) > 0.0 and out["move_target"] == Vector2(200, 0), "it heads for the point")
	fails += _ok("perk" in out["reactions"], "setting off gets a perk")
	fails += _ok(float(out["desired_speed"]) < 118.0, "…at a pace the player (118 px/s) can keep up with")
	var there := g.act(_percept("", Vector2(200, 0)), s, cfg, _rng(), 0.05)
	fails += _ok(float(there["desired_speed"]) == 0.0, "standing on the point it stops")
	return fails


static func _test_guide_hold_stands_and_faces_the_player(cfg: Dictionary) -> int:
	var g := CompanionActions.GuideAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	g.score(_percept("guide", Vector2.ZERO, Vector2(200, 0), true), s, cfg, _rng())
	var out := g.act(_percept("", Vector2.ZERO), s, cfg, _rng(), 0.05)
	var fails := 0
	fails += _ok(float(out["desired_speed"]) == 0.0, "a hold order stands still")
	fails += _ok(out["look_at"] == Vector2(-200, 0), "…facing the player it is waiting for")
	return fails


static func _test_guide_lapses_when_not_refreshed(cfg: Dictionary) -> int:
	var g := CompanionActions.GuideAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	g.score(_percept("guide", Vector2.ZERO, Vector2(200, 0)), s, cfg, _rng())
	var ttl := float(cfg.get("guide", {}).get("ttl", 0.8))
	for _i in int(ttl / 0.05) + 3:
		g.tick(0.05)
	return _ok(g.score(_percept("", Vector2.ZERO), s, cfg, _rng()) == 0.0, "an unrefreshed guide order lapses on its own (it can never strand the companion)")


static func _test_guide_cancelled_by_call(cfg: Dictionary) -> int:
	var g := CompanionActions.GuideAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	g.score(_percept("guide", Vector2.ZERO, Vector2(200, 0)), s, cfg, _rng())
	return _ok(g.score(_percept("come", Vector2.ZERO), s, cfg, _rng()) == 0.0, "a whistle ('come') cancels the lead at once")


static func _test_guide_glances_back(cfg: Dictionary) -> int:
	var g := CompanionActions.GuideAction.new(5)
	var s := CompanionSelf.make_default(cfg)
	g.score(_percept("guide", Vector2.ZERO, Vector2(2000, 0)), s, cfg, _rng())
	var glanced := false
	for _i in 120:
		g.tick(0.05)
		g.score(_percept("guide", Vector2.ZERO, Vector2(2000, 0)), s, cfg, _rng())
		var out := g.act(_percept("", Vector2.ZERO), s, cfg, _rng(), 0.05)
		if out["look_at"] == Vector2(-200, 0) and float(out["desired_speed"]) == 0.0:
			glanced = true
	return _ok(glanced, "on a long walk it stops now and then to look back at you")


static func _test_brain_routes_guide(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var brain := CompanionBrain.new(cfg, 1, s)
	brain.issue_command("guide", Vector2(100, 0), { "hold": false })
	var intent := brain.update({
		"companion_pos": Vector2.ZERO, "player_pos": Vector2(-50, 0), "player_velocity": Vector2.ZERO,
		"delta": 0.016, "events": [], "time": 0.0,
	})
	return _ok(intent["behavior"] == "guide", "issue_command('guide', point, meta) routes through the brain to a guide beat")


static func _test_postpone_drift() -> int:
	var forms := [{ "species": "fox", "variants": 1 }, { "species": "cat", "variants": 1 }]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var f := CompanionForm.new(forms, { "enabled": true, "morph_interval": [5.0, 5.0] }, rng)
	var start := f.species()
	var fails := 0
	f.postpone_drift(100.0)
	var shifted := false
	for _i in 600:   # 60 s at 0.1 s: well past the 5 s interval
		if f.update(0.1):
			shifted = true
	fails += _ok(not shifted and f.species() == start, "a postponed drift doesn't happen inside the postponement")
	f.postpone_drift(1.0)   # never brings it NEARER
	for _i in 300:
		if f.update(0.1):
			shifted = true
	fails += _ok(not shifted, "postponing never brings the next shift nearer")
	for _i in 600:
		if f.update(0.1):
			shifted = true
	fails += _ok(shifted, "…and the drift resumes once the postponement runs out")
	return fails
