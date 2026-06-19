class_name TestSalamanderHunt
## Tests for the pure riverbank goal logic: hiding salamanders + decoys among rocks,
## counting only salamanders, and reporting completion exactly once.

static func run_all() -> int:
	var fails := 0
	print("TestSalamanderHunt")
	fails += _test_assigns_exactly_count_salamanders()
	fails += _test_found_rises_only_on_salamanders()
	fails += _test_reexamine_is_idempotent()
	fails += _test_newly_complete_fires_once()
	fails += _test_clamps_when_too_few_rocks()
	fails += _test_decoys_get_labels()
	fails += _test_different_seeds_differ()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


static func _decoys() -> Array:
	return [
		{ "label": "a heron feather", "tags": ["odd"] },
		{ "label": "a curl of river-glass", "tags": ["shiny"] },
	]


## Count how many of the rocks hide salamanders by turning every rock over.
static func _count_salamanders(hunt: SalamanderHunt, rock_count: int) -> int:
	var n := 0
	for i in rock_count:
		if hunt.examine(i)["kind"] == "salamander":
			n += 1
	return n


static func _test_assigns_exactly_count_salamanders() -> int:
	var hunt := SalamanderHunt.new()
	hunt.setup(24, 10, _decoys(), 6, _rng(1))
	return _ok(_count_salamanders(hunt, 24) == 10 and hunt.total == 10, "hides exactly `count` salamanders")


static func _test_found_rises_only_on_salamanders() -> int:
	var hunt := SalamanderHunt.new()
	hunt.setup(24, 10, _decoys(), 6, _rng(2))
	var fails := 0
	var running := 0
	for i in 24:
		var r: Dictionary = hunt.examine(i)
		if r["kind"] == "salamander":
			running += 1
		fails += _ok(hunt.found == running, "found tracks salamanders only (rock %d)" % i)
	return _ok(fails == 0, "found never increments on a decoy or empty rock")


static func _test_reexamine_is_idempotent() -> int:
	var hunt := SalamanderHunt.new()
	hunt.setup(10, 5, _decoys(), 3, _rng(3))
	# Find a salamander rock, then examine it again.
	var sal := -1
	for i in 10:
		if hunt.examine(i)["kind"] == "salamander":
			sal = i
			break
	var before: int = hunt.found
	var again: Dictionary = hunt.examine(sal)
	return _ok(again["already_examined"] and hunt.found == before, "re-examining a rock does not double-count")


static func _test_newly_complete_fires_once() -> int:
	var hunt := SalamanderHunt.new()
	hunt.setup(16, 10, _decoys(), 4, _rng(4))
	var newly_count := 0
	var fired_at_ten := false
	for i in 16:
		var r: Dictionary = hunt.examine(i)
		if r["newly_complete"]:
			newly_count += 1
			fired_at_ten = bool(r["complete"]) and int(r["found"]) == 10
	return _ok(newly_count == 1 and fired_at_ten, "newly_complete fires exactly once, on the 10th salamander")


static func _test_clamps_when_too_few_rocks() -> int:
	var hunt := SalamanderHunt.new()
	# Asking for more salamanders + decoys than there are rocks must not crash or over-assign.
	hunt.setup(4, 10, _decoys(), 6, _rng(5))
	var sals := _count_salamanders(hunt, 4)
	return _ok(hunt.total == 4 and sals == 4, "clamps salamander count to the number of rocks")


static func _test_decoys_get_labels() -> int:
	var hunt := SalamanderHunt.new()
	hunt.setup(20, 4, _decoys(), 6, _rng(6))
	var ok := true
	for i in 20:
		var r: Dictionary = hunt.examine(i)
		if r["kind"] == "decoy" and String(r["label"]) == "":
			ok = false
	return _ok(ok, "every decoy reveal carries a non-empty label")


static func _test_different_seeds_differ() -> int:
	var a := SalamanderHunt.new()
	var b := SalamanderHunt.new()
	a.setup(24, 10, _decoys(), 6, _rng(11))
	b.setup(24, 10, _decoys(), 6, _rng(99))
	var diff := false
	for i in 24:
		if a.examine(i)["kind"] != b.examine(i)["kind"]:
			diff = true
			break
	return _ok(diff, "different seeds hide the salamanders in different rocks")
