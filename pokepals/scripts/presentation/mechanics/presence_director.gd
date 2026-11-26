class_name PresenceDirector
extends Node
## SHARED PRESENCE (Rung 3) — the game-side half of multiplayer: "me vs them", lifted out of
## world_controller. Decides WHAT to send (our pair's transforms + a one-time identity), turns a peer's
## wire state into a spawned, smoothed puppet pair, and owns the server save (push + load/adopt). Talks
## only to the Net seam in plain dictionaries, so it survives the planned transport swaps untouched.
##
## The local Player/Companion (from the scene) stay fully authoritative over themselves and keep running
## their own input/brain; remotes are pure puppets, driven only by what arrives over Net. Everything here
## is a no-op until the player actually Hosts/Joins (Net guards broadcast/push), so it's harmless offline.
##
## A CROWD (docs/scaling-design.md, SC-2): everyone in the world is kept in the ROSTER as plain data (name,
## identity, last known transforms), but puppet NODES exist only for the peers the drawing budget
## (CrowdBudget) says to draw: FULL is the person and their companion, LITE the person only (no companion,
## nothing in their hands), and anyone else has no nodes at all. The budget is re-ranked a few times a second,
## and building or freeing puppets is spread over frames, so a crowd arriving, or a walk past many people,
## never stalls a frame. A puppet away from the screen sleeps (no processing at all) until it comes near.

## A brand-new player (no appearance stored on the server yet) needs to CREATE their look before the
## world seeds their save. The world listens for this to open the first-run customizer; on confirm it
## calls apply_local_look(), which is the first push_save that makes the chosen look canonical.
signal needs_creation

const NET_SEND_INTERVAL := 1.0 / 20.0  # how often we broadcast our pair's transforms while they change (~20 Hz)
const NET_KEEPALIVE := 1.0             # how often we send them anyway while nothing changes
const SAVE_INTERVAL := 15.0            # how often to push the companion/wardrobe to the server (sole save)
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const COMPANION_SCENE := preload("res://scenes/companion.tscn")

# The drawing budget's pacing. It is re-ranked every BUDGET_INTERVAL, and sooner (BUDGET_SOON) when a peer
# gets its first position or we jump somewhere. Building puppets may take SPAWN_BUDGET_USEC a frame (at least
# one is always built, so a slow device still gets there); freeing is cheap, but capped too.
const BUDGET_INTERVAL := 0.3
const BUDGET_SOON := 0.05
const SPAWN_BUDGET_USEC := 1500
const RETIRES_PER_FRAME := 24
# A puppet whose owner stands within this of the screen's edge is awake (it eases and animates); farther out
# it sleeps. The margin covers a walk at full speed between two budget passes.
const AWAKE_MARGIN := 96.0
# Our own move this big between frames is a jump (set down elsewhere): re-rank at once.
const LOCAL_JUMP := 256.0

var _player: PlayerView
var _companion: CompanionView
var _scenery: Node2D
var _style: ArtStyle

# EVERY peer in this world, keyed by Net peer id (the player's user_id), as plain data: { p, pf, c, cl:
# their last known transforms (Vector2), seen: whether any have arrived, ident: their last identity packet }.
# Kept for everyone whether drawn or not, so the roster (names, counts, who is here) is always world-wide.
var _roster: Dictionary = {}
# The PUPPET nodes of the peers being drawn: { peer_id: { player, companion?, rod?, lantern?, axe?, tier,
# awake } }. A LITE pair has no companion and nothing in its hands. Built and freed by the budget.
var _remote_pairs: Dictionary = {}
# An identity packet for a peer we have not heard join yet (the packet can race ahead): applied on join.
var _pending_identity: Dictionary = {}
# Each peer's name (FR-0), from their identity packet (the server stamps it, so it can't be faked).
var _peer_names: Dictionary = {}
var _crowd := CrowdBudget.new()
var _budget_t := 0.0           # seconds until the next re-rank
var _queue: Array = []         # peer ids whose puppets need building, changing or freeing, in order
var _retiring: Array = []      # puppet nodes leaving, freed a few a frame
var _last_local := Vector2.ZERO
var _my_cell := Vector2i.ZERO  # our interest cell in a crowd world, to notice when we cross into another
var _my_cell_known := false
var _net_accum := 0.0          # accumulates toward the next NET_SEND_INTERVAL broadcast
var _keepalive_accum := 0.0    # time since we last sent anything
var _last_sent: Array = []     # the last packet we sent, as the server keeps it (whole px, 2-decimal directions)
var _save_accum := 0.0         # accumulates toward the next server SAVE_INTERVAL push
var _bounds := Rect2()         # the world's walkable bounds, kept to CLAMP untrusted remote positions
# What we're doing with our hands, relayed with our identity so friends see it (usable items, U-13): the
# item we hold ("rod" or "") and, while fishing, { b: [x, y], ph, n, k?, r?, c? }. Set by FishingDirector.
var _held := ""
var _fishing: Dictionary = {}


