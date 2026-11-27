class_name TestCompanionLead
## Tests for COMPANION-LED discovery — the companion taking the player to a find. The action is
## exercised directly (so the multi-phase beckon->travel->present trek can be simulated with a
## following or a lagging player), plus checks that perception surfaces the new poi_meta fields
## and falls back to neutral when they're absent.
##
## Pins the design: only a FULLY bonded companion leads; only to an appealing, still-novel prop;
## it presents (delight + shared bond) once and then the find is stale; it gives up if ignored.

static func run_all() -> int:
	var fails := 0
	var cfg: Dictionary = WorldData.load_json("res://data/companion.json")
	print("TestCompanionLead")
	fails += _test_perception_surfaces_poi_meta(cfg)
	fails += _test_perception_falls_back_to_neutral(cfg)
	fails += _test_unbonded_never_leads(cfg)
	fails += _test_will_not_lead_to_stale_prop(cfg)
	fails += _test_bonded_leads_and_presents(cfg)
	fails += _test_presenting_habituates(cfg)
	fails += _test_gives_up_when_ignored(cfg)
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


# A fully bonded self, for the leading beats.
static func _bonded(cfg: Dictionary) -> CompanionSelf:
	var s := CompanionSelf.make_default(cfg)
	s.bond = float(cfg.get("lead", {}).get("min_bond", 1.0))
	return s


# A perception dict the LeadAction reads, for a still-novel appealing prop at `target`.
static func _percept(companion_pos: Vector2, player_pos: Vector2, target: Vector2, appeal: float, novelty: float) -> Dictionary:
	return {
		"companion_pos": companion_pos,
		"player_pos": player_pos,
		"has_poi": true,
		"nearest_poi": target,
		"nearest_poi_id": "crystal",
		"nearest_poi_appeal": appeal,
		"nearest_poi_novelty": novelty,
	}


