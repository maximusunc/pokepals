extends SceneTree
## Headless smoke test for DEVICES (issue 175), with no server: loads the real World scene (the Vale)
## and feeds Net the server's words by hand. Checks:
##   * the menu offers Devices, and the sheet builds: the device list (this device; another with a
##     last-seen line and Sign out, which asks first), a code shown large with its countdown, a too-many
##     answer, and the enter-a-code piece (Join only for a whole code; a warning first when this device
##     has a companion of its own; the waiting line and Cancel);
##   * a new device asking to join brings up "Let it in?" wherever you are, Not now the easy answer;
##   * the welcome card's "Already have a companion? Enter a code" opens the enter-a-code card;
##   * the gate: playing on another device ("Play here"), signed out ("Enter a code" / "Start fresh",
##     which asks first, then makes this device someone new).
## Uses its own identity file, so the machine's real one is never touched. The sheets are reached by path,
## not class name: they speak to the Net autoload, which isn't registered yet when this script compiles.
## Run on its own:
##   godot --headless --path gates-of-elyra --script res://tests/smoke_devices.gd

const ID_PATH := "user://smoke_devices_id.json"

var _world: Node
var _net: Node
var _ident: Node
var _frames := 0
var _done := false
var _fails := 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _done:
		return true
	if _world == null:
		var router := root.get_node("/root/WorldRouter")
		_net = root.get_node("/root/Net")
		_ident = load("res://scripts/world/player_identity.gd").new()
		_ident.path = ID_PATH
		root.add_child(_ident)
		_net.identity = _ident
		_net.prime_world_spec(router.VALE_ID, WorldData.load_json("res://tests/world_fixtures/vale.json"))
		router.current_world = router.VALE_ID
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		_net.emit_signal("world_spec_unchanged", router.VALE_ID)
		return false
	if _frames == 3:
		_net.leave()   # no server here: drop the gate's connect attempt so it can't answer mid-test
	if _frames < 8:
		return false
	_done = true
	paused = false
	_check_menu()
	_check_sheet()
	_check_join_box()
	_check_link_request()
	_check_welcome_link()
	_check_gate()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ID_PATH))
	print("ALL DEVICES SMOKE CHECKS PASSED" if _fails == 0 else "DEVICES SMOKE FAILED: %d" % _fails)
	quit(_fails)
	return true


func _check(cond: bool, label: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + label)
	if not cond:
		_fails += 1


func _check_menu() -> void:
	_check(GearMenu.GRID_ORDER.has("devices") and GearMenu.ICONS.get("devices") == "devices", "the menu has a Devices tile with its icon")


func _is(n: Node, cls: String) -> bool:
	return n.get_script() != null and n.get_script().get_global_name() == cls


func _ui() -> Node:
	return _world.get_node("UI")


func _last(cls: String) -> Node:
	var found: Node = null
	for c in _ui().get_children():
		if c.get_script() != null and c.get_script().get_global_name() == cls:
			found = c
	return found


func _texts(n: Node, out: Array = []) -> Array:
	if n is Label or n is Button:
		out.append(String(n.text))
	for c in n.get_children():
		_texts(c, out)
	return out


func _has_text(n: Node, s: String) -> bool:
	for t in _texts(n):
		if String(t).contains(s):
			return true
	return false


func _button(n: Node, text: String) -> Button:
	if n is Button and String(n.text) == text and n.is_visible_in_tree():
		return n
	for c in n.get_children():
		var b := _button(c, text)
		if b != null:
			return b
	return null


func _check_sheet() -> void:
	_world._on_gear_item("devices")
	var sheet: Node = _last("DevicesPanel")
	_check(sheet != null, "Devices opens its sheet")
	if sheet == null:
		return
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	_net._dispatch("devices", { "devices": [
		{ "id": "d1", "name": "Windows PC", "last_seen_ms": now, "current": true },
		{ "id": "d2", "name": "Chrome on Android", "last_seen_ms": now - 3 * 3_600_000, "current": false },
		{ "id": "d3", "name": "iPad", "last_seen_ms": null, "current": false },
	] })
	_check(_has_text(sheet, "This device") and _has_text(sheet, "Seen 3 hours ago") and _has_text(sheet, "Not seen yet"),
		"the list says which is this device and when the others were seen")
	var signouts := 0
	for t in _texts(sheet):
		if t == "Sign out":
			signouts += 1
	_check(signouts == 2, "Sign out is offered on the other two only (%d)" % signouts)
	_button(sheet, "Sign out").pressed.emit()
	var confirm: Node = _last("ChoiceCard")
	_check(confirm != null and String(confirm.title).begins_with("Sign out Chrome on Android"), "Sign out asks first")
	if confirm != null:
		confirm.queue_free()

	_net._dispatch("link_code", { "code": "abcdefgh", "expires_in": 600 })
	_check(sheet._code_label != null and sheet._code_label.text == "ABCD-EFGH", "the code shows large, as ABCD-EFGH")
	_check(sheet._countdown != null and sheet._countdown.text.ends_with("10:00"), "with a countdown (%s)" % (sheet._countdown.text if sheet._countdown else ""))
	_check(_has_text(sheet, "On your other device, open Menu, Devices, Enter a code."), "and one line of how-to")
	_check(sheet.is_processing(), "the sheet ticks only while a code is up")
	sheet._code_ends_ms = Time.get_ticks_msec() - 1
	sheet._tick()
	_check(not sheet.is_processing() and _has_text(sheet, "That code has run out."), "a code that runs out says so and offers another")
	_net._dispatch("link_failed", { "reason": "too_many" })
	_check(_has_text(sheet, "ten devices"), "ten devices already: it says so kindly")
	sheet.close()


