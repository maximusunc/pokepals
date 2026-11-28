class_name TestDreamGate
## Tests for DreamGate, the pure logic of Dozewood's secret: a companion that only dozes where it feels
## safe (inside a nap spot, with you beside it and still, after a welcomed pet, in a calm mood), dreams,
## wakes when you leave or poke it, and the walk to the dreamed place. No nodes: positions in, events out.

const SPOT := Vector2(0, 0)
const LANDMARK := Vector2(1000, 0)
const CFG := {
	"spot_radius": 100.0, "player_radius": 120.0, "together_distance": 80.0, "still_speed": 10.0,
	"pet_window": 30.0, "calm_arousal": 0.4, "calm_valence": -0.05,
	"fill_seconds_fresh": 10.0, "fill_seconds_bonded": 4.0, "drain_rate": 0.1,
	"settle_at": 0.3, "yawn_at": 0.5, "stir_below": 0.1, "dream_delay": 2.0,
	"wake_distance": 150.0, "wake_cooldown": 5.0, "arrive_radius": 100.0, "companion_radius": 150.0,
	"yawn_after": 20.0, "yawn_every": 60.0,
}
const CALM := Vector2(0.2, 0.0)   # valence, arousal


static func run_all() -> int:
	var fails := 0
	print("TestDreamGate")
	fails += _test_a_petted_companion_settles_and_sleeps_in_a_spot()
	fails += _test_it_never_dozes_outside_a_spot()
	fails += _test_it_needs_a_welcomed_pet()
	fails += _test_the_pet_goes_stale()
	fails += _test_it_needs_you_still()
	fails += _test_it_needs_a_calm_mood()
	fails += _test_bond_makes_it_quicker()
	fails += _test_a_lapse_drains_gently_and_it_stirs()
	fails += _test_the_dream_begins_after_a_beat()
	fails += _test_walking_away_wakes_it()
	fails += _test_a_poke_wakes_it_and_it_does_not_flicker_back()
	fails += _test_a_call_lets_the_drowse_go()
	fails += _test_arriving_needs_the_dream_and_both_of_you()
	fails += _test_arrive_fires_once()
	fails += _test_an_ambient_yawn_when_you_stand_still()
	fails += _test_data_overrides_defaults()
	return fails


static func _ok(cond: bool, label: String) -> int:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	return 0 if cond else 1


static func _gate() -> DreamGate:
	return DreamGate.new([SPOT, Vector2(500, 500)], LANDMARK, CFG)


## Run `secs` seconds in 0.1 s steps with the given positions. Every event is collected into `log`.
static func _run(g: DreamGate, secs: float, comp: Vector2, player: Vector2, mood: Vector2, bond: float, log: Array = []) -> void:
	var t := 0.0
	while t < secs:
		var r := g.update(0.1, comp, player, mood, bond)
		log.append_array(r["events"])
		t += 0.1


static func _test_a_petted_companion_settles_and_sleeps_in_a_spot() -> int:
	var g := _gate()
	g.note_pet()
	var log: Array = []
	_run(g, 14.0, Vector2(10, 0), Vector2(40, 0), CALM, 0.0, log)
	var ok := log.has("settle") and log.has("yawn") and log.has("asleep") and g.is_asleep()
	return _ok(ok and log.find("settle") < log.find("yawn") and log.find("yawn") < log.find("asleep"), "petted, still and calm in a nap spot, it settles, yawns and sleeps")


static func _test_it_never_dozes_outside_a_spot() -> int:
	var g := _gate()
	g.note_pet()
	_run(g, 60.0, Vector2(300, 0), Vector2(330, 0), CALM, 1.0)
	return _ok(g.drowse == 0.0 and g.phase == DreamGate.Phase.AWAKE, "nowhere near a spot, a petted, still, calm companion stays awake")


static func _test_it_needs_a_welcomed_pet() -> int:
	var g := _gate()
	_run(g, 30.0, Vector2(10, 0), Vector2(40, 0), CALM, 1.0)
	return _ok(g.drowse == 0.0 and g.blocker == "pet", "without a pet it does not feel safe (and says why)")


