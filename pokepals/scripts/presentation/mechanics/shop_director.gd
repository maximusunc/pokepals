class_name ShopDirector
extends Node
## The Bazaar's colour shop, lifted out of world_controller. Owns the economy snapshot the server pushes
## on join (our wallet + the colour stock), spawns the merchant's stationary companion puppet, opens the
## shop window on a greeting, and relays buys to the server (the purchase is authoritative there). Talks
## back to the host (the World) only through its small public seam (the hint line).
##
## Online-only: the wallet + stock live server-side; if the snapshot hasn't landed yet the shop opens
## empty and fills in the moment _on_economy_loaded fires. No-op in worlds without a shopkeeper.

const COMPANION_SCENE := preload("res://scenes/companion.tscn")

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _scenery: Node2D
var _shop: ShopController
var _style: ArtStyle

var _npc_companion: CompanionView = null
var _shop_colors: Array = []     # [ { item_def_id, name, swatch, price, owned, … } ], from Net
var _shop_balance := 0
var _shop_currency := "coins"


## Wire up the host seam + scene refs, connect the shop window's buttons, and listen for the server's
## economy + purchase echoes. Net + shop connections are auto-dropped when this node is freed on a world
## hop, so they never duplicate across worlds.
func setup(host: Node, companion: CompanionView, world_art: WorldArt, scenery: Node2D, shop: ShopController, style: ArtStyle) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_scenery = scenery
	_shop = shop
	_style = style
	# A buy relays to the server; a close just resumes the world.
	_shop.buy_requested.connect(_on_shop_buy)
	_shop.closed.connect(_on_shop_closed)
	Net.economy_loaded.connect(_on_economy_loaded)
	Net.purchase_succeeded.connect(_on_purchase_succeeded)
	Net.purchase_failed.connect(_on_purchase_failed)


## Adopt a new wallet balance pushed by a server reward elsewhere (hunt / maze), so the shop is current
## next time it opens. Part of the host seam — set_wallet_balance on the controller delegates here.
func set_balance(balance: int) -> void:
	_shop_balance = balance


## The wallet as we last heard it from the server — read by the wardrobe's coin badge.
func balance() -> int:
	return _shop_balance


## Spawn the merchant's bonded companion as a STATIONARY puppet beside them: a CompanionView flagged
## remote (no brain, no save, never moves), parented into the y-sorted Scenery so it depth-sorts with
## everything else, and given its resting-look from the world data. We pin its target transform to its
## standing spot so the remote-puppet ease holds it there (a remote eases toward its target, which
## would otherwise be the origin). No-op in worlds without an "npc_companion" block.
func spawn_npc(data: Dictionary) -> void:
	var npc: Dictionary = data.get("npc_companion", {})
	if npc.is_empty():
		return
	var rc := COMPANION_SCENE.instantiate() as CompanionView
	rc.set_remote()
	rc.name = "NpcCompanion"
	rc.set_style(_style)
	_scenery.add_child(rc)
	var pos := WorldData.to_vec2(npc.get("position", [0, 0]))
	rc.position = pos
	rc.set_remote_state(pos, Vector2.DOWN)
	var look: Variant = npc.get("look", {})
	if look is Dictionary:
		rc.apply_remote_look(look)
	_npc_companion = rc


## Open the merchant's colour shop. A cozy beat first — the merchant's prop pulses and your companion
## notices — then the shop window opens with the wallet + stock the server pushed on world join.
## Online-only: if the snapshot hasn't landed yet it opens empty and fills in via _on_economy_loaded.
func open_shop(entry: Dictionary) -> void:
	if _shop == null or _shop.is_open():
		return
	_world_art.pulse_interactable(int(entry["render_index"]))
	_companion.notify_interaction(entry["pos"], String(entry["id"]), entry["tags"])
	_host.show_hint("You greet %s." % entry["label"])
	_shop.open(_shop_colors, _shop_balance, _shop_currency)


## The player tapped Buy: relay it to the server (the purchase is authoritative there). The outcome
## comes back via Net.purchase_succeeded / purchase_failed.
func _on_shop_buy(item_def_id: int) -> void:
	Net.buy_color(item_def_id)


## The shop closed — clear the greeting so the world reads clean again.
func _on_shop_closed() -> void:
	if _host.hint_text().begins_with("You greet ") or _host.hint_text() == "A new colour for your wardrobe!":
		_host.set_hint_text("")


## The economy snapshot arrived on world join (per-user: our wallet + the shop's color stock). Cache
## it so the shop opens instantly; if the shop is already open when a fresh snapshot lands, refresh it.
func _on_economy_loaded(currency: String, balance: int, colors: Array) -> void:
	if currency != "":
		_shop_currency = currency
	_shop_balance = balance
	_shop_colors = colors
	if _shop != null and _shop.is_open():
		_shop.open(_shop_colors, _shop_balance, _shop_currency)


## A purchase succeeded: mark the color owned in our cached stock, adopt the new balance, reflect it
## in the open shop, and celebrate. The color is now stored to the wardrobe (server-side); making it
## show on the avatar is the deferred recolor step.
func _on_purchase_succeeded(item_def_id: int, balance: int) -> void:
	_shop_balance = balance
	for c in _shop_colors:
		if c is Dictionary and int(c.get("item_def_id", 0)) == item_def_id:
			c["owned"] = true
			break
	if _shop != null:
		_shop.apply_purchase(item_def_id, balance)
	_host.show_hint("A new colour for your wardrobe!")


## A purchase was refused: let the shop re-enable the row and surface a gentle reason.
func _on_purchase_failed(item_def_id: int, reason: String) -> void:
	if _shop != null:
		_shop.apply_failure(item_def_id, reason)
	_host.show_hint(_purchase_failure_text(reason))


func _purchase_failure_text(reason: String) -> String:
	match reason:
		"insufficient_funds":
			return "You can't quite afford that one yet."
		"already_owned":
			return "That colour is already yours."
		_:
			return "The merchant shakes their head."
