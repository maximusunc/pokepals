extends Control
## The connection gate. The game is ONLINE-ONLY: there is no solo/offline mode and no local save —
## your companion lives on the server — so entering the world REQUIRES connecting. There's no address
## to type: the server URL is resolved automatically (the page origin on web; a build-time config on
## native — see Net.default_server_url). This overlay auto-connects, reflects status, and steps aside
## once the server has handed back your companion (save_loaded). If the link can't be made it offers a
## Retry. Pure presentation.
##
## DEVICES (issue 175). Every way in (cold boot, Retry, "Play here") goes through Net.connect_to, which
## fetches a fresh ticket first. Two more ways to be out, both HELD (nothing reconnects by itself):
##   * playing on another device now (newest wins): "Play here" takes it back;
##   * this device was signed out: "Enter a code" (bring your companion back with a code from another
##     device) or "Start fresh" (after a confirm, this device begins again as a new player).
## When this device becomes someone else (a code linked it, or Start fresh), Net says identity_changed and
## the gate rebuilds the whole world from scratch, which connects as the new player.
##
## It's also the LAST of the three loading stages: the web download page (web/shell.html) and the boot
## splash (assets/loading/boot_splash.png) show the same wordmark and the same fox on the same
## background, at the same spots, so the hand-off from one to the next is seamless. Those two are baked
## by tools/gen_loading.py; the LOADING LAYOUT numbers below mirror its layout constants.

# LOADING LAYOUT, on the 640x360 canvas (mirrors tools/gen_loading.py):
const BG := Color("1b1510")       # gen_loading.BG, also the boot splash's bg_color
const BG_OVER_WORLD := Color(0.106, 0.082, 0.063, 0.82)  # after a disconnect: the world dims beneath
const WORDMARK_SIZE := 16         # gen_loading.WORDMARK_SIZE
const BOX_TOP := 99.0 - 180.0     # the wordmark's ink starts 7px into its Label, at y=106
const GAP := 12.0                 # puts the fox's 64px box at y=132 (gen_loading.FOX_TOP)

@onready var _backdrop: ColorRect = $Backdrop
@onready var _box: VBoxContainer = $Box
@onready var _title: Label = $Box/Title
@onready var _status: Label = $Box/Status
@onready var _retry_button: Button = $Box/RetryButton
var _fox: TrottingFox
# The signed-out state's second button ("Start fresh", or "Back" while it asks to be sure), beside Retry.
var _buttons: HBoxContainer
var _second_button: Button
# What the main button does right now: "retry" (also "Play here"), "code" or "fresh" (confirmed).
var _main_action := "retry"


func _ready() -> void:
	_apply_style()
	_retry_button.pressed.connect(_on_main_pressed)
	Net.superseded.connect(_on_held)
	Net.signed_out.connect(_on_held)
	Net.identity_changed.connect(_on_identity_changed)
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
	# _ready only decides the INITIAL state for this freshly-(re)loaded scene. The "officially joined"
	# guarantee lives elsewhere: the world only ever UNFREEZES in _on_save_loaded, so the window between
	# socket-open and the companion arriving stays frozen no matter what. So here we only tell two fresh
	# loads apart:
	#   • a connected world hop (WorldRouter.go_to reloads this scene without dropping the socket): the
	#     socket is already open → we're mid-session, stay out of the way and leave the world live.
	#   • a cold boot or a post-disconnect reload (socket not open): show the opaque gate, freeze the
	#     world, and auto-connect.
	# We key off Net.is_active() (socket open), NOT the contents of the save — a brand-new player's first
	# load is empty (no companion blob yet), so a save-contents check would wrongly bounce them to the gate
	# on their first portal hop.
	if Net.is_active():
		visible = false
		get_tree().paused = false
		return
	# A cold boot: nothing is drawn behind us yet (just the engine's grey clear colour), so the gate is
	# fully opaque here, continuing the boot splash.
	_backdrop.color = BG
	get_tree().paused = true
	_begin_connect()


