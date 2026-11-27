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
	fails += _test_budget_default_is_unlimited()
	fails += _test_budget_runs_out()
	fails += _test_reexamine_does_not_spend_budget()
	fails += _test_winning_flip_never_reports_run_out()
	fails += _test_unexamined_contents_lists_unflipped_without_mutating()
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


## Rock indices whose hidden content matches `kind`, found WITHOUT turning them over (peek only),
## so a test can choose exactly which rocks to flip.
static func _indices_of_kind(hunt: SalamanderHunt, rock_count: int, kind: String) -> Array:
	var out: Array = []
	for i in rock_count:
		if hunt.content_kind(i) == kind:
			out.append(i)
	return out


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


## With no budget (the default), the hunt never runs out — you can flip every rock, as before.
static func _test_budget_default_is_unlimited() -> int:
	var hunt := SalamanderHunt.new()
	hunt.setup(24, 10, _decoys(), 6, _rng(1))  # no flip_budget arg
	var ran_out := false
	for i in 24:
		if bool(hunt.examine(i)["out_of_flips"]):
			ran_out = true
	return _ok(not ran_out and hunt.budget == 0, "budget 0 means unlimited flips, never out_of_flips")


## Spend the whole budget on non-salamander rocks: the hunt reports out_of_flips with no flips left.
static func _test_budget_runs_out() -> int:
	var hunt := SalamanderHunt.new()
	hunt.setup(24, 10, _decoys(), 6, _rng(2), 3)
	var blanks: Array = _indices_of_kind(hunt, 24, "empty")
	var last: Dictionary = {}
	for k in 3:
		last = hunt.examine(int(blanks[k]))
	var ok := bool(last["out_of_flips"]) and int(last["flips_remaining"]) == 0 and int(last["flips_used"]) == 3
	return _ok(ok and hunt.found < hunt.total, "spending the budget without all salamanders reports out_of_flips")


## Re-tapping an already-flipped rock is a free no-op — it must not spend a flip from the budget.
static func _test_reexamine_does_not_spend_budget() -> int:
	var hunt := SalamanderHunt.new()
	hunt.setup(24, 10, _decoys(), 6, _rng(3), 15)
	hunt.examine(0)
	var used_before: int = hunt.flips_used
	var again: Dictionary = hunt.examine(0)
	return _ok(bool(again["already_examined"]) and hunt.flips_used == used_before, "re-tapping a flipped rock does not spend a flip")


## The flip that finds the LAST salamander reports a win (newly_complete), never run-out — even
## when it is the very last flip of the budget.
static func _test_winning_flip_never_reports_run_out() -> int:
	var hunt := SalamanderHunt.new()
	hunt.setup(24, 10, _decoys(), 6, _rng(4), 10)  # budget exactly equals the salamander count
	var sals: Array = _indices_of_kind(hunt, 24, "salamander")
	var last: Dictionary = {}
	for idx in sals:
		last = hunt.examine(int(idx))
	var ok := bool(last["newly_complete"]) and not bool(last["out_of_flips"]) and int(last["found"]) == 10 and int(last["flips_used"]) == 10
	return _ok(ok, "finding the last salamander on the final flip is a win, not a run-out")


## unexamined_contents() lists exactly the rocks not yet turned over, and is read-only — it must
## not mark them examined or change found / flips_used.
static func _test_unexamined_contents_lists_unflipped_without_mutating() -> int:
	var hunt := SalamanderHunt.new()
	hunt.setup(24, 10, _decoys(), 6, _rng(5), 15)
	hunt.examine(0)
	hunt.examine(1)
	var found_before: int = hunt.found
	var used_before: int = hunt.flips_used
	var rest: Array = hunt.unexamined_contents()
	var has_flipped := false
	for entry in rest:
		if int(entry["index"]) == 0 or int(entry["index"]) == 1:
			has_flipped = true
	var ok := rest.size() == 22 and not has_flipped and hunt.found == found_before and hunt.flips_used == used_before
	return _ok(ok, "unexamined_contents lists only un-flipped rocks and mutates nothing")
