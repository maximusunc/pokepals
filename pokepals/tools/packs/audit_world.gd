extends SceneTree
## Build ONE world headless so `godot --verbose` logs every resource it loads ("Loading resource: ...").
## tools/packs/build_packs.py runs this once per world and reads those log lines to learn which art
## each world really uses. The world is built exactly as the smoke tests build it (server-less, from
## its spec JSON), so what's logged is what a player standing in it would load.
##
##   godot --headless --verbose --path pokepals --script res://tools/packs/audit_world.gd -- <spec.json> <world_id> [http://host:port/ | pack.pck ...]
##
## Extra arguments say how to get the world's packs, for the build's second pass over the EXPORTED
## base (which doesn't contain them): a `http://...` argument runs the real client path, AssetPacks.prepare(),
## against a local server (ask which packs, download, verify, mount); any other argument is a .pck to mount
## directly. The build checks the packed run loads exactly the same art as the source project did: if a
## pack were missing something, the renderers would silently fall back to a plainer look, and this is
## the check that would notice.
##
## Presentation-only tooling; nothing in the game runs this.

const FRAMES := 40

var _world: Node
var _frames := 0
var _started := false
var _ready_to_build := false
var _failed := false


func _process(_delta: float) -> bool:
	if _failed:
		return true
	if not _started:
		_started = true
		_prepare()
		return false
	if not _ready_to_build:
		return false
	_frames += 1
	if _world == null:
		var args := OS.get_cmdline_user_args()
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(args[1], WorldData.load_json(args[0]))
		router.current_world = args[1]
		router.arrival_portal_id = ""
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", args[1])
		return false
	if _frames < FRAMES:
		return false
	print("AUDIT_DONE")
	return true


func _prepare() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: audit_world.gd -- <spec.json> <world_id> [http://host:port/ | pack.pck ...]")
		_failed = true
		return
	for extra in args.slice(2):
		if extra.begins_with("http"):
			var packs := root.get_node("/root/AssetPacks")
			packs.enabled = true
			packs.base_url_override = extra
			if not await packs.prepare(args[1]):
				push_error("AssetPacks.prepare failed for %s" % args[1])
				print("PACKS_FAILED")
				_failed = true
				return
			print("PACKS_OK")
		elif not ProjectSettings.load_resource_pack(extra, false):
			push_error("cannot mount %s" % extra)
			_failed = true
			return
	_ready_to_build = true
