class_name TestFormAffordance
## Tests for C-1 — ONE ACTION PER FORM PER OBJECT. FormAffordance.resolve() is pure (species + object
## in, one verb out), so it's exercised directly with hand-made object entries. The point being pinned:
## the worn form decides the verb; each object names at most one verb per form (never ambiguous); and
## every "can't act here" path (no form, no map, form absent from the map) resolves to "" so the caller
## falls back to a plain visit.

static func run_all() -> int:
	var fails := 0
	print("TestFormAffordance")
	fails += _test_matching_form_resolves_its_verb()
	fails += _test_non_matching_form_resolves_nothing()
	fails += _test_empty_form_resolves_nothing()
	fails += _test_object_without_affordances_resolves_nothing()
	fails += _test_malformed_affordances_resolves_nothing()
	fails += _test_can_act_mirrors_resolve()
	fails += _test_actionable_indices_selects_this_form_only()
	fails += _test_actionable_indices_skips_spent()
	fails += _test_actionable_indices_empty_without_a_form()
	fails += _test_actionable_indices_survives_junk()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


# An interactable entry as world_controller assembles it, carrying an affordance map.
static func _mound() -> Dictionary:
	return { "id": "dig_mound", "label": "a mound of loose earth", "affordances": { "fox": "unearth" } }


# The worn form is named in the object's map -> that one verb.
static func _test_matching_form_resolves_its_verb() -> int:
	return _ok(FormAffordance.resolve("fox", _mound()) == "unearth", "a fox on the mound resolves 'unearth'")


# A form the object doesn't name affords nothing here (a bird can't dig this mound).
static func _test_non_matching_form_resolves_nothing() -> int:
	return _ok(FormAffordance.resolve("bird", _mound()) == "", "a form absent from the map resolves '' (a plain visit)")


# No worn form at all (procedural fallback) -> nothing to resolve.
static func _test_empty_form_resolves_nothing() -> int:
	return _ok(FormAffordance.resolve("", _mound()) == "", "no worn form resolves '' (no verb without a form)")


# A plain object with no affordances map affords no form-verb.
static func _test_object_without_affordances_resolves_nothing() -> int:
	var bench := { "id": "bench", "label": "a weathered bench" }
	return _ok(FormAffordance.resolve("fox", bench) == "", "an object with no affordances resolves '' for any form")


# A malformed affordances value (not a dictionary) never crashes — it just resolves nothing.
static func _test_malformed_affordances_resolves_nothing() -> int:
	var junk := { "id": "junk", "affordances": ["fox", "unearth"] }
	return _ok(FormAffordance.resolve("fox", junk) == "", "a non-dictionary affordances value resolves '' safely")


# can_act() is the boolean face of resolve() — true exactly when a verb resolves.
static func _test_can_act_mirrors_resolve() -> int:
	var fails := 0
	fails += _ok(FormAffordance.can_act("fox", _mound()), "can_act true when the form affords a verb")
	fails += _ok(not FormAffordance.can_act("bird", _mound()), "can_act false when it doesn't")
	return fails


# A world of three objects, two of which a fox can work on: the highlight set is exactly those two,
# and wearing a different shape lights up a different (here, smaller) set. That swap IS the C-3 beat.
static func _test_actionable_indices_selects_this_form_only() -> int:
	var world := [
		_mound(),                                                         # fox
		{ "id": "bench", "label": "a weathered bench" },                   # nobody
		{ "id": "high_nest", "affordances": { "bird": "peek", "fox": "sniff" } },
	]
	var fails := 0
	fails += _ok(FormAffordance.actionable_indices("fox", world) == [0, 2], "a fox lights the mound and the nest")
	fails += _ok(FormAffordance.actionable_indices("bird", world) == [2], "a bird lights only the nest")
	fails += _ok(FormAffordance.actionable_indices("wolf", world) == [], "a shape that affords nothing lights nothing")
	return fails


# Once a verb's effect has fired the object is spent: it stops advertising itself, even though a tap
# still resolves its verb (so the "already turned over" line, not "this shape can't help", is what
# the player hears).
static func _test_actionable_indices_skips_spent() -> int:
	var dug := _mound()
	dug["_spent"] = true
	var fails := 0
	fails += _ok(FormAffordance.actionable_indices("fox", [dug]) == [], "a spent object drops out of the highlight set")
	fails += _ok(FormAffordance.resolve("fox", dug) == "unearth", "...but its verb still resolves for the tap path")
	return fails


# No worn form (the procedural fallback) means nothing to hint at — never a stray highlight.
static func _test_actionable_indices_empty_without_a_form() -> int:
	return _ok(FormAffordance.actionable_indices("", [_mound()]) == [], "no worn form highlights nothing")


# The list is assembled from world data, so a malformed entry must be skipped, not fatal.
static func _test_actionable_indices_survives_junk() -> int:
	var world := ["not a dictionary", _mound()]
	return _ok(FormAffordance.actionable_indices("fox", world) == [1], "a non-dictionary entry is skipped safely")