func _check_join_box() -> void:
	var sheet: Node = load("res://scripts/presentation/devices_panel.gd").new()
	sheet.companion_met = true
	_ui().add_child(sheet)
	var box: Node = null
	for n in sheet.find_children("*", "VBoxContainer", true, false):
		if _is(n, "LinkJoinBox"):
			box = n
	_check(box != null and box.warn_met, "the sheet's enter-a-code piece knows this device has a companion")
	if box == null:
		return
	box.set_code("abcd ef")
	_check(box._join.disabled, "Join waits for a whole code")
	box.set_code("abcd efgh")
	_check(not box._join.disabled and box._field.text == "ABCD EFGH", "a whole code, upper-cased as typed, can Join")
	box._on_join()
	_check(box._confirm.visible and not _net.is_redeeming(), "with a companion here, it asks before leaving it behind")
	box._confirm.visible = false
	_net.redeem_changed.emit("waiting")
	_check(box._status.text == "Waiting for your other device to let you in…" and box._cancel.visible, "waiting shows the line and a Cancel")
	_net.redeem_changed.emit("denied")
	_check(box._status.text.begins_with("Your other device said not now") and not box._cancel.visible, "a no is said kindly, and the wait stops")
	_net.redeem_changed.emit("invalid")
	_check(box._status.text.begins_with("That code didn't work"), "a wrong code too")
	sheet.free()


func _check_link_request() -> void:
	_net._dispatch("link_request", { "device_name": "Safari on iPhone" })
	var card: Node = _last("ChoiceCard")
	_check(card != null and String(card.title) == "Safari on iPhone wants to join you. Let it in?", "a new device asking brings up Let it in?")
	if card == null:
		return
	_check(card.modal and card.default_choice == "no", "it waits for an answer, with Not now the easy one")
	_check(_button(card, "Let it in") != null and _button(card, "Not now") != null, "Let it in / Not now")
	_net._dispatch("link_request", { "device_name": "Another" })
	var cards := 0
	for c in _ui().get_children():
		if c is ChoiceCard and not c.is_queued_for_deletion():
			cards += 1
	_check(cards == 1, "only one at a time")
	card.free()


func _check_welcome_link() -> void:
	_world._open_cards(["welcome"], true, Callable(), true)
	var panel: Node = _last("WelcomePanel")
	var link: LinkButton = null
	if panel != null:
		for n in panel.find_children("*", "LinkButton", true, false):
			link = n
	_check(link != null and link.text == "Already have a companion? Enter a code", "the welcome card offers Enter a code")
	if link == null:
		return
	link.pressed.emit()
	var join: Node = _last("LinkJoinPanel")
	_check(join != null and not join.box.warn_met, "it opens the enter-a-code card, with no warning for a newcomer")
	if join != null:
		join.free()
	panel.free()
	_world._open_cards([], false)
	panel = _last("WelcomePanel")
	_check(panel != null and panel.find_children("*", "LinkButton", true, false).is_empty(), "a reread doesn't offer it")
	if panel != null:
		panel.free()


func _check_gate() -> void:
	var lobby: Node = _world.get_node("UI/Lobby")
	lobby.visible = false   # as if we were in the world
	_net._dispatch("superseded", {})
	_check(lobby.visible and paused, "playing elsewhere brings the gate back over a frozen world")
	_check(lobby._status.text == "You're playing on another device now." and lobby._retry_button.text == "Play here"
		and not lobby._second_button.visible, "…saying so, with Play here")
	_net.disconnected.emit()   # the server then closes the socket
	_check(lobby._retry_button.text == "Play here", "the drop that follows doesn't turn it into a plain Retry")

	_net._dispatch("signed_out", {})
	_check(lobby._status.text == "This device was signed out." and lobby._retry_button.text == "Enter a code"
		and lobby._second_button.visible and lobby._second_button.text == "Start fresh", "signed out: Enter a code / Start fresh")
	lobby._on_main_pressed()
	var join: Node = null
	for c in lobby.get_children():
		if _is(c, "LinkJoinPanel"):
			join = c
	_check(join != null, "Enter a code opens the enter-a-code card on the gate")
	if join != null:
		join.free()
	lobby._on_second_pressed()
	_check(lobby._status.text.begins_with("Start fresh on this device?") and lobby._retry_button.text == "Start fresh"
		and lobby._second_button.text == "Back", "Start fresh asks first")
	lobby._on_second_pressed()
	_check(lobby._retry_button.text == "Enter a code", "Back goes back")
	lobby._on_second_pressed()
	var before := String(_ident.id())
	var changed := [false]
	_net.identity_changed.disconnect(lobby._on_identity_changed)   # don't really rebuild the world here
	_net.identity_changed.connect(func() -> void: changed[0] = true)
	lobby._on_main_pressed()
	_check(changed[0] and String(_ident.id()) != before and _net.held() == "", "Start fresh makes this device someone new")
	var saved: Dictionary = root.get_node("/root/SaveStore").load_json(ID_PATH)
	_check((saved.get("previous", []) as Array).has(before), "the old token is kept in the file, not destroyed")
