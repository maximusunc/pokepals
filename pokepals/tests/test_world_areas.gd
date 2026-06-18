class_name TestWorldAreas
## Tests for the pure area resolver: world position -> "world_id:region_id" (or "world_id").

static func run_all() -> int:
	var fails := 0
	print("TestWorldAreas")
	fails += _test_resolves_region()
	fails += _test_outside_regions_is_world_default()
	fails += _test_no_world_id_is_empty()
	fails += _test_first_match_wins()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _regions() -> Array:
	return [
		{ "id": "clearing", "min": Vector2(0, 0), "max": Vector2(100, 100) },
		{ "id": "grove", "min": Vector2(100, 0), "max": Vector2(200, 100) },
	]


static func _test_resolves_region() -> int:
	return _ok(WorldAreas.resolve(Vector2(50, 50), "vale", _regions()) == "vale:clearing", "a position inside a region resolves to world:region")


static func _test_outside_regions_is_world_default() -> int:
	return _ok(WorldAreas.resolve(Vector2(500, 500), "vale", _regions()) == "vale", "a position in no region resolves to the world default area")


static func _test_no_world_id_is_empty() -> int:
	return _ok(WorldAreas.resolve(Vector2(50, 50), "", _regions()) == "", "with no world id there are no areas (empty string)")


static func _test_first_match_wins() -> int:
	# x == 100 sits on the shared edge of both regions; the earlier-listed one wins.
	return _ok(WorldAreas.resolve(Vector2(100, 50), "vale", _regions()) == "vale:clearing", "overlapping regions resolve to the first match")
