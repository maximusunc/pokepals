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
