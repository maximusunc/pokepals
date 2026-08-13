class_name FormAffordance
extends RefCounted
## C-1 — ONE ACTION PER FORM PER OBJECT. Pure decision logic, no nodes: given the animal the
## companion is currently WEARING (its daemon form) and an object it was told to act on, answer the
## single verb that form performs on that object — or "" when this form can do nothing here.
##
## The rule is deliberately un-magical: an object AUTHORS an explicit `affordances` map, form species
## -> verb (e.g. { "fox": "unearth" } on a mound of loose earth). Because each form names at most one
## verb, resolution is never ambiguous — which is exactly the design's stance that "ambiguity is a
## level-design bug (split the object)." Tag-based generalisation ("a fox digs ANYTHING tagged
## diggable") is a different, later item (F-3 contextual filtering); this resolver stays explicit so a
## first slice has no hidden behaviour.
##
## Kept node-free and side-effect-free (species in, verb out) so it's unit-testable like
## CompanionForm and portable if the world logic ever moves onto a server.


## The verb the worn form performs on this target, or "" if none. `target` is an interactable entry
## as assembled by world_controller._setup_contents (it carries the object's `affordances` map). A
## missing/empty form, a target with no affordances, or a form absent from the map all resolve to ""
## (the caller then falls back to a plain visit).
static func resolve(form_species: String, target: Dictionary) -> String:
	if form_species == "":
		return ""
	var affordances: Variant = target.get("affordances", {})
	if not (affordances is Dictionary):
		return ""
	return String((affordances as Dictionary).get(form_species, ""))


## Whether the worn form can act on this target at all — a thin convenience over resolve() for
## call-sites that only need the yes/no (e.g. deciding between an order and a plain visit).
static func can_act(form_species: String, target: Dictionary) -> bool:
	return resolve(form_species, target) != ""


## C-3 — WHICH OBJECTS THIS FORM COULD ACT ON: the indices into `targets` the worn form affords a
## verb on, for the presentation to highlight. This is the whole hint layer in one pure call — the
## view asks it again whenever the form shifts, and what lights up changes with the shape.
##
## It differs from can_act() in one way: a target already marked SPENT (`_spent`, set by the
## controller once a verb's world effect has fired — the mound is dug) drops out of the set, so a
## finished object stops advertising itself. resolve()/can_act() deliberately keep answering for it,
## since a tap on a spent object should still reach its verb and say "already turned over" rather
## than the wrong "this shape can't help here". Non-dictionary entries are skipped, never fatal.
static func actionable_indices(form_species: String, targets: Array) -> Array:
	var out: Array = []
	if form_species == "":
		return out
	for i in targets.size():
		var t: Variant = targets[i]
		if not (t is Dictionary):
			continue
		var target: Dictionary = t
		if can_act(form_species, target) and not bool(target.get("_spent", false)):
			out.append(i)
	return out
