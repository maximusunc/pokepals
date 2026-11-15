extends SceneTree
## Headless smoke test for the CARPENTER (home building; docs/usable-items-design.md "Home building"): loads
## the real World scene in the Bazaar and plays the server's side by hand through Net. Finds the carpenter;
## her window shows what she asks (100 wood, 300 coins) against what you have, Build my house waiting until you
## have it all; her answer (the server's) pays her and turns the window to how the build is going; and the
## tinker now makes an axe too. Run on its own:
##   godot --headless --path pokepals --script res://tests/smoke_carpenter.gd

var _world: Node
var _net: Node
var _frames := 0
var _step := 0
var _fails := 0


func _ok(cond: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fails += 1


func _build() -> void:
	var router := root.get_node("/root/WorldRouter")
	_net = root.get_node("/root/Net")
	router.current_world = router.BAZAAR_ID
	router.arrival_portal_id = "bazaar_entry"
	router.pending_transition = true
	_net.prime_world_spec(router.BAZAAR_ID, WorldData.load_json("res://tests/world_fixtures/bazaar.json"))
	_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	_net.emit_signal("world_spec_unchanged", router.BAZAAR_ID)
	paused = false


func _wood(n: int) -> Dictionary:
	return { "items": [{ "item_def_id": 244, "name": "Wood", "category": "material", "key": "wood", "quantity": n }] }


func _panel(script_file: String) -> Node:
	var found: Node = null
	for c in _world.get_node("UI").get_children():
		var sc: Variant = c.get_script()
		if sc != null and String((sc as Script).resource_path).ends_with(script_file):
			found = c
	return found


func _texts(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append("[%s]" % (c as Button).text)
		_texts(c, out)
	return out


func _button(n: Node, text: String) -> Button:
	if n == null:
		return null
	for c in n.get_children():
		if c is Button and (c as Button).text == text:
			return c
		var b := _button(c, text)
		if b != null:
			return b
	return null


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		_build()
		return false
	if _frames < 6:
		return false
	if _frames > 2000:
		print("CARPENTER SMOKE FAILED: timed out at step %d" % _step)
		quit(1)
		return true
	match _step:
		0:
			print("SmokeCarpenter")
			var carpenter: Dictionary = {}
			for e in _world._interactables:
				if String(e.get("builds", "")) == "house":
					carpenter = e
			_ok(not carpenter.is_empty(), "the Bazaar has a carpenter to examine")
			_ok(_world.get_node_or_null("Scenery/StandingPerson_holder_8") != null, "she stands at her stall as a person")
			_net._dispatch("economy", { "currency": "coins", "balance": 500, "colors": [] })
			_net._dispatch("house", { "state": "none", "left_ms": 0, "build_ms": 600000, "wood": 100, "coins": 300 })
			_net._dispatch("inventory", _wood(40))
			_world._player.set_process(false)
			_world._player.position = carpenter["pos"] + Vector2(0, -16)
			_world._invalidate_nearest()
			_world._try_interact()
			_step = 1
		1:
			var p := _panel("carpenter_panel.gd")
			_ok(p != null, "examining her opens her window")
			var t := _texts(p) if p != null else []
			_ok(t.has("·  Wood  (40 of 100)") and t.has("✓  300 coins  (you have 500)"), "it shows the wood and coins she asks against what you have")
			_ok(_button(p, "Build my house") != null and _button(p, "Build my house").disabled, "short of wood: Build my house waits")
			_ok(" ".join(t).contains("axe"), "and it tells you where wood comes from")
			_net._dispatch("inventory", _wood(100))
			_step = 2
		2:
			var p := _panel("carpenter_panel.gd")
			_ok(_button(p, "Build my house") != null and not _button(p, "Build my house").disabled, "with 100 wood: it's ready")
			_net._dispatch("house_commissioned", { "house": { "state": "building", "left_ms": 600000, "build_ms": 600000, "wood": 100, "coins": 300 }, "balance": 200, "currency": "coins" })
			_net._dispatch("inventory", _wood(0))
			_step = 3
		3:
			var p := _panel("carpenter_panel.gd")
			var t := " ".join(_texts(p)) if p != null else ""
			_ok(_world._shop_dir.balance() == 200, "she's paid")
			_ok(t.contains("10 minutes") and _button(p, "Build my house") == null, "her window says the build is under way")
			_ok(_world.hint_text().contains("start right away"), "and she says she's off to start")
			# The tinker makes an axe now too.
			_ok(_world._interactables.any(func(e: Dictionary) -> bool: return bool(e.get("crafts", false))), "the tinker is still here (she makes the axe)")
			_step = 9
		9:
			print("")
			if _fails == 0:
				print("ALL CARPENTER SMOKE CHECKS PASSED")
				quit(0)
			else:
				print("CARPENTER SMOKE FAILED: %d" % _fails)
				quit(1)
			return true
	return false
