class_name TestWorldPortals
## Pins the shape of the doorways across every world fixture (each is an exact copy of a server seed):
## the Vale is the hub, and its only doorway is the big Gateway (no small direct portals); every other
## world has a small portal home standing close to where you arrive, and every portal home leads to
## the Vale's Gateway. "Close" means near enough to see on arrival, but far enough that you don't
## start inside its trigger (world_controller arms a portal once you're 22 + 18 px clear of it).

const FIXTURES := ["riverbank", "bazaar", "maze", "ruin", "nocthollow", "bobbledown", "clickton", "drifthallow", "dozewood", "steamhollow", "hollowsong", "underroot", "lanternfold", "stillglass", "home"]
const ARM_CLEAR := 40.0  # world_controller's PORTAL_RANGE + PORTAL_ARM_BUFFER
const NEAR := 120.0      # how close to the arrival spot the way home must stand
const VALE_ID := "11111111-1111-1111-1111-111111111111"
const HUB_GATEWAY_ID := "vale_gateway"


static func run_all() -> int:
	var fails := 0
	print("TestWorldPortals")
	fails += _test_vale_has_only_the_gateway()
	for name in FIXTURES:
		fails += _test_way_home_by_the_arrival(name)
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _load(name: String) -> Dictionary:
	return WorldData.load_json("res://tests/world_fixtures/%s.json" % name)


static func _test_vale_has_only_the_gateway() -> int:
	var d := _load("vale")
	var fails := 0
	fails += _ok(String(d.get("gateway", {}).get("id", "")) == HUB_GATEWAY_ID, "the Vale has its Gateway")
	fails += _ok((d.get("portals", []) as Array).is_empty(), "the Gateway is the Vale's only doorway")
	return fails


static func _test_way_home_by_the_arrival(name: String) -> int:
	var d := _load(name)
	var spawn := WorldData.to_vec2(d["player_spawn"])
	var fails := 0
	var nearest := INF
	for p in d.get("portals", []):
		fails += _ok(String(p["target_world"]) == VALE_ID and String(p["target_portal"]) == HUB_GATEWAY_ID,
			"%s: %s leads to the Vale's Gateway" % [name, p["id"]])
		nearest = minf(nearest, spawn.distance_to(WorldData.to_vec2(p["position"])))
	fails += _ok(nearest <= NEAR, "%s: a portal home stands by the arrival spot (%.0f px)" % [name, nearest])
	fails += _ok(nearest > ARM_CLEAR, "%s: …but you don't arrive inside its trigger" % name)
	return fails
