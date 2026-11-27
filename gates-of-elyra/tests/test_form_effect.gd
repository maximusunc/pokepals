class_name TestFormEffect
## Tests for F-2's effect layer — WHAT A PERFORMED VERB DOES, read from the object's authored
## `form_effects`. FormEffect.plan() is pure (object + verb in, a plan out), so it's exercised with
## hand-made entries. The points being pinned: an authored effect speaks its line, spends the object
## and resolves its reveal (beside the object OR anywhere in the world); an effect is allowed to be a
## pure moment with no reveal; a spent object says its own "already done" line and changes nothing;
## and a verb nobody authored an effect for still gets acknowledged without using the object up.

static func run_all() -> int:
	var fails := 0
	print("TestFormEffect")
	fails += _test_authored_effect_speaks_spends_and_reveals()
	fails += _test_reveal_offset_is_relative_to_the_object()
	fails += _test_reveal_position_lands_anywhere()
	fails += _test_effect_without_a_reveal_is_a_pure_moment()
	fails += _test_spent_object_says_its_own_line_and_does_nothing()
	fails += _test_unauthored_verb_is_acknowledged_but_doesnt_spend()
	fails += _test_malformed_effects_never_crash()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


# The Vale's mound, as world_controller assembles it: a fox digs it and turns up a stone beside it.
static func _mound() -> Dictionary:
	return {
		"id": "dig_mound",
		"label": "a mound of loose earth",
		"pos": Vector2(370, -10),
		"affordances": { "fox": "unearth" },
		"form_effects": {
			"unearth": {
				"hint": "…and noses up a smooth, cool stone.",
				"spent_hint": "The earth here is already turned over.",
				"reveal": {
					"id": "unearthed_curio", "label": "a smooth, cool stone", "type": "chime_stone",
					"color": [0.66, 0.70, 0.78], "tags": ["shiny", "stone"], "lore": "River-worn.",
					"offset": [22, -6],
				},
			},
		},
	}


static func _test_authored_effect_speaks_spends_and_reveals() -> int:
	var plan := FormEffect.plan(_mound(), "unearth")
	var fails := 0
	fails += _ok(not bool(plan["already"]), "a fresh object isn't 'already done'")
	fails += _ok(bool(plan["spends"]), "an authored effect uses the object up")
	fails += _ok(String(plan["hint"]) == "…and noses up a smooth, cool stone.", "it speaks the authored line")
	var reveal: Dictionary = plan["reveal"]
	fails += _ok(String(reveal.get("id", "")) == "unearthed_curio", "it reveals the authored object")
	fails += _ok(String(reveal.get("type", "")) == "chime_stone", "carrying the art type to draw it with")
	fails += _ok(reveal.get("color") is Color, "with its colour parsed ready for world_art")
	return fails


# An "offset" reveal lands beside the thing it came out of.
static func _test_reveal_offset_is_relative_to_the_object() -> int:
	var plan := FormEffect.plan(_mound(), "unearth")
	var reveal: Dictionary = plan["reveal"]
	return _ok(reveal["pos"] == Vector2(370, -10) + Vector2(22, -6), "an offset reveal lands beside the object")


# A "position" reveal lands anywhere — the bird surveying from the pillar spots something far off.
static func _test_reveal_position_lands_anywhere() -> int:
	var pillar := {
		"id": "leaning_pillar", "label": "a leaning pillar", "pos": Vector2(640, -280),
		"form_effects": { "survey": { "hint": "…", "reveal": { "id": "spotted_blooms", "position": [420, -450] } } },
	}
	var reveal: Dictionary = FormEffect.plan(pillar, "survey")["reveal"]
	return _ok(reveal["pos"] == Vector2(420, -450), "an absolute reveal lands across the world, not beside the object")


# The cat's coax leaves nothing behind — the moment IS the effect. It still spends the object.
static func _test_effect_without_a_reveal_is_a_pure_moment() -> int:
	var bush := {
		"id": "berry_bush", "label": "a bush heavy with berries", "pos": Vector2(600, -120),
		"form_effects": { "coax": { "hint": "…fills, all at once, with birdsong." } },
	}
	var plan := FormEffect.plan(bush, "coax")
	var fails := 0
	fails += _ok((plan["reveal"] as Dictionary).is_empty(), "an effect may reveal nothing at all")
	fails += _ok(bool(plan["spends"]), "…and still uses the object up (the moment doesn't repeat)")
	fails += _ok(String(plan["hint"]).ends_with("birdsong."), "…and still speaks its line")
	return fails


static func _test_spent_object_says_its_own_line_and_does_nothing() -> int:
	var dug := _mound()
	dug["_spent"] = true
	var plan := FormEffect.plan(dug, "unearth")
	var fails := 0
	fails += _ok(bool(plan["already"]), "a spent object reports 'already done'")
	fails += _ok(not bool(plan["spends"]), "…so there's nothing more to spend")
	fails += _ok((plan["reveal"] as Dictionary).is_empty(), "…and nothing more to reveal")
	fails += _ok(String(plan["hint"]) == "The earth here is already turned over.", "…and it says the authored spent line")
	return fails


# A form affords a verb the object authors no effect for: the companion still went and performed the
# gesture, so it's acknowledged — but nothing is consumed, so the object keeps its highlight.
static func _test_unauthored_verb_is_acknowledged_but_doesnt_spend() -> int:
	var bare := { "id": "bench", "label": "a weathered bench", "pos": Vector2.ZERO, "affordances": { "wolf": "heave" } }
	var plan := FormEffect.plan(bare, "heave")
	var fails := 0
	fails += _ok(not bool(plan["spends"]), "an unwired verb doesn't use the object up")
	fails += _ok(String(plan["hint"]) == FormEffect.DEFAULT_HINT % "a weathered bench", "…but is still acknowledged out loud")
	fails += _ok((plan["reveal"] as Dictionary).is_empty(), "…and reveals nothing")
	return fails


# form_effects comes from world data, so junk must degrade to the default, never crash.
static func _test_malformed_effects_never_crash() -> int:
	var fails := 0
	var junk := { "label": "junk", "pos": Vector2.ZERO, "form_effects": ["not", "a", "dictionary"] }
	fails += _ok(String(FormEffect.plan(junk, "heave")["hint"]) == FormEffect.DEFAULT_HINT % "junk", "a non-dictionary form_effects degrades to the default line")
	var junk_verb := { "label": "junk", "pos": Vector2.ZERO, "form_effects": { "heave": "oops" } }
	fails += _ok(not bool(FormEffect.plan(junk_verb, "heave")["spends"]), "a non-dictionary effect body spends nothing")
	var junk_reveal := { "label": "junk", "pos": Vector2.ZERO, "form_effects": { "heave": { "hint": "…", "reveal": 7 } } }
	fails += _ok((FormEffect.plan(junk_reveal, "heave")["reveal"] as Dictionary).is_empty(), "a non-dictionary reveal is simply no reveal")
	return fails