# perceive() should surface the nearest prop's identity/appeal/novelty when poi_meta is present.
static func _test_perception_surfaces_poi_meta(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var poi := Vector2(120, 100)
	var ctx := {
		"companion_pos": Vector2(100, 100),
		"player_pos": Vector2(100, 100),
		"player_velocity": Vector2.ZERO,
		"events": [],
		"points_of_interest": [poi],
		"poi_meta": [{ "pos": poi, "id": "shiny_thing", "tags": ["shiny"] }],
	}
	var p := CompanionPerception.perceive(ctx, s, cfg)
	var fails := 0
	fails += _ok(String(p["nearest_poi_id"]) == "shiny_thing", "perception surfaces the nearest prop's id")
	fails += _ok(float(p["nearest_poi_appeal"]) > 0.6, "perception appraises a shiny prop as appealing")
	fails += _ok(is_equal_approx(float(p["nearest_poi_novelty"]), 1.0), "a never-seen prop reads as fully novel")
	return fails


# Without poi_meta, the new fields degrade to neutral — so every existing consumer is unchanged.
static func _test_perception_falls_back_to_neutral(cfg: Dictionary) -> int:
	var s := CompanionSelf.make_default(cfg)
	var poi := Vector2(120, 100)
	var ctx := {
		"companion_pos": Vector2(100, 100),
		"player_pos": Vector2(100, 100),
		"player_velocity": Vector2.ZERO,
		"events": [],
		"points_of_interest": [poi],
	}
	var p := CompanionPerception.perceive(ctx, s, cfg)
	var neutral := float(cfg["appraisal"]["neutral"])
	var fails := 0
	fails += _ok(String(p["nearest_poi_id"]) == "", "no poi_meta -> empty id")
	fails += _ok(is_equal_approx(float(p["nearest_poi_appeal"]), neutral), "no poi_meta -> neutral appeal")
	fails += _ok(is_equal_approx(float(p["nearest_poi_novelty"]), 1.0), "no poi_meta -> full novelty")
	return fails


# A companion that isn't fully bonded never leads, even with a perfect candidate.
static func _test_unbonded_never_leads(cfg: Dictionary) -> int:
	var lead := CompanionActions.LeadAction.new(cfg, 2)
	var s := CompanionSelf.make_default(cfg)
	s.bond = float(cfg["lead"]["min_bond"]) - 0.05  # just shy of fully bonded
	lead.tick(float(cfg["lead"]["interval"]) + 1.0)  # elapse the spacing
	var p := _percept(Vector2(0, 0), Vector2(0, 0), Vector2(200, 0), 0.9, 1.0)
	return _ok(lead.score(p, s, cfg, _rng()) == 0.0, "an un-fully-bonded companion never leads")


# It won't lead to a prop you've already discovered together (low novelty).
static func _test_will_not_lead_to_stale_prop(cfg: Dictionary) -> int:
	var lead := CompanionActions.LeadAction.new(cfg, 2)
	var s := _bonded(cfg)
	lead.tick(float(cfg["lead"]["interval"]) + 1.0)
	var stale := float(cfg["lead"]["min_novelty"]) - 0.1
	var p := _percept(Vector2(0, 0), Vector2(0, 0), Vector2(200, 0), 0.9, stale)
	return _ok(lead.score(p, s, cfg, _rng()) == 0.0, "a fully bonded companion won't lead to a stale (low-novelty) prop")


# Drive a lead to completion with a perfectly-following player, integrating the companion's
# motion from the returned intent. Returns whether it ever presented (delight) and the bond delta.
static func _drive(lead: CompanionActions.LeadAction, s: CompanionSelf, cfg: Dictionary, target: Vector2, follow: bool) -> Dictionary:
	var companion_pos := Vector2(0, 0)
	var presented := false
	var bond_before := s.bond
	for _i in 6000:
		# Player either trails right at the companion (follows) or stays put far away (ignores).
		var player_pos := companion_pos if follow else Vector2(5000, 0)
		var p := _percept(companion_pos, player_pos, target, 0.9, 1.0)
		var intent := lead.act(p, s, cfg, _rng(), 0.05)
		if "delight" in intent["reactions"]:
			presented = true
		var sp := float(intent["desired_speed"])
		if sp > 0.0:
			companion_pos = companion_pos.move_toward(intent["move_target"], sp * 0.05)
		# Released? (active beat ended — score now re-checks gates; cooldown was just re-armed.)
		if lead.score(_percept(companion_pos, player_pos, target, 0.9, 1.0), s, cfg, _rng()) <= 0.0:
			break
	return { "presented": presented, "bond_gain": s.bond - bond_before }


# cfg with bond headroom above the lead gate, so a "fully bonded" companion (bond >= min_bond)
# still has room for the discovery bump to be observable rather than clamped at the ceiling.
static func _lead_cfg(cfg: Dictionary) -> Dictionary:
	var c := cfg.duplicate(true)
	c["bond"]["max"] = 100.0
	c["lead"]["min_bond"] = 1.0
	return c


# The payoff: a fully bonded companion beckons, travels to the find, and presents it — a delight
# and a bond bump — when the player follows.
static func _test_bonded_leads_and_presents(cfg: Dictionary) -> int:
	var c := _lead_cfg(cfg)
	var lead := CompanionActions.LeadAction.new(c, 2)
	var s := CompanionSelf.make_default(c)
	s.bond = 1.0  # meets the gate (min_bond), with headroom below the lifted max
	lead.tick(float(c["lead"]["interval"]) + 1.0)
	var activate := _percept(Vector2(0, 0), Vector2(0, 0), Vector2(300, 0), 0.9, 1.0)
	var ok_active := lead.score(activate, s, c, _rng()) > 0.0
	var r := _drive(lead, s, c, Vector2(300, 0), true)
	var fails := 0
	fails += _ok(ok_active, "a fully bonded companion sets off to lead toward an appealing novel find")
	fails += _ok(bool(r["presented"]), "it presents the find on arrival (delight)")
	fails += _ok(float(r["bond_gain"]) > 0.0, "presenting a led discovery grows bond")
	return fails


static func _test_presenting_habituates(cfg: Dictionary) -> int:
	# Use a cfg whose bond.max is high enough that a fully bonded companion still has headroom,
	# so two successive led discoveries of the SAME prop are both observable — and the second
	# grows bond strictly less (novelty habituation, keyed by prop id).
	var c := cfg.duplicate(true)
	c["bond"]["max"] = 100.0  # plenty of headroom; gate uses lead.min_bond which we also lift
	c["lead"]["min_bond"] = 1.0
	var s := CompanionSelf.make_default(c)
	s.bond = 1.0  # >= min_bond
	var first_b := s.bond
	s.record_led_discovery("crystal", 0.9, c)
	var first := s.bond - first_b
	var second_b := s.bond
	s.record_led_discovery("crystal", 0.9, c)
	var second := s.bond - second_b
	var fails := 0
	fails += _ok(first > 0.0, "a led discovery grows bond")
	fails += _ok(second < first, "leading to the same prop again grows bond less (habituation)")
	return fails


# If the player doesn't follow, the companion gives up gracefully — it never presents, and the
# beat releases instead of trekking on forever.
static func _test_gives_up_when_ignored(cfg: Dictionary) -> int:
	var lead := CompanionActions.LeadAction.new(cfg, 2)
	var s := _bonded(cfg)
	lead.tick(float(cfg["lead"]["interval"]) + 1.0)
	var activate := _percept(Vector2(0, 0), Vector2(5000, 0), Vector2(300, 0), 0.9, 1.0)
	lead.score(activate, s, cfg, _rng())
	var r := _drive(lead, s, cfg, Vector2(300, 0), false)
	var fails := 0
	fails += _ok(not bool(r["presented"]), "an ignored lead never reaches the presentation")
	fails += _ok(is_equal_approx(float(r["bond_gain"]), 0.0), "an abandoned lead grows no bond")
	return fails
