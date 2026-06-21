extends Node
## Net — the transport-agnostic SYNC SEAM (the "pipe"), registered as an autoload.
##
## This is the one place that touches Godot's networking. Everything above it (the world,
## the avatars) talks to Net in plain dictionaries and never sees ENet, RPCs, or peer ids
## beyond an opaque int. That's deliberate: the TRANSPORT here is Godot ENet (a listen-
## server — one player Hosts, the other Joins by IP), and it is EXPECTED to be swapped for
## WebSockets and then an authoritative Elixir/Phoenix server in later rungs. When that
## happens, only this file changes; the game-side "me vs them" code carries forward.
##
## What ever crosses the wire is only PRESENTATION STATE:
##   • identity (reliable, once): a one-time packet — appearance + companion resting-look —
##     so a peer can render *who you are*.
##   • state (unreliable, ~20 Hz): the live transforms of your player+companion, newest wins.
## Identity is pure JSON already (PlayerAppearance.to_dict()); the seam stays data-only.
##
## TRUST MODEL (this rung): peer-to-peer with self-authority and NO referee, so a peer *can*
## forge its own payloads. That's inherent to P2P and unfixable without an authoritative
## server (a Rung-4 job). We keep the blast radius at zero instead: every incoming payload is
## untrusted input that may ONLY update the SENDER's puppet for rendering — it never writes to
## disk or moves your avatar. The sender id comes from the transport
## (multiplayer.get_remote_sender_id()), not the payload, so a peer can't impersonate another.

## A peer connected / disconnected. The world spawns or frees that peer's puppet pair.
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## A peer's one-time identity packet arrived (re-emitted from the RPC). { name, appearance, companion_look }.
signal identity_received(peer_id: int, payload: Dictionary)
## A peer's high-rate transform packet arrived (re-emitted from the RPC).
signal state_received(peer_id: int, payload: Dictionary)
## Connection lifecycle, for the lobby to reflect status.
signal connected()           # this client finished connecting (or this host went live)
signal connection_failed()   # this client could not reach the host
signal disconnected()        # the link dropped (host quit / we left)

const DEFAULT_PORT := 24565

# Our own identity packet, stashed so we can push it to any peer that connects (now or later)
# without the world having to listen for every join. Set once by the world via set_local_identity.
var _local_identity: Dictionary = {}


func _ready() -> void:
	# MultiplayerAPI fires these on every peer. We translate them into our own clean signals so
	# nothing upstream depends on Godot's networking object directly.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## True while a real ENet link is up (host or client). Broadcasts no-op when false, so the
## world can call broadcast_state every frame and it simply does nothing until connected.
func is_active() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and peer is ENetMultiplayerPeer and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


## True once we're the host (id 1). Meaningful only while is_active().
func is_host() -> bool:
	return is_active() and multiplayer.is_server()


## Our peer id (host == 1). 0 before connecting.
func local_id() -> int:
	if not is_active():
		return 0
	return multiplayer.get_unique_id()


## HOST a listen-server on `port`. Returns OK or a Godot error code the lobby can surface.
func host(port: int = DEFAULT_PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	# A host is "connected" the instant it goes live (there's no server to wait for).
	connected.emit()
	return OK


## JOIN a host at `ip`:`port`. Returns OK or a Godot error code. Success of the actual
## handshake arrives later via connected()/connection_failed().
func join(ip: String, port: int = DEFAULT_PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


## Tear the link down (and reset), e.g. on leaving. Safe to call when not connected.
func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_local_identity = {}


## The LAN addresses this device is reachable at, so the host can read one out to a friend.
## IPv4 only and minus loopback, which is what a friend on the same network would type.
func local_ip_addresses() -> Array:
	var out: Array = []
	for addr in IP.get_local_addresses():
		var s := String(addr)
		if s.count(".") == 3 and not s.begins_with("127."):
			out.append(s)
	return out


## Hand Net our local identity packet. Net stashes it and delivers it (reliably) to every
## peer already connected and to any that connect later — so the world sets it once and never
## worries about join timing. Re-call it if the identity changes (e.g. a bond milestone).
func set_local_identity(payload: Dictionary) -> void:
	_local_identity = payload.duplicate(true)
	if is_active():
		for id in multiplayer.get_peers():
			_send_identity_to(id)


## Broadcast our live transform packet to every other peer (unreliable: newest wins, dropped
## packets don't matter). A no-op until connected, so it's safe to call unconditionally.
func broadcast_state(payload: Dictionary) -> void:
	if not is_active():
		return
	_receive_state.rpc(payload)


# --- internals -------------------------------------------------------------------------

func _send_identity_to(peer_id: int) -> void:
	if _local_identity.is_empty():
		return
	_receive_identity.rpc_id(peer_id, _local_identity)


func _on_peer_connected(id: int) -> void:
	peer_joined.emit(id)
	# Push our identity straight to the newcomer (and we'll receive theirs the same way).
	_send_identity_to(id)


func _on_peer_disconnected(id: int) -> void:
	peer_left.emit(id)


func _on_connected_to_server() -> void:
	connected.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	disconnected.emit()


## Identity arrives here (reliable). We re-emit it tagged with the TRANSPORT's sender id, never
## a value from the payload — so a peer can't claim to be someone else. The world validates the
## contents (appearance against the catalog, look floats clamped) before rendering them.
@rpc("any_peer", "call_remote", "reliable")
func _receive_identity(payload: Dictionary) -> void:
	identity_received.emit(multiplayer.get_remote_sender_id(), payload)


## Live transforms arrive here (unreliable). Same discipline: tagged with the transport sender,
## treated as untrusted input the world clamps before it moves the sender's puppet.
@rpc("any_peer", "call_remote", "unreliable")
func _receive_state(payload: Dictionary) -> void:
	state_received.emit(multiplayer.get_remote_sender_id(), payload)
