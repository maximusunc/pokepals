class_name TankPanel
extends CozySheet
## The fish TANK's window (usable items, step 3; docs/usable-items-design.md), opened by examining the tank at
## home. For the home's owner: the fish swimming in it, each with "Take out", and the rare fish you carry,
## each with "Put in" while there's room. For a visitor: just what's swimming there. Changes are the server's
## (Server.Tank): we ask, and the window refreshes from the tank and the inventory it sends back.

var owner_mine := true      # is this our own tank?
var owner_name := ""
var capacity := 3
var fish: Array = []        # what's in the tank now: [{ item_def_id, key, name, color }]

var _list: VBoxContainer
var _busy := false


func _build() -> void:
	width = 300.0
	eyebrow("Fish tank")
	heading("Your tank" if owner_mine else ("%s's tank" % owner_name if owner_name != "" else "A fish tank"))
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	body.add_child(_list)
	var done := CozySheet.pill("Done", close, false, 10)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(done)
	Net.tank_received.connect(_on_tank)
	Net.inventory_received.connect(func(_items: Array) -> void: _fill())
	Net.tank_failed.connect(func(_reason: String) -> void:
		_busy = false
		_fill())
	_fill()


func _on_tank(_owner: String, new_fish: Array) -> void:
	fish = new_fish
	_busy = false
	_fill()


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	section("Swimming (%d of %d)" % [fish.size(), capacity], _list)
	if fish.is_empty():
		note("Nothing swimming yet." + (" Rare fish you catch can live here." if owner_mine else ""), _list)
	for i in fish.size():
		var f: Dictionary = fish[i]
		var row_item := { "key": f.get("key", ""), "category": "rare_fish", "color": f.get("color"), "name": f.get("name", "a fish"), "quantity": 1 }
		var buttons: Array = []
		if owner_mine:
			var index := i
			buttons.append(CozySheet.pill("Take out", func() -> void: _take(index), false, 9))
		_list.add_child(BagPanel.item_row(row_item, buttons))
	if not owner_mine:
		return
	section("Your rare fish", _list)
	var any := false
	for it in Net.inventory():
		if not (it is Dictionary) or String((it as Dictionary).get("category", "")) != "rare_fish" or int((it as Dictionary).get("quantity", 0)) <= 0:
			continue
		any = true
		var id := int((it as Dictionary).get("item_def_id", 0))
		var buttons: Array = []
		if fish.size() < capacity:
			buttons.append(CozySheet.pill("Put in", func() -> void: _put(id), true, 9))
		_list.add_child(BagPanel.item_row(it, buttons))
	if not any:
		note("You're not carrying any rare fish. They're rare, but they're out there.", _list)
	elif fish.size() >= capacity:
		note("The tank is full. Take one out to make room.", _list)


func _put(item_def_id: int) -> void:
	if _busy:
		return
	_busy = true
	Net.tank_put(item_def_id)


func _take(index: int) -> void:
	if _busy:
		return
	_busy = true
	Net.tank_take(index)
