extends SceneTree
## Dev tool: play the whole DEVICES flow (issue 175) against a REAL server, with two devices in one
## process. Needs a running, seeded server (see server/README.md):
##   godot --headless --path gates-of-elyra --script res://tests/e2e_devices.gd -- ws://127.0.0.1:4000/ws
## Each device is its own Net (the real script) speaking for its own PlayerIdentity, kept in its own
## scratch file (the machine's real identity is never touched). No world scene is built: only the link.
##   1. device A connects (a ticket first, then the socket) and joins the Vale; asks for a code
##   2. device B, a different new player, redeems it; A is asked "Let it in?" and allows
##   3. B adopts its new token, reconnects, and is A's player (same id, same friend code)
##   4. A is told it's playing on another device now, and its socket closes (no reconnect)
##   5. B lists the devices (two) and signs A out; A's next connect is turned away: signed out
## Not part of the headless suite (it needs the server).

const VALE_ID := "11111111-1111-1111-1111-111111111111"
const STEP_TIMEOUT_MS := 20000

var _url := "ws://127.0.0.1:4000/ws"
var _a: Node
var _b: Node
var _steps: Array = []
var _step_started := 0
var _fails := 0
var _started := false
# What the devices heard, by event.
var _heard := {}
var _a_id := ""
var _a_code := ""
var _b_first_id := ""
var _link_code := ""


func _process(_delta: float) -> bool:
	paused = false
	if not _started:
		_started = true
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_url = args[0]
		_a = _device("a")
		_b = _device("b")
		_plan()
		_step_started = Time.get_ticks_msec()
		return false
	if _steps.is_empty():
		_finish()
		return true
	var step: Array = _steps[0]
	if (step[1] as Callable).call():
		_steps.pop_front()
		_step_started = Time.get_ticks_msec()
		if String(step[0]) != "":
			print("  PASS  ", step[0])
		(step[2] as Callable).call()
	elif Time.get_ticks_msec() - _step_started > STEP_TIMEOUT_MS:
		print("  FAIL  (timed out) ", step[0])
		print("    A heard: ", _heard["a"].keys(), "  held: ", _a.held(), "  active: ", _a.is_active())
		print("    B heard: ", _heard["b"].keys())
		_fails += 1
		_steps.clear()
	return false


