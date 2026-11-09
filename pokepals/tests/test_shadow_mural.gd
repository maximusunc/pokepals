class_name TestShadowMural
## Tests for Lanternfold's pure logic: ShadowCast (the lantern's projection onto the cliff-face screen),
## ShadowMask (does one silhouette have another's shape) and MuralGuide (a companion's shadow filling the gap
## a bird left in the mural). No nodes: positions and forms in, numbers and events out.

const FACE := { "x0": -180.0, "x1": 180.0, "base_y": 0.0, "height": 130.0 }
const LANTERN := Vector2(0, 190)
const SPOT := Vector2(40, 111)
const CFG := {
	"face": FACE, "lantern": [0, 190], "spot": [40, 111], "species": "bird", "hover": 18.0,
	"hold_low": 2.0, "hold_high": 1.0, "settle_radius": 36.0,
}


static func run_all() -> int:
	var fails := 0
	print("TestShadowMural")
	fails += _test_a_shadow_is_life_size_at_the_screen_and_grows_toward_the_lantern()
	fails += _test_it_slides_with_the_thing_and_stands_on_the_foot_of_the_face()
	fails += _test_only_a_thing_aloft_throws_a_shadow_up_the_face()
	fails += _test_no_shadow_behind_the_lantern_or_beside_it()
	fails += _test_ground_for_inverts_project()
	fails += _test_the_cone_ends_where_the_face_does()
	fails += _test_mask_iou()
	fails += _test_the_bird_at_the_spot_fills_the_gap_after_a_hold()
	fails += _test_the_wrong_form_never_fills_it()
	fails += _test_the_wrong_spot_never_fills_it()
	fails += _test_moving_does_not_fill_it()
	fails += _test_the_settle_helps_only_the_right_animal()
	fails += _test_losing_the_fit_drains_the_hold_gently()
	fails += _test_bond_shortens_the_hold()
	fails += _test_events_fire_once()
	fails += _test_the_companion_notices_the_gap_and_rests()
	fails += _test_a_done_mural_stays_done()
	return fails


static func _ok(cond: bool, label: String) -> int:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	return 0 if cond else 1


## Silhouettes: a bird (a wide-ish blob), a wolf (a long low shape) and a rabbit (tall and narrow).
static func _masks() -> Dictionary:
	return {
		"bird": ShadowMask.solid_rect(32, 32, 4, 9, 24, 18, 16.0, 24.0),
		"wolf": ShadowMask.solid_rect(32, 32, 0, 4, 31, 8, 16.0, 24.0),
		"rabbit": ShadowMask.solid_rect(32, 32, 10, 3, 8, 24, 16.0, 24.0),
	}


static func _guide(extra: Dictionary = {}) -> MuralGuide:
	var cfg: Dictionary = CFG.duplicate()
	cfg.merge(extra, true)
	var g := MuralGuide.new(cfg)
	g.set_masks(_masks())
	return g


## Run `secs` seconds in 0.1 s steps; every event is collected into `log`. Returns the last update.
static func _run(g: MuralGuide, secs: float, species: String, at: Vector2, speed: float, player: Vector2, bond: float, log: Array = []) -> Dictionary:
	var t := 0.0
	var r := {}
	while t < secs:
		r = g.update(0.1, species, at, speed, player, bond)
		log.append_array(r["events"])
		t += 0.1
	return r


static func _test_a_shadow_is_life_size_at_the_screen_and_grows_toward_the_lantern() -> int:
	var fails := 0
	var foot := ShadowCast.project(FACE, LANTERN, Vector2(30, 0), 0.0)
	fails += _ok(bool(foot["ok"]) and is_equal_approx(float(foot["s"]), 1.0), "at the screen's foot a shadow is life size")
	fails += _ok(is_equal_approx(float(foot["x"]), 30.0), "...and lands right where the thing stands")
	var mid := ShadowCast.project(FACE, LANTERN, Vector2(0, 95), 0.0)
	fails += _ok(is_equal_approx(float(mid["s"]), 2.0), "halfway to the lantern it is twice life size")
	var near := ShadowCast.project(FACE, LANTERN, Vector2(0, 142), 0.0)
	fails += _ok(float(near["s"]) > float(mid["s"]), "nearer the lantern it is bigger still")
	return fails


