class_name TestKeepsakeChoice
## Tests for HS-3 — the companion's keepsake choice. KeepsakeChoice is pure (finds + identity in, a
## choice out), so it's exercised with hand-made finds. Pinned: the bond opens 3..7 spots; liking is
## the temperament match to the grown identity plus a together bonus; empty spots fill at once; a swap
## needs a clear margin and happens at most once a visit; the favourite comes first.

const CURIOUS := { "curiosity": 0.9, "energy": 0.6, "clinginess": 0.3 }
const SNUG := { "curiosity": 0.2, "energy": 0.2, "clinginess": 0.9 }


static func run_all() -> int:
	var fails := 0
	print("TestKeepsakeChoice")
	fails += _test_spots_follow_the_bond()
	fails += _test_liking_prefers_a_matching_temperament()
	fails += _test_together_counts_extra()
	fails += _test_empty_spots_fill_with_the_best_liked()
	fails += _test_a_clear_favourite_comes_first()
	fails += _test_a_close_call_keeps_the_old_choice()
	fails += _test_a_clearly_better_find_swaps_once()
	fails += _test_vanished_finds_are_dropped()
	fails += _test_nothing_changes_when_settled()
	return fails


static func _ok(cond: bool, label: String) -> int:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	return 0 if cond else 1


static func _find(id: String, t: Dictionary, together := false) -> Dictionary:
	return { "id": id, "temperament": t, "together": together }


static func _test_spots_follow_the_bond() -> int:
	return _ok(KeepsakeChoice.spots_for_bond(0.0) == 3 and KeepsakeChoice.spots_for_bond(0.5) == 5
		and KeepsakeChoice.spots_for_bond(1.0) == 7 and KeepsakeChoice.spots_for_bond(9.0) == 7,
		"the bond opens 3 to 7 spots")


static func _test_liking_prefers_a_matching_temperament() -> int:
	var odd := _find("odd", { "curiosity": 0.95, "energy": 0.6, "clinginess": 0.3 })
	var warm := _find("warm", { "curiosity": 0.1, "energy": 0.2, "clinginess": 0.95 })
	return _ok(KeepsakeChoice.liking(odd, CURIOUS) > KeepsakeChoice.liking(warm, CURIOUS)
		and KeepsakeChoice.liking(warm, SNUG) > KeepsakeChoice.liking(odd, SNUG),
		"a curious companion likes the strange find, a snug one the warm find")


static func _test_together_counts_extra() -> int:
	var t := { "curiosity": 0.5, "energy": 0.5, "clinginess": 0.5 }
	return _ok(is_equal_approx(KeepsakeChoice.liking(_find("a", t, true), CURIOUS) - KeepsakeChoice.liking(_find("a", t), CURIOUS), KeepsakeChoice.TOGETHER_BONUS),
		"a find made together is liked by the bonus more")


static func _test_empty_spots_fill_with_the_best_liked() -> int:
	var finds := [_find("a", SNUG), _find("b", CURIOUS), _find("c", SNUG), _find("d", CURIOUS), _find("e", SNUG)]
	var r := KeepsakeChoice.choose(finds, CURIOUS, 3, [])
	return _ok(r["keep"].size() == 3 and r["keep"].has("b") and r["keep"].has("d") and r["filled"].size() == 3 and r["changed"],
		"three empty spots take the three best-liked finds")


static func _test_a_clear_favourite_comes_first() -> int:
	var r := KeepsakeChoice.choose([_find("snug", SNUG), _find("curious", CURIOUS)], CURIOUS, 3, [])
	return _ok(r["keep"][0] == "curious", "the favourite is first")


static func _test_a_close_call_keeps_the_old_choice() -> int:
	var a := _find("a", { "curiosity": 0.8, "energy": 0.6, "clinginess": 0.3 })
	var b := _find("b", { "curiosity": 0.9, "energy": 0.6, "clinginess": 0.3 })
	var full := [_find("x", CURIOUS), _find("y", CURIOUS), a, b]
	var r := KeepsakeChoice.choose(full, CURIOUS, 3, ["x", "y", "a"])
	return _ok(r["swapped_in"] == "" and not r["changed"], "a slightly better find doesn't unseat a keepsake")


static func _test_a_clearly_better_find_swaps_once() -> int:
	var finds := [_find("s1", SNUG), _find("s2", SNUG), _find("s3", SNUG), _find("c1", CURIOUS), _find("c2", CURIOUS)]
	var r := KeepsakeChoice.choose(finds, CURIOUS, 3, ["s1", "s2", "s3"])
	var swaps: int = 0
	for id in ["s1", "s2", "s3"]:
		if not r["keep"].has(id):
			swaps += 1
	return _ok(swaps == 1 and r["swapped_in"] in ["c1", "c2"] and r["swapped_out"] != "" and r["keep"][0] == r["swapped_in"],
		"a clearly better find swaps in, only one per visit, and becomes the favourite")


static func _test_vanished_finds_are_dropped() -> int:
	var r := KeepsakeChoice.choose([_find("a", CURIOUS)], CURIOUS, 3, ["gone", "a"])
	return _ok(r["keep"] == ["a"] and r["changed"], "a keepsake with no find behind it is dropped")


static func _test_nothing_changes_when_settled() -> int:
	var finds := [_find("a", CURIOUS), _find("b", SNUG)]
	var first := KeepsakeChoice.choose(finds, CURIOUS, 3, [])
	var again := KeepsakeChoice.choose(finds, CURIOUS, 3, first["keep"])
	return _ok(not again["changed"] and again["keep"] == first["keep"], "a settled choice stays put")