func _finish() -> void:
	for who in ["a", "b"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://e2e_devices_%s.json" % who))
	print("ALL DEVICES E2E CHECKS PASSED" if _fails == 0 else "DEVICES E2E FAILED: %d" % _fails)
	quit(0 if _fails == 0 else 1)


## A device: a fresh identity in its own file, and a Net speaking for it. Everything it hears is noted.
func _device(who: String) -> Node:
	var path := "user://e2e_devices_%s.json" % who
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var ident: Node = load("res://scripts/world/player_identity.gd").new()
	ident.path = path
	ident.name = "Identity_" + who
	root.add_child(ident)
	var net: Node = load("res://scripts/net/net.gd").new()
	net.identity = ident
	net.name = "Net_" + who
	root.add_child(net)
	_heard[who] = {}
	var note := func(event: String, value: Variant = true) -> void: _heard[who][event] = value
	net.connected.connect(func() -> void:
		note.call("connected")
		net.enter_world(VALE_ID))
	net.connection_failed.connect(func() -> void: note.call("connection_failed"))
	net.disconnected.connect(func() -> void: note.call("disconnected"))
	net.relocate_requested.connect(func(wid: String) -> void: net.enter_world(wid))
	net.profile_received.connect(func(n: String, c: String) -> void: note.call("profile", [n, c]))
	net.link_code_received.connect(func(code: String, secs: int) -> void: note.call("link_code", [code, secs]))
	net.link_requested.connect(func(dn: String) -> void: note.call("link_request", dn))
	net.link_failed.connect(func(r: String) -> void: note.call("link_failed", r))
	net.devices_received.connect(func(ds: Array) -> void: note.call("devices", ds))
	net.superseded.connect(func() -> void: note.call("superseded"))
	net.signed_out.connect(func() -> void: note.call("signed_out"))
	net.redeem_changed.connect(func(s: String) -> void: note.call("redeem", s))
	net.identity_changed.connect(func() -> void: note.call("identity_changed"))
	return net


func _has(who: String, event: String) -> bool:
	return _heard[who].has(event)


func _forget(who: String, events: Array) -> void:
	for e in events:
		_heard[who].erase(e)


func _step(label: String, cond: Callable, then: Callable = func() -> void: pass) -> void:
	_steps.append([label, cond, then])


func _expect(cond: bool, label: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + label)
	if not cond:
		_fails += 1


func _plan() -> void:
	_step("", func() -> bool: return true, func() -> void: _a.connect_to(_url))
	_step("device A fetched a ticket, opened the socket and joined the Vale", func() -> bool:
		return _a.local_id() != "" and _has("a", "profile"), func() -> void:
			_a_id = _a.local_id()
			_a_code = String(_heard["a"]["profile"][1])
			print("    A is %s, friend code %s" % [_a_id, _a_code])
			_expect(not String(_a._socket_url(_url, "x")).contains(String(_a.identity.id())), "the socket address carries no device token")
			_b.connect_to(_url))
	_step("device B joined too, as someone else", func() -> bool: return _b.local_id() != "", func() -> void:
		_b_first_id = _b.local_id()
		_expect(_b_first_id != _a_id, "B starts as a different player")
		_a.request_link_code())
	_step("A was given a code", func() -> bool: return _has("a", "link_code"), func() -> void:
		_link_code = String(_heard["a"]["link_code"][0])
		print("    code %s, good for %ds" % [DeviceLink.format(_link_code), int(_heard["a"]["link_code"][1])])
		_expect(DeviceLink.is_complete(_link_code), "the code is 8 characters")
		# typed the way a person might: lower case, with a space
		_b.start_redeem(DeviceLink.format(_link_code).to_lower().replace("-", " ")))
	_step("B is waiting for A to let it in", func() -> bool: return _b.redeem_state() in ["waiting", "sending"])
	_step("A is asked whether to let B in", func() -> bool: return _has("a", "link_request"), func() -> void:
		print("    asked about: ", _heard["a"]["link_request"])
		_a.answer_link(true))
	_step("B was let in and became A's player on this device", func() -> bool: return _has("b", "identity_changed"), func() -> void:
		_expect(_b.redeem_state() == "linked", "the redeem says linked")
		var saved := FileAccess.get_file_as_string(ProjectSettings.globalize_path("user://e2e_devices_b.json"))
		_expect(saved.contains("previous"), "B's old token was kept in its file")
		_b.connect_to(_url))
	_step("B reconnected as A's player (same id, same friend code)", func() -> bool:
		return _b.local_id() != "" and _has("b", "profile") and String(_heard["b"]["profile"][1]) == _a_code and _b.local_id() == _a_id)
	_step("A's socket was closed by the server", func() -> bool: return _has("a", "disconnected") and not _a.is_active(), func() -> void:
		_expect(_has("a", "superseded") and _a.held() == "superseded", "A was told it's playing on another device now (held: '%s')" % _a.held())
		_forget("b", ["devices"])
		_b.request_devices())
	_step("B lists two devices, one of them itself", func() -> bool:
		if not _has("b", "devices"):
			return false
		var ds: Array = _heard["b"]["devices"]
		return ds.size() == 2 and ds.filter(func(d: Dictionary) -> bool: return bool(d.get("current", false))).size() == 1, func() -> void:
			var other: Dictionary = (_heard["b"]["devices"] as Array).filter(func(d: Dictionary) -> bool: return not bool(d.get("current", false)))[0]
			print("    signing out ", other.get("name"), " (", other.get("id"), ")")
			_forget("b", ["devices"])
			_b.revoke_device(other.get("id")))
	_step("B's list shrinks to one", func() -> bool:
		return _has("b", "devices") and (_heard["b"]["devices"] as Array).size() == 1, func() -> void:
			_forget("a", ["signed_out", "connected"])
			_a.connect_to(_url))
	_step("A's next connect is turned away: signed out", func() -> bool: return _has("a", "signed_out") and _a.held() == "signed_out", func() -> void:
		_expect(not _has("a", "connected"), "A never reached the socket"))
