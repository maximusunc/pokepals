extends Node
## Net — the transport-agnostic SYNC SEAM (the "pipe"), registered as an autoload.
##
## This is the one place that touches networking. Everything above it (the world, the avatars)
## talks to Net in plain dictionaries and never sees the socket, the wire protocol, or peer ids
## beyond an opaque int. The TRANSPORT is a WebSocket to an AUTHORITATIVE Elixir/Phoenix server,
## now over **Phoenix Channels** (the Phoenix v2 serializer) rather than a raw JSON relay.
##
## TOPOLOGY: every client opens one WebSocket to the server and joins the single "world" channel.
## The server assigns each client an id, tracks the roster (Phoenix.Presence), RELAYS presentation
## between clients, and is the SOLE store of each player's companion + wardrobe (Postgres), keyed by
## the player's identity token (PlayerIdentity). The game is online-only: there is no local game save.
##
## AUTH happens once, at connect: the identity token is sent as a connect param in the socket URL,
## and the server resolves it to an internal account before the channel is ever joined. There is no
## separate "hello" round-trip anymore — the server pushes our canonical save ("load") on join.
##
## What crosses the wire, as Phoenix channel events on the "world" topic:
##   • PRESENTATION (relayed to peers):
##       - identity (on join / on change): appearance + companion resting-look, so a peer can
##         render *who you are*.
##       - state (~20 Hz): the live transforms of your player+companion, newest wins. Godot has no
##         JSON Vector2, so each is marshalled to a [x, y] array at this seam (and back), so the
##         dict handed up to the world stays Vector2-valued.
##   • PERSISTENCE (point-to-point with the server; NEVER relayed to peers):
##       - load (server → us, on join): our canonical companion + wardrobe (or nulls for a new player).
##       - save (us → server, periodic + on exit): the canonical write.
##
## PHOENIX WIRE PROTOCOL: the Phoenix "v2" serializer frames every message as a JSON array
##   [join_ref, ref, topic, event, payload]
## We send phx_join to enter the channel, a periodic phoenix/heartbeat to stay alive, and our own
## events (identity/state/save). The server's pushes arrive as the same array shape; we dispatch on
## the event name exactly as the old raw protocol did, so the rest of Net is barely changed.
##
## TRUST MODEL: the SERVER stamps the sender id onto every relayed frame — clients never send their
## own id, so a peer can't impersonate another. Incoming presentation payloads are untrusted input
## the world clamps/validates and may ONLY move the SENDER's puppet. The identity token is a bearer
## credential, sent only to the server (in the connect URL) and never relayed.

## A peer connected / disconnected. The world spawns or frees that peer's puppet pair.
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## A peer's identity packet arrived (re-emitted, id stamped by the server). { name, appearance, companion_look }.
signal identity_received(peer_id: int, payload: Dictionary)
## A peer's high-rate transform packet arrived (re-emitted, id stamped by the server).
signal state_received(peer_id: int, payload: Dictionary)
## Connection lifecycle, for the lobby to reflect status.
signal connected()           # the server accepted us (our 'welcome' arrived with our id)
signal connection_failed()   # we never reached the server (bad URL / refused / unreachable / join rejected)
signal disconnected()        # an established link dropped (server quit / we left)
## Our server-canonical save arrived after connecting: our companion + wardrobe to adopt. Either
## value is null for a brand-new player (the world then seeds the server). Untyped so null passes.
signal save_loaded(companion, appearance)

## Where a client connects by default — the channel mount point. Net rewrites this into the full
## Phoenix socket URL (…/websocket?vsn=2.0.0&token=…) in connect_to(), so the lobby shows a clean
## address and the user only ever types host:port (optionally with /ws).
const DEFAULT_SERVER_URL := "ws://127.0.0.1:4000/ws"

## The single channel topic we join. Matches `Server.WorldChannel`'s "world".
const TOPIC := "world"
## Phoenix closes a socket that goes silent; send a heartbeat well inside that window.
const HEARTBEAT_INTERVAL := 25.0

var _socket: WebSocketPeer = null
# Our server-assigned id, from the 'welcome' frame. 0 until the server accepts us.
var _my_id: int = 0
# True once the socket has reached STATE_OPEN at least once this session — lets us tell a
# never-connected failure apart from a dropped established link when the socket closes.
var _was_open: bool = false
# True once we've joined the "world" channel (got 'welcome'). Channel events (identity/state/save)
# no-op until then; join + heartbeat don't need it.
var _joined: bool = false
# Monotonic message ref for the Phoenix protocol (every sent frame gets a unique ref).
var _ref: int = 0
# The ref stamped on our phx_join, reused as the join_ref on every later "world" frame — exactly as
# phoenix.js does, so the server never treats our messages as stale from a previous channel instance.
var _join_ref: String = ""
# Time since the last heartbeat, so _process can pace them without a Timer node.
var _heartbeat_accum: float = 0.0
# Our own identity packet, stashed so we can (re)send it the moment we've joined, without the world
# caring about connect timing. Set by the world via set_local_identity().
var _local_identity: Dictionary = {}
# The in-session mirror of our server-canonical save ({ "companion": {...}, "appearance": {...} }).
# Set from the server's 'load' and from every push_save. NOT written to disk — it just survives
# world-scene reloads (Net is an autoload), so hopping between worlds carries the companion without
# a server round-trip. Cleared on disconnect, so a reconnect reloads fresh from the server.
var _session_save: Dictionary = {}


