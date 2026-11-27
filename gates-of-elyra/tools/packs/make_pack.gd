extends SceneTree
## Write ONE world pack: a .pck holding only the given assets, in exactly the form an exported game
## stores them (the asset's `.import` record + the compiled file it points at under .godot/imported/),
## so mounting it makes `load("res://assets/...")` just work. Used by tools/packs/build_packs.py, on a
## scratch copy of the project that has already been imported.
##
## Why not Godot's own `--export-pack`? It also stores the autoload scripts, project settings and
## splash image in every pack (~77 KB of dead weight each); with a pack per world that adds up.
##
##   godot --headless --path <project> --script res://tools/packs/make_pack.gd -- <out.pck> <list.txt>
##
## <list.txt> holds one res:// path per line. Exits with a non-zero code on any problem.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: make_pack.gd -- <out.pck> <list.txt>")
		quit(2)
		return
	var packer := PCKPacker.new()
	if packer.pck_start(args[0]) != OK:
		push_error("cannot start %s" % args[0])
		quit(1)
		return
	var count := 0
	for line in FileAccess.get_file_as_string(args[1]).split("\n", false):
		var res_path := line.strip_edges()
		if res_path == "":
			continue
		var files := _files_for(res_path)
		if files.is_empty():
			push_error("nothing to pack for %s" % res_path)
			quit(1)
			return
		for f in files:
			if packer.add_file(f, f) != OK:  # the scratch project is the cwd, so res:// resolves
				push_error("cannot add %s" % f)
				quit(1)
				return
			count += 1
	if packer.flush() != OK:
		push_error("flush failed")
		quit(1)
		return
	print("PACKED %d files -> %s" % [count, args[0]])
	quit(0)


## Everything the engine needs to load `res_path`: for an imported asset, its `.import` record and the
## compiled file(s) that record points at; for a plain file, itself.
func _files_for(res_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var import_path := res_path + ".import"
	if not FileAccess.file_exists(import_path):
		if FileAccess.file_exists(res_path):
			out.append(res_path)
		return out
	out.append(import_path)
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return PackedStringArray()
	for dest in cfg.get_value("deps", "dest_files", PackedStringArray()):
		out.append(String(dest))
	return out
