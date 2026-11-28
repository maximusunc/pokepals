class_name FormEffect
extends RefCounted
## F-2 (follow-on) — WHAT A PERFORMED VERB DOES, as data. Given an object and the verb its form just
## performed on it, answer a PLAN: the line to say, whether the object is used up, and what (if
## anything) it reveals. Pure decision logic, no nodes — the controller executes the plan.
##
## This replaces the per-verb `match` the first slice used. A verb's effect is AUTHORED ON THE OBJECT
## in the world spec, beside the affordance that names it:
##
##     "affordances":  { "rabbit": "wriggle" },
##     "form_effects": {
##       "wriggle": {
##         "hint":       "…what the player is told when it happens",
##         "spent_hint": "…and what they're told if they ask again (optional)",
##         "reveal": {                       // optional — an effect can be a pure moment
##           "id": "…", "label": "…", "type": "mushrooms", "color": [r,g,b],
##           "tags": ["…"], "lore": "…",
##           "offset": [dx, dy]              // beside the object … or "position": [x, y] for a
##         }                                 //   spot elsewhere in the world (the bird's survey)
##       }
##     }
##
## So a new verb needs NO GDScript: author the affordance, the line, and the reveal. That's the
## "one action per form per object" rule (C-1) carried through to consequences, and it keeps the
## brain — and now the controller — blind to what any particular verb means.

## The default line when a form performs a verb the object names but authors no effect for (the
## companion still went and did the gesture, so this acknowledges rather than silently dropping it).
const DEFAULT_HINT := "Your companion tends to %s."
## The default line for acting on something whose effect has already fired.
const DEFAULT_SPENT_HINT := "Your companion has already seen to that."


## The plan for performing `verb` on `target` (an interactable entry as world_controller assembles
## it). Always returns a usable plan — an unauthored verb degrades to a spoken acknowledgement.
##
##   already: the effect already fired; say `hint` and change nothing.
##   spends:  mark the target `_spent` after applying (only ever true for an AUTHORED effect —
##            an unwired verb doesn't use the object up).
##   reveal:  {} or a ready-to-add interactable { id, label, type, color, tags, lore, pos: Vector2 }.
static func plan(target: Dictionary, verb: String) -> Dictionary:
	var label := String(target.get("label", "it"))
	var effects: Variant = target.get("form_effects", {})
	var effect: Dictionary = {}
	if effects is Dictionary:
		var raw: Variant = (effects as Dictionary).get(verb, {})
		if raw is Dictionary:
			effect = raw

	if effect.is_empty():
		return { "verb": verb, "already": false, "spends": false, "hint": DEFAULT_HINT % label, "reveal": {} }

	if bool(target.get("_spent", false)):
		return {
			"verb": verb,
			"already": true,
			"spends": false,
			"hint": String(effect.get("spent_hint", DEFAULT_SPENT_HINT)),
			"reveal": {},
		}

	return {
		"verb": verb,
		"already": false,
		"spends": true,
		"hint": String(effect.get("hint", DEFAULT_HINT % label)),
		"reveal": _reveal(effect.get("reveal", {}), target),
	}


## Resolve an authored reveal into a ready-to-add interactable, with its world position worked out:
## an explicit "position" lands it anywhere in the world (the bird spots something across the vale),
## an "offset" places it beside the object it came out of. Returns {} when nothing is revealed — an
## effect is allowed to be a pure moment with no lasting object.
static func _reveal(raw: Variant, target: Dictionary) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return {}
	var spec: Dictionary = raw
	var origin: Vector2 = target.get("pos", Vector2.ZERO)
	var pos := origin
	if spec.has("position"):
		pos = WorldData.to_vec2(spec["position"])
	elif spec.has("offset"):
		pos = origin + WorldData.to_vec2(spec["offset"])
	return {
		"id": String(spec.get("id", "")),
		"label": String(spec.get("label", "something")),
		"type": String(spec.get("type", "chime_stone")),
		"color": WorldData.to_color(spec.get("color", [0.66, 0.70, 0.78])),
		"tags": spec.get("tags", []),
		"lore": String(spec.get("lore", "")),
		"pos": pos,
	}
