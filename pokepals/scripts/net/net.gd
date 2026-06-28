extends Node
## Net — the transport-agnostic SYNC SEAM (the "pipe"), registered as an autoload.
##
## This is the one place that touches networking. Everything above it (the world, the avatars)
## talks to Net in plain dictionaries and never sees the socket, the wire protocol, or peer ids
## beyond an opaque string. The TRANSPORT is a WebSocket to an AUTHORITATIVE Elixir/Phoenix server,
## over **Phoenix Channels** (the Phoenix v2 serializer).
##
## MULTI-WORLD: there is ONE socket per client (authenticated once, at connect, by the identity
## token), but the player is in ONE WORLD AT A TIME, and each world is its own Phoenix channel topic
## "world:<world_id>". Net joins the world the player is in and re-joins (leave + join) when they
## travel. Presence (who's here) and live transforms are scoped to that world's channel by the
## server, so players in different worlds don't see each other.
##
## WORLD SPECS come from the SERVER — the client bundles NO world specs. On joining a world, the
## server sends that world's spec (display-agnostic core + presentation profiles), which Net caches
## by a content ETAG (in memory AND on disk, under user://world_cache). The client sends the etag it
## already has (known_etag) so an unchanged spec isn't re-sent; because the etag is derived from the
## spec's content, ANY back-end edit to a world invalidates the cache on its own — no version to bump,
## no new client build to ship for a world change. This is also what lets the catalog grow to many
## worlds without baking any of them into the client.
##
## What crosses the wire, as Phoenix channel events on the current "world:<world_id>" topic:
##   • PRESENTATION (relayed to peers in the same world):
##       - identity (on join / change): appearance + companion resting-look.
##       - state (~20 Hz): live transforms of your player+companion (Vector2s marshalled to [x,y]).
##   • WORLD SPEC (server -> us, on join): world_spec / world_spec_unchanged.
##   • PERSISTENCE (point-to-point with the server; per-USER, same in every world):
##       - load (server -> us, on join): our canonical companion + wardrobe (or nulls for a new player).
##       - save (us -> server): the canonical write.
##
## TRUST MODEL: the SERVER stamps the sender id (the player's user_id) onto every relayed frame —
## clients never send their own id, so a peer can't impersonate another. Incoming presentation
## payloads are untrusted input the world clamps/validates. The token is a bearer credential, sent
## only to the server (in the connect URL) and never relayed.

## A peer connected / disconnected (within our current world). The peer id is the player's stable
## user_id (a string). The world spawns or frees that peer's puppet pair.
signal peer_joined(peer_id: String)
signal peer_left(peer_id: String)
## A peer's identity packet arrived (re-emitted, id stamped by the server). { name, appearance, companion_look }.
signal identity_received(peer_id: String, payload: Dictionary)
## A peer's high-rate transform packet arrived (re-emitted, id stamped by the server).
signal state_received(peer_id: String, payload: Dictionary)
## Connection lifecycle, for the lobby to reflect status.
signal connected()           # the socket is open (the server accepted our token)
signal connection_failed()   # we never reached the server (bad URL / refused / unreachable)
signal disconnected()        # an established link dropped (server quit / we left)
## Our server-canonical save arrived after joining a world: our companion + wardrobe to adopt. Either
## value is null for a brand-new player. Untyped so null passes.
signal save_loaded(companion, appearance)
## The economy snapshot arrived after joining a world (per-user, same in every world): our wallet and
## the shop's color stock, each color flagged owned. currency is the spend currency's name (e.g.
## "coins"); colors is an Array of { item_def_id, name, color_slot, ramp, swatch, price, owned }.
signal economy_loaded(currency: String, balance: int, colors: Array)
## A shop purchase resolved. On success: the bought color's id + our new balance (the color is now
## owned). On failure: the id we tried + a short reason string (insufficient_funds, already_owned, …).
signal purchase_succeeded(item_def_id: int, balance: int)
signal purchase_failed(item_def_id: int, reason: String)
## The server resolved a salamander-hunt reward claim: how many we found, the coins it paid out (the
## SERVER decides the amount; 0 below the reward threshold), and our new wallet balance.
signal hunt_reward(found: int, amount: int, balance: int)
## A world's spec arrived (and was cached, in memory + on disk): the display-agnostic core +
## presentation profiles. The world layer builds (first paint) or rebuilds (the world changed under
## us) from it. spec = { "core": {...}, "profiles": { "2d": {...} } }.
signal world_spec_received(world_id: String, version: int, spec: Dictionary)
## We reached the server but it REFUSED our world-channel join (e.g. the world isn't in the catalog —
## reason "unknown_world"; usually the server hasn't been seeded). The lobby surfaces this instead of
## hanging on "loading".
signal world_join_failed(reason: String)

