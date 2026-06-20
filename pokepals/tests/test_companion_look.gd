class_name TestCompanionLook
## Tests for the companion's RESTING LOOK mapping — the pure function (CompanionLook) that turns
## its grown identity + bond into the small pose offsets the body rig reads. Pure data in, plain
## dict out (no nodes, no filesystem), so this also documents the mapping's guarantees: a fresh
## companion reads neutral, the look crystallizes as the bond deepens, each trait pushes the pose
## the intended way, the body grows over the bond arc, and the coat warms only late.

const EPS := 0.0001


static func run_all() -> int:
	var fails := 0
	print("TestCompanionLook")
	var cfg := _test_cfg()
	fails += _test_fresh_companion_reads_neutral(cfg)
	fails += _test_curiosity_perks_ears_and_lifts_gaze(cfg)
	fails += _test_energy_livens_idle_and_tail(cfg)
	fails += _test_clinginess_relaxes_ears(cfg)
	fails += _test_offsets_crystallize_with_bond(cfg)
	fails += _test_body_grows_over_the_bond(cfg)
	fails += _test_coat_warms_only_late(cfg)
	fails += _test_deterministic_and_pure(cfg)
	fails += _test_missing_block_is_a_safe_noop()
	fails += _test_shipped_config_has_the_block()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


# A self-contained tuning block so the assertions don't depend on the shipped numbers: every
# axis is present with a clear lo=0..hi span, the gate opens linearly (bond_exp 1), and size /
# coat have round, easy-to-assert bounds.
static func _test_cfg() -> Dictionary:
	return {
		"identity_look": {
			"ease_rate": 0.6,
			"bond_floor": 0.0,
			"bond_exp": 1.0,
			"ear_curiosity": { "trait": "curiosity", "lo": 0.0, "hi": 2.0 },
			"ear_clinginess": { "trait": "clinginess", "lo": 0.0, "hi": 1.5 },
			"bounce_energy": { "trait": "energy", "lo": 0.0, "hi": 0.6 },
			"bounce_clinginess": { "trait": "clinginess", "lo": 0.0, "hi": 0.2 },
			"wag_energy": { "trait": "energy", "lo": 0.0, "hi": 0.2 },
			"eye_curiosity": { "trait": "curiosity", "lo": 0.0, "hi": 1.0 },
			"coat": { "bond_start": 0.7, "warm": [0.06, 0.0, -0.05] },
			"size": { "scale_floor": 0.85, "scale_exp": 0.8 },
		},
	}


static func _ident(cur: float, ene: float, cli: float) -> Dictionary:
	return { "curiosity": cur, "energy": ene, "clinginess": cli }


# A fresh companion (bond 0): the identity-driven offsets are gated to ~0 (you can't read its
# grown self yet), the coat is cold, and it sits at its starting (smaller) size.
static func _test_fresh_companion_reads_neutral(cfg: Dictionary) -> int:
	var look := CompanionLook.resting_look(_ident(0.5, 0.5, 0.5), 0.0, cfg)
	var fails := 0
	fails += _ok(absf(float(look["ear_rest"])) < EPS, "fresh: ears at rest (no perk/relax)")
	fails += _ok(absf(float(look["bounce_base"])) < EPS, "fresh: no resting bounce bias")
	fails += _ok(absf(float(look["wag_life"])) < EPS, "fresh: no resting tail life")
	fails += _ok(absf(float(look["eye_lift"])) < EPS, "fresh: no gaze lift")
	fails += _ok(absf(float(look["coat_warm"])) < EPS, "fresh: coat not yet warmed")
	fails += _ok(absf(float(look["body_scale"]) - 0.85) < EPS, "fresh: sits at the starting size (scale_floor)")
	return fails