static func _test_it_slides_with_the_thing_and_stands_on_the_foot_of_the_face() -> int:
	var fails := 0
	var p := ShadowCast.project(FACE, LANTERN, Vector2(20, 95), 0.0)
	fails += _ok(is_equal_approx(float(p["x"]), 40.0), "a thing 20 px off the lantern's line at s=2 throws 40 px off it")
	fails += _ok(is_equal_approx(float(p["v"]), 0.0), "a thing standing on the ground throws a shadow standing on the face's foot")
	var q := ShadowCast.project(FACE, LANTERN, Vector2(-20, 95), 0.0)
	fails += _ok(float(q["x"]) < 0.0, "and it slides the same way the thing does")
	return fails


static func _test_only_a_thing_aloft_throws_a_shadow_up_the_face() -> int:
	var fails := 0
	var p := ShadowCast.project(FACE, LANTERN, Vector2(0, 95), 18.0)
	fails += _ok(is_equal_approx(float(p["v"]), 36.0), "held 18 px up at s=2, its shadow is 36 px up the face")
	var g := _guide()
	fails += _ok(float(g.cast_of("bird", SPOT)["v"]) > 0.0, "the bird's shadow is in the air")
	fails += _ok(is_equal_approx(float(g.cast_of("wolf", SPOT)["v"]), 0.0), "a wolf's shadow stands on the ground")
	return fails


static func _test_no_shadow_behind_the_lantern_or_beside_it() -> int:
	var fails := 0
	fails += _ok(not bool(ShadowCast.project(FACE, LANTERN, Vector2(0, 260), 0.0)["ok"]), "south of the lantern: its light is behind you, no shadow")
	fails += _ok(not bool(ShadowCast.project(FACE, LANTERN, Vector2(0, 185), 0.0)["ok"]), "right beside the lantern: it blocks the light, no shadow")
	fails += _ok(not bool(ShadowCast.project(FACE, LANTERN, Vector2(0, -10), 0.0)["ok"]), "past the screen's foot: no shadow")
	return fails


static func _test_ground_for_inverts_project() -> int:
	var at := Vector2(37, 104)
	var p := ShadowCast.project(FACE, LANTERN, at, 0.0)
	var back := ShadowCast.ground_for(FACE, LANTERN, float(p["x"]), float(p["s"]))
	return _ok(back.distance_to(at) < 0.01, "ground_for(project(p)) is p")


static func _test_the_cone_ends_where_the_face_does() -> int:
	var fails := 0
	fails += _ok(ShadowCast.in_cone(FACE, LANTERN, Vector2(0, 100)), "on the lantern's line, in the light")
	fails += _ok(not ShadowCast.in_cone(FACE, LANTERN, Vector2(400, 100)), "far off to one side the shadow misses the face")
	return fails


static func _test_mask_iou() -> int:
	var fails := 0
	var m := _masks()
	var bird: ShadowMask = m["bird"]
	fails += _ok(ShadowMask.iou(bird, 1.0, bird, 1.0) > 0.98, "a silhouette is its own shape")
	fails += _ok(ShadowMask.iou(bird, 1.0, m["rabbit"], 1.0) < 0.5, "a tall narrow shape is not a bird's")
	var big := ShadowMask.iou(bird, 1.0, bird, 1.6)
	fails += _ok(big > 0.2 and big < 0.6, "the same shape much bigger overlaps only partly (%.2f)" % big)
	var lop := ShadowMask.solid_rect(32, 32, 2, 9, 12, 18, 16.0, 24.0)
	var flop := ShadowMask.solid_rect(32, 32, 14, 9, 12, 18, 16.0, 24.0)
	fails += _ok(ShadowMask.iou(lop, 1.0, flop, 1.0) > 0.98, "shapes are lined up centre to centre (position is another question)")
	fails += _ok(ShadowMask.iou(ShadowMask.new(), 1.0, bird, 1.0) == 0.0, "an empty mask matches nothing")
	var left := ShadowMask.solid_rect(32, 32, 2, 9, 12, 6, 16.0, 24.0)
	var left2 := ShadowMask.solid_rect(32, 32, 2, 9, 12, 6, 16.0, 24.0)
	fails += _ok(ShadowMask.iou(left, 1.0, left2, 1.0, true) > 0.9, "mirroring a symmetric-about-its-box silhouette still matches")
	return fails


