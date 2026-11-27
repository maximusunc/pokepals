class_name SalamanderHunt
extends RefCounted
## The riverbank goal as PURE LOGIC: hide a handful of little salamanders (and some
## non-counting decoys) among the rocks, track which rocks have been turned over, and
## report progress. No nodes, no rendering, no filesystem — state in, state out — so it's
## unit-testable, runs headless, and could move to a server later. The presentation layer
## (world_controller) owns *where* the rocks are and *how* a reveal looks; this owns only
## the rules of the hunt: what's under each rock, how many salamanders are left, and when
## the last one is found.
##
## Each visit calls setup() with a fresh RNG, so the salamanders are re-hidden differently
## every time — the world is meant to reset and surprise you on each return.

## What a rock hides. Only SALAMANDER counts toward the goal.
enum Content { EMPTY, SALAMANDER, DECOY }

var total := 0                  # how many salamanders are hidden (the goal count)
var found := 0                  # how many have been uncovered so far

# The flip budget: how many NEW rocks you may turn over before the hunt ends. 0 disables it
# (unlimited flips — the old behavior, and what worlds without a budget / older tests get).
# This is what turns "flip every rock" into a real decision: spend your flips where your
# companion's tell says a salamander is hiding.
var budget := 0                 # max NEW flips allowed (0 = unlimited / disabled)
var flips_used := 0             # NEW rocks turned over so far

var _contents: Array = []       # rock_index -> Content
var _decoy_defs: Array = []     # [{ label, tags }]; assigned decoys index into this
var _decoy_at: Dictionary = {}  # rock_index -> decoy def index
var _examined: Dictionary = {}  # rock_index -> true once turned over


## Lay out the hunt over `rock_count` rocks: pick `salamander_count` rocks to hide
## salamanders, `decoy_count` more to hide (non-counting) decoys cycling through
## `decoy_defs`, and leave the rest empty. Shuffled with the given RNG so each visit
## differs. Clamps gracefully if there aren't enough rocks for the requested counts.
## `flip_budget` (optional, default 0 = unlimited) caps how many NEW rocks may be turned over
## before the hunt ends — see `budget`. Kept as a trailing default so existing callers/tests that
## don't care about a budget are unchanged.
func setup(rock_count: int, salamander_count: int, decoy_defs: Array, decoy_count: int, rng: RandomNumberGenerator, flip_budget: int = 0) -> void:
	_decoy_defs = decoy_defs
	_contents.clear()
	_decoy_at.clear()
	_examined.clear()
	_contents.resize(rock_count)
	_contents.fill(Content.EMPTY)

	var order: Array = []
	for i in rock_count:
		order.append(i)
	_shuffle(order, rng)

	total = clampi(salamander_count, 0, rock_count)
	found = 0
	budget = maxi(0, flip_budget)
	flips_used = 0
	var cursor := 0
	for s in total:
		_contents[order[cursor]] = Content.SALAMANDER
		cursor += 1

	var decoys := clampi(decoy_count, 0, rock_count - cursor)
	for d in decoys:
		var idx: int = order[cursor]
		_contents[idx] = Content.DECOY
		if not _decoy_defs.is_empty():
			_decoy_at[idx] = d % _decoy_defs.size()
		cursor += 1


## Turn over the rock at `index`. Returns a result the presentation can render and the
## controller can act on:
##   { kind:"salamander"|"decoy"|"empty", label, tags,
##     found, total, complete, newly_complete, already_examined,
##     flips_used, flips_remaining, out_of_flips }
## Re-examining the same rock is a harmless no-op (already_examined=true, no double count, no
## budget spent — the early return below happens before flips_used ticks up).
func examine(index: int) -> Dictionary:
	var result := {
		"kind": "empty",
		"label": "",
		"tags": [],
		"found": found,
		"total": total,
		"complete": found >= total and total > 0,
		"newly_complete": false,
		"already_examined": false,
		"flips_used": flips_used,
		"flips_remaining": flips_remaining(),
		"out_of_flips": false,
	}
	if index < 0 or index >= _contents.size():
		return result
	if _examined.get(index, false):
		result["already_examined"] = true
		return result
	_examined[index] = true
	# A genuinely new flip — spend one from the budget. (Re-taps returned above and never reach here.)
	flips_used += 1

	var content: int = _contents[index]
	match content:
		Content.SALAMANDER:
			found += 1
			result["kind"] = "salamander"
			result["label"] = "a little river salamander!"
			result["tags"] = ["water", "shiny", "odd"]
			if found >= total:
				result["newly_complete"] = true
		Content.DECOY:
			result["kind"] = "decoy"
			var def: Dictionary = _decoy_def_for(index)
			result["label"] = String(def.get("label", "a small find"))
			result["tags"] = def.get("tags", ["odd"])
		_:
			result["kind"] = "empty"
			result["label"] = "nothing but cool, damp sand"
			result["tags"] = []

	result["found"] = found
	result["complete"] = found >= total and total > 0
	result["flips_used"] = flips_used
	result["flips_remaining"] = flips_remaining()
	result["out_of_flips"] = out_of_flips()
	return result


## Flips left before the budget is spent. 0 once exhausted; a large sentinel when unlimited
## (budget == 0) so callers can compare/print without special-casing the disabled case.
func flips_remaining() -> int:
	if budget <= 0:
		return 999999
	return maxi(0, budget - flips_used)


## True once the budget is spent AND the hunt isn't already won — the run-out terminal state.
## The `found < total` guard means the flip that finds the LAST salamander reports `newly_complete`
## (a win), never run-out, even if it happens to be the final flip of the budget.
func out_of_flips() -> bool:
	return budget > 0 and flips_used >= budget and found < total


func is_examined(index: int) -> bool:
	return _examined.get(index, false)


## What a rock hides, as a string ("salamander" | "decoy" | "empty"), WITHOUT turning it over.
## Read-only — used by the controller to know where to point a subtle companion glance.
func content_kind(index: int) -> String:
	if index < 0 or index >= _contents.size():
		return "empty"
	match _contents[index]:
		Content.SALAMANDER:
			return "salamander"
		Content.DECOY:
			return "decoy"
		_:
			return "empty"


func is_complete() -> bool:
	return total > 0 and found >= total


## Every rock NOT yet turned over, with what it hides: [{ index:int, kind:String }]. For the
## run-out reveal — the controller flips these face-up so you see what you missed. Read-only:
## it does NOT mark them examined and does NOT touch found/flips_used (so reveal-all can't
## double-count or spend phantom budget).
func unexamined_contents() -> Array:
	var out: Array = []
	for i in _contents.size():
		if not _examined.get(i, false):
			out.append({ "index": i, "kind": content_kind(i) })
	return out


## The decoy definition assigned to a rock (empty dict if none / not a decoy).
func _decoy_def_for(index: int) -> Dictionary:
	if not _decoy_at.has(index) or _decoy_defs.is_empty():
		return {}
	return _decoy_defs[int(_decoy_at[index])]


## Fisher–Yates shuffle in place, using the supplied seeded/randomized RNG so the caller
## controls determinism (tests seed it; a real visit randomize()s it).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