## Wire up to the Net seam: publish our identity once, and react to peers joining, moving, and leaving,
## plus our save loading. Safe to call always — none of it does anything until the player Hosts or Joins.
## Connections are auto-dropped when this node is freed on a world hop, so they never duplicate.
func setup(player: PlayerView, companion: CompanionView, scenery: Node2D, style: ArtStyle) -> void:
	_player = player
	_companion = companion
	_scenery = scenery
	_style = style
	Net.set_local_identity(_local_identity())
	# Re-publish our identity whenever our companion shifts daemon form, so friends re-render the
	# new animal (the same refresh path a wardrobe change uses).
	_companion.form_changed.connect(_on_local_form_changed)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.identity_received.connect(_on_identity_received)
	Net.state_received.connect(_on_state_received)
	Net.save_loaded.connect(_on_save_loaded)
	Net.disconnected.connect(_on_disconnected)


## Hand over the world's walkable bounds (computed during the build) so remote positions can be clamped.
func set_bounds(rect: Rect2) -> void:
	_bounds = rect


## Hand over the world spec's `crowd` block ({ cell, full, lite }; see CrowdBudget). No block (null or {})
## means no interest cells and the default budget, which a small world never reaches.
func set_crowd(block: Variant) -> void:
	_crowd.configure(CrowdBudget.settings_from(block))
	_my_cell_known = false
	_budget_t = 0.0


## Re-dress from the in-session save the server already gave us: hopping between worlds reloads the scene
## with a fresh placeholder companion, so if we're already connected we adopt the held save at once.
func apply_session_save_if_any() -> void:
	if Net.has_session_save():
		var s := Net.session_save()
		_apply_server_save(s.get("companion"), s.get("appearance"))


## How many other players are in this world with us, drawn or not (the place chip's "N here", the Ruin's
## paired-hall waking). The whole roster, not just who is on screen.
func peer_count() -> int:
	return _roster.size()


## How many other players have puppets right now (the drawing budget's FULL and LITE).
func drawn_count() -> int:
	return _remote_pairs.size()


## Stream our local pair's transforms to peers: about 20 times a second while they change, and once a second
## (a keepalive) while they don't. The packet stays tiny: our player's position+facing and our companion's
## position+attention (the Net seam marshals the Vector2s for the wire). "Changed" is judged at the precision
## the server keeps (whole pixels, directions to two decimals), so a sub-pixel drift is not a change. A no-op
## until connected (Net.broadcast_state guards it), so it's harmless offline.
func broadcast(delta: float) -> void:
	if not Net.is_active():
		return
	_net_accum += delta
	_keepalive_accum += delta
	if _net_accum < NET_SEND_INTERVAL:
		return
	_net_accum = 0.0
	var key := [
		_player.position.round(), (_player.facing() * 100.0).round(),
		_companion.position.round(), (_companion.look_dir() * 100.0).round(),
	]
	if key == _last_sent and _keepalive_accum < NET_KEEPALIVE:
		return
	_last_sent = key
	_keepalive_accum = 0.0
	Net.broadcast_state({
		"p": _player.position,
		"pf": _player.facing(),
		"c": _companion.position,
		"cl": _companion.look_dir(),
	})


## Periodically push our companion + wardrobe to the server (the sole save). A no-op until
## connected; the world calls it every frame.
func push_save_periodic(delta: float) -> void:
	if not Net.is_active():
		return
	_save_accum += delta
	if _save_accum < SAVE_INTERVAL:
		return
	_save_accum = 0.0
	push_save()