## The gate in the shared UiStyle voice: a Silkscreen wordmark over the dark backdrop (the
## same pixel-caps treatment as the wardrobe's WARDROBE header), quiet paper status text,
## and the gold primary button for Retry.
func _apply_style() -> void:
	_title.text = "GATES OF ELYRA"
	var wordmark := UiFonts.pixel(false, 1)
	if wordmark != null:
		_title.add_theme_font_override("font", wordmark)
	_title.add_theme_font_size_override("font_size", WORDMARK_SIZE)
	_box.offset_top = BOX_TOP
	_box.add_theme_constant_override("separation", int(GAP))
	# The fox, between the wordmark and the status line. It trots while we're connecting and stands
	# still while we wait on a Retry.
	_fox = TrottingFox.new(2)
	_fox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(_fox)
	_box.move_child(_fox, _title.get_index() + 1)
	_title.add_theme_color_override("font_shadow_color", Color(20.0 / 255.0, 14.0 / 255.0, 8.0 / 255.0, 0.55))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 1)
	UiStyle.set_font(_status, 500, 10)
	_status.add_theme_color_override("font_color", UiStyle.PAPER)
	UiStyle.gold_button(_retry_button, 11)
	# Retry sits in a row with room for a second, quieter button (the signed-out state's).
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 8)
	_box.add_child(_buttons)
	_retry_button.reparent(_buttons)
	_second_button = Button.new()
	_second_button.visible = false
	UiStyle.pill_button(_second_button, 11)
	_second_button.pressed.connect(_on_second_pressed)
	_buttons.add_child(_second_button)


## Start (or retry) connecting to the resolved server. No address is typed — web derives it from the
## page origin, native reads the baked-in config (see Net.default_server_url).
func _begin_connect() -> void:
	_retry_button.visible = false
	_second_button.visible = false
	_fox.trotting = true
	var err := Net.connect_to(Net.default_server_url())
	if err != OK:
		_status.text = "Couldn't start connecting (error %d)." % err
		_offer("Retry", "retry")
		_fox.trotting = false
		return
	_status.text = "Connecting…"


## Show the main button as `text`, doing `action`, and (optionally) the quieter second one.
func _offer(text: String, action: String, second := "") -> void:
	_main_action = action
	_retry_button.text = text
	_retry_button.visible = true
	_second_button.text = second
	_second_button.visible = second != ""


func _on_main_pressed() -> void:
	match _main_action:
		"code": _open_code_entry()
		"fresh": Net.start_fresh()
		_: _begin_connect()


func _on_second_pressed() -> void:
	if _main_action == "fresh":
		_show_held()   # "Back": not starting fresh after all
	else:
		_ask_start_fresh()


## Off the server and staying off until the player says (see DEVICES above). Called on the word itself
## and again when the socket then closes: it only ever shows the state, so twice is harmless.
func _on_held() -> void:
	if _is_stale():
		return
	_show_held()


func _show_held() -> void:
	var why := Net.held()
	if why == "":
		return
	if not visible or not get_tree().paused:
		_reshow()   # we were in the world: freeze it under the gate again
	if why == "superseded":
		_status.text = "You're playing on another device now."
		_offer("Play here", "retry")
	else:
		_status.text = "This device was signed out."
		_offer("Enter a code", "code", "Start fresh")
	_fox.trotting = false


## Start fresh, but only once they're sure: their companion isn't lost, it lives on with their other
## devices, but this device won't be it any more.
func _ask_start_fresh() -> void:
	_status.text = "Start fresh on this device? You'll begin again as someone new. Your companion stays with your other devices."
	_offer("Start fresh", "fresh", "Back")


func _open_code_entry() -> void:
	add_child(LinkJoinPanel.new())


## This device is someone else now (a code linked it, or Start fresh): rebuild the world from nothing, the
## way a fresh boot does, so nothing of the old player lingers. The new scene's gate connects as the new
## player, and the server sets them down where they last stood.
func _on_identity_changed() -> void:
	if _is_stale():
		return
	_status.text = "Bringing your companion here…"
	WorldRouter.gateway_departure = {}
	WorldRouter.go_to(WorldRouter.VALE_ID, "")


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
	_status.text = "Couldn't reach the server. Check that it's running, then retry."
	_offer("Retry", "retry")
	_fox.trotting = false


## We reached the server but it refused to let us into the world — almost always because the server's
## world catalog is empty (run its seeds). Surface it instead of hanging on "loading".
func _on_world_join_failed(reason: String) -> void:
	if _is_stale():
		return
	if reason == "unknown_world":
		_status.text = "The server has no world to enter yet. Seed it: mix run priv/repo/seeds.exs"
	else:
		_status.text = "The server refused entry to the world (%s)." % reason
	_offer("Retry", "retry")
	_fox.trotting = false


## The link dropped. With no offline mode, the player returns to the gate to reconnect.
func _on_disconnected() -> void:
	if _is_stale():
		return
	if Net.held() != "":
		_show_held()
		return
	_status.text = "Disconnected from the server. Reconnect to keep playing."
	_reshow()


func _reshow() -> void:
	# Re-freeze the world under the opaque gate: no movement, and no portal can fire to sneak us back
	# into a disconnected world. Offer Retry — there's nothing else to configure.
	get_tree().paused = true
	_backdrop.color = BG_OVER_WORLD
	visible = true
	modulate.a = 1.0
	_offer("Retry", "retry")
	_fox.trotting = false


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