static func _test_the_bird_at_the_spot_fills_the_gap_after_a_hold() -> int:
	var g := _guide()
	var log: Array = []
	var r := _run(g, 1.0, "bird", SPOT, 0.0, Vector2(0, 60), 0.0, log)
	var fails := 0
	fails += _ok(float(r["fit"]) > 0.99, "the bird on the spot fits the gap")
	fails += _ok(not g.is_done() and float(r["filling"]) > 0.0, "it fills in over a hold, not at once")
	_run(g, 1.5, "bird", SPOT, 0.0, Vector2(0, 60), 0.0, log)
	fails += _ok(g.is_done(), "held long enough, the gap is filled")
	fails += _ok(log.has("complete"), "and says so")
	return fails


static func _test_the_wrong_form_never_fills_it() -> int:
	var fails := 0
	for sp in ["wolf", "rabbit"]:
		var g := _guide()
		var log: Array = []
		_run(g, 30.0, sp, SPOT, 0.0, Vector2(0, 60), 1.0, log)
		fails += _ok(not g.is_done(), "a %s on the spot never fills it" % sp)
	var g2 := _guide()
	var log2: Array = []
	_run(g2, 1.0, "wolf", SPOT, 0.0, Vector2(0, 60), 0.0, log2)
	fails += _ok(log2.has("wrong"), "but it is told, once, that the shape is wrong")
	var wolf_fit := float(g2.fit_of("wolf", SPOT)["fit"])
	fails += _ok(wolf_fit < 0.6, "a wolf's fit is low even on the spot (%.2f)" % wolf_fit)
	return fails


static func _test_the_wrong_spot_never_fills_it() -> int:
	var fails := 0
	for off in [Vector2(120, 0), Vector2(0, 60), Vector2(0, -45), Vector2(-90, 20)]:
		var g := _guide()
		_run(g, 20.0, "bird", SPOT + off, 0.0, Vector2(0, 60), 1.0)
		fails += _ok(not g.is_done(), "a bird %s px from the spot does not fill it" % str(off))
	return fails


static func _test_moving_does_not_fill_it() -> int:
	var g := _guide()
	_run(g, 20.0, "bird", SPOT, 60.0, Vector2(0, 60), 1.0)
	return _ok(not g.is_done(), "a bird on the spot but pacing about does not hold the shadow still")


static func _test_the_settle_helps_only_the_right_animal() -> int:
	var fails := 0
	var g := _guide()
	fails += _ok(g.settle_target("bird", SPOT + Vector2(20, 10)) == SPOT, "a bird told to stand near the spot settles on it")
	fails += _ok(g.settle_target("bird", SPOT + Vector2(90, 0)) == SPOT + Vector2(90, 0), "told further off, it stands where it was told")
	fails += _ok(g.settle_target("wolf", SPOT + Vector2(10, 0)) == SPOT + Vector2(10, 0), "a wolf is not helped")
	# the settle makes a pixel-hunt unnecessary: a tap 20 px off, settled, fills it
	var at := g.settle_target("bird", SPOT + Vector2(20, 10))
	_run(g, 4.0, "bird", at, 0.0, Vector2(0, 60), 0.0)
	fails += _ok(g.is_done(), "a sloppy tap near the spot is enough once settled")
	return fails