static func _test_the_pet_goes_stale() -> int:
	var g := _gate()
	g.note_pet()
	_run(g, 31.0, Vector2(300, 0), Vector2(330, 0), CALM, 0.0)   # the pet ages out away from any spot
	_run(g, 20.0, Vector2(10, 0), Vector2(40, 0), CALM, 0.0)
	return _ok(g.drowse == 0.0 and g.blocker == "pet", "a pet from long ago no longer counts")


static func _test_it_needs_you_still() -> int:
	var g := _gate()
	g.note_pet()
	var x := 40.0
	for i in 100:
		x += 3.0 if i % 2 == 0 else -3.0     # fidgeting back and forth at 30 px/s
		g.update(0.1, Vector2(10, 0), Vector2(x, 0), CALM, 1.0)
	return _ok(g.drowse == 0.0 and g.blocker == "still", "pacing about keeps it awake")


static func _test_it_needs_a_calm_mood() -> int:
	var cfg := CFG.duplicate()
	cfg["pet_window"] = 999.0       # keep the pet fresh: only the mood is in question
	var g := DreamGate.new([SPOT], LANDMARK, cfg)
	g.note_pet()
	_run(g, 30.0, Vector2(10, 0), Vector2(40, 0), Vector2(0.2, 0.8), 1.0)   # wound up
	var wound := g.drowse == 0.0 and g.blocker == "calm"
	var h := DreamGate.new([SPOT], LANDMARK, cfg)
	h.note_pet()
	_run(h, 30.0, Vector2(10, 0), Vector2(40, 0), Vector2(-0.4, 0.0), 1.0)  # withdrawn
	return _ok(wound and h.drowse == 0.0 and h.blocker == "calm", "wound up or withdrawn, it will not drift off")


static func _test_bond_makes_it_quicker() -> int:
	var fresh := _gate()
	var bonded := _gate()
	fresh.note_pet()
	bonded.note_pet()
	_run(fresh, 6.0, Vector2(10, 0), Vector2(40, 0), CALM, 0.0)
	_run(bonded, 6.0, Vector2(10, 0), Vector2(40, 0), CALM, 1.0)
	return _ok(bonded.is_asleep() and not fresh.is_asleep() and fresh.drowse > 0.0 and is_equal_approx(fresh.fill_seconds(0.0), 10.0) and is_equal_approx(fresh.fill_seconds(1.0), 4.0),
		"a bonded companion drifts off sooner than a fresh one")


static func _test_a_lapse_drains_gently_and_it_stirs() -> int:
	var g := _gate()
	g.note_pet()
	_run(g, 4.0, Vector2(10, 0), Vector2(40, 0), CALM, 0.0)             # drowse ~0.4, settled
	var settled := g.phase == DreamGate.Phase.DROWSY
	var before := g.drowse
	_run(g, 2.0, Vector2(10, 0), Vector2(100, 0), CALM, 0.0)            # you step off a moment (still near it)
	var gentle := g.drowse < before and g.drowse > before - 0.3 and g.phase == DreamGate.Phase.DROWSY
	var log: Array = []
	_run(g, 10.0, Vector2(10, 0), Vector2(100, 0), CALM, 0.0, log)
	return _ok(settled and gentle and log.has("stir") and g.phase == DreamGate.Phase.AWAKE, "a lapse drains the drowse gently; left alone it gets back up")


static func _test_the_dream_begins_after_a_beat() -> int:
	var g := _gate()
	g.note_pet()
	var log: Array = []
	_run(g, 10.5, Vector2(10, 0), Vector2(40, 0), CALM, 0.0, log)      # asleep at ~10 s
	var asleep_only := g.is_asleep() and not g.is_dreaming() and not g.dreamt
	_run(g, 2.5, Vector2(10, 0), Vector2(40, 0), CALM, 0.0, log)
	return _ok(asleep_only and g.is_dreaming() and g.dreamt and log.has("dream"), "the dream starts a beat after it falls asleep, and is remembered")