## Send the current companion self + worn wardrobe up as the canonical save.
func push_save() -> void:
	Net.push_save(_companion.self_dict(), _player.appearance_dict())


## Persist on the ways a session can end (window close, app backgrounded, world hop / quit), if connected.
func flush_save_on_exit() -> void:
	if Net.is_active():
		push_save()


## Our one-time identity packet: who we are, for a friend to render. Pure presentation data —
## the player's worn look (already JSON) and the companion's resting-look floats (its grown self,
## with no mind attached). The friend never receives our save, our brain, or our bond — only this.
func _local_identity() -> Dictionary:
	var out := {
		"name": "Friend",
		"appearance": _player.appearance_dict(),
		"companion_look": _companion.resting_look_payload(),
		"companion_form": _companion.companion_form_payload(),
		"held": _held,
	}
	if not _fishing.is_empty():
		out["fishing"] = _fishing
	return out


## What we hold and our fishing changed (FishingDirector): re-publish our identity so friends see it. Only
## sent when something actually changed, since every identity update goes to everyone in the world.
func set_activity(held: String, fishing: Dictionary) -> void:
	if held == _held and fishing == _fishing:
		return
	_held = held
	_fishing = fishing.duplicate(true)
	Net.set_local_identity(_local_identity())


## Our companion just changed daemon form: refresh the relayed identity so peers re-render it.
func _on_local_form_changed() -> void:
	Net.set_local_identity(_local_identity())


## Our canonical save arrived from the server (or nulls for a brand-new player).
func _on_save_loaded(companion, appearance) -> void:
	_apply_server_save(companion, appearance)


## Adopt a loaded save. A returning player's stored companion + look are applied and re-broadcast.
## A brand-new player (no appearance stored yet) is instead sent through first-run CREATION: we hold
## off seeding the server and raise needs_creation, and the world drives apply_local_look() on confirm
## — so the FIRST thing saved is the look the player actually chose, not a silent default.
func _apply_server_save(companion, appearance) -> void:
	var had_companion := companion is Dictionary and not (companion as Dictionary).is_empty()
	var had_appearance := appearance is Dictionary and not (appearance as Dictionary).is_empty()
	if had_companion:
		_companion.replace_self(companion)
	if had_appearance:
		_player.apply_appearance(appearance)
	if not had_appearance:
		# Brand-new player: let the world run creation; it will apply_local_look() (first push_save).
		needs_creation.emit()
		return
	# Our relayed presentation identity may have changed (loaded look) — refresh it for peers.
	Net.set_local_identity(_local_identity())
	if not had_companion:
		push_save()  # rare partial save: seed the companion self we started with


## Adopt a look the player just chose (first-run creation OR a wardrobe change): dress the live avatar,
## re-broadcast our identity so friends re-render us, and persist it to the server as the canonical save.
## The single write path both entry points share.
func apply_local_look(look: Dictionary) -> void:
	_player.apply_appearance(look)
	Net.set_local_identity(_local_identity())
	push_save()


# --- The roster: everyone in the world, as data -------------------------------------------------------


## A peer arrived: add them to the roster. No nodes yet: they get puppets once a position has arrived and
## the budget says to draw them. Any identity that beat them here is kept with them.
func _on_peer_joined(peer_id: String) -> void:
	if _roster.has(peer_id):
		return
	_roster[peer_id] = {
		"p": Vector2.ZERO, "pf": Vector2.DOWN, "c": Vector2.ZERO, "cl": Vector2.DOWN,
		"seen": false, "ident": _pending_identity.get(peer_id, {}),
	}
	_pending_identity.erase(peer_id)


## A peer left: forget them and let their puppets go at once (a friend quitting simply vanishes rather than
## freezing in place).
func _on_peer_left(peer_id: String) -> void:
	_roster.erase(peer_id)
	_drop_pair(peer_id)
	_pending_identity.erase(peer_id)
	_peer_names.erase(peer_id)


## The session ended: we left on purpose, or the server dropped us. Despawn every remote puppet
## pair so friends don't linger frozen in the world while we're back at the gate (and so a later
## reconnect doesn't leave the old ghosts behind). The lobby gate reappears on its own (it also
## listens for disconnected()); our own player + companion stay put.
func _on_disconnected() -> void:
	for peer_id in _remote_pairs.keys():
		_drop_pair(peer_id)
	_roster.clear()
	_queue.clear()
	_pending_identity.clear()
	_peer_names.clear()


