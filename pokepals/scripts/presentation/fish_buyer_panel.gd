class_name FishBuyerPanel
extends CozySheet
## The FISHMONGER's window (usable items, step 2; docs/usable-items-design.md): the fish buyer in the bazaar.
## Lists what you carry that they'll buy (common fish and reeled-up odds and ends) with what they pay, and
## sells one, or all of a kind. Rare fish are listed too, so you can see why they're not taken: they're for
## keeping. The sale is the server's (Economy.sell): we ask, and the list refreshes from the inventory it
## sends back, with the new balance in the coin line.

## The host world, for the wallet (set_wallet_balance) and the hint line.
var host: Node
var balance := 0

var _list: VBoxContainer
var _coins: Label
var _busy := false


func _build() -> void:
	width = 320.0
	eyebrow("The fishmonger")
	heading("\"Let's see what you've got.\"")
	_coins = note("", null, UiStyle.LABEL_BROWN)
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(220.0, get_viewport_rect().size.y - 170.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_list)
	body.add_child(scroll)
	var done := CozySheet.pill("Done", close, false, 10)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(done)
	Net.inventory_received.connect(_fill)
	Net.sold.connect(_on_sold)
	Net.sell_failed.connect(_on_sell_failed)
	_show_balance()
	_fill(Net.inventory())


func _show_balance() -> void:
	_coins.text = "You have %d coins." % balance


func _fill(items: Array) -> void:
	_busy = false
	for c in _list.get_children():
		c.queue_free()
	var sellable := 0
	var rare: Array = []
	for it in items:
		if not (it is Dictionary):
			continue
		var d: Dictionary = it
		var cat := String(d.get("category", ""))
		var qty := int(d.get("quantity", 0))
		if qty <= 0:
			continue
		if cat == "rare_fish":
			rare.append(d)
			continue
		if not (cat in ["fish", "material"]) or not (d.get("sell") is float or d.get("sell") is int):
			continue
		var price := int(d["sell"])
		var id := int(d.get("item_def_id", 0))
		var buttons: Array = [CozySheet.pill("Sell 1", func() -> void: _sell(id, 1), false, 9)]
		if qty > 1:
			buttons.append(CozySheet.pill("Sell all (%d)" % (price * qty), func() -> void: _sell(id, 0), true, 9))
		_list.add_child(BagPanel.item_row(d, buttons, "%d %s each" % [price, "coin" if price == 1 else "coins"]))
		sellable += 1
	if sellable == 0:
		note("Nothing to sell just now. Catch a few fish and come back!", _list)
	if not rare.is_empty():
		section("Yours to keep", _list)
		for d in rare:
			_list.add_child(BagPanel.item_row(d, [], "Too fine for the barrel: a tank at home"))


## Sell `quantity` of an item (0 = all of it).
func _sell(item_def_id: int, quantity: int) -> void:
	if _busy:
		return
	_busy = true
	Net.sell(item_def_id, quantity)


func _on_sold(_item_def_id: int, quantity: int, coins: int, new_balance: int) -> void:
	balance = new_balance
	_show_balance()
	if host != null:
		host.set_wallet_balance(new_balance)
		host.show_hint("Sold %d for %d %s." % [quantity, coins, "coin" if coins == 1 else "coins"])


func _on_sell_failed(reason: String) -> void:
	_busy = false
	if host == null:
		return
	match reason:
		"not_at_buyer":
			host.show_hint("Step up to the fishmonger's stall to sell.")
		"not_bought_here":
			host.show_hint("\"Not that one, friend. Keep it.\"")
		_:
			host.show_hint("\"Hm, something's off. Try again?\"")
