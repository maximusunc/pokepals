extends Control
## The LAN lobby overlay: Host, or Join by IP. It only drives the Net seam (Net.host / Net.join)
## and reflects connection status, then gets out of the way the moment a friend is actually here.
## Pure presentation — gameplay is wired to Net's signals by the world, not here.
##
## This is intentionally the whole "connection UX" for this rung: one device Hosts and reads its
## LAN IP out loud; the other types it and Joins. Later transports (WebSockets, a real server)
## replace what Host/Join do under the hood without changing this screen's shape.

@onready var _host_button: Button = $Box/HostButton
@onready var _ip_edit: LineEdit = $Box/JoinRow/IpEdit
@onready var _join_button: Button = $Box/JoinRow/JoinButton
@onready var _solo_button: Button = $Box/SoloButton
@onready var _status: Label = $Box/Status


func _ready() -> void:
	_host_button.pressed.connect(_on_host)
	_join_button.pressed.connect(_on_join)
	_solo_button.pressed.connect(_on_solo)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	_status.text = "Wander together on your local network."


func _on_host() -> void:
	var err := Net.host()
	if err != OK:
		_status.text = "Couldn't host (error %d). Is the port already in use?" % err
		return
	var ips := Net.local_ip_addresses()
	var ip_text := ", ".join(ips) if not ips.is_empty() else "(unknown — check your network)"
	_status.text = "Hosting. Have your friend Join at:\n%s" % ip_text
	_set_controls_enabled(false)


func _on_join() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip == "":
		_status.text = "Type the host's IP first."
		return
	var err := Net.join(ip)
	if err != OK:
		_status.text = "Couldn't start joining (error %d)." % err
		return
	_status.text = "Connecting to %s…" % ip
	_set_controls_enabled(false)


## Just wander offline — the existing single-player experience, one tap away and fully intact.
## The whole Net layer stays dormant (nothing is ever sent or spawned) until a session is started.
func _on_solo() -> void:
	visible = false


## Host went live, or this client linked to the host. We hold the panel until a PEER actually
## arrives (peer_joined) — so the host keeps seeing its IP to read out while it waits.
func _on_connected() -> void:
	if not Net.is_host():
		_status.text = "Connected! Looking for your friend…"


func _on_connection_failed() -> void:
	_status.text = "Couldn't reach that host. Check the IP, and that they're hosting."
	_set_controls_enabled(true)


func _on_disconnected() -> void:
	_status.text = "Disconnected."
	_reshow()


## A friend is really here — fade the lobby away and let the two of you just be in the world.
func _on_peer_joined(_id: int) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: visible = false)


func _on_peer_left(_id: int) -> void:
	_status.text = "Your friend left."
	_reshow()


func _reshow() -> void:
	visible = true
	modulate.a = 1.0
	_set_controls_enabled(true)


func _set_controls_enabled(on: bool) -> void:
	_host_button.disabled = not on
	_join_button.disabled = not on
	_ip_edit.editable = on