## A peer's identity arrived. Kept in the roster, and their puppets (if drawn) are dressed now; one that
## races ahead of their join is stashed until it lands. Untrusted input, validated by the appliers.
func _on_identity_received(peer_id: String, payload: Dictionary) -> void:
	if payload.has("name"):
		_peer_names[peer_id] = String(payload["name"])
	if not _roster.has(peer_id):
		_pending_identity[peer_id] = payload
		return
	_roster[peer_id]["ident"] = payload
	if _remote_pairs.has(peer_id):
		_apply_remote_identity(peer_id, payload)


## A peer's live transforms arrived (about 20 Hz while they move, once a second or never while they stand;
## nothing here counts on a rate). Treat every field as UNTRUSTED: positions are clamped to the world
## bounds, non-Vector2 junk is ignored (a field left out keeps its last value), and the data can only move
## THIS peer's puppet, never our avatar, never the save. Kept in the roster whether drawn or not.
func _on_state_received(peer_id: String, payload: Dictionary) -> void:
	var rec: Dictionary = _roster.get(peer_id, {})
	if rec.is_empty():
		return
	var p: Variant = payload.get("p")
	if p is Vector2:
		rec["p"] = _clamp_to_bounds(p)
		if not rec["seen"]:
			# Their first position: they can be drawn now, so re-rank soon rather than on the slow timer.
			rec["seen"] = true
			_budget_t = minf(_budget_t, BUDGET_SOON)
	if payload.get("pf") is Vector2:
		rec["pf"] = payload["pf"]
	if payload.get("c") is Vector2:
		rec["c"] = _clamp_to_bounds(payload["c"])
	if payload.get("cl") is Vector2:
		rec["cl"] = payload["cl"]
	var pair: Dictionary = _remote_pairs.get(peer_id, {})
	if pair.is_empty():
		return
	(pair["player"] as PlayerView).set_remote_state(rec["p"], rec["pf"])
	var rc: Variant = pair.get("companion")
	if rc != null:
		(rc as CompanionView).set_remote_state(rec["c"], rec["cl"])


# --- The drawing budget: who has puppets ----------------------------------------------------------------


func _process(delta: float) -> void:
	if _player == null:
		return
	_budget_t -= delta
	if _player.position.distance_squared_to(_last_local) > LOCAL_JUMP * LOCAL_JUMP:
		_budget_t = 0.0
	_last_local = _player.position
	if _crowd.cell > 0.0:
		_track_my_cell()
	if _budget_t <= 0.0:
		_budget_t = BUDGET_INTERVAL
		_rebudget()
	_work_queue(SPAWN_BUDGET_USEC)
	_retire_some(RETIRES_PER_FRAME)


## In a crowd world the server only tells us about the 3 x 3 cells round us. When we step into another cell,
## anyone we last placed in a cell that has just come into sight may have left it while we could not hear,
## so we forget where they were (no puppet) until the server's snapshot of those cells says where they are.
## Without this a peer who walked off unseen would stand there as a ghost when we came back.
func _track_my_cell() -> void:
	var now := CrowdBudget.cell_of(_player.position, _crowd.cell)
	if not _my_cell_known:
		_my_cell = now
		_my_cell_known = true
		return
	if now == _my_cell:
		return
	for peer_id in _roster:
		var rec: Dictionary = _roster[peer_id]
		if rec["seen"] and CrowdBudget.came_into_sight(rec["p"], _crowd.cell, _my_cell, now):
			rec["seen"] = false
	_my_cell = now
	_budget_t = minf(_budget_t, BUDGET_SOON)


