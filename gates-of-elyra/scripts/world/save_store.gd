extends Node
## Local persistence for player-side save data, written to user:// — the per-user
## writable location Godot provides on every platform (desktop, mobile, web). This
## is the single side-effecting IO boundary for saves: the world logic stays pure
## and just hands it plain dictionaries to read and write.
##
## Registered as the "SaveStore" autoload (see project.godot), so it's reachable
## from anywhere as SaveStore.load_json(...). It deliberately has no class_name, to
## avoid clashing with the autoload singleton of the same name.

## Load a JSON object from user://. Returns {} if the file is missing, empty, or
## not a JSON object — callers then fall back to defaults.
func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## Write a JSON object to user://. Returns true on success.
func save_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveStore: could not open %s for writing" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func has_save(path: String) -> bool:
	return FileAccess.file_exists(path)


func delete_save(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