# Curiosity (read at full bond, so the gate is open): perks the ears (a larger ear_rest, which
# the view subtracts from ear_offset to raise them) and carries the gaze higher.
static func _test_curiosity_perks_ears_and_lifts_gaze(cfg: Dictionary) -> int:
	var curious := CompanionLook.resting_look(_ident(1.0, 0.5, 0.5), 1.0, cfg)
	var incurious := CompanionLook.resting_look(_ident(0.3, 0.5, 0.5), 1.0, cfg)
	var fails := 0
	fails += _ok(float(curious["ear_rest"]) > float(incurious["ear_rest"]) + EPS, "curiosity perks the ears more")
	fails += _ok(float(curious["eye_lift"]) > float(incurious["eye_lift"]) + EPS, "curiosity lifts the gaze more")
	return fails


# Energy: a livelier resting idle (bigger bounce bias) and a little resting tail-life floor.
static func _test_energy_livens_idle_and_tail(cfg: Dictionary) -> int:
	var lively := CompanionLook.resting_look(_ident(0.5, 1.0, 0.5), 1.0, cfg)
	var calm := CompanionLook.resting_look(_ident(0.5, 0.25, 0.5), 1.0, cfg)
	var fails := 0
	fails += _ok(float(lively["bounce_base"]) > float(calm["bounce_base"]) + EPS, "energy livens the idle bounce")
	fails += _ok(float(lively["wag_life"]) > float(calm["wag_life"]) + EPS, "energy gives the resting tail more life")
	return fails


# Clinginess relaxes the ears: increasing it monotonically softens the resting ear pose (a lower
# ear_rest), so a clingy companion carries softer ears than an aloof one at equal curiosity.
static func _test_clinginess_relaxes_ears(cfg: Dictionary) -> int:
	var aloof := CompanionLook.resting_look(_ident(0.7, 0.5, 0.1), 1.0, cfg)
	var middling := CompanionLook.resting_look(_ident(0.7, 0.5, 0.5), 1.0, cfg)
	var clingy := CompanionLook.resting_look(_ident(0.7, 0.5, 0.9), 1.0, cfg)
	var fails := 0
	fails += _ok(float(aloof["ear_rest"]) > float(middling["ear_rest"]) + EPS, "more clinginess relaxes the ears (1)")
	fails += _ok(float(middling["ear_rest"]) > float(clingy["ear_rest"]) + EPS, "more clinginess relaxes the ears (2)")
	return fails


# Crystallization: the SAME identity reads ~zero at bond 0 and full at bond 1, with a partway bond
# landing strictly between — the look is something the companion grows into as you bond.
static func _test_offsets_crystallize_with_bond(cfg: Dictionary) -> int:
	var ident := _ident(1.0, 1.0, 0.2)
	var at0 := CompanionLook.resting_look(ident, 0.0, cfg)
	var at_half := CompanionLook.resting_look(ident, 0.5, cfg)
	var at1 := CompanionLook.resting_look(ident, 1.0, cfg)
	var fails := 0
	fails += _ok(absf(float(at0["ear_rest"])) < EPS, "bond 0: identity pose gated to ~zero")
	fails += _ok(float(at1["ear_rest"]) > float(at_half["ear_rest"]) + EPS, "bond 1 reads stronger than mid bond")
	fails += _ok(float(at_half["ear_rest"]) > float(at0["ear_rest"]) + EPS, "mid bond reads stronger than fresh")
	fails += _ok(float(at1["bounce_base"]) > float(at0["bounce_base"]) + EPS, "bounce bias too crystallizes with bond")
	return fails


# The companion GROWS over the bond arc (bond alone, regardless of identity): scale_floor at bond
# 0, exactly 1.0 at bond 1, and monotonically increasing between.
static func _test_body_grows_over_the_bond(cfg: Dictionary) -> int:
	var a := CompanionLook.resting_look(_ident(0.5, 0.5, 0.5), 0.0, cfg)
	var b := CompanionLook.resting_look(_ident(0.5, 0.5, 0.5), 0.5, cfg)
	var c := CompanionLook.resting_look(_ident(0.5, 0.5, 0.5), 1.0, cfg)
	var fails := 0
	fails += _ok(absf(float(a["body_scale"]) - 0.85) < EPS, "bond 0: body at scale_floor")
	fails += _ok(absf(float(c["body_scale"]) - 1.0) < EPS, "bond 1: body at full size")
	fails += _ok(float(b["body_scale"]) > float(a["body_scale"]) + EPS and float(c["body_scale"]) > float(b["body_scale"]) + EPS, "body size grows monotonically with bond")
	# Identity does not change size — only the bond does.
	var hi := CompanionLook.resting_look(_ident(1.0, 1.0, 1.0), 0.5, cfg)
	fails += _ok(absf(float(hi["body_scale"]) - float(b["body_scale"])) < EPS, "size depends on bond alone, not identity")
	return fails


