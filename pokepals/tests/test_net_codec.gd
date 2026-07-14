class_name TestNetCodec
## Tests for the Net seam's wire codec — the Vector2 ⇄ [x, y] marshalling that lets live transform
## state survive a JSON round-trip while the dict contract handed up to the world stays
## Vector2-valued. Pure static functions in net.gd, so these run headless with no socket and no
## autoload, and they double as documentation of the 'state' frame shape (p, pf, c, cl).

const NetScript := preload("res://scripts/net/net.gd")


static func run_all() -> int:
	var fails := 0
	print("TestNetCodec")
	fails += _test_encode_vectors_to_arrays()
	fails += _test_encode_passes_through_non_vectors()
	fails += _test_decode_arrays_to_vectors()
	fails += _test_round_trip_preserves_transforms()
	fails += _test_decode_leaves_non_pair_arrays_alone()
	fails += _test_decode_ambient_carries_pos_and_form()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


# The real state payload the world broadcasts: player + companion position and facing.
static func _sample_state() -> Dictionary:
	return {
		"p": Vector2(12.5, -3.0),
		"pf": Vector2(1, 0),
		"c": Vector2(40.0, 8.25),
		"cl": Vector2(-1, 0),
	}


static func _test_encode_vectors_to_arrays() -> int:
	var enc: Dictionary = NetScript._encode_state(_sample_state())
	var fails := 0
	fails += _ok(enc["p"] is Array and enc["p"][0] == 12.5 and enc["p"][1] == -3.0, "a Vector2 encodes to a 2-element [x, y] array")
	fails += _ok(enc["cl"] is Array and enc["cl"][0] == -1, "every Vector2 field is encoded, not just the first")
	return fails


static func _test_encode_passes_through_non_vectors() -> int:
	# The envelope fields net.gd adds ("t") and anything else non-Vector2 must survive untouched —
	# JSON.stringify needs them as-is.
	var enc: Dictionary = NetScript._encode_state({ "t": "state", "p": Vector2(1, 2), "n": 7 })
	var fails := 0
	fails += _ok(String(enc.get("t", "")) == "state", "a string field passes through encode untouched")
	fails += _ok(int(enc.get("n", 0)) == 7, "a number field passes through encode untouched")
	return fails


static func _test_decode_arrays_to_vectors() -> int:
	# What arrives off the wire after JSON.parse_string: arrays, with an "id"/"t" envelope.
	var wire := { "id": 3, "p": [12.5, -3.0], "pf": [1, 0] }
	var dec: Dictionary = NetScript._decode_state(wire)
	var fails := 0
	fails += _ok(dec["p"] is Vector2 and (dec["p"] as Vector2).is_equal_approx(Vector2(12.5, -3.0)), "a 2-number array decodes back to a Vector2")
	fails += _ok(dec["pf"] is Vector2, "an integer-valued pair also decodes to a Vector2")
	fails += _ok(int(dec.get("id", 0)) == 3, "a non-array envelope field is left alone by decode")
	return fails


static func _test_round_trip_preserves_transforms() -> int:
	# encode → JSON text → parse → decode must reproduce the original Vector2s. This is the whole
	# contract: state goes out as JSON and comes back rendering-ready.
	var original := _sample_state()
	var text := JSON.stringify(NetScript._encode_state(original))
	var parsed: Variant = JSON.parse_string(text)
	var fails := 0
	if not (parsed is Dictionary):
		return _ok(false, "the encoded state is valid JSON that parses to a Dictionary")
	var back: Dictionary = NetScript._decode_state(parsed)
	for key in original:
		var v: Vector2 = original[key]
		fails += _ok(back.get(key) is Vector2 and (back[key] as Vector2).is_equal_approx(v), "%s survives the JSON round-trip as a Vector2" % key)
	return fails


static func _test_decode_leaves_non_pair_arrays_alone() -> int:
	# Only 2-number arrays are coordinates. A 3-element array, or a pair of strings, must NOT be
	# coerced into a Vector2 — guards future non-coordinate array fields on the same frame.
	var dec: Dictionary = NetScript._decode_state({ "trio": [1, 2, 3], "words": ["a", "b"] })
	var fails := 0
	fails += _ok(dec["trio"] is Array and (dec["trio"] as Array).size() == 3, "a 3-element array is not mistaken for a Vector2")
	fails += _ok(dec["words"] is Array, "a 2-element non-number array is left as an array")
	return fails


static func _test_decode_ambient_carries_pos_and_form() -> int:
	# The ambient-pal batch: id + position + facing, plus the pal's current animal form (s/v), which the
	# server can shift over time. A blank/absent species means a formless pal; malformed entries drop.
	var wire := [
		{ "id": "pal_1", "p": [10.0, 20.0], "l": [1, 0], "s": "fox", "v": 2 },
		{ "id": "pal_2", "p": [0, 0], "l": [0, 1] },          # no form → formless
		{ "p": [5, 5], "l": [0, 1] },                          # no id → dropped
	]
	var dec: Array = NetScript._decode_ambient(wire)
	var fails := 0
	fails += _ok(dec.size() == 2, "the id-less entry is dropped, the rest survive")
	fails += _ok((dec[0]["pos"] as Vector2).is_equal_approx(Vector2(10.0, 20.0)), "pal position decodes to a Vector2")
	fails += _ok(String(dec[0]["species"]) == "fox" and int(dec[0]["variant"]) == 2, "the pal's form (species + coat) decodes")
	fails += _ok(String(dec[1]["species"]) == "" and int(dec[1]["variant"]) == 0, "a pal with no form decodes as formless")
	return fails
