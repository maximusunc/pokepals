extends Control
## The connection overlay: type a server URL and Connect, or wander Solo. It only drives the Net
## seam (Net.connect_to) and reflects connection status, then gets out of the way the moment a
## friend is actually here. Pure presentation — gameplay is wired to Net's signals by the world.
##
## This is the whole "connection UX" for this rung: everyone connects to one minimal authoritative
## server (run it on a machine on your network, or locally), and the server introduces the players
## to each other. There's no Host concept anymore — the server is the host.

@onready var _url_edit: LineEdit = $Box/UrlRow/UrlEdit
@onready var _connect_button: Button = $Box/UrlRow/ConnectButton
@onready var _solo_button: Button = $Box/SoloButton
@onready var _status: Label = $Box/Status


func _ready() -> void:
	_url_edit.text = Net.DEFAULT_SERVER_URL
	_connect_button.pressed.connect(_on_connect)
	_solo_button.pressed.connect(_on_solo)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	# The lobby is the world-ENTRY gate, meant to greet the player ONCE on a fresh launch.
	# Travelling between worlds reloads this whole scene (WorldRouter.go_to → change_scene_to_file),
	# which would otherwise pop the lobby back up on every hop — and again on the way back. Two
	# conditions mean "we're already in the world, don't greet again": arriving via a portal
	# (WorldRouter.pending_transition is still set here, since children _ready before the world root
	# consumes it), or an active session. Either way, stay out of the way.
	if WorldRouter.pending_transition or Net.is_active():
		visible = false
		return
	_status.text = "Connect to a server to wander together — or just wander solo."


func _on_connect() -> void:
	var url := _url_edit.text.strip_edges()
	if url == "":
		_status.text = "Type the server's address first."
		return
	var err := Net.connect_to(url)
	if err != OK:
		_status.text = "Couldn't start connecting (error %d). Check the address." % err
		return
	_status.text = "Connecting to %s…" % url
	_set_controls_enabled(false)


## Just wander offline — the existing single-player experience, one tap away and fully intact.
## The whole Net layer stays dormant (nothing is ever sent or spawned) until a session is started.
func _on_solo() -> void:
	visible = false


## The server accepted us. We hold the panel until a PEER actually arrives (peer_joined), so a
## lone first arrival still sees a friendly "waiting" message instead of a blank world.
func _on_connected() -> void:
	_status.text = "Connected! Looking for your friend…"


func _on_connection_failed() -> void:
	_status.text = "Couldn't reach that server. Check the address, and that it's running."
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
	_connect_button.disabled = not on
	_url_edit.editable = on
