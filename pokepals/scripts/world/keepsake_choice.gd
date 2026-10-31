class_name KeepsakeChoice
extends RefCounted
## HS-3 — the companion chooses which finds become KEEPSAKES at home. Pure decision logic, no nodes
## (finds + the companion's grown identity in, a choice out), so it's unit-testable and could move to a
## server one day. It lives on the client because the companion's mind does.
##
## How it chooses (see docs/home-world-and-secrets-design.md, HS-3):
##   * how many: the bond opens spots, from 3 at bond 0 to 7 at full bond (spots_for_bond);
##   * which: each keepsake carries a small temperament (curiosity / energy / clinginess, the same
##     keys and 0..1 scale as the companion's identity). The nearer it sits to the companion's grown
##     identity, the more the companion likes it (the same nearest-match it uses to pick its signature
##     form), and finds made TOGETHER (it was right beside you) count extra;
##   * stability: choices are kept. Empty spots fill straight away, but a current keepsake is only
##     swapped out when a new find beats it by a clear margin, and never more than one swap per visit,
##     so the home changes rarely and noticeably, and never churns.
## The favourite is always first: the list is re-ordered by liking only when the set changes.

const MIN_SPOTS := 3
const MAX_SPOTS := 7
## How much extra a find made together is liked.
const TOGETHER_BONUS := 0.15
## How much more a new find must be liked than the least-liked keepsake before the companion swaps.
const SWAP_MARGIN := 0.12
const TRAITS := ["curiosity", "energy", "clinginess"]


## How many keepsake spots this bond opens (3..7).
static func spots_for_bond(bond: float) -> int:
	return MIN_SPOTS + roundi(float(MAX_SPOTS - MIN_SPOTS) * clampf(bond, 0.0, 1.0))


## How much the companion likes a find, 0..~1.15: closeness of the keepsake's temperament to its grown
## identity (1 = identical, 0 = opposite corners), plus the together bonus. A trait the keepsake doesn't
## name counts as a neutral 0.5.
static func liking(find: Dictionary, identity: Dictionary) -> float:
	var temperament: Variant = find.get("temperament", {})
	if not (temperament is Dictionary):
		temperament = {}
	var sq := 0.0
	for t in TRAITS:
		var a := float((temperament as Dictionary).get(t, 0.5))
		var b := float(identity.get(t, 0.5))
		sq += (a - b) * (a - b)
	var closeness := 1.0 - sqrt(sq) / sqrt(float(TRAITS.size()))
	return closeness + (TOGETHER_BONUS if bool(find.get("together", false)) else 0.0)


## The companion's choice. `finds` are the home's find entries ({ id, temperament, together, … }),
## `current` the keepsake ids it chose before (favourite first). Returns:
##   { keep: Array (favourite first), filled: Array (ids newly placed in empty spots),
##     swapped_out: String, swapped_in: String ("" when no swap), changed: bool }
static func choose(finds: Array, identity: Dictionary, spots: int, current: Array) -> Dictionary:
	spots = clampi(spots, MIN_SPOTS, MAX_SPOTS)
	var by_id: Dictionary = {}
	for f in finds:
		if f is Dictionary and String(f.get("id", "")) != "":
			by_id[String(f["id"])] = f
	var like := func(id: String) -> float: return liking(by_id[id], identity)

	# What it already keeps, minus anything no longer there, within the spots it has.
	var keep: Array = []
	for id in current:
		if by_id.has(String(id)) and not keep.has(String(id)) and keep.size() < spots:
			keep.append(String(id))
	var candidates: Array = by_id.keys().filter(func(id: String) -> bool: return not keep.has(id))
	candidates.sort_custom(func(a: String, b: String) -> bool: return like.call(a) > like.call(b))

	# Fill empty spots with the best-liked of the rest.
	var filled: Array = []
	while keep.size() < spots and not candidates.is_empty():
		var id: String = candidates.pop_front()
		keep.append(id)
		filled.append(id)

	# At most one swap: the best-liked newcomer against the least-liked keepsake, by a clear margin.
	var swapped_out := ""
	var swapped_in := ""
	if not candidates.is_empty() and not keep.is_empty():
		var worst: String = keep[0]
		for id in keep:
			if like.call(id) < like.call(worst):
				worst = id
		var best: String = candidates[0]
		if like.call(best) > like.call(worst) + SWAP_MARGIN:
			keep[keep.find(worst)] = best
			swapped_out = worst
			swapped_in = best

	var changed := not filled.is_empty() or swapped_in != "" or keep.size() != current.size()
	if changed:
		keep.sort_custom(func(a: String, b: String) -> bool: return like.call(a) > like.call(b))
	return {
		"keep": keep, "filled": filled, "swapped_out": swapped_out, "swapped_in": swapped_in, "changed": changed,
	}