static func _test_walking_away_wakes_it() -> int:
	var g := _gate()
	g.note_pet()
	_run(g, 14.0, Vector2(10, 0), Vector2(40, 0), CALM, 0.0)
	var log: Array = []
	_run(g, 1.0, Vector2(10, 0), Vector2(400, 0), CALM, 0.0, log)
	return _ok(log.has("wake") and g.phase == DreamGate.Phase.AWAKE and g.drowse == 0.0 and not g.is_dreaming() and g.dreamt, "walking away wakes it, and the dream is still remembered")


static func _test_a_poke_wakes_it_and_it_does_not_flicker_back() -> int:
	var g := _gate()
	g.note_pet()
	_run(g, 14.0, Vector2(10, 0), Vector2(40, 0), CALM, 0.0)
	var r := g.update(0.1, Vector2(10, 0), Vector2(40, 0), CALM, 0.0, true)
	var woke: bool = (r["events"] as Array).has("wake") and g.phase == DreamGate.Phase.AWAKE
	# still, calm, in the spot, but no pet since: it stays up
	_run(g, 20.0, Vector2(10, 0), Vector2(40, 0), CALM, 1.0)
	return _ok(woke and g.drowse == 0.0, "a pet or a call wakes it, and it needs a fresh pet to doze again")


static func _test_a_call_lets_the_drowse_go() -> int:
	var g := _gate()
	g.note_pet()
	_run(g, 4.0, Vector2(10, 0), Vector2(40, 0), CALM, 0.0)
	g.note_call()
	return _ok(g.drowse == 0.0 and g.phase == DreamGate.Phase.AWAKE, "a call while it is drowsy lets the drowse go")


static func _test_arriving_needs_the_dream_and_both_of_you() -> int:
	var g := _gate()
	# at the landmark without having dreamed: nothing
	var r := g.update(0.1, LANDMARK, LANDMARK + Vector2(20, 0), CALM, 0.0)
	var none_before := not (r["events"] as Array).has("arrive") and not g.arrived
	# dream first
	g.note_pet()
	_run(g, 17.0, Vector2(10, 0), Vector2(40, 0), CALM, 0.0)
	g.update(0.1, Vector2(10, 0), Vector2(40, 0), CALM, 0.0, true)       # a poke wakes it
	# you reach it alone (the companion still back at the hollow): not yet
	g.update(0.1, Vector2(10, 0), LANDMARK, CALM, 0.0)
	var alone := not g.arrived
	var r2 := g.update(0.1, LANDMARK + Vector2(30, 0), LANDMARK, CALM, 0.0)
	return _ok(none_before and g.dreamt and alone and g.arrived and (r2["events"] as Array).has("arrive"), "the place is found only after the dream, with both of you there")


static func _test_arrive_fires_once() -> int:
	var g := _gate()
	g.note_pet()
	_run(g, 17.0, Vector2(10, 0), Vector2(40, 0), CALM, 0.0)
	g.update(0.1, Vector2(10, 0), Vector2(40, 0), CALM, 0.0, true)
	var log: Array = []
	_run(g, 3.0, LANDMARK, LANDMARK, CALM, 0.0, log)
	return _ok(log.count("arrive") == 1, "arriving is announced once")


static func _test_an_ambient_yawn_when_you_stand_still() -> int:
	var g := _gate()
	var log: Array = []
	_run(g, 21.0, Vector2(300, 0), Vector2(330, 0), CALM, 0.0, log)
	var first := log.count("yawn_ambient") == 1
	_run(g, 30.0, Vector2(300, 0), Vector2(330, 0), CALM, 0.0, log)
	var quiet := log.count("yawn_ambient") == 1          # not again for a good while
	_run(g, 40.0, Vector2(300, 0), Vector2(330, 0), CALM, 0.0, log)
	return _ok(first and quiet and log.count("yawn_ambient") == 2, "standing still anywhere earns a yawn now and then, not constantly")


static func _test_data_overrides_defaults() -> int:
	var g := DreamGate.new([[0, 0]], LANDMARK, { "fill_seconds_fresh": 99.0, "nonsense": 1 })
	return _ok(is_equal_approx(g.fill_seconds(0.0), 99.0) and g.spot_at(Vector2(50, 0)) == 0, "the world's data overrides the defaults; unknown keys are ignored")
