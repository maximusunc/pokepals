class_name TestSeatLogic
## Tests for SeatLogic, the pure half of sitting together: which seat an avatar is on (a pure function of where
## it is and whether it is still), the nearest free seat to sit on, and where you step off to. Also checks the
## real Lingerlong spec: every seat's step-off point is clear of the furniture.

const SEATS := [
	{ "id": "bench_a", "at": [138, 244], "face": [-1, 0] },
	{ "id": "bench_b", "at": [162, 244], "face": [-1, 0] },
	{ "id": "edge", "at": [-120, -456], "face": [0, -1], "lift": 3, "clip": 8 },
	{ "id": "far", "at": [5000, 5000] },
	{ "id": "broken" },
	"junk",
]


static func run_all() -> int:
	var fails := 0
	print("TestSeatLogic")
	fails += _test_reads_the_spec()
	fails += _test_seated_is_position_and_stillness()
	fails += _test_nearest_free()
	fails += _test_stand_point()
	fails += _test_lingerlong_seats_step_off_clear()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _test_reads_the_spec() -> int:
	var f := 0
	var s := SeatLogic.from_spec(SEATS)
	f += _ok(s.size() == 4, "malformed seats are skipped")
	f += _ok(s.seat(0)["face"].is_equal_approx(Vector2(-1, 0)), "a seat's face is read and normalised")
	f += _ok(s.seat(3)["face"] == Vector2(0, 1), "a seat with no face looks south")
	f += _ok(is_equal_approx(s.seat(2)["lift"], 3.0) and s.seat(2)["clip"] == 8, "a seat may give its own lift and clip")
	f += _ok(is_equal_approx(s.seat(0)["lift"], SeatLogic.LIFT) and s.seat(0)["clip"] == SeatLogic.CLIP, "else the defaults")
	f += _ok(SeatLogic.from_spec(null).is_empty() and SeatLogic.from_spec({}).is_empty(), "no seats list, no seats")
	return f


static func _test_seated_is_position_and_stillness() -> int:
	var f := 0
	var s := SeatLogic.from_spec(SEATS)
	f += _ok(s.seated(Vector2(138, 244), true) == 0, "still on an anchor: seated")
	f += _ok(s.seated(Vector2(139.5, 245), true) == 0, "a pixel or two off still counts")
	f += _ok(s.seated(Vector2(138, 244), false) == -1, "moving through an anchor: not seated")
	f += _ok(s.seated(Vector2(145, 244), true) == -1, "a few px away: not seated")
	f += _ok(s.seated(Vector2(161, 244), true) == 1, "the other half of the bench")
	f += _ok(s.seated(Vector2(5000, 5000), true) == 3, "found through the grid far from the rest")
	f += _ok(s.seated(Vector2(127.9, 244), true) == -1 and s.seated(Vector2(-64, -64), true) == -1, "nothing across a cell edge")
	return f


static func _test_nearest_free() -> int:
	var f := 0
	var s := SeatLogic.from_spec(SEATS)
	f += _ok(s.nearest_free(Vector2(120, 250), 30.0) == 0, "the nearest seat in reach")
	f += _ok(s.nearest_free(Vector2(120, 250), 10.0) == -1, "nothing in reach")
	f += _ok(s.nearest_free(Vector2(120, 250), 60.0, [Vector2(138, 244)]) == 1, "a taken seat is passed over for the next")
	f += _ok(s.nearest_free(Vector2(120, 250), 60.0, [Vector2(138, 244), Vector2(162, 245)]) == -1, "both taken: none")
	f += _ok(s.nearest_free(Vector2(120, 250), 60.0, [Vector2(138, 270), "junk"]) == 0, "someone nearby but not on it doesn't take it")
	return f


static func _test_stand_point() -> int:
	var f := 0
	var s := SeatLogic.from_spec(SEATS)
	f += _ok(s.stand_point(0).is_equal_approx(Vector2(138 - SeatLogic.STAND_OUT, 244)), "you step off the way the seat faces")
	f += _ok(s.seated(s.stand_point(0), true) == -1, "standing there you aren't sitting")
	var t := SeatLogic.from_spec([{ "at": [0, 0], "face": [0, -1], "off": [5, 30] }])
	f += _ok(t.stand_point(0) == Vector2(5, 30), "or where the seat says to step off")
	return f


## Every seat in the real world: the anchor is on the plaza, and its step-off point is clear of the furniture's
## collision (the resolver leaves it nearly where it is), so getting up never wedges you in a bench.
static func _test_lingerlong_seats_step_off_clear() -> int:
	var f := 0
	var data := WorldData.load_json("res://tests/world_fixtures/lingerlong.json")
	var core: Dictionary = data.get("core", data)
	var s := SeatLogic.from_spec(core.get("seats", []))
	f += _ok(s.size() >= 30, "Lingerlong has its seats (%d)" % s.size())
	var solids := Solids.build(core, [], core.get("collision", {}))
	var bounds := Rect2(-1600, -2200, 3200, 3400)
	var stuck: Array = []
	for i in s.size():
		var p := s.stand_point(i)
		var r := Solids.resolve(p, 6.0, solids, bounds, 2.0)
		if r.distance_to(p) > 4.0:
			stuck.append("%s %s->%s" % [s.seat(i)["id"], p, r])
	f += _ok(stuck.is_empty(), "every seat's step-off point is clear %s" % [stuck])
	return f