static func _test_losing_the_fit_drains_the_hold_gently() -> int:
	var g := _guide()
	_run(g, 1.2, "bird", SPOT, 0.0, Vector2(0, 60), 0.0)
	var before := g.filling()
	_run(g, 0.3, "bird", SPOT + Vector2(150, 0), 0.0, Vector2(0, 60), 0.0)
	var after := g.filling()
	var fails := 0
	fails += _ok(after < before and after > 0.0, "a lost fit drains the hold a little, not all at once (%.2f -> %.2f)" % [before, after])
	_run(g, 5.0, "bird", SPOT + Vector2(150, 0), 0.0, Vector2(0, 60), 0.0)
	fails += _ok(g.filling() == 0.0 and not g.is_done(), "kept away, it empties")
	return fails


static func _test_bond_shortens_the_hold() -> int:
	var fresh := _guide()
	var bonded := _guide()
	var t_fresh := 0.0
	while not fresh.is_done() and t_fresh < 20.0:
		fresh.update(0.1, "bird", SPOT, 0.0, Vector2(0, 60), 0.0)
		t_fresh += 0.1
	var t_bonded := 0.0
	while not bonded.is_done() and t_bonded < 20.0:
		bonded.update(0.1, "bird", SPOT, 0.0, Vector2(0, 60), 1.0)
		t_bonded += 0.1
	return _ok(t_bonded < t_fresh and t_bonded > 0.5, "a bonded companion fills it faster (%.1fs vs %.1fs)" % [t_bonded, t_fresh])


static func _test_events_fire_once() -> int:
	var g := _guide()
	var log: Array = []
	_run(g, 1.0, "bird", SPOT, 0.0, Vector2(0, 100), 0.0, log)
	_run(g, 1.0, "bird", SPOT, 0.0, Vector2(0, 100), 0.0, log)
	var fails := 0
	for key in ["arrive", "shadow", "close", "holding"]:
		fails += _ok(log.count(key) == 1, "'%s' is said once" % key)
	return fails


static func _test_the_companion_notices_the_gap_and_rests() -> int:
	var g := _guide()
	var far := Vector2(0, 900)
	var r := _run(g, 1.0, "wolf", Vector2(0, 700), 0.0, far, 0.0)
	var fails := 0
	fails += _ok(not bool(r["point"]), "far from the stage it points at nothing")
	var g2 := _guide()
	var log: Array = []
	var r2 := g2.update(0.1, "wolf", Vector2(0, 700), 0.0, Vector2(0, 150), 0.0)
	log.append_array(r2["events"])
	fails += _ok(bool(r2["point"]), "as you come near the stage it points")
	fails += _ok((r2["target"] as Vector2).y < 0.0, "at the gap, which is up the face, north of its foot")
	var t := 0.0
	var still_pointing := true
	while t < 3.0:
		r2 = g2.update(0.1, "wolf", Vector2(0, 700), 0.0, Vector2(0, 150), 0.0)
		still_pointing = bool(r2["point"])
		t += 0.1
	fails += _ok(not still_pointing, "it points for a moment, then rests")
	# bond widens how far it notices from
	var a := _guide()
	var b := _guide()
	var ra := a.update(0.1, "wolf", Vector2(0, 700), 0.0, Vector2(500, 111), 0.0)
	var rb := b.update(0.1, "wolf", Vector2(0, 700), 0.0, Vector2(500, 111), 1.0)
	fails += _ok(not bool(ra["point"]) and bool(rb["point"]), "a bonded companion notices it from further off")
	return fails


static func _test_a_done_mural_stays_done() -> int:
	var g := _guide()
	_run(g, 4.0, "bird", SPOT, 0.0, Vector2(0, 60), 1.0)
	var done := g.is_done()
	_run(g, 10.0, "wolf", Vector2(200, 40), 80.0, Vector2(0, 60), 1.0)
	return _ok(done and g.is_done() and g.filling() == 1.0, "once the gap is filled, wandering off or changing shape cannot undo it")