## Re-rank everyone, queue whatever puppets must be built, changed or freed (nearest first, frees before
## builds), and wake the puppets near the screen while the far ones sleep.
func _rebudget() -> void:
	var positions: Dictionary = {}
	for peer_id in _roster:
		var rec: Dictionary = _roster[peer_id]
		if rec["seen"]:
			positions[peer_id] = rec["p"]
	var tiers := _crowd.rank(_player.position, positions)
	var frees: Array = []
	for peer_id in _remote_pairs:
		if _wanted_tier(peer_id) < 0:
			frees.append(peer_id)
	# Builds and tier changes, nearest first: sorted natively as (distance², index) pairs.
	var ids: Array = []
	var keyed: Array = []
	for peer_id in tiers:
		var want := _wanted_tier(peer_id)
		if want < 0:
			continue
		var pair: Dictionary = _remote_pairs.get(peer_id, {})
		if pair.is_empty() or int(pair["tier"]) != want:
			keyed.append(Vector2(_player.position.distance_squared_to(positions[peer_id]), ids.size()))
			ids.append(peer_id)
	keyed.sort()
	var order: Array = []
	for k in keyed:
		order.append(ids[int((k as Vector2).y)])
	_queue = frees + order
	_wake_near_screen()


## The puppet tier the budget wants for a peer: FULL or LITE, or -1 for no puppets.
func _wanted_tier(peer_id: String) -> int:
	var t := _crowd.tier_of(peer_id)
	return t if t == CrowdBudget.FULL or t == CrowdBudget.LITE else -1


## Build, change or free queued puppets for up to `budget_usec` this frame (always at least one). Each is
## checked again as it comes up, since the crowd may have moved on since it was queued.
func _work_queue(budget_usec: int) -> void:
	if _queue.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var done := 0
	while not _queue.is_empty():
		if done > 0 and Time.get_ticks_usec() - t0 >= budget_usec:
			break
		var peer_id: String = _queue.pop_front()
		_sync_pair(peer_id)
		done += 1


## Make a peer's puppets match the tier the budget wants for it, right now.
func _sync_pair(peer_id: String) -> void:
	var want := _wanted_tier(peer_id) if _roster.has(peer_id) else -1
	var pair: Dictionary = _remote_pairs.get(peer_id, {})
	if want < 0:
		if not pair.is_empty():
			_drop_pair(peer_id)
		return
	if pair.is_empty():
		_spawn_pair(peer_id, want)
	elif int(pair["tier"]) != want:
		_set_pair_tier(peer_id, want)


## Build the puppets for a peer into the y-sorted Scenery layer so they depth-sort with us and the trees,
## straight at their last known spot. They're flagged remote BEFORE entering the tree (set_remote: no input,
## no brain, no save), then dressed from the identity the roster holds.
func _spawn_pair(peer_id: String, tier: int) -> void:
	var rec: Dictionary = _roster[peer_id]
	var rp := PLAYER_SCENE.instantiate() as PlayerView
	rp.set_remote()
	rp.name = "RemotePlayer_%s" % peer_id
	rp.set_style(_style)
	rp.position = rec["p"]
	rp.set_remote_state(rec["p"], rec["pf"])
	# Dressed before it enters the tree, so it never builds the default look first.
	var appearance: Variant = (rec["ident"] as Dictionary).get("appearance")
	if appearance is Dictionary:
		rp.apply_identity(appearance)
	_scenery.add_child(rp)
	# On a world that re-lights its visitors (Nocthollow), friends wear the planet's light too.
	OtherworldLook.apply(rp, _style.actor_look())
	_remote_pairs[peer_id] = { "player": rp, "tier": CrowdBudget.LITE, "awake": true }
	if tier == CrowdBudget.FULL:
		_set_pair_tier(peer_id, CrowdBudget.FULL)
	elif not (rec["ident"] as Dictionary).is_empty():
		_apply_remote_identity(peer_id, rec["ident"])
	_wake_pair(_remote_pairs[peer_id], _awake_rect())


## Move a drawn peer between FULL and LITE: their companion and the things in their hands come and go.
func _set_pair_tier(peer_id: String, tier: int) -> void:
	var pair: Dictionary = _remote_pairs[peer_id]
	var rec: Dictionary = _roster[peer_id]
	pair["tier"] = tier
	if tier == CrowdBudget.FULL:
		if pair.get("companion") == null:
			var rc := COMPANION_SCENE.instantiate() as CompanionView
			rc.set_remote()
			rc.name = "RemoteCompanion_%s" % peer_id
			rc.set_style(_style)
			rc.position = rec["c"]
			rc.set_remote_state(rec["c"], rec["cl"])
			_scenery.add_child(rc)
			OtherworldLook.apply(rc, _style.actor_look(), 0.7)
			pair["companion"] = rc
			if not bool(pair.get("awake", true)):
				rc.set_remote_awake(false)
	else:
		for key in ["companion", "rod", "lantern", "axe"]:
			var n: Variant = pair.get(key)
			if n != null:
				_retire(n)
				pair.erase(key)
	if not (rec["ident"] as Dictionary).is_empty():
		_apply_remote_identity(peer_id, rec["ident"])