## Where a client connects by default — the channel mount point. Net rewrites this into the full
## Phoenix socket URL (…/websocket?vsn=2.0.0&token=…) in connect_to().
const DEFAULT_SERVER_URL := "ws://192.168.86.38:4000/ws"

## Phoenix closes a socket that goes silent; send a heartbeat well inside that window.
const HEARTBEAT_INTERVAL := 25.0

## Where fetched world specs are cached on disk (one JSON per world_id), so revisits across SESSIONS
## skip the download — the client confirms freshness by sending the cached etag on join.
const CACHE_DIR := "user://world_cache"

var _socket: WebSocketPeer = null
# Our id, from a world's 'welcome' frame: our stable user_id. Empty until we've joined a world.
var _my_id: String = ""
# True once the socket has reached STATE_OPEN at least once this session.
var _was_open: bool = false
# True once we've joined our CURRENT world channel (its 'welcome' arrived).
var _joined: bool = false
# Monotonic message ref for the Phoenix protocol.
var _ref: int = 0
# The join_ref of our current world channel (reused as join_ref on its frames, phoenix.js-style).
var _world_join_ref: String = ""
# The world we WANT to be in (persists across a reconnect so we rejoin it) and the one we're CURRENTLY
# joined to. Both are world_ids (strings). "" = none.
var _desired_world: String = ""
var _desired_known_etag: String = ""
var _current_world: String = ""
var _heartbeat_accum: float = 0.0
# Our own identity packet, stashed so we can (re)send it the moment we've joined a world.
var _local_identity: Dictionary = {}
# In-session mirror of our server-canonical save; survives world-scene reloads (Net is an autoload).
var _session_save: Dictionary = {}
# Cached world specs by world_id: { world_id: { "etag": String, "version": int, "spec": Dictionary } }.
# Kept across world hops and reconnects (and, via the on-disk mirror in CACHE_DIR, across sessions) so
# revisits skip the download — the server is asked only to confirm the cached etag is still current.
# DEFERRED SEAM: CDN-fetched heavy assets (textures/audio) belong alongside this when worlds get large.
var _world_specs: Dictionary = {}


func _ready() -> void:
	# Pump the socket even while the tree is paused. The connect gate freezes the world (get_tree().paused)
	# until the player is officially loaded in; if Net paused too, the connect/reconnect handshake could
	# never complete and you'd be stuck on a black gate. As an autoload Net is the one node that must keep
	# ticking regardless of the gate.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Warm the in-memory cache from disk so a returning player's worlds paint instantly (and we can send
	# their etags on join to skip the download). A changed world still re-ships — the etag won't match.
	_load_disk_cache()