func _process(delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				# The link is up: join the "world" channel. Identity is flushed once we're joined
				# (on 'welcome'); the server loads our save on join, so there's no 'hello' to send.
				_send_join()
			_pump_heartbeat(delta)
			while _socket.get_available_packet_count() > 0:
				_handle_frame(_socket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_on_socket_closed()


## True while the socket is open. broadcast_state()/push_save() no-op when false, so the world can
## call them every frame and they simply do nothing until we're connected.
func is_active() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


## Our server-assigned id (0 before 'welcome'). There is no host concept anymore.
func local_id() -> int:
	return _my_id


## CONNECT to the server. `base_url` is the friendly address the lobby shows / the user types
## (host:port, optionally with the "/ws" mount). Net rewrites it into the full Phoenix socket URL
## with the v2 serializer and our identity token. Returns OK or a Godot error code the lobby can
## surface; handshake success arrives later via connected()/connection_failed().
func connect_to(base_url: String = DEFAULT_SERVER_URL) -> int:
	_reset_socket()
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(_phoenix_url(base_url))
	if err != OK:
		_socket = null
		return err
	return OK


## Tear the link down, e.g. the player pressing "Leave". Safe to call when not connected.
##
## If the link is OPEN we close it GRACEFULLY: we keep the socket so _process keeps polling until it
## reaches STATE_CLOSED, which both flushes any final frame (e.g. a last save the world queued just
## before leaving) AND surfaces the drop through the normal path — _on_socket_closed emits
## disconnected(), exactly as a server-side drop would, so the lobby gate reappears. If we were only
## mid-connect (never OPEN), there's nothing to flush, so we just drop it now.
func leave() -> void:
	if _socket == null:
		return
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.close()
	else:
		_reset_socket()


## The LAN addresses this device is reachable at — informational, so whoever runs the server can
## read one out to a friend. IPv4 only and minus loopback.
func local_ip_addresses() -> Array:
	var out: Array = []
	for addr in IP.get_local_addresses():
		var s := String(addr)
		if s.count(".") == 3 and not s.begins_with("127."):
			out.append(s)
	return out


## Hand Net our local identity packet. Net stashes it and sends it as soon as we've joined the
## channel (and again whenever it changes, e.g. a bond milestone) — so the world sets it once and
## never worries about connect timing. The server relays it, id-stamped, to every other client.
func set_local_identity(payload: Dictionary) -> void:
	_local_identity = payload.duplicate(true)
	_flush_identity()


## Broadcast our live transform packet (newest wins; a dropped frame doesn't matter). A no-op until
## joined, so it's safe to call unconditionally every frame.
func broadcast_state(payload: Dictionary) -> void:
	if not _can_send():
		return
	_push_event("state", _encode_state(payload))


## Persist our companion + wardrobe to the server (the SOLE save). Also updates the in-session
## mirror, so a world hop carries the companion even before the next send. A no-op until joined.
func push_save(companion: Dictionary, appearance: Dictionary) -> void:
	_session_save = { "companion": companion, "appearance": appearance }
	if not _can_send():
		return
	_push_event("save", { "companion": companion, "appearance": appearance })


## The in-session mirror of our server save (set by 'load' and push_save), so a freshly-loaded world
## scene can dress its companion without a round-trip. Empty until our first load/save this session.
func session_save() -> Dictionary:
	return _session_save


func has_session_save() -> bool:
	return not _session_save.is_empty()


# --- internals -------------------------------------------------------------------------

## Rewrite a friendly base URL into the Phoenix socket URL: ensure the "/websocket" suffix the
## Phoenix transport listens on, then append the v2 serializer version and our identity token.
func _phoenix_url(base_url: String) -> String:
	var url := base_url.strip_edges()
	while url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	if not url.ends_with("/websocket"):
		url += "/websocket"
	var token := PlayerIdentity.id().uri_encode()
	return "%s?vsn=2.0.0&token=%s" % [url, token]


## True once the socket is open AND we've joined the channel — the gate for our own events.
func _can_send() -> bool:
	return is_active() and _joined


## Join the "world" channel, recording the join_ref we'll reuse for every later "world" frame.
func _send_join() -> void:
	_join_ref = _next_ref()
	_send_raw([_join_ref, _join_ref, TOPIC, "phx_join", {}])


func _flush_identity() -> void:
	if not _can_send() or _local_identity.is_empty():
		return
	_push_event("identity", _local_identity)


## Pace Phoenix heartbeats so the server doesn't reap us as idle. Heartbeats ride the special
## "phoenix" topic with a null join_ref.
func _pump_heartbeat(delta: float) -> void:
	_heartbeat_accum += delta
	if _heartbeat_accum >= HEARTBEAT_INTERVAL:
		_heartbeat_accum = 0.0
		_send_raw([null, _next_ref(), "phoenix", "heartbeat", {}])


func _reset_socket() -> void:
	_socket = null
	_my_id = 0
	_was_open = false
	_joined = false
	_ref = 0
	_join_ref = ""
	_heartbeat_accum = 0.0
	# A new session reloads from the server; don't carry a stale companion across a reconnect.
	_session_save = {}


func _on_socket_closed() -> void:
	# Distinguish "never reached the server" from "an established link dropped".
	var was_up := _was_open
	_reset_socket()
	if was_up:
		disconnected.emit()
	else:
		connection_failed.emit()


## Decode one Phoenix v2 frame: [join_ref, ref, topic, event, payload]. We dispatch on the event
## name; the routing fields (join_ref/ref/topic) are not needed once we're on a single topic.
func _handle_frame(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if not (data is Array) or (data as Array).size() != 5:
		return  # malformed frame: ignore rather than crash
	var arr := data as Array
	var event := String(arr[3])
	var payload: Variant = arr[4]
	if not (payload is Dictionary):
		payload = {}
	_dispatch(event, payload)


## Map a channel event to the world-facing signals. These mirror the old raw protocol exactly, so
## everything above Net is unchanged — only the framing around them moved to Phoenix Channels.
func _dispatch(event: String, payload: Dictionary) -> void:
	match event:
		"phx_reply":
			# The reply to our phx_join. An error means the server refused the channel — surface it
			# as a failed connection. (We learn our id from 'welcome', not from this reply.)
			if String(payload.get("status", "")) == "error":
				connection_failed.emit()
		"welcome":
			# The server has accepted us into the world: adopt our id, learn who's already here, and
			# (now that we're joined) flush our identity.
			_my_id = int(payload.get("id", 0))
			_joined = true
			connected.emit()
			_flush_identity()
			var peers: Variant = payload.get("peers", [])
			if peers is Array:
				for peer in peers:
					if not (peer is Dictionary):
						continue
					var pid := int(peer.get("id", 0))
					if pid == 0:
						continue
					peer_joined.emit(pid)
					var ident: Variant = peer.get("identity", {})
					if ident is Dictionary and not (ident as Dictionary).is_empty():
						identity_received.emit(pid, ident)
		"join":
			var jid := int(payload.get("id", 0))
			if jid != 0:
				peer_joined.emit(jid)
		"leave":
			var lid := int(payload.get("id", 0))
			if lid != 0:
				peer_left.emit(lid)
		"identity":
			var iid := int(payload.get("id", 0))
			if iid != 0:
				identity_received.emit(iid, _strip_id(payload))
		"state":
			var sid := int(payload.get("id", 0))
			if sid != 0:
				state_received.emit(sid, _decode_state(_strip_id(payload)))
		"load":
			# Our canonical save (either field null for a brand-new player). Mirror it for world
			# hops, then hand it up so the world adopts (or seeds) it.
			var companion: Variant = payload.get("companion")
			var appearance: Variant = payload.get("appearance")
			if companion is Dictionary:
				_session_save["companion"] = companion
			if appearance is Dictionary:
				_session_save["appearance"] = appearance
			save_loaded.emit(companion, appearance)


## Send one of OUR channel events on the "world" topic. Adds nothing to the payload — the server
## stamps the sender id — so the world hands Net the bare presentation dict.
func _push_event(event: String, payload: Dictionary) -> void:
	_push_event_frame(event, payload)


## Frame and send a Phoenix message on the "world" topic: the stable join_ref, a fresh ref.
func _push_event_frame(event: String, payload: Dictionary) -> void:
	_send_raw([_join_ref, _next_ref(), TOPIC, event, payload])


func _send_raw(frame: Array) -> void:
	if _socket == null:
		return
	_socket.send_text(JSON.stringify(frame))


func _next_ref() -> String:
	_ref += 1
	return str(_ref)


## Drop the server-stamped "id" so what's emitted upward is the bare presentation payload the world
## expects. (Unlike the old protocol there's no "t" envelope key — the event name carried that.)
func _strip_id(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	out.erase("id")
	return out


## Vector2 → [x, y] for every Vector2-valued field (JSON has no Vector2). Pure + static so it's
## unit-testable and portable. Non-Vector2 fields pass through untouched.
static func _encode_state(payload: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in payload:
		var v: Variant = payload[k]
		out[k] = [v.x, v.y] if v is Vector2 else v
	return out


## [x, y] → Vector2 for every 2-number array (the inverse of _encode_state). This is load-bearing:
## the world's _as_vec2() returns ZERO for anything that isn't already a Vector2, so handing
## Vector2-valued dicts up state_received is exactly what lets the world layer stay untouched.
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
