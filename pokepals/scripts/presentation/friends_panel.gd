class_name FriendsPanel
extends CozySheet
## Friends (FR-0..FR-5), from the gear menu: who you are (your generated name, with a New name button,
## and your friend code), adding someone by their code, requests waiting for you (Accept / Not now /
## Block), your friends (whether they're home or playing; Remove / Block), and the switch that closes
## your home to visitors. It reads Net's snapshot and re-draws whenever the server sends a fresh one, so
## it's never out of date while it's open.

var _content: VBoxContainer
var _code_field: LineEdit
var _result: Label


func _build() -> void:
	width = 360.0
	eyebrow("Friends")
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(330.0, get_viewport_rect().size.y - 150.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	body.add_child(scroll)
	var done := CozySheet.pill("Close", close, false, 10)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(done)
	Net.friends_received.connect(func(_s: Dictionary) -> void: _render())
	Net.profile_received.connect(func(_n: String, _c: String) -> void: _render())
	Net.friend_result.connect(_on_friend_result)
	_render()
	Net.request_friends()


func _render() -> void:
	var typed := _code_field.text if _code_field != null else ""
	var result_text := _result.text if _result != null else ""
	for c in _content.get_children():
		c.queue_free()
	var snap := Net.friends_snapshot()

	# Who you are.
	section("You", _content)
	row(Net.my_name() if Net.my_name() != "" else "…", [CozySheet.pill("New name", Net.reroll_name)], _content,
		"Your friend code: %s" % Net.friend_code())

	# Add by code.
	section("Add a friend by code", _content)
	var add := HBoxContainer.new()
	add.add_theme_constant_override("separation", 5)
	_code_field = CozySheet.field("Their friend code")
	_code_field.text = typed
	_code_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_field.text_submitted.connect(func(_t: String) -> void: _send_code())
	add.add_child(_code_field)
	add.add_child(CozySheet.pill("Ask", _send_code, true))
	_content.add_child(add)
	_result = note(result_text, _content)

	# Requests waiting for you.
	var incoming: Array = snap.get("incoming", [])
	if not incoming.is_empty():
		section("Waiting for you", _content)
		for r in incoming:
			var id := String(r["id"])
			row(String(r["name"]), [
				CozySheet.pill("Accept", Net.accept_friend.bind(id), true),
				CozySheet.pill("Not now", Net.decline_friend.bind(id)),
				CozySheet.pill("Block", Net.block_player.bind(id)),
			], _content, "would like to be friends")

	# Your friends.
	section("Your friends", _content)
	var friends: Array = snap.get("friends", [])
	if friends.is_empty():
		note("No friends yet. Tap someone you meet, or share your code.", _content)
	for f in friends:
		var id := String(f["id"])
		row(String(f["name"]), [
			CozySheet.pill("Remove", Net.remove_friend.bind(id)),
			CozySheet.pill("Block", Net.block_player.bind(id)),
		], _content, FriendsPanel.status_text(f))

	# Your home.
	section("Your home", _content)
	var closed_toggle := CheckButton.new()
	closed_toggle.text = "Closed to visitors"
	closed_toggle.focus_mode = Control.FOCUS_NONE
	UiStyle.set_font(closed_toggle, 600, 10)
	closed_toggle.add_theme_color_override("font_color", UiStyle.INK_STRONG)
	closed_toggle.set_pressed_no_signal(bool(snap.get("home_closed", false)))
	closed_toggle.toggled.connect(Net.set_home_closed)
	_content.add_child(closed_toggle)
	note("Friends can visit your home any time, even while you're away. Closing it pauses every visit.", _content)


## "In their home", "Playing", or "Away": how a friend is right now.
static func status_text(f: Dictionary) -> String:
	if bool(f.get("home_now", false)):
		return "In their home"
	if bool(f.get("online", false)):
		return "Playing"
	return "Away"


func _send_code() -> void:
	var code := _code_field.text.strip_edges()
	if code == "":
		return
	Net.request_friend_by_code(code)
	_result.text = "Asking…"


func _on_friend_result(r: Dictionary) -> void:
	if _result == null:
		return
	if bool(r.get("ok", false)):
		_code_field.text = ""
		_result.text = ("You and %s are friends now." if String(r.get("status", "")) == "friends" \
			else "Asked %s. They'll see it next time they look.") % String(r.get("name", "them"))
	else:
		_result.text = FriendsPanel.reason_text(String(r.get("reason", "")))


static func reason_text(reason: String) -> String:
	match reason:
		"no_such_code": return "No one has that code."
		"self": return "That's your own code."
		"already_friends": return "You're already friends."
		_: return "That didn't go through."
