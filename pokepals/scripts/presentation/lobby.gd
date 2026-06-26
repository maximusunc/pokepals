extends Control
## The connection gate. The game is ONLINE-ONLY: there is no solo/offline mode and no local save —
## your companion lives on the server — so entering the world REQUIRES connecting. This overlay
## takes a server URL, drives the Net seam (Net.connect_to), reflects status, and steps aside once
## the server has handed back your companion (save_loaded). Pure presentation.

@onready var _url_edit: LineEdit = $Box/UrlRow/UrlEdit
@onready var _connect_button: Button = $Box/UrlRow/ConnectButton
@onready var _status: Label = $Box/Status


func _ready() -> void:
	_url_edit.text = Net.DEFAULT_SERVER_URL
	_connect_button.pressed.connect(_on_connect)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.save_loaded.connect(_on_save_loaded)
	Net.world_join_failed.connect(_on_world_join_failed)
	# The lobby is the world-ENTRY gate. Travelling between worlds reloads this whole scene
	# (WorldRouter.go_to → change_scene_to_file), which would otherwise pop the gate back up on every
	# hop. Two conditions mean "we're already in the world, don't gate again": arriving via a portal
	# (WorldRouter.pending_transition is still set here, since children _ready before the world root
	# consumes it), or an already-active session. Either way, stay out of the way.
	if WorldRouter.pending_transition or Net.is_active():
		visible = false
		return
	_status.text = "Connect to a server to play with your companion."


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


## The server accepted us; our companion is on its way. Hold the gate until it actually arrives
## (save_loaded), so the world doesn't flash a placeholder before the real companion loads.
func _on_connected() -> void:
	_status.text = "Connected! Loading your companion…"


## Our companion + wardrobe are here (or we're a brand-new player). Fade the gate away and let the
## player be in the world — connected-and-alone is the normal way to play.
func _on_save_loaded(_companion, _appearance) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: visible = false)


func _on_connection_failed() -> void:
	_status.text = "Couldn't reach that server. Check the address, and that it's running."
	_set_controls_enabled(true)


## We reached the server but it refused to let us into the world — almost always because the server's
## world catalog is empty (run its seeds). Surface it instead of hanging on "loading".
func _on_world_join_failed(reason: String) -> void:
	if reason == "unknown_world":
		_status.text = "The server has no world to enter yet. Seed it: mix run priv/repo/seeds.exs"
	else:
		_status.text = "The server refused entry to the world (%s)." % reason
	_set_controls_enabled(true)


## The link dropped. With no offline mode, the player returns to the gate to reconnect.
func _on_disconnected() -> void:
	_status.text = "Disconnected from the server. Reconnect to keep playing."
	_reshow()


func _reshow() -> void:
	visible = true
	modulate.a = 1.0
	_set_controls_enabled(true)


func _set_controls_enabled(on: bool) -> void:
	_connect_button.disabled = not on
	_url_edit.editable = on
