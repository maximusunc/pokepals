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

## A brand-new player (no appearance stored on the server yet) needs to CREATE their look before the
## world seeds their save. The world listens for this to open the first-run customizer; on confirm it
## calls apply_local_look(), which is the first push_save that makes the chosen look canonical.
signal needs_creation

const NET_SEND_INTERVAL := 1.0 / 20.0  # how often we broadcast our pair's transforms (~20 Hz)
const SAVE_INTERVAL := 15.0            # how often to push the companion/wardrobe to the server (sole save)
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const COMPANION_SCENE := preload("res://scenes/companion.tscn")

var _player: PlayerView
var _companion: CompanionView
var _scenery: Node2D
var _style: ArtStyle

# Each connected peer's PUPPET pair, keyed by Net peer id (the player's user_id): { peer_id: { player,
# companion } }. Spawned on peer_joined, freed on peer_left, driven entirely by transforms over Net.
# An identity packet that lands before its pair exists is stashed and applied the moment it spawns.
var _remote_pairs: Dictionary = {}
var _pending_identity: Dictionary = {}
var _net_accum := 0.0          # accumulates toward the next NET_SEND_INTERVAL broadcast
var _save_accum := 0.0         # accumulates toward the next server SAVE_INTERVAL push
var _bounds := Rect2()         # the world's walkable bounds, kept to CLAMP untrusted remote positions


## Wire up to the Net seam: publish our identity once, and react to peers joining, moving, and leaving,
## plus our save loading. Safe to call always — none of it does anything until the player Hosts or Joins.
## Connections are auto-dropped when this node is freed on a world hop, so they never duplicate.
func setup(player: PlayerView, companion: CompanionView, scenery: Node2D, style: ArtStyle) -> void:
	_player = player
	_companion = companion
	_scenery = scenery
	_style = style
	Net.set_local_identity(_local_identity())
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.identity_received.connect(_on_identity_received)
	Net.state_received.connect(_on_state_received)
	Net.save_loaded.connect(_on_save_loaded)
	Net.disconnected.connect(_on_disconnected)


## Hand over the world's walkable bounds (computed during the build) so remote positions can be clamped.
func set_bounds(rect: Rect2) -> void:
	_bounds = rect


## Re-dress from the in-session save the server already gave us: hopping between worlds reloads the scene
## with a fresh placeholder companion, so if we're already connected we adopt the held save at once.
func apply_session_save_if_any() -> void:
	if Net.has_session_save():
		var s := Net.session_save()
		_apply_server_save(s.get("companion"), s.get("appearance"))


## How many remote pairs are present (the Ruin's paired-hall waking reads this to tier its payoff).
func peer_count() -> int:
	return _remote_pairs.size()


## Stream our local pair's transforms to peers at ~20 Hz. The packet stays tiny: our player's
## position+facing and our companion's position+attention (the Net seam marshals the Vector2s for
## the wire). A no-op until connected (Net.broadcast_state guards it), so it's harmless offline.
func broadcast(delta: float) -> void:
	if not Net.is_active():
		return
	_net_accum += delta
	if _net_accum < NET_SEND_INTERVAL:
		return
	_net_accum = 0.0
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
	return {
		"name": "Friend",
		"appearance": _player.appearance_dict(),
		"companion_look": _companion.resting_look_payload(),
	}


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


## A peer arrived: spawn its puppet pair (a remote Player + Companion) into the y-sorted Scenery
## layer so they depth-sort with us and the trees. They're flagged remote BEFORE entering the tree
## (set_remote → no input, no brain, no save). Any identity that beat them here is applied at once.
func _on_peer_joined(peer_id: String) -> void:
	if _remote_pairs.has(peer_id):
		return
	var rp := PLAYER_SCENE.instantiate() as PlayerView
	rp.set_remote()
	rp.name = "RemotePlayer_%s" % peer_id
	var rc := COMPANION_SCENE.instantiate() as CompanionView
	rc.set_remote()
	rc.name = "RemoteCompanion_%s" % peer_id
	rp.set_style(_style)
	rc.set_style(_style)
	_scenery.add_child(rp)
	_scenery.add_child(rc)
	# Start them where our own pair stands so they don't pop in from the origin; the first state
	# packet snaps them to the truth a frame later. (Remotes never collide — their owner is.)
	rp.position = _player.position
	rc.position = _companion.position
	rp.set_remote_state(_player.position, Vector2.DOWN)
	rc.set_remote_state(_companion.position, Vector2.DOWN)
	_remote_pairs[peer_id] = { "player": rp, "companion": rc }
	if _pending_identity.has(peer_id):
		_apply_remote_identity(peer_id, _pending_identity[peer_id])
		_pending_identity.erase(peer_id)


