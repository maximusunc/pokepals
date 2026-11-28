class_name DevicesPanel
extends CozySheet
## Devices (issue 175), from the menu: playing as yourself on more than one device.
##   * Play on another device: Get a code, shown large with a quiet countdown and one line of how-to.
##   * Bring your companion here: type a code from your other device (LinkJoinBox), with a plain
##     warning first if this device already has a companion of its own.
##   * Your devices: each one's name, "This device" or when it was last seen, and Sign out (with a
##     confirm) on the others.
## A new device asking to join (the "Let it in?" card) is the SocialDirector's: it can arrive with this
## sheet closed. Presentation only: Net asks, the server decides.

## This device's companion is met, so joining another player here would leave it behind: ask first.
var companion_met := false

var _code_box: VBoxContainer
var _list: VBoxContainer
var _code_label: Label
var _countdown: Label
var _code_ends_ms := 0
var _shown_secs := -1


func _build() -> void:
	width = 360.0
	eyebrow("Devices")
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, minf(330.0, get_viewport_rect().size.y - 110.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(content)
	body.add_child(scroll)

	section("Play on another device", content)
	_code_box = VBoxContainer.new()
	_code_box.add_theme_constant_override("separation", 4)
	content.add_child(_code_box)
	_show_ask()

	section("Bring your companion here", content)
	note("Playing on another device already? Type the code it shows you.", content)
	var join := LinkJoinBox.new()
	join.warn_met = companion_met
	content.add_child(join)

	section("Your devices", content)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	content.add_child(_list)

	var done := CozySheet.pill("Close", close, false, 10)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(done)

	Net.devices_received.connect(_on_devices)
	Net.link_code_received.connect(_on_code)
	Net.link_failed.connect(_on_link_failed)
	set_process(false)
	_render_list()
	Net.request_devices()


# ── a code for another device ──

func _clear_code_box() -> void:
	for c in _code_box.get_children():
		c.queue_free()
	_code_label = null
	_countdown = null
	set_process(false)


func _show_ask(line := "") -> void:
	_clear_code_box()
	if line != "":
		note(line, _code_box, UiStyle.INK_STRONG)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 5)
	var words := note("Get a code here, then type it on your other device.", r)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ask := CozySheet.pill("Get a code", _ask_code, true)
	ask.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ask)
	_code_box.add_child(r)


func _ask_code() -> void:
	_clear_code_box()
	note("Getting a code…", _code_box)
	Net.request_link_code()


func _on_code(code: String, expires_in: int) -> void:
	if not is_inside_tree():
		return
	_clear_code_box()
	_code_label = UiStyle.label(DeviceLink.format(code), 24, UiStyle.INK_STRONG, 700)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_box.add_child(_code_label)
	_countdown = UiStyle.label("", 9, UiStyle.MUTED, 500)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_box.add_child(_countdown)
	var how := note("On your other device, open Menu, Devices, Enter a code.", _code_box, UiStyle.INK_SOFT)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_ends_ms = Time.get_ticks_msec() + maxi(expires_in, 1) * 1000
	_shown_secs = -1
	set_process(true)
	_tick()


## The countdown under the code: redrawn only when the second it shows changes, and only while a code
## is up (the sheet doesn't process otherwise).
func _process(_delta: float) -> void:
	_tick()


func _tick() -> void:
	if _countdown == null:
		set_process(false)
		return
	var left := float(_code_ends_ms - Time.get_ticks_msec()) / 1000.0
	if left <= 0.0:
		_show_ask("That code has run out.")
		return
	var secs := ceili(left)
	if secs != _shown_secs:
		_shown_secs = secs
		_countdown.text = "Good for %s" % DeviceLink.countdown_text(left)


func _on_link_failed(reason: String) -> void:
	if not is_inside_tree():
		return
	_show_ask(DevicesPanel.link_failed_text(reason))


static func link_failed_text(reason: String) -> String:
	if reason == "too_many":
		return "You already play on ten devices. Sign one out below, then try again."
	if reason == "expired":
		return "That device stopped waiting before you answered. Ask it to try again with a new code."
	return "That device couldn't join just now. Try again with a new code."


# ── the list ──

func _on_devices(_devices: Array) -> void:
	if is_inside_tree():
		_render_list()


func _render_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var devices := Net.devices()
	if devices.is_empty():
		note("Looking…", _list)
		return
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	for d in devices:
		if not (d is Dictionary):
			continue
		var dev := d as Dictionary
		var dev_name := String(dev.get("name", "")) if String(dev.get("name", "")) != "" else "A device"
		if bool(dev.get("current", false)):
			row(dev_name, [], _list, "This device")
		else:
			row(dev_name, [CozySheet.pill("Sign out", _confirm_sign_out.bind(dev.get("id"), dev_name))], _list,
				DeviceLink.seen_text(dev.get("last_seen_ms"), now))


func _confirm_sign_out(id: Variant, dev_name: String) -> void:
	var card := ChoiceCard.new()
	card.title = "Sign out %s?" % dev_name
	card.text = "It won't play as you any more. To bring it back, give it a new code."
	card.choices = [{ "id": "out", "label": "Sign out", "gold": true }, { "id": "", "label": "Keep it" }]
	card.default_choice = ""
	card.chosen.connect(func(choice: String) -> void:
		if choice == "out":
			Net.revoke_device(id))
	get_parent().add_child(card)
