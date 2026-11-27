class_name TestGlyphMap
## Tests for GlyphMap, the pure data of Glyphfall's page: what the ground is in every character cell, and
## the characters, inks and tints of the things standing on it. No nodes and no picture: the tests build a
## small page exactly as GlyphPage does and read cells back.

const CELL := Vector2(8, 12)
const PLACES := { " ": 0, "A": 1, "B": 2, "|": 3, "s": 4, "x": 5 }
const RED := [1.0, 0.0, 0.0]
const GREEN := [0.0, 1.0, 0.0]
const BLUE := [0.0, 0.0, 1.0]
const TREE := { "rows": [" A ", "AAA", " | "], "fg": [0.0, 1.0, 0.0], "map": { "|": [1.0, 0.0, 0.0] }, "fill": [0.0, 0.0, 1.0], "fillmap": { "|": [1.0, 0.0, 0.0] } }
const STUMP := { "rows": ["s"], "fg": [1.0, 0.0, 0.0] }


static func run_all() -> int:
	var fails := 0
	print("TestGlyphMap")
	fails += _test_cells_are_pinned_to_the_world()
	fails += _test_a_pond_is_water_with_a_shore()
	fails += _test_a_path_lies_over_shore_but_not_water()
	fails += _test_a_stamp_sits_on_its_cell_and_spaces_are_gaps()
	fails += _test_inks_and_tints_per_character()
	fails += _test_a_nearer_thing_overlaps_a_farther_one()
	fails += _test_a_felled_tree_shows_its_stump_and_grows_back()
	fails += _test_outside_the_map_is_grass()
	fails += _test_from_spec_builds_the_page()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _map() -> GlyphMap:
	return GlyphMap.new(CELL, Vector2(-400, -300), Vector2(400, 300), PLACES)


static func _test_cells_are_pinned_to_the_world() -> int:
	var m := _map()
	return _ok(m.cell_of(Vector2(0, 0)) == Vector2i(0, 0) and m.cell_of(Vector2(-1, -1)) == Vector2i(-1, -1)
		and m.cell_of(Vector2(15.9, 23.9)) == Vector2i(1, 1) and m.centre_of(Vector2i(1, 1)) == Vector2(12, 18),
		"a cell is 8 x 12 world px, counted from the world's origin")


static func _test_a_pond_is_water_with_a_shore() -> int:
	var m := _map()
	m.paint_pond(Vector2(0, 0), 60.0, 14.0)
	return _ok(m.ground_at(Vector2(0, 0)) == GlyphMap.WATER and m.ground_at(Vector2(50, 0)) == GlyphMap.WATER
		and m.ground_at(Vector2(68, 0)) == GlyphMap.SHORE and m.ground_at(Vector2(100, 0)) == GlyphMap.GRASS,
		"a pond is water, ringed by a band of shore, and then grass")


static func _test_a_path_lies_over_shore_but_not_water() -> int:
	var m := _map()
	m.paint_pond(Vector2(0, 0), 60.0, 14.0)
	m.paint_path(Vector2(-200, 6), Vector2(200, 6), 9.0)
	return _ok(m.ground_at(Vector2(-150, 6)) == GlyphMap.PATH and m.ground_at(Vector2(68, 6)) == GlyphMap.PATH
		and m.ground_at(Vector2(0, 6)) == GlyphMap.WATER and m.ground_at(Vector2(-150, 40)) == GlyphMap.GRASS,
		"a path is written across grass and shore, and stops at the water")


static func _test_a_stamp_sits_on_its_cell_and_spaces_are_gaps() -> int:
	var m := _map()
	m.add_thing(Vector2(100, 100), TREE)
	m.restamp()
	# the tree's own cell holds the bottom row's middle character; the rows rise from there
	var fails := _ok(m.char_at(Vector2(100, 100)) == "|" and m.char_at(Vector2(100, 88)) == "A" and m.char_at(Vector2(100, 76)) == "A",
		"a stamp's bottom row sits on the thing's cell, centred")
	fails += _ok(m.char_at(Vector2(92, 88)) == "A" and m.char_at(Vector2(108, 88)) == "A" and m.char_at(Vector2(92, 76)) == "" and m.char_at(Vector2(92, 100)) == "",
		"a space in a stamp is a gap: nothing is laid there")
	return fails


