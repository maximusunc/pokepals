class_name JournalPanel
extends CozySheet
## The JOURNAL (HS-5): every place you've found something, newest first. Each entry shows the keepsake
## and the line from the moment you found it, the world it came from (with a way to go back: an
## invitation, never a gate), when, and the friends who were with you. Opened from the gear menu (your
## own), or by examining the book on its stand in a home (that home's owner's).

## The player chose to travel to a world from an entry.
signal travel_requested(world_id: String, world_name: String)

## Whose journal: "" for our own.
var owner_id := ""
var _list: VBoxContainer
var _title: Label


func _build() -> void:
	width = 360.0
	eyebrow("Journal")
	_title = heading("…")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(300.0, get_viewport_rect().size.y - 150.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	body.add_child(scroll)
	var done := CozySheet.pill("Close", close, false, 10)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(done)
	note("Opening the book…", _list)
	Net.journal_received.connect(_on_journal)
	Net.request_journal(owner_id)


func _on_journal(owner: String, owner_name: String, entries: Array) -> void:
	if owner_id != "" and owner != owner_id:
		return
	_title.text = "Your journal" if owner == Net.local_id() else "%s's journal" % owner_name
	for c in _list.get_children():
		c.queue_free()
	if entries.is_empty():
		note("Nothing written yet. Every world hides something; when you find it, it's written here.", _list)
	for e in entries:
		_list.add_child(_entry(e))


func _entry(e: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var keepsake: Dictionary = e.get("keepsake", {})
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = WorldData.to_color(keepsake.get("color", [0.7, 0.7, 0.7]))
	sb.set_corner_radius_all(999)
	dot.add_theme_stylebox_override("panel", sb)
	top.add_child(dot)
	var label := String(keepsake.get("label", "a keepsake"))
	var name_label := UiStyle.label(label.capitalize() if label == label.to_lower() else label, 10, UiStyle.INK_STRONG, 700)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var world_id := String(e.get("world_id", "")) if e.get("world_id") != null else ""
	if world_id != "" and world_id != WorldRouter.current_world:
		top.add_child(CozySheet.pill("Visit", func() -> void:
			travel_requested.emit(world_id, String(e.get("world_name", "")))
			close()))
	box.add_child(top)
	if String(e.get("found_line", "")) != "":
		note("“%s”" % String(e["found_line"]), box, UiStyle.INK_SOFT)
	var where := "Found in %s, %s" % [String(e.get("world_name", "somewhere")), JournalPanel.date_text(String(e.get("found_at", "")))]
	var with_names: Array = e.get("with", [])
	if not with_names.is_empty():
		where += ", with %s" % SecretDirector.names_phrase(with_names)
	note(where + ".", box)
	return box


## "2026-10-31" -> "31 October 2026".
static func date_text(iso: String) -> String:
	var parts := iso.split("-")
	if parts.size() != 3:
		return iso
	var months := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	var m := clampi(int(parts[1]), 1, 12)
	return "%d %s %s" % [int(parts[2]), months[m - 1], parts[0]]
