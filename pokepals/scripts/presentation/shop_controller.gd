class_name ShopController
extends Control
## The bazaar shop window: buy COLORS for your wardrobe from the merchant. A thin PRESENTATION
## surface over the Net economy seam — it shows the shop's stock + your wallet, lets you tap Buy,
## and reflects what the SERVER decides. It never moves currency or grants anything itself: the
## purchase is server-authoritative (Economy.purchase: sink + grant, atomic, ledgered). The world
## controller wires this panel's signals to Net and feeds it the economy snapshot.
##
## A bought color is recorded as OWNED (the persisted "choice"); making the color actually appear
## on the avatar is a deliberately deferred next step (the recolor shader), so a purchased swatch
## reads here as "Owned" rather than changing how you look — yet.

## The player tapped Buy on a color. The world controller relays this to Net.buy_color(id).
signal buy_requested(item_def_id: int)
## The player closed the shop (Close button / Examine again). The world hides the panel + resumes.
signal closed()

@onready var _title: Label = $Panel/Box/Title
@onready var _balance_label: Label = $Panel/Box/Balance
@onready var _list: VBoxContainer = $Panel/Box/Scroll/List
@onready var _close_button: Button = $Panel/Box/CloseButton

var _currency := "coins"
var _balance := 0
# item_def_id -> { price:int, owned:bool, button:Button, status:Label }
var _rows: Dictionary = {}


func _ready() -> void:
	visible = false
	_close_button.pressed.connect(close)


func is_open() -> bool:
	return visible


## Open the shop with the current stock + wallet, rebuilding the color list.
func open(colors: Array, balance: int, currency: String) -> void:
	_currency = currency if currency != "" else "coins"
	_balance = balance
	_rebuild(colors)
	_update_balance_label()
	visible = true


## Hide the shop and tell the world to resume.
func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## The server confirmed a purchase: adopt the new balance and mark the color owned.
func apply_purchase(item_def_id: int, balance: int) -> void:
	_balance = balance
	_update_balance_label()
	if _rows.has(item_def_id):
		_set_owned(item_def_id)
	_refresh_affordability()


## A purchase was refused: re-enable the row so the player can try something else.
func apply_failure(item_def_id: int, _reason: String) -> void:
	_refresh_affordability()


## Refresh just the wallet (e.g. a fresh economy snapshot landed while the shop is open).
func set_balance(balance: int) -> void:
	_balance = balance
	_update_balance_label()
	_refresh_affordability()


# --- internals -------------------------------------------------------------------------

func _rebuild(colors: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	_rows.clear()
	for c in colors:
		if c is Dictionary:
			_add_row(c)


## Build one color row: swatch · name · price · Buy (or "Owned"). Stashes the row's controls so
## affordability/ownership can be refreshed without rebuilding the whole list.
func _add_row(color: Dictionary) -> void:
	var item_def_id := int(color.get("item_def_id", 0))
	if item_def_id == 0:
		return
	var price := int(color.get("price", 0))
	var owned := bool(color.get("owned", false))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(26, 26)
	swatch.color = _swatch_color(color.get("swatch", []))
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = String(color.get("name", "a colour"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var price_label := Label.new()
	price_label.text = "%d %s" % [price, _currency]
	price_label.custom_minimum_size = Vector2(84, 0)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price_label)

	var status := Label.new()
	status.custom_minimum_size = Vector2(64, 0)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.visible = false
	row.add_child(status)

	var buy := Button.new()
	buy.text = "Buy"
	buy.custom_minimum_size = Vector2(64, 0)
	buy.pressed.connect(_on_buy_pressed.bind(item_def_id))
	row.add_child(buy)

	_list.add_child(row)
	_rows[item_def_id] = { "price": price, "owned": owned, "button": buy, "status": status }
	if owned:
		_set_owned(item_def_id)
	else:
		_refresh_row_affordability(item_def_id)


func _on_buy_pressed(item_def_id: int) -> void:
	if not _rows.has(item_def_id):
		return
	var r: Dictionary = _rows[item_def_id]
	if bool(r["owned"]):
		return
	# Optimistically disable the button so a double-tap can't fire two buys; the server's reply
	# (apply_purchase / apply_failure) settles the row.
	(r["button"] as Button).disabled = true
	buy_requested.emit(item_def_id)


func _set_owned(item_def_id: int) -> void:
	var r: Dictionary = _rows[item_def_id]
	r["owned"] = true
	var buy := r["button"] as Button
	buy.visible = false
	var status := r["status"] as Label
	status.text = "Owned"
	status.visible = true


func _refresh_affordability() -> void:
	for id in _rows:
		if not bool(_rows[id]["owned"]):
			_refresh_row_affordability(int(id))


## Enable Buy only when the color is affordable; a too-dear color shows a disabled button so the
## price still reads but the tap can't fire.
func _refresh_row_affordability(item_def_id: int) -> void:
	var r: Dictionary = _rows[item_def_id]
	var buy := r["button"] as Button
	buy.disabled = int(r["price"]) > _balance


func _update_balance_label() -> void:
	_balance_label.text = "Your purse:  %d %s" % [_balance, _currency]


func _swatch_color(swatch: Variant) -> Color:
	if swatch is Array and (swatch as Array).size() >= 3:
		return Color(float(swatch[0]), float(swatch[1]), float(swatch[2]))
	return Color(0.8, 0.8, 0.8)
