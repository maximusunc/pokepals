class_name DataLoader
## Loads the static game definitions (types, moves, creatures) from JSON into
## plain dictionaries, and validates them. This is the ONLY file in scripts/battle
## allowed to touch the filesystem — it is deliberately separate from
## BattleLogic.resolve_turn, which stays IO-free and takes already-loaded defs.
## On a future server this is the part you swap (DB/file read); the resolve logic
## ports unchanged.

const _CREATURE_FIELDS := ["name", "type", "max_hp", "atk", "def", "spd", "moves"]
const _MOVE_FIELDS := ["name", "type", "power", "accuracy"]


## Load everything. Returns { "types": {...}, "moves": {...}, "creatures": {...} }
## where the inner dicts are keyed by id (moves/creatures) or are the raw type data.
static func load_all(base_path: String = "res://data/") -> Dictionary:
	var types: Dictionary = _load_json(base_path.path_join("types.json"))
	var moves_file: Dictionary = _load_json(base_path.path_join("moves.json"))
	var creatures_file: Dictionary = _load_json(base_path.path_join("creatures.json"))

	var defs := {
		"types": types,
		"moves": moves_file.get("moves", {}),
		"creatures": creatures_file.get("creatures", {}),
	}
	_validate(defs)
	return defs


static func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "Missing data file: %s" % path)
	var text: String = FileAccess.get_file_as_string(path)
	assert(text != "", "Could not read data file (empty or unreadable): %s" % path)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "Data file is not a JSON object: %s" % path)
	return parsed


## Fail loud on malformed data so a typo in JSON is caught at load, not mid-battle.
static func _validate(defs: Dictionary) -> void:
	var types: Dictionary = defs["types"]
	assert(types.has("chart"), "types.json must contain a 'chart' object")
	var valid_types: Array = types.get("types", [])
	assert(valid_types.size() >= 3, "Expected at least 3 types in types.json")

	var moves: Dictionary = defs["moves"]
	assert(moves.size() > 0, "No moves defined in moves.json")
	for move_id in moves:
		var move: Dictionary = moves[move_id]
		for field in _MOVE_FIELDS:
			assert(move.has(field), "Move '%s' is missing required field '%s'" % [move_id, field])
		assert(valid_types.has(move["type"]), "Move '%s' has unknown type '%s'" % [move_id, move["type"]])

	var creatures: Dictionary = defs["creatures"]
	assert(creatures.size() > 0, "No creatures defined in creatures.json")
	for creature_id in creatures:
		var creature: Dictionary = creatures[creature_id]
		for field in _CREATURE_FIELDS:
			assert(creature.has(field), "Creature '%s' is missing required field '%s'" % [creature_id, field])
		assert(valid_types.has(creature["type"]), "Creature '%s' has unknown type '%s'" % [creature_id, creature["type"]])
		for move_id in creature["moves"]:
			assert(moves.has(move_id), "Creature '%s' references unknown move '%s'" % [creature_id, move_id])
