class_name WorldData
## Loads the companion + world JSON definitions into plain dictionaries. This is
## the world layer's one touch of the filesystem, kept separate from the behavior
## logic (companion_brain) so that logic stays pure and portable. Vectors are
## returned as plain Arrays here; presentation converts them to Vector2 as needed.

static func load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "Missing data file: %s" % path)
	var text: String = FileAccess.get_file_as_string(path)
	assert(text != "", "Could not read data file (empty or unreadable): %s" % path)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "Data file is not a JSON object: %s" % path)
	return parsed


## Helper: turn a [x, y] JSON array into a Vector2.
static func to_vec2(arr: Array) -> Vector2:
	return Vector2(float(arr[0]), float(arr[1]))


## Helper: turn an [r, g, b] (optionally [r,g,b,a]) JSON array into a Color.
static func to_color(arr: Array) -> Color:
	var a := 1.0 if arr.size() < 4 else float(arr[3])
	return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