## A peer left: free its puppet pair and forget it. Clean despawn so a friend quitting simply
## vanishes rather than freezing in place.
func _on_peer_left(peer_id: String) -> void:
	if _remote_pairs.has(peer_id):
		var pair: Dictionary = _remote_pairs[peer_id]
		(pair["player"] as Node).queue_free()
		(pair["companion"] as Node).queue_free()
		_remote_pairs.erase(peer_id)
	_pending_identity.erase(peer_id)


## The session ended — we left on purpose, or the server dropped us. Despawn every remote puppet
## pair so friends don't linger frozen in the world while we're back at the gate (and so a later
## reconnect doesn't leave the old ghosts behind). The lobby gate reappears on its own (it also
## listens for disconnected()); our own player + companion stay put.
func _on_disconnected() -> void:
	for peer_id in _remote_pairs.keys():
		var pair: Dictionary = _remote_pairs[peer_id]
		(pair["player"] as Node).queue_free()
		(pair["companion"] as Node).queue_free()
	_remote_pairs.clear()
	_pending_identity.clear()


## A peer's identity arrived. If its puppets exist, dress them now; otherwise stash it until they
## spawn (the packet can race ahead of peer_joined). Untrusted input — validated by the appliers.
func _on_identity_received(peer_id: String, payload: Dictionary) -> void:
	if _remote_pairs.has(peer_id):
		_apply_remote_identity(peer_id, payload)
	else:
		_pending_identity[peer_id] = payload


func _apply_remote_identity(peer_id: String, payload: Dictionary) -> void:
	var pair: Dictionary = _remote_pairs[peer_id]
	var appearance: Variant = payload.get("appearance", {})
	if appearance is Dictionary:
		(pair["player"] as PlayerView).apply_identity(appearance)
	var look: Variant = payload.get("companion_look", {})
	if look is Dictionary:
		(pair["companion"] as CompanionView).apply_remote_look(look)


## A peer's live transforms arrived (~20 Hz). Treat every field as UNTRUSTED: positions are clamped
## to the world bounds, non-Vector2 junk is ignored, and the data can only move THIS peer's puppet —
## never our avatar, never the save. The puppets interpolate toward it for smooth motion.
func _on_state_received(peer_id: String, payload: Dictionary) -> void:
	if not _remote_pairs.has(peer_id):
		return
	var pair: Dictionary = _remote_pairs[peer_id]
	(pair["player"] as PlayerView).set_remote_state(_clamp_to_bounds(_as_vec2(payload.get("p"))), _as_vec2(payload.get("pf")))
	(pair["companion"] as CompanionView).set_remote_state(_clamp_to_bounds(_as_vec2(payload.get("c"))), _as_vec2(payload.get("cl")))


## Coerce an untrusted wire value to a Vector2, defaulting to zero for anything else — so a
## malformed packet can never crash us or inject a wrong type into the rig.
func _as_vec2(v: Variant) -> Vector2:
	return v if v is Vector2 else Vector2.ZERO


## Keep a remote position inside the walkable world, so a peer (honest or not) can never park its
## puppet out in the void past the edges.
func _clamp_to_bounds(p: Vector2) -> Vector2:
	if _bounds.size == Vector2.ZERO:
		return p
	return Vector2(
		clampf(p.x, _bounds.position.x, _bounds.end.x),
		clampf(p.y, _bounds.position.y, _bounds.end.y))
