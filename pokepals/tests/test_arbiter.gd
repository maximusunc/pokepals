class_name TestArbiter
## Tests for the cross-action decision rules — bands, the zero-bid rule, commitment
## hysteresis, and interruptibility — using stub actions with fixed desires so the
## arbiter's logic is checked in isolation from any real behavior.

# A stub action with a fixed desire and (optionally) a fixed commitment, for driving the
# arbiter. A commitment < 0 means "use the base default" (the cfg's commit_bonus).
class StubAction extends CompanionActions.CompanionAction:
	var _desire := 0.0
	var _commitment := -1.0

	func _init(p_id: String, p_band: int, p_desire: float, p_commitment := -1.0) -> void:
		id = p_id
		band = p_band
		behavior = p_id
		_desire = p_desire
		_commitment = p_commitment

	func score(_perception: Dictionary, _s: CompanionSelf, _cfg: Dictionary, _rng: RandomNumberGenerator) -> float:
		return _desire

	func commitment(cfg: Dictionary) -> float:
		return _commitment if _commitment >= 0.0 else super.commitment(cfg)


static func run_all() -> int:
	var fails := 0
	print("TestArbiter")
	fails += _test_higher_band_wins_regardless_of_desire()
	fails += _test_zero_bid_is_ineligible()
	fails += _test_within_band_highest_desire_wins()
	fails += _test_tie_breaks_by_order()
	fails += _test_commitment_resists_marginal_rival()
	fails += _test_committed_holds_same_band()
	fails += _test_higher_band_breaks_committed()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _cfg(commit := 0.0) -> Dictionary:
	return { "arbiter": { "commit_bonus": commit } }


static func _rng() -> RandomNumberGenerator:
	return RandomNumberGenerator.new()


static func _test_higher_band_wins_regardless_of_desire() -> int:
	# A huge desire in a low band still loses to any eligible higher band.
	var actions := [StubAction.new("low", 1, 100.0), StubAction.new("high", 2, 0.1)]
	var d := CompanionArbiter.new().decide(actions, {}, null, _cfg(), _rng())
	return _ok(d["winner"].id == "high", "a higher band wins even against a much larger lower-band desire")


static func _test_zero_bid_is_ineligible() -> int:
	# A higher band that bids 0 must NOT win — a lower band that actually bids takes it.
	var actions := [StubAction.new("silent_high", 2, 0.0), StubAction.new("bidding_low", 1, 1.0)]
	var d := CompanionArbiter.new().decide(actions, {}, null, _cfg(), _rng())
	return _ok(d["winner"].id == "bidding_low", "an action bidding 0 is ineligible whatever its band")


static func _test_within_band_highest_desire_wins() -> int:
	var actions := [StubAction.new("a", 1, 3.0), StubAction.new("b", 1, 7.0)]
	var d := CompanionArbiter.new().decide(actions, {}, null, _cfg(), _rng())
	return _ok(d["winner"].id == "b", "within a band, the keener desire wins")


static func _test_tie_breaks_by_order() -> int:
	var actions := [StubAction.new("first", 1, 5.0), StubAction.new("second", 1, 5.0)]
	var d := CompanionArbiter.new().decide(actions, {}, null, _cfg(), _rng())
	return _ok(d["winner"].id == "first", "an exact tie goes to the earlier-listed action")


static func _test_commitment_resists_marginal_rival() -> int:
	var arb := CompanionArbiter.new()
	var cfg := _cfg(0.5)
	# Frame 1: A wins (keener), becomes the running action.
	var a := StubAction.new("a", 1, 5.0)
	var b := StubAction.new("b", 1, 4.0)
	arb.decide([a, b], {}, null, cfg, _rng())
	# Frame 2: B is now marginally keener (5.2 vs 5.0) but within the commit bonus.
	b._desire = 5.2
	var d := arb.decide([a, b], {}, null, cfg, _rng())
	var fails := 0
	fails += _ok(d["winner"].id == "a", "a running action resists a rival within the commit bonus (no jitter)")
	# A rival that clearly exceeds the bonus does take over.
	b._desire = 6.0
	var d2 := arb.decide([a, b], {}, null, cfg, _rng())
	fails += _ok(d2["winner"].id == "b", "a clearly keener rival still wins")
	return fails


static func _test_committed_holds_same_band() -> int:
	var arb := CompanionArbiter.new()
	var cfg := _cfg()
	# Make A the running action first via a frame where only A bids.
	var a := StubAction.new("a", 1, 5.0, 100.0)  # large commitment = a committed beat
	var b := StubAction.new("b", 1, 0.0)
	arb.decide([a, b], {}, null, cfg, _rng())  # only a bids -> a runs
	# Now B is far keener, but A's commitment (5 + 100) keeps it ahead within the band.
	b._desire = 9.0
	var d := arb.decide([a, b], {}, null, cfg, _rng())
	return _ok(d["winner"].id == "a", "a committed action (high commitment) holds against a keener same-band rival")


static func _test_higher_band_breaks_committed() -> int:
	var arb := CompanionArbiter.new()
	var cfg := _cfg()
	var a := StubAction.new("a", 1, 5.0, 100.0)  # committed, low band
	var hi := StubAction.new("hi", 2, 0.0)
	arb.decide([a, hi], {}, null, cfg, _rng())  # only a bids -> a runs
	hi._desire = 0.1
	var d := arb.decide([a, hi], {}, null, cfg, _rng())
	return _ok(d["winner"].id == "hi", "a higher band breaks in even on a committed action (commitment is within-band only)")