## A peer's puppets go: hidden at once, freed over the next frames.
func _drop_pair(peer_id: String) -> void:
	var pair: Dictionary = _remote_pairs.get(peer_id, {})
	if pair.is_empty():
		return
	_retire(pair["player"])
	var rc: Variant = pair.get("companion")
	if rc != null:
		_retire(rc)
	_remote_pairs.erase(peer_id)


func _retire(node: Variant) -> void:
	if node == null or not is_instance_valid(node):
		return
	var n := node as Node
	if n is CanvasItem:
		(n as CanvasItem).visible = false
	n.process_mode = Node.PROCESS_MODE_DISABLED
	_retiring.append(n)


func _retire_some(count: int) -> void:
	var k := mini(count, _retiring.size())
	for i in k:
		var n: Node = _retiring[i]
		if is_instance_valid(n):
			n.queue_free()
	if k > 0:
		_retiring = _retiring.slice(k)


## The world rect round the screen within which puppets stay awake (empty: no framing, all awake).
func _awake_rect() -> Rect2:
	return ViewCull.visible_world_rect(_scenery, AWAKE_MARGIN) if _scenery != null else Rect2()


## Wake the drawn puppets near the screen and put the rest to sleep (only those that changed are touched).
func _wake_near_screen() -> void:
	var rect := _awake_rect()
	for peer_id in _remote_pairs:
		_wake_pair(_remote_pairs[peer_id], rect, _roster.get(peer_id, {}))


func _wake_pair(pair: Dictionary, rect: Rect2, rec: Dictionary = {}) -> void:
	var rp: PlayerView = pair["player"]
	var at: Vector2 = rec.get("p", rp.position)
	var on := not rect.has_area() or rect.has_point(at)
	if on == bool(pair.get("awake", true)):
		return
	pair["awake"] = on
	rp.set_remote_awake(on)
	var rc: Variant = pair.get("companion")
	if rc != null:
		(rc as CompanionView).set_remote_awake(on)


## Settle the budget at once: re-rank and build or free every queued puppet in one go. For tests, and for
## anything that cannot wait a few frames.
func flush_puppets() -> void:
	_budget_t = BUDGET_INTERVAL
	_rebudget()
	_work_queue(1 << 30)
	_retire_some(_retiring.size())


# --- Reading who is here -----------------------------------------------------------------------------


## Where every drawn remote player stands right now (native creatures react to friends as well as to us).
## Only the drawn ones: anyone not drawn is far off or past the budget.
func remote_player_positions() -> Array:
	var out: Array = []
	for pair in _remote_pairs.values():
		var rp: Node2D = pair["player"]
		if is_instance_valid(rp):
			out.append(rp.position)
	return out


## Where every friend carrying a lit lantern stands (the dark worlds clear a warm pocket round each). Read
## from what they hold, so a friend drawn LITE (no lantern node) still lights the dark round them.
func remote_lantern_positions() -> Array:
	var out: Array = []
	for peer_id in _remote_pairs:
		var rec: Dictionary = _roster.get(peer_id, {})
		if rec.is_empty() or String((rec["ident"] as Dictionary).get("held", "")) != "lantern":
			continue
		var rp: Variant = _remote_pairs[peer_id].get("player")
		if is_instance_valid(rp):
			out.append((rp as Node2D).position)
	return out


## A peer's name, or "a wanderer" if their identity hasn't arrived yet.
func peer_name(peer_id: String) -> String:
	return String(_peer_names.get(peer_id, "a wanderer"))


## Whether a peer is in this world with us right now (drawn or not).
func has_peer(peer_id: String) -> bool:
	return _roster.has(peer_id)


