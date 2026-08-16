class_name EncounterDirector
extends Node
## THE FIRST MEETING — the finding-your-companion beat. A brand-new player (or one who just chose
## New Companion) doesn't start with a partner at their side: the world around them holds a small
## flock of wild, shape-shifting creatures (EncounterPal), and ONE of them — pre-assigned at
## spawn, indistinguishable by looks since every animal shimmers between the same species — is
## their true companion. Examining a wild one earns a polite nothing and it walks off; examining
## the true one plays the bonding ceremony, and the companion steps out of the flock into its
## real body (the CompanionView), following from then on. The choice already made, discovered by
## meeting — never picked from a menu.
##
## Runs entirely client-side: the flock is a personal beat (each player finds their OWN companion;
## a friend standing beside you sees your ordinary companion, not your search), so nothing here
## touches the wire. Whether the meeting still needs to happen is part of the companion's
## server-saved self (CompanionSelf.met), so it survives sessions/devices and replays only after
## a New Companion reset.
##
## Activation is reactive: we wait until the server's save has SETTLED (Net.save_loaded, or the
## in-session mirror on a world hop) before trusting is_met() — the placeholder self before that
## always says unmet and would false-start the search. Offline/headless runs never settle, so the
## whole mechanic stays inert there and every smoke test sees the world exactly as before.

## The search just began (the world hides the ambient pals + form highlights while it runs).
signal search_started
## The companion is now at the player's side, met and revealed (the world brings the HUD back).
signal bonded

var _host: Node          # world_controller — for show_hint (same seam the other directors use)
var _player: Node2D
var _companion: CompanionView
var _scenery: Node2D
var _cfg: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _interactables: Array = []   # the controller's live examine list (shared by reference)
var _solids: Array = []
var _bounds := Rect2()
var _body_radius := 6.0
var _margin := 2.0

var _save_settled := false
var _searching := false
var _ceremony := false
# The flock: [{ "pal": EncounterPal, "entry": Dictionary, "companion": bool }].
var _flock: Array = []


## Wire up. Net.save_loaded marks the save settled when it arrives this session; on a world hop
## the in-session mirror already holds it (the controller applies it synchronously during build),
## so we settle immediately. Connections auto-drop with this node on a world hop.
func setup(host: Node, player: Node2D, companion: CompanionView, scenery: Node2D) -> void:
	_host = host
	_player = player
	_companion = companion
	_scenery = scenery
	_rng.randomize()
	_cfg = WorldData.load_json("res://data/companion.json").get("encounter", {})
	_save_settled = Net.has_session_save()
	Net.save_loaded.connect(_on_save_loaded)


## The server's canonical save arrived (a returning player's companion, or nulls for a brand-new
## one): is_met() is now trustworthy, so update() may act on it. A bound method — not a lambda —
## so the connection is auto-dropped with this node on a world hop, like every director's.
func _on_save_loaded(_companion_save: Variant, _appearance: Variant) -> void:
	_save_settled = true


## The built world's pieces the flock needs: the controller's live examine list (we inject each
## animal into it, by reference), and the barriers/bounds the creatures walk against.
func set_world(interactables: Array, solids: Array, bounds: Rect2, body_radius: float, margin: float) -> void:
	_interactables = interactables
	_solids = solids
	_bounds = bounds
	_body_radius = body_radius
	_margin = margin


## Whether the player is currently mid-search (companion hidden, flock out). The controller reads
## this every frame to gate the companion HUD, orders, and highlights.
func is_searching() -> bool:
	return _searching


## Called every built frame by the controller. Starts the search the moment we KNOW the companion
## is unmet (save settled), keeps the flock's examine entries and the hidden companion's shadow
## position current while searching, and re-arms automatically after a New Companion reset (the
## fresh self is unmet again, so the finding beat replays).
func update(_delta: float) -> void:
	if _searching:
		_update_search()
		return
	if not _save_settled or not _companion.is_local() or _companion.is_met():
		return
	_begin_search()


func _update_search() -> void:
	# A save can land mid-search and hand us an already-met companion (a reconnect race): the
	# search is moot — fold it up and reveal quietly.
	if _companion.is_met():
		_finish(false)
		return
	for rec in _flock:
		var pal := rec["pal"] as EncounterPal
		(rec["entry"] as Dictionary)["pos"] = pal.position
		if bool(rec["companion"]):
			# Its roam disc follows YOU (a shade bigger than the screen), so the one that matters
			# is always somewhere near — sometimes just past the edge of what you can see.
			pal.anchor = _player.position
			# The hidden real companion shadows it, so a friend's view of "your companion" moves
			# through the world honestly while you search.
			_companion.position = pal.position


