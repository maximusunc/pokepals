class_name TestRuinMechanisms
## Tests for the pure Ruin mechanism logic: a hidden plate the search uncovers, weight on an
## uncovered plate raising a linked slab, the Threshold latch holding the doorway open once raised,
## and the order of uncover/settle never mattering.

static func run_all() -> int:
	var fails := 0
	print("TestRuinMechanisms")
	fails += _test_starts_closed()
	fails += _test_uncover_sets_found_once()
	fails += _test_weight_alone_does_not_open()
	fails += _test_found_plus_weight_opens_once()
	fails += _test_latched_slab_stays_open_after_release()
	fails += _test_non_latching_slab_falls_shut_on_release()
	fails += _test_order_independent_settle_then_uncover()
	fails += _test_unknown_ward_is_safe_noop()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _test_starts_closed() -> int:
	var r := RuinMechanisms.new()
	r.add_ward("gate")
	return _ok(not r.is_found("gate") and not r.is_open("gate") and not r.is_occupied("gate"), "a fresh ward starts hidden and shut")


static func _test_uncover_sets_found_once() -> int:
	var r := RuinMechanisms.new()
	r.add_ward("gate")
	var first: Dictionary = r.uncover("gate")
	var second: Dictionary = r.uncover("gate")
	return _ok(bool(first["newly_found"]) and not bool(second["newly_found"]) and r.is_found("gate"), "uncover sets found, and newly_found fires exactly once")


static func _test_weight_alone_does_not_open() -> int:
	var r := RuinMechanisms.new()
	r.add_ward("gate")
	# Stand on the still-buried plate: weight is registered, but nothing engages until it's uncovered.
	var res: Dictionary = r.set_occupied("gate", true)
	return _ok(r.is_occupied("gate") and not bool(res["open"]) and not r.is_open("gate"), "weight on a still-buried plate opens nothing")


static func _test_found_plus_weight_opens_once() -> int:
	var r := RuinMechanisms.new()
	r.add_ward("gate")
	r.uncover("gate")
	var res: Dictionary = r.set_occupied("gate", true)
	# Settling again must not re-fire the one-time "slab rises" flourish.
	var again: Dictionary = r.set_occupied("gate", true)
	return _ok(r.is_open("gate") and bool(res["newly_open"]) and not bool(again["newly_open"]), "an uncovered, weighted plate opens the slab, newly_open exactly once")


static func _test_latched_slab_stays_open_after_release() -> int:
	var r := RuinMechanisms.new()
	r.add_ward("gate", true)  # latch
	r.uncover("gate")
	r.set_occupied("gate", true)
	var res: Dictionary = r.set_occupied("gate", false)  # companion steps off
	return _ok(r.is_open("gate") and not bool(res["newly_open"]) and not r.is_occupied("gate"), "a latched Threshold slab stays open after the companion steps off")


static func _test_non_latching_slab_falls_shut_on_release() -> int:
	var r := RuinMechanisms.new()
	r.add_ward("gate", false)  # no latch — the Paired-Hall "slips when it leaves" seam
	r.uncover("gate")
	r.set_occupied("gate", true)
	var open_while_held := r.is_open("gate")
	r.set_occupied("gate", false)
	return _ok(open_while_held and not r.is_open("gate"), "a non-latching slab is open only while the plate is weighted")


static func _test_order_independent_settle_then_uncover() -> int:
	var r := RuinMechanisms.new()
	r.add_ward("gate")
	# Reverse order: weight lands first (on buried moss), THEN the search uncovers it — must still open,
	# and the open must be reported by the uncover() call that completes the pair.
	r.set_occupied("gate", true)
	var res: Dictionary = r.uncover("gate")
	return _ok(r.is_open("gate") and bool(res["newly_open"]), "settle-then-uncover opens too — order never matters")


static func _test_unknown_ward_is_safe_noop() -> int:
	var r := RuinMechanisms.new()
	var u: Dictionary = r.uncover("ghost")
	var o: Dictionary = r.set_occupied("ghost", true)
	return _ok(not bool(u["found"]) and not bool(o["open"]) and not r.is_open("ghost") and r.ward_ids().is_empty(), "operating on an undeclared ward is a harmless no-op")
