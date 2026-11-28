class_name TestArtStyle
## Tests for ArtStyle's PER-WORLD re-skin: a world spec's "art" block deep-merges over the shared
## art.json, so one world (Nocthollow) can swap its palette, trees and visitors' light while every
## other world keeps the shared look. The points pinned: nested dictionaries merge key by key (naming
## one palette colour keeps the rest), arrays and scalars replace, the base is never mutated, and a
## world with no override gets exactly the shared style.

static func run_all() -> int:
	var fails := 0
	print("TestArtStyle")
	fails += _test_nested_dicts_merge_key_by_key()
	fails += _test_arrays_and_scalars_replace()
	fails += _test_base_is_not_mutated()
	fails += _test_world_override_reskins_only_what_it_names()
	fails += _test_no_override_is_the_shared_style()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _test_nested_dicts_merge_key_by_key() -> int:
	var base := { "palette": { "ground_top": [1, 1, 1], "water": [0, 0, 1] } }
	var out := ArtStyle.deep_merge(base, { "palette": { "ground_top": [0, 0, 0] } })
	var fails := 0
	fails += _ok(out["palette"]["ground_top"] == [0, 0, 0], "a named palette colour is replaced")
	fails += _ok(out["palette"]["water"] == [0, 0, 1], "an unnamed palette colour survives the merge")
	return fails


static func _test_arrays_and_scalars_replace() -> int:
	var base := { "props": { "types": ["crystal", "lantern"], "render": "sprite" }, "n": 1 }
	var out := ArtStyle.deep_merge(base, { "props": { "types": ["glowcaps"] }, "n": 2 })
	var fails := 0
	fails += _ok(out["props"]["types"] == ["glowcaps"], "an array in the override replaces the base array")
	fails += _ok(out["props"]["render"] == "sprite", "a sibling key of a replaced array is kept")
	fails += _ok(out["n"] == 2, "a scalar in the override replaces the base")
	return fails


static func _test_base_is_not_mutated() -> int:
	var base := { "palette": { "grass": [0, 1, 0] } }
	var over := { "palette": { "grass": [0, 0, 1] }, "entities": { "tree": { "variants": [{ "trunk": "a" }] } } }
	var out := ArtStyle.deep_merge(base, over)
	out["entities"]["tree"]["variants"][0]["trunk"] = "changed"
	var fails := 0
	fails += _ok(base["palette"]["grass"] == [0, 1, 0], "merging never writes into the base")
	fails += _ok(String(over["entities"]["tree"]["variants"][0]["trunk"]) == "a", "the merged result doesn't alias the override")
	return fails


static func _test_world_override_reskins_only_what_it_names() -> int:
	var over := {
		"palette": { "ground_top": [0.07, 0.06, 0.17] },
		"actor_look": { "aura": [0.5, 0.95, 1.0] },
		"entities": { "crystal_spire": { "render": "sprite", "sway": 0.0 } },
	}
	var shared := ArtStyle.load_style()
	var s := ArtStyle.load_style("res://data/art.json", over)
	var fails := 0
	fails += _ok(s.color("ground_top").is_equal_approx(Color(0.07, 0.06, 0.17)), "the world's own ground colour is used")
	fails += _ok(s.color("water").is_equal_approx(shared.color("water")), "a colour the world didn't name stays shared")
	fails += _ok(not s.actor_look().is_empty(), "the world's actor_look comes through")
	fails += _ok(float(s.entity("crystal_spire").get("sway", 1.0)) == 0.0, "a world can add a scenery kind of its own")
	fails += _ok(not s.entity("tree").is_empty(), "the shared tree art is still there under the override")
	return fails


static func _test_no_override_is_the_shared_style() -> int:
	var s := ArtStyle.load_style("res://data/art.json", {})
	var fails := 0
	fails += _ok(s.actor_look().is_empty(), "the shared style re-lights nobody (meadow worlds look as before)")
	fails += _ok(s.color("grass").is_equal_approx(Color(0.30, 0.46, 0.28)), "the shared grass colour matches the old hard-coded tufts")
	return fails