## Raise the flock. If the meeting can't be staged (no pal art, or the block is disabled), mark
## the companion met and move on — the world simply behaves as it did before this beat existed.
func _begin_search() -> void:
	var forms := PalView.available_forms()
	if not bool(_cfg.get("enabled", true)) or forms.is_empty():
		_companion.mark_met(0.0)
		return
	_searching = true
	_ceremony = false

	# The true companion's roam radius: a little bigger than the screen, computed from what this
	# device actually shows (the camera sits at zoom 1 in play).
	var half_diag := (get_viewport().get_visible_rect().size * 0.5).length()
	var comp_radius := half_diag * float(_cfg.get("screen_radius_factor", 1.15))

	var n := maxi(2, int(_cfg.get("flock_size", 7)))
	var chosen := _rng.randi_range(0, n - 1)
	for i in n:
		var pal := EncounterPal.new()
		pal.name = "EncounterPal_%d" % i
		pal.setup(forms, _cfg)
		pal.set_solids(_solids, _bounds, _body_radius, _margin)
		_scenery.add_child(pal)
		pal.position = _spawn_spot()
		pal.anchor = pal.position
		var entry := {
			"pos": pal.position,
			"label": "a shifting creature",
			"id": "encounter_pal_%d" % i,
			"tags": [],
			"kind": "encounter_pal",
			"render_index": -1,  # not world_art's to draw; the examine routing returns before any pulse
			"lore": "",
			"affordances": {},
		}
		_interactables.append(entry)
		var is_companion := i == chosen
		if is_companion:
			pal.wander_radius = comp_radius
			pal.bond_finished.connect(_on_bond_finished)
		_flock.append({ "pal": pal, "entry": entry, "companion": is_companion })

	# The real companion steps backstage: invisible, mind paused, shadowing the flock.
	_companion.visible = false
	_companion.set_process(false)
	_host.show_hint(String(_cfg.get("hint_search",
		"Wild creatures wander here, shifting shape as they go. One of them is waiting for you — walk up and Examine them.")))
	search_started.emit()


## A spot for a flock member: a ring around the player, kept inside the world and out of solids.
func _spawn_spot() -> Vector2:
	var span: Array = _cfg.get("spawn_radius", [120.0, 380.0])
	var p: Vector2 = _player.position \
		+ Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU)) * _rng.randf_range(float(span[0]), float(span[1]))
	return Solids.resolve(p, _body_radius, _solids, _bounds, _margin)


## The controller's examine routed to a flock creature. The wild ones give the "no spark" beat and
## leave; the true one starts the ceremony.
func examine_pal(entry: Dictionary) -> void:
	var rec := _find(entry)
	if rec.is_empty() or _ceremony:
		return
	var pal := rec["pal"] as EncounterPal
	if not pal.can_examine():
		return
	if bool(rec["companion"]):
		_ceremony = true
		pal.begin_bond(_player)
		_host.show_hint(String(_cfg.get("hint_notice", "This one doesn't leave. It goes very still — and looks right back at you.")))
		return
	pal.examine_rebuff(_player.position)
	var lines: Array = _cfg.get("lines_disinterest", ["The %s looks you over without much interest, and pads away."])
	_host.show_hint(String(lines[_rng.randi_range(0, lines.size() - 1)]) % pal.species_name())


## Whether the examine scan should pass over this flock entry right now (mid-ceremony, walking
## away, or inside its rebuff cooldown) — the moving-creature sibling of the hunt's rock skip.
func should_skip(entry: Dictionary) -> bool:
	var rec := _find(entry)
	if rec.is_empty():
		return true
	if _ceremony:
		return true
	return not (rec["pal"] as EncounterPal).can_examine()


## The ceremony finished: the flock member IS the companion now. Reveal for real.
func _on_bond_finished(_species: String, _variant: int) -> void:
	_finish(true)


## Fold the search up and hand the world its companion. ceremonial=true is the real path (the
## bonding just played); false is the quiet fallback (a save race said it was already met).
func _finish(ceremonial: bool) -> void:
	_searching = false
	_ceremony = false
	var comp_pal: EncounterPal = null
	for rec in _flock:
		if bool(rec["companion"]):
			comp_pal = rec["pal"] as EncounterPal
		_interactables.erase(rec["entry"])
	# The companion wakes exactly where — and as — the animal you met.
	if comp_pal != null:
		_companion.position = comp_pal.position
	_companion.visible = true
	_companion.set_process(true)
	if ceremonial:
		_companion.mark_met(float(_cfg.get("bond_seed", 0.12)))
		if comp_pal != null:
			_companion.instruct_form(comp_pal.species_name(), comp_pal.worn_variant())
		_host.show_hint(String(_cfg.get("hint_bonded",
			"It was this one all along. Your companion — yours, and no one else's — falls in beside you.")))
	# The rest of the flock drifts back into the wild.
	for rec in _flock:
		var pal := rec["pal"] as EncounterPal
		if pal == comp_pal:
			pal.queue_free()
		else:
			pal.depart(_player.position)
	_flock.clear()
	bonded.emit()


func _find(entry: Dictionary) -> Dictionary:
	for rec in _flock:
		if rec["entry"] == entry:
			return rec
	return {}
