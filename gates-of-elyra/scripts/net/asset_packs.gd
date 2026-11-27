extends Node
## World PACKS: the art that only one world (or a few) needs, downloaded the first time the player goes
## there instead of shipping in the game's first download.
##
## The web build keeps only what every player needs in its base .pck (the Vale, homes, the wardrobe, the
## companion, the UI); each other world's own art is a separate .pck on the server (tools/packs builds
## them; Server.Packs describes them). Before the client JOINS a world it calls prepare(): ask the server
## which packs that world needs, fetch the ones it doesn't have, check them, and mount them into res://.
## From then on `load("res://assets/...")` finds the world's art exactly as if it had always been there,
## so none of the drawing code knows packs exist.
##
## Why before the join and not after: once we're in the world's channel the server starts talking
## (roster, state, ...) and the world's directors must already exist to hear it. So the world isn't
## joined, or built, until its art is here.
##
## A pack's file name carries a hash of its content, so a cached copy is valid forever: we keep
## downloaded packs in user:// (on the web that is the browser's own storage), and a returning player
## downloads nothing. A new build of a world's art is simply a new file name.
##
## Only the WEB build is split; it is the one that has to be small. Editor runs and the native
## exports bundle everything in res://, so every pack's probe file already exists and nothing is
## fetched (`enabled` is false there and prepare() returns at once). The editor keeps working with no
## server and no build.
##
## Registered as an autoload (singleton) named AssetPacks, so a download survives the scene reload a
## world hop does. It processes while the tree is paused (the connection gate pauses it).

## A download is about to start: how many bytes, and the world's display name.
signal download_started(world_name: String, total_bytes: int)
## Bytes received so far of `total_bytes`.
signal download_progress(done_bytes: int, total_bytes: int)

## Where fetched packs live.
const CACHE_DIR := "user://packs"
## Per-request ceiling, in seconds, so a dead connection fails instead of hanging the loading screen.
const REQUEST_TIMEOUT := 60.0
## How many times a failed download is tried before giving up.
const ATTEMPTS := 2

## Whether this build fetches packs at all. Only the web export is split (see above).
var enabled := OS.has_feature("web")
## Tests point this at a local server ("http://127.0.0.1:8123/"); empty = derive from the server URL.
var base_url_override := ""

# world_id -> { "name": String, "packs": Array of descriptors }. Per session: a world's packs are asked
# for once, so travelling back and forth costs no further round trips.
var _worlds: Dictionary = {}
# pack id -> true, for packs this session mounted from a file (so we never mount one twice).
var _mounted: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Whether this world can be entered right now with no waiting: nothing to fetch (packs off, a home, or
## we've already learned it needs none / has them all).
func is_world_ready(world_id: String) -> bool:
	if not enabled or _is_home(world_id):
		return true
	return _worlds.has(world_id) and PackLogic.missing(_worlds[world_id]["packs"]).is_empty()


## Make sure everything `world_id` needs is mounted, downloading what isn't. Returns true when the world
## can be built with all its art (or when it needs none), false if a download failed, in which case the
## caller may still go in: the renderers fall back to a plainer look rather than break.
##
## A coroutine: `await AssetPacks.prepare(id)`. When nothing has to be fetched it finishes without
## yielding, so callers pay nothing for a world that is already ready.
func prepare(world_id: String) -> bool:
	if not enabled or _is_home(world_id):
		return true
	if not _worlds.has(world_id):
		var fetched: Variant = await _fetch_world_packs(world_id)
		if fetched == null:
			# The server couldn't tell us (offline, or an older server without the route): carry on with
			# the base. The socket will fail loudly on its own if the server really is down.
			push_warning("AssetPacks: couldn't ask which packs %s needs; entering with the base art" % world_id)
			return true
		_worlds[world_id] = fetched
	var info: Dictionary = _worlds[world_id]
	var need := PackLogic.missing(info["packs"])
	if need.is_empty():
		return true

	var total := 0
	for pack in need:
		total += int(pack["bytes"])
	download_started.emit(String(info["name"]), total)
	var done_before := 0
	for pack in need:
		var ok := false
		for attempt in ATTEMPTS:
			ok = await _install(pack, done_before, total)
			if ok:
				break
		if not ok:
			push_warning("AssetPacks: couldn't get pack '%s' for %s" % [pack["id"], world_id])
			return false
		done_before += int(pack["bytes"])
		download_progress.emit(done_before, total)
	return true


func _is_home(world_id: String) -> bool:
	return world_id.begins_with(WorldRouter.HOME_PREFIX)


func _base() -> String:
	return base_url_override if base_url_override != "" else PackLogic.http_base(Net.default_server_url())


## Ask the server which packs a world needs: { "name", "packs" }, or null if it can't be reached/read.
func _fetch_world_packs(world_id: String) -> Variant:
	var body: PackedByteArray = await _http_get(_base() + "worlds/" + world_id.uri_encode() + "/packs")
	if body.is_empty():
		return null
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("packs") is Array):
		return null
	return { "name": String((parsed as Dictionary).get("name", "")), "packs": (parsed as Dictionary)["packs"] }


