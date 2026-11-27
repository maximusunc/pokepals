class_name CarpenterPanel
extends CozySheet
## The CARPENTER's window (home building; docs/usable-items-design.md "Home building"): the carpenter in the
## bazaar, who builds you a house at home. What she asks (the wood and the coins, from Net.house_status(), each
## ticked off against what you have), a **Build my house** button once you have it all, and, once she's agreed,
## how the build is going. The commission is the server's (Server.House): we ask, and the window refreshes from
## its answer.

## The host world, for the wallet (set_wallet_balance) and the hint line.
var host: Node
var balance := 0

var _list: VBoxContainer
var _busy := false


func _build() -> void:
	width = 320.0
	eyebrow("The carpenter")
	heading("\"A house of your own?\"")
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	body.add_child(_list)
	var done := CozySheet.pill("Done", close, false, 10)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(done)
	Net.inventory_received.connect(func(_items: Array) -> void: _fill())
	Net.house_status_received.connect(func(_s: Dictionary) -> void: _fill())
	Net.house_commissioned.connect(_on_commissioned)
	Net.house_refused.connect(_on_refused)
	_fill()


func _have(key: String) -> int:
	var n := 0
	for it in Net.inventory():
		if it is Dictionary and String((it as Dictionary).get("key", "")) == key:
			n += int((it as Dictionary).get("quantity", 0))
	return n


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var st := Net.house_status()
	var state := String(st.get("state", "none"))
	if state == "building":
		var mins := int(ceil(float(st.get("left_ms", 0)) / 60000.0))
		note("\"I'm on it! It's going up in the north of your glade. About %d minute%s, and it's yours: go and watch, if you like.\"" % [maxi(mins, 1), "" if mins == 1 else "s"], _list)
		return
	if state == "built":
		note("\"Your house is finished. I hope you love it. Everything you've found has moved in with you.\"", _list)
		return
	var wood_need := int(st.get("wood", 100))
	var coins_need := int(st.get("coins", 300))
	var wood := _have("wood")
	note("\"Bring me %d pieces of wood and %d coins, and I'll build you a house at home: a kitchen, a living room with a fire, a bedroom, and room for everything you've found.\"" % [wood_need, coins_need], _list)
	var needs := VBoxContainer.new()
	needs.add_theme_constant_override("separation", 2)
	var wl := HBoxContainer.new()
	wl.add_theme_constant_override("separation", 5)
	wl.add_child(ItemIconView.make("wood", "material", Color(0.66, 0.46, 0.28), 16.0))
	wl.add_child(UiStyle.label("%s  Wood  (%d of %d)" % ["✓" if wood >= wood_need else "·", mini(wood, wood_need), wood_need], 9,
		UiStyle.INK_STRONG if wood >= wood_need else UiStyle.MUTED, 600))
	needs.add_child(wl)
	needs.add_child(UiStyle.label("%s  %d coins  (you have %d)" % ["✓" if balance >= coins_need else "·", coins_need, balance], 9,
		UiStyle.INK_STRONG if balance >= coins_need else UiStyle.MUTED, 600))
	_list.add_child(needs)
	var build := CozySheet.pill("Build my house", _commission, true, 10)
	build.disabled = wood < wood_need or balance < coins_need
	build.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_list.add_child(build)
	if wood < wood_need:
		note("Wood comes from trees, in any world but the Vale. You'll need an axe: the tinker makes one from three pieces of driftwood and two river stones, both lying about on the Riverbank.", _list, UiStyle.MUTED)


func _commission() -> void:
	if _busy:
		return
	_busy = true
	Net.commission_house()


func _on_commissioned(_status: Dictionary, new_balance: int) -> void:
	_busy = false
	balance = new_balance
	if host != null:
		host.set_wallet_balance(balance)
		host.show_hint("\"It's a deal! I'll head over to your home and start right away.\"")
	_fill()


func _on_refused(reason: String) -> void:
	_busy = false
	if host == null:
		return
	match reason:
		"not_enough":
			host.show_hint("\"A few more pieces of wood, friend.\"")
		"insufficient_funds":
			host.show_hint("\"I'll need the coins too, when you have them.\"")
		"have_house":
			host.show_hint("\"You've already got a house! One's plenty.\"")
		"not_at_carpenter":
			host.show_hint("Step up to the carpenter's stall.")
		_:
			host.show_hint("\"Hm, something's off. Try again?\"")
