class_name BagPanel
extends CozySheet
## The BAG (usable items; docs/usable-items-design.md): everything you carry, with how many of each,
## grouped by what it is: tools, fish, rare fish, and odds and ends you've reeled up. Opened from the gear
## menu. Read-only for now (rearranging the hotbar comes once there's more than one tool to arrange).
## Fills from what the server last told us (Net.inventory) and refreshes when that changes.

const GROUPS := [
	["tool", "Tools"],
	["fish", "Fish"],
	["rare_fish", "Rare fish"],
	["material", "Odds and ends"],
]

var _list: VBoxContainer


func _build() -> void:
	width = 300.0
	eyebrow("Bag")
	heading("What you carry")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(240.0, get_viewport_rect().size.y - 150.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	body.add_child(scroll)
	var done := CozySheet.pill("Close", close, false, 10)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(done)
	Net.inventory_received.connect(_fill)
	_fill(Net.inventory())


func _fill(items: Array) -> void:
	for c in _list.get_children():
		c.queue_free()
	var any := false
	for g in GROUPS:
		var rows: Array = []
		for it in items:
			if it is Dictionary and String((it as Dictionary).get("category", "")) == String(g[0]) and int((it as Dictionary).get("quantity", 0)) > 0:
				rows.append(it)
		if rows.is_empty():
			continue
		any = true
		section(String(g[1]), _list)
		for it in rows:
			_list.add_child(item_row(it))
	if not any:
		note("Nothing yet. There's a fishing rod on a post by the little pond in the Vale.", _list)


## One item: its picture, its name, and how many.
static func item_row(it: Dictionary, buttons: Array = [], sub := "") -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	r.add_child(ItemIconView.make(String(it.get("key", "")), String(it.get("category", "")), FishingDirector.color_of(it.get("color"))))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	var qty := int(it.get("quantity", 0))
	var name_label := UiStyle.label(String(it.get("name", "something")) + ("  x%d" % qty if qty > 1 else ""), 10, UiStyle.INK_STRONG, 700)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	words.add_child(name_label)
	if sub != "":
		words.add_child(UiStyle.label(sub, 8, UiStyle.MUTED, 500))
	r.add_child(words)
	for b in buttons:
		(b as Button).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(b)
	return r