## Get one pack onto disk (from the cache, or by downloading), verified, and mounted.
func _install(pack: Dictionary, done_before: int, total: int) -> bool:
	var id := String(pack["id"])
	var file_name := String(pack["url"]).get_file()
	var path := CACHE_DIR + "/" + file_name
	if not (FileAccess.file_exists(path) and FileAccess.get_sha256(path) == String(pack["sha256"])):
		var body: PackedByteArray = await _http_get(_base() + String(pack["url"]), func(received: int) -> void:
			download_progress.emit(done_before + mini(received, int(pack["bytes"])), total))
		if body.size() != int(pack["bytes"]) or _sha256(body) != String(pack["sha256"]):
			return false  # truncated or corrupted: don't keep it
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
		_forget_old_versions(id, file_name)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return false
		f.store_buffer(body)
		f.close()
	if not _mount(path, id):
		DirAccess.remove_absolute(path)  # a bad cached copy would fail forever; drop it so we refetch
		return false
	return ResourceLoader.exists(String(pack["probe"]))


func _mount(path: String, id: String) -> bool:
	if _mounted.has(path):
		return true
	# replace_files = false: should a file exist twice, the one already in the game wins.
	if not ProjectSettings.load_resource_pack(path, false):
		return false
	_mounted[path] = true
	return true


## Packs are named "<id>.<hash>.pck"; once a new build of <id> is stored, older copies are dead weight.
func _forget_old_versions(id: String, keep: String) -> void:
	var dir := DirAccess.open(CACHE_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f != keep and f.begins_with(id + ".") and f.ends_with(".pck"):
			dir.remove(f)


static func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## GET `url`; the body, or an empty array on any failure. `on_progress(received_bytes)` is called each
## frame while it downloads. The browser (web) or the engine (native) undoes gzip transfer encoding.
func _http_get(url: String, on_progress: Callable = Callable()) -> PackedByteArray:
	var req := HTTPRequest.new()
	req.timeout = REQUEST_TIMEOUT
	# In a browser the fetch API has ALREADY undone a gzip transfer encoding by the time Godot sees the
	# body; if Godot then tried to gunzip it again the request would fail (RESULT_BODY_DECOMPRESS_FAILED).
	# So on the web the browser alone negotiates and decodes gzip; elsewhere the engine does.
	req.accept_gzip = not OS.has_feature("web")
	add_child(req)
	var state := { "done": false, "ok": false, "body": PackedByteArray() }
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		state["ok"] = result == HTTPRequest.RESULT_SUCCESS and code == 200
		state["body"] = body
		state["done"] = true)
	if req.request(url) != OK:
		req.queue_free()
		return PackedByteArray()
	while not state["done"]:
		await get_tree().process_frame
		if on_progress.is_valid():
			on_progress.call(req.get_downloaded_bytes())
	req.queue_free()
	return state["body"] if state["ok"] else PackedByteArray()
