class_name TestPackLogic
## Tests for PackLogic (the pure parts of AssetPacks): turning the socket URL into the server's HTTP
## address, and deciding which of a world's packs still have to be fetched. (The download itself is exercised end to end by
## tools/packs/build_packs.py's verify step, which runs the real client against a local server.)

static func run_all() -> int:
	var fails := 0
	print("TestPackLogic")
	fails += _test_http_base_from_socket_url()
	fails += _test_missing_packs_are_those_whose_probe_is_absent()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _test_http_base_from_socket_url() -> int:
	var fails := 0
	fails += _ok(PackLogic.http_base("wss://play.example.com/ws") == "https://play.example.com/", "wss://host/ws -> https://host/")
	fails += _ok(PackLogic.http_base("ws://192.168.86.38:4000/ws") == "http://192.168.86.38:4000/", "ws://ip:port/ws keeps the port, drops the mount")
	fails += _ok(PackLogic.http_base("ws://localhost:4000") == "http://localhost:4000/", "no path at all still gets a trailing slash")
	fails += _ok(PackLogic.http_base("  wss://a.b/ws/websocket  ") == "https://a.b/", "stray spaces and a deeper path are dropped")
	return fails


static func _test_missing_packs_are_those_whose_probe_is_absent() -> int:
	var fails := 0
	var here := { "id": "here", "probe": "res://assets/fonts/SpaceGrotesk.ttf" }
	var gone := { "id": "gone", "probe": "res://assets/this_file_does_not_exist.png" }
	var blank := { "id": "blank" }
	var need := PackLogic.missing([here, gone, blank])
	fails += _ok(need.size() == 2, "a pack whose probe file exists is not missing (%d missing)" % need.size())
	fails += _ok(need[0]["id"] == "gone", "an absent probe is missing")
	fails += _ok(need[1]["id"] == "blank", "a descriptor with no probe counts as missing, never as present")
	fails += _ok(PackLogic.missing([]).is_empty(), "no packs, nothing missing")
	return fails