func _process(delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				connected.emit()
				# Join whatever world the world layer asked for (queued before we were open).
				_switch_to_world()
			_pump_heartbeat(delta)
			while _socket.get_available_packet_count() > 0:
				_handle_frame(_socket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_on_socket_closed()


## True while the socket is open. Sends no-op when false.
func is_active() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


## Our id — our user_id (empty before our first world 'welcome').
func local_id() -> String:
	return _my_id


## CONNECT to the server at `base_url` (host:port, optionally with the "/ws" mount). Net rewrites it
## into the full Phoenix socket URL with the v2 serializer and our identity token. Returns OK or a
## Godot error code; handshake result arrives via connected()/connection_failed().
func connect_to(base_url: String = DEFAULT_SERVER_URL) -> int:
	_reset_socket()
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(_phoenix_url(base_url))
	if err != OK:
		_socket = null
		return err
	return OK


## Tear the whole link down (e.g. "Leave"). Graceful close if open, so a final queued frame flushes
## and the drop surfaces through disconnected() exactly like a server-side drop.
func leave() -> void:
	if _socket == null:
		return
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.close()
	else:
		_reset_socket()


## Enter a world: join its channel (or queue the join until the socket is open). On travel, call this
## with the new world_id — Net leaves the old world channel and joins the new one. Sends our cached
## content etag so the server skips re-sending an unchanged spec (and ships a fresh one if it changed).
func enter_world(world_id: String, known_etag: String = "") -> void:
	_desired_world = world_id
	_desired_known_etag = known_etag if known_etag != "" else cached_etag(world_id)
	if is_active():
		_switch_to_world()


## Leave the current world without dropping the socket (rarely needed directly; travel uses enter_world).
func leave_world() -> void:
	if _current_world != "":
		_send_raw([_world_join_ref, _next_ref(), _world_topic(_current_world), "phx_leave", {}])
	_current_world = ""
	_desired_world = ""
	_joined = false


## The cached spec for a world (its { core, profiles }), or {} if we haven't fetched it this session.
func cached_spec(world_id: String) -> Dictionary:
	var entry: Dictionary = _world_specs.get(world_id, {})
	return entry.get("spec", {})


## The display-agnostic CORE of a cached world spec (what the world layer builds from), or {}.
func cached_spec_core(world_id: String) -> Dictionary:
	return cached_spec(world_id).get("core", {})


## The content etag of the cached spec for a world, or "" if we don't have it. This is the cache
## validator we echo back on join (known_etag) so an unchanged world isn't re-downloaded.
func cached_etag(world_id: String) -> String:
	return String(_world_specs.get(world_id, {}).get("etag", ""))


## TEST-ONLY: seed the in-memory spec cache directly (no socket), so headless smoke tests can build a
## world server-less. Wraps the display-agnostic CORE in the { core, profiles } envelope the world
## layer expects; does NOT touch the disk cache. Not used by the running game (which always fetches).
func prime_world_spec(world_id: String, core: Dictionary) -> void:
	_world_specs[world_id] = { "etag": "primed", "version": 0, "spec": { "core": core, "profiles": {} } }


## The version of the cached spec for a world, or 0 if we don't have it (author-facing metadata).
func cached_version(world_id: String) -> int:
	return int(_world_specs.get(world_id, {}).get("version", 0))


## The LAN addresses this device is reachable at — informational. IPv4 only, minus loopback.
func local_ip_addresses() -> Array:
	var out: Array = []
	for addr in IP.get_local_addresses():
		var s := String(addr)
		if s.count(".") == 3 and not s.begins_with("127."):
			out.append(s)
	return out


## Hand Net our local identity packet; sent as soon as we've joined a world (and on every change).
func set_local_identity(payload: Dictionary) -> void:
	_local_identity = payload.duplicate(true)
	_flush_identity()


## Broadcast our live transform packet to the current world (newest wins). No-op until joined.
func broadcast_state(payload: Dictionary) -> void:
	if not _can_send():
		return
	_push_event("state", _encode_state(payload))


## Persist our companion + wardrobe to the server (per-user, the SOLE save). Mirrors in-session too.
func push_save(companion: Dictionary, appearance: Dictionary) -> void:
	_session_save = { "companion": companion, "appearance": appearance }
	if not _can_send():
		return
	_push_event("save", { "companion": companion, "appearance": appearance })


## Ask the server to BUY a color from the shop. The purchase is server-authoritative (it sinks the
## price and grants the color atomically); the outcome arrives back as purchase_succeeded /
## purchase_failed. A no-op until we've joined a world (the server stamps our id from the socket).
func buy_color(item_def_id: int) -> void:
	if not _can_send():
		return
	_push_event("buy", { "item_def_id": item_def_id })


## Tell the server we finished the salamander hunt, reporting how many of the ten we found. The reward
## is decided + minted server-side; the outcome arrives back as hunt_reward. A no-op until we've
## joined a world (so a hunt completed before the link is up simply pays nothing — online-only).
func claim_hunt_reward(found: int) -> void:
	if not _can_send():
		return
	_push_event("hunt_complete", { "found": found })


## The in-session mirror of our server save, so a freshly-loaded world scene can dress its companion
## without a round-trip. Empty until our first load/save this session.
func session_save() -> Dictionary:
	return _session_save


func has_session_save() -> bool:
	return not _session_save.is_empty()


# --- internals -------------------------------------------------------------------------

func _phoenix_url(base_url: String) -> String:
	var url := base_url.strip_edges()
	while url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	if not url.ends_with("/websocket"):
		url += "/websocket"
	var token := PlayerIdentity.id().uri_encode()
	return "%s?vsn=2.0.0&token=%s" % [url, token]


func _world_topic(world_id: String) -> String:
	return "world:" + world_id


func _can_send() -> bool:
	return is_active() and _joined and _current_world != ""


## Join the desired world channel (leaving the current one first, if different). A no-op if we're
## already in the desired world, or if there's no desired world / the socket isn't open yet.
func _switch_to_world() -> void:
	var wid := _desired_world
	if wid == "" or not is_active():
		return
	if _current_world == wid and _joined:
		return
	# Leave the old world channel (using ITS join_ref) before switching.
	if _current_world != "" and _current_world != wid:
		_send_raw([_world_join_ref, _next_ref(), _world_topic(_current_world), "phx_leave", {}])
	_current_world = wid
	_joined = false
	_world_join_ref = _next_ref()
	_send_raw([_world_join_ref, _world_join_ref, _world_topic(wid), "phx_join", { "known_etag": _desired_known_etag }])


func _flush_identity() -> void:
	if not _can_send() or _local_identity.is_empty():
		return
	_push_event("identity", _local_identity)


func _pump_heartbeat(delta: float) -> void:
	_heartbeat_accum += delta
	if _heartbeat_accum >= HEARTBEAT_INTERVAL:
		_heartbeat_accum = 0.0
		_send_raw([null, _next_ref(), "phoenix", "heartbeat", {}])


func _reset_socket() -> void:
	_socket = null
	_my_id = ""
	_was_open = false
	_joined = false
	_ref = 0
	_world_join_ref = ""
	_current_world = ""
	_heartbeat_accum = 0.0
	# A new session reloads the companion from the server; don't carry it across a reconnect.
	_session_save = {}
	# Keep _desired_world (so a reconnect rejoins the same world), _local_identity, and _world_specs.


func _on_socket_closed() -> void:
	var was_up := _was_open
	_reset_socket()
	if was_up:
		disconnected.emit()
	else:
		connection_failed.emit()


## Decode one Phoenix v2 frame: [join_ref, ref, topic, event, payload]. Dispatch on the event name.
func _handle_frame(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if not (data is Array) or (data as Array).size() != 5:
		return
	var arr := data as Array
	var event := String(arr[3])
	var payload: Variant = arr[4]
	if not (payload is Dictionary):
		payload = {}
	if event == "phx_reply":
		_handle_reply(arr, payload)
	else:
		_dispatch(event, payload)


## A reply to one of our sent frames: [join_ref, ref, topic, "phx_reply", { status, response }]. We
## only act on a FAILED join of our current world channel (its ref is our world join_ref), so a hang
## becomes a visible error rather than an endless "loading".
func _handle_reply(arr: Array, payload: Dictionary) -> void:
	if String(payload.get("status", "")) != "error":
		return
	if String(arr[1]) != _world_join_ref:
		return
	var response: Variant = payload.get("response", {})
	var reason := "join_failed"
	if response is Dictionary:
		reason = String((response as Dictionary).get("reason", reason))
	_joined = false
	world_join_failed.emit(reason)


func _dispatch(event: String, payload: Dictionary) -> void:
	match event:
		"world_spec":
			var wid := String(payload.get("world_id", ""))
			var version := int(payload.get("version", 0))
			var etag := String(payload.get("etag", ""))
			var spec: Variant = payload.get("spec", {})
			if wid != "" and spec is Dictionary:
				var entry := { "etag": etag, "version": version, "spec": spec }
				_world_specs[wid] = entry
				_persist_spec(wid, entry)
				world_spec_received.emit(wid, version, spec)
		"world_spec_unchanged":
			# Our cached spec is current; nothing to do (the world layer already has it).
			pass
		"welcome":
			# We're in the world: adopt our id, mark joined, flush identity, learn who's here.
			_my_id = String(payload.get("id", ""))
			_joined = true
			_flush_identity()
			var peers: Variant = payload.get("peers", [])
			if peers is Array:
				for peer in peers:
					if not (peer is Dictionary):
						continue
					var pid := String(peer.get("id", ""))
					if pid == "":
						continue
					peer_joined.emit(pid)
					var ident: Variant = peer.get("identity", {})
					if ident is Dictionary and not (ident as Dictionary).is_empty():
						identity_received.emit(pid, ident)
		"join":
			var jid := String(payload.get("id", ""))
			if jid != "":
				peer_joined.emit(jid)
		"leave":
			var lid := String(payload.get("id", ""))
			if lid != "":
				peer_left.emit(lid)
		"identity":
			var iid := String(payload.get("id", ""))
			if iid != "":
				identity_received.emit(iid, _strip_id(payload))
		"state":
			var sid := String(payload.get("id", ""))
			if sid != "":
				state_received.emit(sid, _decode_state(_strip_id(payload)))
		"load":
			var companion: Variant = payload.get("companion")
			var appearance: Variant = payload.get("appearance")
			if companion is Dictionary:
				_session_save["companion"] = companion
			if appearance is Dictionary:
				_session_save["appearance"] = appearance
			save_loaded.emit(companion, appearance)
		"economy":
			var colors: Variant = payload.get("colors", [])
			economy_loaded.emit(
				String(payload.get("currency", "")),
				int(payload.get("balance", 0)),
				colors if colors is Array else [])
		"bought":
			purchase_succeeded.emit(int(payload.get("item_def_id", 0)), int(payload.get("balance", 0)))
		"buy_failed":
			purchase_failed.emit(int(payload.get("item_def_id", 0)), String(payload.get("reason", "")))
		"hunt_reward":
			hunt_reward.emit(
				int(payload.get("found", 0)),
				int(payload.get("amount", 0)),
				int(payload.get("balance", 0)))


## Send one of OUR channel events on the current world topic (stable join_ref, fresh ref).
func _push_event(event: String, payload: Dictionary) -> void:
	_send_raw([_world_join_ref, _next_ref(), _world_topic(_current_world), event, payload])


func _send_raw(frame: Array) -> void:
	if _socket == null:
		return
	_socket.send_text(JSON.stringify(frame))


func _next_ref() -> String:
	_ref += 1
	return str(_ref)


# --- world-spec disk cache ------------------------------------------------------------------
# One JSON file per world under CACHE_DIR ({ etag, version, spec }), so a returning player's worlds
# paint without a download. Freshness is the etag's job: on join we send the cached etag, and the
# server re-ships only if the world has changed. Best-effort — any I/O failure just means a refetch.

## Load every cached world spec from disk into the in-memory map (called once, on _ready).
func _load_disk_cache() -> void:
	var dir := DirAccess.open(CACHE_DIR)
	if dir == null:
		return  # no cache yet (first run) — nothing to warm
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var wid := fname.substr(0, fname.length() - 5)
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE_DIR + "/" + fname))
			if parsed is Dictionary and (parsed as Dictionary).get("spec") is Dictionary:
				var p := parsed as Dictionary
				_world_specs[wid] = {
					"etag": String(p.get("etag", "")),
					"version": int(p.get("version", 0)),
					"spec": p.get("spec", {}),
				}
		fname = dir.get_next()
	dir.list_dir_end()


## Mirror one world's cache entry to disk. world_id is a server UUID (used as the filename); guard
## against path-y ids just in case so a malformed id can never escape CACHE_DIR.
func _persist_spec(world_id: String, entry: Dictionary) -> void:
	if world_id == "" or world_id.contains("/") or world_id.contains("\\") or world_id.contains(".."):
		return
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open(CACHE_DIR + "/" + world_id + ".json", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(entry))
	f.close()


## Drop the server-stamped "id" so what's emitted upward is the bare presentation payload.
func _strip_id(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	out.erase("id")
	return out


## Vector2 → [x, y] for every Vector2-valued field (JSON has no Vector2). Pure + static, unit-testable.
static func _encode_state(payload: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in payload:
		var v: Variant = payload[k]
		out[k] = [v.x, v.y] if v is Vector2 else v
	return out


## [x, y] → Vector2 for every 2-number array (the inverse of _encode_state).
static func _decode_state(payload: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in payload:
		var v: Variant = payload[k]
		if v is Array and v.size() == 2 and _is_number(v[0]) and _is_number(v[1]):
			out[k] = Vector2(v[0], v[1])
		else:
			out[k] = v
	return out


static func _is_number(v: Variant) -> bool:
	return v is float or v is int
