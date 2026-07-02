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
	# The lobby is the world-ENTRY gate, and it owns the one switch that decides whether the world is
	# playable: get_tree().paused. While the gate is up the whole world tree is frozen (Net is the lone
	# exception — PROCESS_MODE_ALWAYS — so the socket keeps pumping), so nothing can move, no portal can
	# fire, and a not-yet-joined client never walks around or broadcasts.
	#
	# _ready only decides the INITIAL pause state for this freshly-(re)loaded scene. The "officially
	# joined" guarantee lives elsewhere: the world only ever UNFREEZES in _on_save_loaded, so the window
	# between socket-open and the companion arriving stays frozen no matter what. So here we only need to
	# tell two fresh loads apart:
	#   • a connected world hop (WorldRouter.go_to reloads this scene without dropping the socket): the
	#     socket is already open → we're mid-session, stay out of the way and leave the world live.
	#   • a cold boot or a post-disconnect reload (socket not open): show the opaque gate and freeze the
	#     world until we connect and load in.
	# We key off Net.is_active() (socket open), NOT the contents of the save — a brand-new player's first
	# load is empty (no companion blob yet), so a save-contents check would wrongly bounce them to the gate
	# on their first portal hop.
	if Net.is_active():
		visible = false
		get_tree().paused = false
		return
	_status.text = "Connect to a server to play with your companion."
	get_tree().paused = true


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
	if _is_stale():
		return
	_status.text = "Connected! Loading your companion…"


## Our companion + wardrobe are here (or we're a brand-new player). Fade the gate away and let the
## player be in the world — connected-and-alone is the normal way to play.
func _on_save_loaded(_companion, _appearance) -> void:
	if _is_stale():
		return
	# Officially in the world now — this is the ONE place the world becomes playable. Unfreeze before the
	# fade so the player can move the instant the gate clears. (The fade itself animates while we're
	# transitioning out of pause because this Control is PROCESS_MODE_ALWAYS.)
	get_tree().paused = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: visible = false)


func _on_connection_failed() -> void:
	if _is_stale():
		return
	_status.text = "Couldn't reach that server. Check the address, and that it's running."
	_set_controls_enabled(true)


## We reached the server but it refused to let us into the world — almost always because the server's
## world catalog is empty (run its seeds). Surface it instead of hanging on "loading".
func _on_world_join_failed(reason: String) -> void:
	if _is_stale():
		return
	if reason == "unknown_world":
		_status.text = "The server has no world to enter yet. Seed it: mix run priv/repo/seeds.exs"
	else:
		_status.text = "The server refused entry to the world (%s)." % reason
	_set_controls_enabled(true)


## The link dropped. With no offline mode, the player returns to the gate to reconnect.
func _on_disconnected() -> void:
	if _is_stale():
		return
	_status.text = "Disconnected from the server. Reconnect to keep playing."
	_reshow()


func _reshow() -> void:
	# Re-freeze the world under the opaque gate: no movement, and no portal can fire to sneak us back
	# into a disconnected world.
	get_tree().paused = true
	visible = true
	modulate.a = 1.0
	_set_controls_enabled(true)


func _set_controls_enabled(on: bool) -> void:
	_connect_button.disabled = not on
	_url_edit.editable = on


## True if this lobby is detached from the scene tree — it's a torn-down husk that should NOT react.
##
## We subscribe to the Net AUTOLOAD's signals, and Net outlives any single world scene. When a world
## reloads mid-connect — e.g. the server ships a freshly-changed spec and world_controller rebuilds via
## get_tree().reload_current_scene() — this old lobby leaves the tree a frame (or more) before it's
## actually freed. If a Net signal fires in that window our handler runs on a husk whose get_tree() is
## null, and `get_tree().paused = …` crashes. The fresh scene's lobby owns the gate now, so a stale one
## simply bows out. (A normal, single-lobby connect never trips this — it's always in the tree.)
func _is_stale() -> bool:
	return not is_inside_tree()