## The peer whose avatar stands nearest a world point, within `radius`, or "" (a tap on a player). Only
## drawn players can be tapped.
func peer_at(world_pos: Vector2, radius: float) -> String:
	var best := ""
	var best_d := radius
	for peer_id in _remote_pairs:
		var rp: Node2D = _remote_pairs[peer_id]["player"]
		if not is_instance_valid(rp):
			continue
		# Measured to the middle of the body, not the feet, so a tap on the figure itself counts.
		var d := world_pos.distance_to(rp.position + Vector2(0, -14))
		if d <= best_d:
			best = peer_id
			best_d = d
	return best


## peer_at for a perspective view: the player whose drawn body (its middle, lifted off its feet and scaled by
## depth) is nearest a screen position, within `radius` measured at that player's own scale.
func peer_at_screen(screen_pos: Vector2, radius: float) -> String:
	var best := ""
	var best_d := INF
	for peer_id in _remote_pairs:
		var rp: Node2D = _remote_pairs[peer_id]["player"]
		if not is_instance_valid(rp):
			continue
		var feet := PerspectiveView.to_screen(rp, rp.position)
		if feet.z <= 0.0:
			continue
		var d := screen_pos.distance_to(Vector2(feet.x, feet.y - 14.0 * feet.z)) / feet.z
		if d <= radius and d < best_d:
			best = peer_id
			best_d = d
	return best


## Every drawn remote player + companion node (whose footsteps glow on a world that asks for it, whose
## shadows Lanternfold throws). A LITE pair gives only its player.
func remote_actors() -> Array:
	var out: Array = []
	for pair in _remote_pairs.values():
		out.append(pair["player"])
		var rc: Variant = pair.get("companion")
		if rc != null:
			out.append(rc)
	return out


## Dress a drawn peer's puppets from their identity: the person always; their companion and what they hold
## only when drawn FULL.
func _apply_remote_identity(peer_id: String, payload: Dictionary) -> void:
	var pair: Dictionary = _remote_pairs[peer_id]
	var appearance: Variant = payload.get("appearance", {})
	if appearance is Dictionary:
		(pair["player"] as PlayerView).apply_identity(appearance)
	var rc: Variant = pair.get("companion")
	if rc == null:
		return
	var look: Variant = payload.get("companion_look", {})
	if look is Dictionary:
		(rc as CompanionView).apply_remote_look(look)
	var form: Variant = payload.get("companion_form", {})
	if form is Dictionary:
		(rc as CompanionView).apply_remote_form(
			String((form as Dictionary).get("species", "")), int((form as Dictionary).get("variant", 0)))
	# What they hold and their fishing (U-13): a rod in their hand, the cast, the bite, the catch.
	var held := String(payload.get("held", ""))
	var rod: RodView = pair.get("rod")
	if rod == null and held != "":
		rod = RodView.new()
		rod.name = "Rod"
		(pair["player"] as Node).add_child(rod)
		pair["rod"] = rod
	if rod != null:
		rod.apply_remote(held, payload.get("fishing"))
	# A friend carrying a lantern: drawn in their hand, and it lights the dark worlds round them too.
	var lantern: LanternView = pair.get("lantern")
	if lantern == null and held == "lantern":
		lantern = LanternView.new()
		lantern.name = "Lantern"
		(pair["player"] as Node).add_child(lantern)
		pair["lantern"] = lantern
	if lantern != null:
		lantern.visible = held == "lantern"
		lantern.set_process(lantern.visible)  # a lantern put away needs no work
	# A friend carrying an axe (home building): over their shoulder.
	var axe: AxeView = pair.get("axe")
	if axe == null and held == "axe":
		axe = AxeView.new()
		axe.name = "Axe"
		(pair["player"] as Node).add_child(axe)
		pair["axe"] = axe
	if axe != null:
		axe.visible = held == "axe"
		axe.set_process(axe.visible)


## Keep a remote position inside the walkable world, so a peer (honest or not) can never park its
## puppet out in the void past the edges.
func _clamp_to_bounds(p: Vector2) -> Vector2:
	if _bounds.size == Vector2.ZERO:
		return p
	return Vector2(
		clampf(p.x, _bounds.position.x, _bounds.end.x),
		clampf(p.y, _bounds.position.y, _bounds.end.y))
