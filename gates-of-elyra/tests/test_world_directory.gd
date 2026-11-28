class_name TestWorldDirectory
## Tests for WorldDirectory — the Gateway's search state. Pure (requests out, answers in), so it's
## driven directly with hand-made server answers. The points being pinned: only the LATEST search's
## answer is ever kept (typing fast can't flash stale results), pages append in order, featured worlds
## shelve above the rest only when browsing (not searching), and junk cards from the wire are dropped.

static func run_all() -> int:
	var fails := 0
	print("TestWorldDirectory")
	fails += _test_fresh_search_adopts_its_answer()
	fails += _test_stale_answer_is_ignored()
	fails += _test_pages_append_in_order()
	fails += _test_no_more_page_when_server_says_so()
	fails += _test_browsing_shelves_featured_first()
	fails += _test_search_is_one_flat_shelf()
	fails += _test_status_text()
	fails += _test_junk_cards_are_dropped()
	fails += _test_presence_text()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _card(id: String, name: String, featured := false, players := 0) -> Dictionary:
	return { "world_id": id, "name": name, "blurb": "", "tags": [], "featured": featured, "players": players }


static func _names(worlds: Array) -> Array:
	return worlds.map(func(w: Dictionary) -> String: return String(w["name"]))


static func _test_fresh_search_adopts_its_answer() -> int:
	var d := WorldDirectory.new()
	var req := d.begin_search("  river ")
	var fails := _ok(d.is_loading() and d.query() == "river", "a search trims its query and starts loading")
	var took := d.accept(req, 0, [_card("a", "Riverbank")], false)
	fails += _ok(took and not d.is_loading() and _names(d.worlds()) == ["Riverbank"], "its answer is adopted")
	return fails


static func _test_stale_answer_is_ignored() -> int:
	var d := WorldDirectory.new()
	var old := d.begin_search("riv")
	var latest := d.begin_search("rive")
	var fails := _ok(not d.accept(old, 0, [_card("x", "Stale")], false), "an answer to a replaced search is refused")
	fails += _ok(d.worlds().is_empty() and d.is_loading(), "…and leaves the latest search still waiting")
	fails += _ok(d.accept(latest, 0, [_card("a", "Riverbank")], false), "the latest search's answer lands")
	fails += _ok(not d.accept(latest, 0, [_card("a", "Riverbank")], false), "a duplicate answer is refused")
	return fails


static func _test_pages_append_in_order() -> int:
	var d := WorldDirectory.new()
	d.accept(d.begin_search(""), 0, [_card("a", "A"), _card("b", "B")], true)
	var fails := _ok(d.has_more() and d.next_offset() == 2, "a page with more to come reports the next offset")
	var req := d.begin_more()
	fails += _ok(d.begin_more() == -1, "a second 'more' while one is in flight is refused")
	fails += _ok(not d.accept(req, 0, [_card("z", "Wrong offset")], false), "a page at the wrong offset is refused")
	fails += _ok(d.accept(req, 2, [_card("c", "C")], false), "the next page lands at its offset")
	fails += _ok(_names(d.worlds()) == ["A", "B", "C"] and not d.has_more(), "pages append in order")
	return fails


static func _test_no_more_page_when_server_says_so() -> int:
	var d := WorldDirectory.new()
	d.accept(d.begin_search(""), 0, [_card("a", "A")], false)
	return _ok(d.begin_more() == -1, "no 'more' request once the server says it's the last page")


static func _test_browsing_shelves_featured_first() -> int:
	var d := WorldDirectory.new()
	d.accept(d.begin_search(""), 0, [_card("r", "Ruin", true), _card("b", "Bazaar"), _card("m", "Maze")], false)
	var s := d.sections()
	var fails := _ok(s.size() == 2 and s[0]["title"] == "Featured" and s[1]["title"] == "All worlds", "browsing shows Featured, then All worlds")
	fails += _ok(_names(s[0]["worlds"]) == ["Ruin"] and _names(s[1]["worlds"]) == ["Bazaar", "Maze"], "each world sits on exactly one shelf")
	d.accept(d.begin_search(""), 0, [_card("b", "Bazaar")], false)
	fails += _ok(d.sections().size() == 1 and d.sections()[0]["title"] == "All worlds", "an empty Featured shelf is left out")
	return fails


static func _test_search_is_one_flat_shelf() -> int:
	var d := WorldDirectory.new()
	d.accept(d.begin_search("r"), 0, [_card("r", "Ruin", true), _card("v", "Riverbank")], false)
	var s := d.sections()
	return _ok(s.size() == 1 and s[0]["title"] == "Matches" and _names(s[0]["worlds"]) == ["Ruin", "Riverbank"], "a search is one Matches shelf in server order")


static func _test_status_text() -> int:
	var d := WorldDirectory.new()
	var req := d.begin_search("")
	var fails := _ok(d.status_text() == "Looking for worlds…", "loading reads as looking")
	d.accept(req, 0, [], false)
	fails += _ok(d.status_text() == "No other worlds to visit yet.", "an empty catalog says so")
	d.accept(d.begin_search("zzz"), 0, [], false)
	fails += _ok(d.status_text() == "No worlds match \"zzz\".", "an empty search names the query")
	d.accept(d.begin_search(""), 0, [_card("a", "A")], false)
	fails += _ok(d.status_text() == "", "no status line while there are cards")
	return fails


static func _test_junk_cards_are_dropped() -> int:
	var d := WorldDirectory.new()
	d.accept(d.begin_search(""), 0, [
		"not a card",
		{ "name": "No id" },
		{ "world_id": 42, "name": "Numeric id" },
		{ "world_id": "ok", "players": "lots", "accent": [1, 0], "featured": "yes" },
	], false)
	var w := d.worlds()
	var fails := _ok(w.size() == 1 and w[0]["world_id"] == "ok", "cards without a usable world id are dropped")
	fails += _ok(w[0]["name"] == "An unnamed world" and w[0]["players"] == 0, "missing name / bad count get safe defaults")
	fails += _ok(w[0]["accent"] == [] and w[0]["featured"] == false, "a short accent and a non-bool featured are ignored")
	return fails


static func _test_presence_text() -> int:
	var fails := _ok(WorldDirectory.presence_text(0) == "quiet", "nobody there reads 'quiet'")
	fails += _ok(WorldDirectory.presence_text(3) == "3 here", "a crowd reads 'N here'")
	return fails
