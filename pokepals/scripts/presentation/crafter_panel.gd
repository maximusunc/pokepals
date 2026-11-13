class_name CrafterPanel
extends CozySheet
## The TINKER's window (usable items, crafting; docs/usable-items-design.md): the crafter in the bazaar. For
## each thing she can make (the recipes the server pushed on join, Net.recipes): what it is, what it takes
## (each material with how many you have of how many it needs, ticked off when you have enough), her fee
## against your coins, and a Craft button when you have it all. The craft is the server's (Server.Crafting):
## we ask, and the window refreshes from the inventory it sends back.

## The host world, for the wallet (set_wallet_balance) and the hint line.
var host: Node
var balance := 0

var _list: VBoxContainer
var _coins: Label
var _busy := false


func _build() -> void:
	width = 320.0
	eyebrow("The tinker")
	heading("\"What shall we make?\"")
	_coins = note("", null, UiStyle.LABEL_BROWN)
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	body.add_child(_list)
	var done := CozySheet.pill("Done", close, false, 10)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(done)
	Net.inventory_received.connect(func(_items: Array) -> void: _fill())
	Net.recipes_received.connect(func(_r: Array) -> void: _fill())
	Net.crafted.connect(_on_crafted)
	Net.craft_failed.connect(_on_failed)
	_fill()


func _have(item_def_id: int) -> int:
	var n := 0
	for it in Net.inventory():
		if it is Dictionary and int((it as Dictionary).get("item_def_id", 0)) == item_def_id:
			n += int((it as Dictionary).get("quantity", 0))
	return n


func _fill() -> void:
	_coins.text = "You have %d coins." % balance
	for c in _list.get_children():
		c.queue_free()
	var recipes := Net.recipes()
	if recipes.is_empty():
		note("\"Nothing on the bench just now.\"", _list)
		return
	for r in recipes:
		if r is Dictionary:
			_recipe(r)


func _recipe(r: Dictionary) -> void:
	var makes: Dictionary = r.get("makes", {})
	var fee := int(r.get("fee", 0))
	var can_make := balance >= fee
	var needs_box := VBoxContainer.new()
	needs_box.add_theme_constant_override("separation", 2)
	for n in r.get("needs", []):
		if not (n is Dictionary):
			continue
		var have := _have(int(n.get("item_def_id", 0)))
		var need := int(n.get("quantity", 1))
		can_make = can_make and have >= need
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 5)
		line.add_child(ItemIconView.make(String(n.get("key", "")), String(n.get("category", "")), FishingDirector.color_of(n.get("color")), 16.0))
		var mark := "✓" if have >= need else "·"
		var col := UiStyle.INK_STRONG if have >= need else UiStyle.MUTED
		line.add_child(UiStyle.label("%s  %s  (%d of %d)" % [mark, String(n.get("name", "")), mini(have, need), need], 9, col, 600))
		needs_box.add_child(line)
	var fee_col := UiStyle.INK_STRONG if balance >= fee else UiStyle.MUTED
	needs_box.add_child(UiStyle.label("%s  %d coins for the tinker" % ["✓" if balance >= fee else "·", fee], 9, fee_col, 600))
	var id := String(r.get("id", ""))
	var craft := CozySheet.pill("Craft", func() -> void: _craft(id), true, 10)
	craft.disabled = not can_make
	var head := BagPanel.item_row({ "key": makes.get("key", ""), "category": makes.get("category", ""), "color": makes.get("color"),
		"name": makes.get("name", "something"), "quantity": 1 }, [craft], String(r.get("line", "")))
	_list.add_child(head)
	_list.add_child(needs_box)


func _craft(recipe_id: String) -> void:
	if _busy:
		return
	_busy = true
	Net.craft(recipe_id)


func _on_crafted(item: Dictionary) -> void:
	_busy = false
	balance = int(item.get("balance", balance))
	if host != null:
		host.set_wallet_balance(balance)
		host.show_hint("The tinker hands you a %s. It's on your hotbar." % String(item.get("name", "something")).to_lower())
	_fill()


func _on_failed(reason: String) -> void:
	_busy = false
	if host == null:
		return
	match reason:
		"not_enough":
			host.show_hint("\"You're a little short of the makings, friend.\"")
		"insufficient_funds":
			host.show_hint("\"Ten coins for my trouble, when you have them.\"")
		"not_at_crafter":
			host.show_hint("Step up to the tinker's stall to craft.")
		_:
			host.show_hint("\"Hm, something's off. Try again?\"")
