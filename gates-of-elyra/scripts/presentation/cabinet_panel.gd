class_name CabinetPanel
extends CozySheet
## The CURIO CABINET in your house (home building; docs/usable-items-design.md "Home building"): every find
## you've ever made, whatever is on show. The house shows a curated few (your companion's keepsakes on the
## plinths, the newest of the rest on the shelves), so nothing you've found is ever out of reach: it's all in
## here, newest first, each with its line and where it is ("by the fire", "on a shelf", or in the cabinet).
## Read-only. Opened by HouseDirector.open_cabinet; a friend's cabinet can be looked in too.

## The home's finds as the spec carries them ([{ id, label, type, color, line }], oldest first).
var finds: Array = []
## Which finds are on show, and where: id -> "keepsake" | "shelf".
var on_show: Dictionary = {}
## Whose cabinet ("" = yours).
var owner_name := ""

var _list: VBoxContainer


func _build() -> void:
	width = 320.0
	eyebrow("The curio cabinet")
	heading("Everything you've found" if owner_name == "" else "Everything %s has found" % owner_name)
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
	_fill()


func _fill() -> void:
	if finds.is_empty():
		note("Empty, for now. Every world hides one secret; whatever you find will be kept here.", _list)
		return
	var newest := finds.duplicate()
	newest.reverse()
	for f in newest:
		if not (f is Dictionary):
			continue
		var id := String(f.get("id", ""))
		var where := "In the cabinet"
		match String(on_show.get(id, "")):
			"keepsake":
				where = "On show: a keepsake"
			"shelf":
				where = "On show: on a shelf"
		_list.add_child(BagPanel.item_row({
			"key": String(f.get("type", "")), "category": "", "color": f.get("color"),
			"name": _sentence(String(f.get("label", "something"))),
		}, [], where))
		var line := String(f.get("line", ""))
		if line != "":
			note(line, _list)


static func _sentence(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s
