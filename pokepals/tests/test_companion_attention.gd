class_name TestCompanionAttention
## Tests for the SOCIAL REFERENCING read — what the player seems to be attending to.
## Pure kinematics + a dwell timer, so it's exercised directly with hand-made contexts.

static func run_all() -> int:
	var fails := 0
	var cfg: Dictionary = WorldData.load_json("res://data/companion.json")
	print("TestCompanionAttention")
	fails += _test_none_without_pois(cfg)
	fails += _test_far_poi_is_ignored(cfg)
	fails += _test_attends_when_slow_and_near(cfg)
	fails += _test_dwell_strengthens_over_time(cfg)
	fails += _test_fast_player_does_not_attend(cfg)
	fails += _test_approach_engages_immediately(cfg)
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _ctx(player_pos: Vector2, player_vel: Vector2, pois: Array) -> Dictionary:
	return { "player_pos": player_pos, "player_velocity": player_vel, "points_of_interest": pois }


static func _test_none_without_pois(cfg: Dictionary) -> int:
	var a := CompanionAttention.new()
	var out := a.update(_ctx(Vector2.ZERO, Vector2.ZERO, []), cfg, 0.1)
	return _ok(not out["has_attended"], "no attention when there are no points of interest")


static func _test_far_poi_is_ignored(cfg: Dictionary) -> int:
	var a := CompanionAttention.new()
	var out: Dictionary
	for _i in 20:  # even after lingering, a prop beyond the radius never registers
		out = a.update(_ctx(Vector2.ZERO, Vector2.ZERO, [Vector2(900, 0)]), cfg, 0.1)
	return _ok(not out["has_attended"], "a prop beyond the attention radius is ignored")


static func _test_attends_when_slow_and_near(cfg: Dictionary) -> int:
	var a := CompanionAttention.new()
	var poi := Vector2(50, 0)
	var out: Dictionary
	for _i in 15:  # stand still, near the prop, long enough to dwell
		out = a.update(_ctx(Vector2.ZERO, Vector2.ZERO, [poi]), cfg, 0.1)
	var fails := 0
	fails += _ok(out["has_attended"], "attends to a prop the still player lingers near")
	fails += _ok((out["attended_object"] as Vector2).is_equal_approx(poi), "reports the right prop as attended")
	fails += _ok(float(out["attention_strength"]) > 0.5, "a settled, lingered gaze reads as strong attention")
	return fails


static func _test_dwell_strengthens_over_time(cfg: Dictionary) -> int:
	var a := CompanionAttention.new()
	var poi := Vector2(50, 0)
	var ctx := _ctx(Vector2.ZERO, Vector2.ZERO, [poi])
	a.update(ctx, cfg, 0.1)
	var early := float(a.update(ctx, cfg, 0.1)["attention_strength"])
	var late := 0.0
	for _i in 15:
		late = float(a.update(ctx, cfg, 0.1)["attention_strength"])
	return _ok(late > early, "attention strengthens the longer the player lingers (the latency beat)")


static func _test_fast_player_does_not_attend(cfg: Dictionary) -> int:
	var a := CompanionAttention.new()
	var poi := Vector2(50, 0)
	var out: Dictionary
	for _i in 15:  # blowing past the prop at speed is not 'attending'
		out = a.update(_ctx(Vector2.ZERO, Vector2(300, 0), [poi]), cfg, 0.1)
	return _ok(not out["has_attended"], "a fast-moving player isn't read as attending to anything")


static func _test_approach_engages_immediately(cfg: Dictionary) -> int:
	var a := CompanionAttention.new()
	var poi := Vector2(50, 0)
	# Moving slowly TOWARD the prop: approach should engage attention on the first frame,
	# without waiting for dwell to build.
	var out := a.update(_ctx(Vector2.ZERO, Vector2(30, 0), [poi]), cfg, 0.1)
	var fails := 0
	fails += _ok(out["has_attended"], "approaching a prop engages attention at once")
	fails += _ok(float(out["attention_strength"]) > 0.2, "approach gives a meaningful strength immediately")
	return fails
