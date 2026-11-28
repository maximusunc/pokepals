class_name ItemIconView
extends Control
## An item's little picture (ItemIcon) as a Control, so it can sit in a row of a panel (the bag, the
## fishmonger's window) beside the item's name.

var key := ""
var kind := ""
var tint := Color(0.8, 0.84, 0.88)


static func make(item_key: String, item_kind: String, color: Color, px := 22.0) -> ItemIconView:
	var v := ItemIconView.new()
	v.key = item_key
	v.kind = item_kind
	v.tint = color
	v.custom_minimum_size = Vector2(px, px)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _draw() -> void:
	ItemIcon.draw(self, key, kind, size * 0.5, minf(size.x, size.y), tint)
