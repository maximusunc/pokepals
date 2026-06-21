extends Node
## Net — the transport-agnostic SYNC SEAM (the "pipe"), registered as an autoload.
##
## This is the one place that touches networking. Everything above it (the world, the avatars)
## talks to Net in plain dictionaries and never sees the socket, JSON, or peer ids beyond an
## opaque int. That's deliberate: the TRANSPORT here is now a raw WebSocket to a MINIMAL
## AUTHORITATIVE SERVER (Rung 4, step 1 — Elixir/Phoenix). Earlier rungs spoke Godot ENet
## peer-to-peer; the seam stayed put and only this file changed. Later Rung-4 steps deepen the
## same server (Phoenix Presence for a real roster, then Postgres persistence) without changing
## the game-side "me vs them" code above this line.
##
## TOPOLOGY: every client opens one WebSocket to the server (there is no "host" anymore). The
## server assigns each client an id, holds the roster, and RELAYS presentation state between
## clients. It does not simulate movement or run the companion brain — it routes.
##
## What ever crosses the wire is only PRESENTATION STATE, as JSON text frames:
##   • identity (reliable, on connect / on change): appearance + companion resting-look, so a
##     peer can render *who you are*. Pure JSON already (PlayerAppearance.to_dict()).
##   • state (~20 Hz): the live transforms of your player+companion, newest wins. Godot has no
##     JSON Vector2, so each Vector2 is marshalled to a [x, y] array at this seam (and back), so
##     the dict contract handed up to the world stays Vector2-valued.
##
## TRUST MODEL: the SERVER stamps the sender id onto every relayed frame — clients never send
## their own id, so a peer can't impersonate another (the same anti-impersonation rule we had
## when the id came from the ENet transport). Beyond identity/routing the server is not yet a
## referee: incoming payloads are still untrusted input the presentation layer clamps
## (_clamp_to_bounds) and bounds before rendering, and they may ONLY move the SENDER's puppet —
## never our avatar or our save. Server-side validation of discrete world-events is a later
## Rung-4 job; the dispatch-by-"t" shape below is the seam it will attach to.

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


func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				# The link is up: push whatever identity we've been handed.
				_flush_identity()
			while _socket.get_available_packet_count() > 0:
				_handle_frame(_socket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_on_socket_closed()


## True while the socket is open. broadcast_state() no-ops when false, so the world can call it
## every frame and it simply does nothing until we're connected.
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


# --- internals -------------------------------------------------------------------------

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
