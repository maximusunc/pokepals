extends Node
## Net — the transport-agnostic SYNC SEAM (the "pipe"), registered as an autoload.
##
## This is the one place that touches networking. Everything above it (the world, the avatars)
## talks to Net in plain dictionaries and never sees the socket, JSON, or peer ids beyond an
## opaque int. The TRANSPORT is a raw WebSocket to an AUTHORITATIVE Elixir/Phoenix server.
##
## TOPOLOGY: every client opens one WebSocket to the server. The server assigns each client an id,
## tracks the roster (Phoenix.Presence), RELAYS presentation between clients, and — as of the
## persistence step — is the SOLE store of each player's companion + wardrobe (Postgres), keyed by
## a local identity token (PlayerIdentity). The game is online-only: there is no local game save.
##
## What crosses the wire, as JSON text frames:
##   • PRESENTATION (relayed to peers):
##       - identity (on connect / on change): appearance + companion resting-look, so a peer can
##         render *who you are*.
##       - state (~20 Hz): the live transforms of your player+companion, newest wins. Godot has no
##         JSON Vector2, so each is marshalled to a [x, y] array at this seam (and back), so the
##         dict handed up to the world stays Vector2-valued.
##   • PERSISTENCE (point-to-point with the server; NEVER relayed to peers):
##       - hello (on connect): our identity token, so the server can find our save.
##       - load (server → us): our canonical companion + wardrobe (or nulls for a new player).
##       - save (us → server, periodic + on exit): the canonical write.
##
## TRUST MODEL: the SERVER stamps the sender id onto every relayed frame — clients never send their
## own id, so a peer can't impersonate another. Incoming presentation payloads are untrusted input
## the world clamps/validates and may ONLY move the SENDER's puppet. The identity token is a bearer
## credential, kept point-to-point and never relayed.

## A peer connected / disconnected. The world spawns or frees that peer's puppet pair.
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## A peer's identity packet arrived (re-emitted, id stamped by the server). { name, appearance, companion_look }.
signal identity_received(peer_id: int, payload: Dictionary)
## A peer's high-rate transform packet arrived (re-emitted, id stamped by the server).
signal state_received(peer_id: int, payload: Dictionary)
## Connection lifecycle, for the lobby to reflect status.
signal connected()           # the server accepted us (our 'welcome' arrived with our id)
signal connection_failed()   # we never reached the server (bad URL / refused / unreachable)
signal disconnected()        # an established link dropped (server quit / we left)
## Our server-canonical save arrived after connecting: our companion + wardrobe to adopt. Either
## value is null for a brand-new player (the world then seeds the server). Untyped so null passes.
signal save_loaded(companion, appearance)

## Where a client connects by default. The server listens on :4000 and upgrades GET /ws.
const DEFAULT_SERVER_URL := "ws://127.0.0.1:4000/ws"

var _socket: WebSocketPeer = null
# Our server-assigned id, from the 'welcome' frame. 0 until the server accepts us.
var _my_id: int = 0
# True once the socket has reached STATE_OPEN at least once this session — lets us tell a
# never-connected failure apart from a dropped established link when the socket closes.
var _was_open: bool = false
# Our own identity packet, stashed so we can (re)send it the moment the socket is open, without
# the world caring about connect timing. Set by the world via set_local_identity().
var _local_identity: Dictionary = {}
# The in-session mirror of our server-canonical save ({ "companion": {...}, "appearance": {...} }).
# Set from the server's 'load' and from every push_save. NOT written to disk — it just survives
# world-scene reloads (Net is an autoload), so hopping between worlds carries the companion without
# a server round-trip. Cleared on disconnect, so a reconnect reloads fresh from the server.
var _session_save: Dictionary = {}


func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				# The link is up: identify ourselves (so the server can load our save), then
				# push whatever presentation identity we've been handed.
				_send_hello()
				_flush_identity()
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


## CONNECT to the server at `url`. Returns OK or a Godot error code the lobby can surface.
## Success of the handshake arrives later via connected()/connection_failed().
func connect_to(url: String = DEFAULT_SERVER_URL) -> int:
	_reset_socket()
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(url)
	if err != OK:
		_socket = null
		return err
	return OK


## Tear the link down (and reset), e.g. on leaving. Safe to call when not connected.
func leave() -> void:
	if _socket != null:
		_socket.close()
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


## Hand Net our local identity packet. Net stashes it and sends it as soon as the socket is open
## (and again whenever it changes, e.g. a bond milestone) — so the world sets it once and never
## worries about connect timing. The server relays it, id-stamped, to every other client.
func set_local_identity(payload: Dictionary) -> void:
	_local_identity = payload.duplicate(true)
	_flush_identity()


## Broadcast our live transform packet (newest wins; a dropped frame doesn't matter). A no-op
## until connected, so it's safe to call unconditionally every frame.
func broadcast_state(payload: Dictionary) -> void:
	if not is_active():
		return
	var msg := _encode_state(payload)
	msg["t"] = "state"
	_socket.send_text(JSON.stringify(msg))


## Persist our companion + wardrobe to the server (the SOLE save). Also updates the in-session
## mirror, so a world hop carries the companion even before the next send. A no-op until connected.
func push_save(companion: Dictionary, appearance: Dictionary) -> void:
	_session_save = { "companion": companion, "appearance": appearance }
	if not is_active():
		return
	_socket.send_text(JSON.stringify({ "t": "save", "companion": companion, "appearance": appearance }))


## The in-session mirror of our server save (set by 'load' and push_save), so a freshly-loaded world
## scene can dress its companion without a round-trip. Empty until our first load/save this session.
func session_save() -> Dictionary:
	return _session_save


func has_session_save() -> bool:
	return not _session_save.is_empty()


# --- internals -------------------------------------------------------------------------

func _send_hello() -> void:
	if not is_active():
		return
	_socket.send_text(JSON.stringify({ "t": "hello", "player_id": PlayerIdentity.id() }))


func _flush_identity() -> void:
	if not is_active() or _local_identity.is_empty():
		return
	var msg := _local_identity.duplicate(true)
	msg["t"] = "identity"
	_socket.send_text(JSON.stringify(msg))


func _reset_socket() -> void:
	_socket = null
	_my_id = 0
	_was_open = false
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


func _handle_frame(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		return  # malformed frame: ignore rather than crash
	match String(data.get("t", "")):
		"welcome":
			# The server has accepted us: adopt our id and learn who's already here.
			_my_id = int(data.get("id", 0))
			connected.emit()
			var peers: Variant = data.get("peers", [])
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
			var jid := int(data.get("id", 0))
			if jid != 0:
				peer_joined.emit(jid)
		"leave":
			var lid := int(data.get("id", 0))
			if lid != 0:
				peer_left.emit(lid)
		"identity":
			var iid := int(data.get("id", 0))
			if iid != 0:
				identity_received.emit(iid, _strip_envelope(data))
		"state":
			var sid := int(data.get("id", 0))
			if sid != 0:
				state_received.emit(sid, _decode_state(_strip_envelope(data)))
		"load":
			# Our canonical save (either field null for a brand-new player). Mirror it for world
			# hops, then hand it up so the world adopts (or seeds) it.
			var companion: Variant = data.get("companion")
			var appearance: Variant = data.get("appearance")
			if companion is Dictionary:
				_session_save["companion"] = companion
			if appearance is Dictionary:
				_session_save["appearance"] = appearance
			save_loaded.emit(companion, appearance)


## Drop the routing envelope ("t" and the server-stamped "id") so what's emitted upward is the
## bare presentation payload the world expects.
func _strip_envelope(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	out.erase("t")
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