# The coat warming is a LATE, emergent cue: nothing until bond_start, then ramping to full by
# bond 1 — "fully bonded, fully itself", never a low-bond readout.
static func _test_coat_warms_only_late(cfg: Dictionary) -> int:
	var ident := _ident(0.5, 0.5, 0.5)
	var fails := 0
	fails += _ok(absf(float(CompanionLook.resting_look(ident, 0.5, cfg)["coat_warm"])) < EPS, "coat stays cold below bond_start")
	fails += _ok(absf(float(CompanionLook.resting_look(ident, 0.7, cfg)["coat_warm"])) < EPS, "coat still cold AT bond_start")
	fails += _ok(float(CompanionLook.resting_look(ident, 0.85, cfg)["coat_warm"]) > EPS, "coat begins warming past bond_start")
	fails += _ok(absf(float(CompanionLook.resting_look(ident, 1.0, cfg)["coat_warm"]) - 1.0) < EPS, "coat fully warm at bond 1")
	return fails


# Deterministic, and it never mutates its inputs (so a caller can hold the identity dict safely).
static func _test_deterministic_and_pure(cfg: Dictionary) -> int:
	var ident := _ident(0.8, 0.6, 0.4)
	var before := ident.duplicate(true)
	var a := CompanionLook.resting_look(ident, 0.6, cfg)
	var b := CompanionLook.resting_look(ident, 0.6, cfg)
	var fails := 0
	fails += _ok(_same(a, b), "same inputs give the same look (deterministic)")
	fails += _ok(_same(ident, before), "the identity dict is not mutated")
	return fails


# A config with no identity_look block is a silent no-op: neutral offsets, no coat, full size.
static func _test_missing_block_is_a_safe_noop() -> int:
	var look := CompanionLook.resting_look(_ident(1.0, 1.0, 1.0), 1.0, {})
	var fails := 0
	fails += _ok(absf(float(look["ear_rest"])) < EPS, "no block: no ear bias")
	fails += _ok(absf(float(look["bounce_base"])) < EPS, "no block: no bounce bias")
	fails += _ok(absf(float(look["coat_warm"])) < EPS, "no block: no coat warming")
	fails += _ok(absf(float(look["body_scale"]) - 1.0) < EPS, "no block: full size (no scaling)")
	return fails


# Guards the SHIPPED config: the block exists and a fully bonded, highly-curious companion reads a
# real (non-zero) perked-ear pose — so the feature is actually wired into the game's tuning.
static func _test_shipped_config_has_the_block() -> int:
	var cfg := WorldData.load_json("res://data/companion.json")
	var fails := 0
	fails += _ok(cfg.has("identity_look"), "shipped companion.json defines identity_look")
	var look := CompanionLook.resting_look(_ident(1.0, 0.7, 0.6), 1.0, cfg)
	fails += _ok(float(look["ear_rest"]) > EPS, "shipped: a bonded, curious companion perks its ears")
	fails += _ok(float(look["body_scale"]) > float(CompanionLook.resting_look(_ident(1.0, 0.7, 0.6), 0.0, cfg)["body_scale"]) + EPS, "shipped: it grows from fresh to bonded")
	return fails


static func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key):
			return false
		if typeof(a[key]) == TYPE_FLOAT or typeof(a[key]) == TYPE_INT:
			if absf(float(a[key]) - float(b[key])) > EPS:
				return false
		elif a[key] != b[key]:
			return false
	return true