static func _test_inks_and_tints_per_character() -> int:
	var m := _map()
	m.add_thing(Vector2(100, 100), TREE)
	m.restamp()
	return _ok(m.ink_at(Vector2(100, 88)) == Color(0, 1, 0) and m.ink_at(Vector2(100, 100)) == Color(1, 0, 0)
		and m.fill_at(Vector2(100, 88)) == Color(0, 0, 1) and m.fill_at(Vector2(100, 100)) == Color(1, 0, 0)
		and m.fill_at(Vector2(92, 76)).a == 0.0,
		"a thing has its ink and its tint, and particular characters their own (a trunk under a crown)")


static func _test_a_nearer_thing_overlaps_a_farther_one() -> int:
	var m := _map()
	# registered south first: the order they are added in must not matter
	m.add_thing(Vector2(100, 112), { "rows": ["BBB", "BBB"], "fg": BLUE })
	m.add_thing(Vector2(100, 100), TREE)
	m.restamp()
	return _ok(m.char_at(Vector2(100, 100)) == "B" and m.char_at(Vector2(100, 88)) == "A",
		"things are laid north to south, so the nearer one is in front")


static func _test_a_felled_tree_shows_its_stump_and_grows_back() -> int:
	var m := _map()
	m.add_thing(Vector2(100, 100), TREE, STUMP)
	m.restamp()
	var fails := _ok(m.set_down(Vector2(100, 100), true) and not m.set_down(Vector2(100, 100), true), "felling a tree is a change, once")
	m.restamp()
	fails += _ok(m.char_at(Vector2(100, 100)) == "s" and m.char_at(Vector2(100, 88)) == "", "a felled tree is its stump, and its crown is gone")
	fails += _ok(m.set_down(Vector2(100, 100), false), "growing back is a change too")
	m.restamp()
	fails += _ok(m.char_at(Vector2(100, 88)) == "A", "and it stands again")
	return fails


static func _test_outside_the_map_is_grass() -> int:
	var m := _map()
	m.add_thing(Vector2(5000, 5000), TREE)
	m.restamp()
	return _ok(m.ground_at(Vector2(5000, 5000)) == GlyphMap.GRASS and m.char_at(Vector2(5000, 5000)) == "",
		"beyond the page there is only grass, and a thing out there is harmless")


static func _test_from_spec_builds_the_page() -> int:
	var data := {
		"bounds": { "min": [-400, -300], "max": [400, 300] },
		"ponds": [{ "center": [-200, 0], "radius": 50 }],
		"paths": [{ "from": [0, 150], "to": [300, 150] }],
		"trees": [[100, 100], [200, 100, "pine"]],
		"landmarks": [{ "type": "great_tree", "position": [0, -100] }],
		"props": [{ "type": "bench", "position": [300, 0], "color": [1.0, 0.0, 0.0] }, { "type": "unknown_thing", "position": [300, 60] }],
		"portals": [{ "position": [-300, 200] }],
	}
	var cfg := { "cell": [8, 12], "stamps": {
		"tree": TREE, "pine": { "rows": ["B"], "fg": GREEN }, "great_tree": { "rows": ["AA"], "fg": GREEN }, "stump": STUMP,
		"bench": { "rows": ["x"], "fg": GREEN, "use_color": true }, "portal": { "rows": ["B"], "fg": BLUE } } }
	var m := GlyphMap.from_spec(data, cfg, PLACES)
	var fails := _ok(m.ground_at(Vector2(-200, 0)) == GlyphMap.WATER and m.ground_at(Vector2(150, 150)) == GlyphMap.PATH, "the spec's ponds and paths are on the page")
	fails += _ok(m.char_at(Vector2(100, 88)) == "A" and m.char_at(Vector2(200, 100)) == "B" and m.char_at(Vector2(0, -100)) == "A",
		"trees are stamped by their kind, and landmarks by their type")
	fails += _ok(m.char_at(Vector2(300, 0)) == "x" and m.ink_at(Vector2(300, 0)) == Color(1, 0, 0), "a prop that asks for it is inked in its own colour")
	fails += _ok(m.char_at(Vector2(300, 60)) == "" and m.char_at(Vector2(-300, 200)) == "B" and m.thing_count() == 5, "a thing with no stamp is not drawn; the portal is")
	return fails
