extends Node2D
## Wires the slice together: loads the world, places the player and companion,
## hands the companion its player to follow, frames the camera, and routes cozy
## interactions. When the player examines a nearby prop, the prop glows and the
## companion is told about it — so it can notice and wander over. The controller
## decides *that* an interaction happened; the companion's brain decides how to feel
## about it.

const ART_PATH := "res://data/art.json"
const INTERACT_RANGE := 60.0
# How close the player must be to the companion for the Pet affordance to appear. Mirrors the
# brain's pet.range (companion.json) so the button only shows when a pet would actually land.
const PET_RANGE := 56.0
# How close the player must walk to a portal to step through it, and how far they must then
# step away before a just-used portal re-arms (so arriving on a portal doesn't bounce you back).
const PORTAL_RANGE := 22.0
const PORTAL_ARM_BUFFER := 18.0
# Shared presence (Rung 3): how often we broadcast our own pair's transforms to peers. ~20 Hz is
# plenty for a cozy walk-around — remote puppets interpolate between samples (see PlayerView).
const NET_SEND_INTERVAL := 1.0 / 20.0
const SAVE_INTERVAL := 15.0  # how often to push the companion/wardrobe to the server (sole save)
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const COMPANION_SCENE := preload("res://scenes/companion.tscn")

# The world SPEC is fully SERVER-HOSTED: the client bundles NO world specs. Net fetches a world's spec
# on join and caches it (in memory + on disk, keyed by a content etag); we build from that. A cold
# first visit (nothing cached yet) shows a brief loading screen and builds the moment the spec arrives;
# a revisit paints instantly from the cache. Because the cache is content-keyed, a back-end world edit
# is picked up with no new client build — see _on_world_spec_arrived.

@onready var _world_art: WorldArt = $WorldArt
@onready var _scenery: Scenery = $Scenery
@onready var _player: PlayerView = $Scenery/Player
@onready var _companion: CompanionView = $Scenery/Companion
@onready var _camera: CameraRig = $Camera2D
@onready var _hint: Label = $UI/HintLabel
@onready var _joystick: VirtualJoystick = $UI/Joystick
@onready var _examine_button: Button = $UI/ExamineButton
@onready var _call_button: Button = $UI/CallButton
@onready var _pet_button: Button = $UI/PetButton
@onready var _reset_button: Button = $UI/ResetButton
@onready var _leave_button: Button = $UI/LeaveButton
@onready var _seek_button: Button = $UI/SeekButton
@onready var _return_button: Button = $UI/ReturnButton
@onready var _debug: DebugOverlay = $DebugOverlay
@onready var _debug_button: Button = $UI/DebugButton
@onready var _day_tint: CanvasModulate = $DayTint
@onready var _vignette: ColorRect = $Vignette/Rect
@onready var _pollen: CPUParticles2D = $Camera2D/Pollen
@onready var _goal_label: Label = $UI/GoalLabel
@onready var _fade: ColorRect = $Fade/Rect
@onready var _shop: ShopController = $UI/ShopPanel

# Per-mechanic directors, created in _build_world. Each owns one self-contained world mechanic so this
# controller can stay a conductor — it builds the world and drives the directors, rather than being
# every mechanic itself. See scripts/presentation/mechanics/.
var _hunt_dir: HuntDirector

var _interactables: Array = []  # examinable things: [ { pos, label, id, tags, kind, render_index, hunt_index? } ]
var _portals: Array = []  # walk-through doorways: [ { id, pos, target_world, target_portal, render_index, armed } ]
# THE RUIN (companion-as-actor puzzle): ward state is now SERVER-AUTHORITATIVE (shared across everyone
# in the world). This client DETECTS its own companion's actions and reports abstract intents (uncover /
# occupy) to the server, then RENDERS whatever ward state the server echoes back (Net.ward_state_received)
# — so two players' companions can work the same wards and converge on one truth. Each ward dict carries
# the per-ward geometry for detection plus local flags mirroring the server (found/open) and which
# intents we've already sent. Empty in worlds without a "ruin" spec block.
var _wards: Array = []  # [ { id, plate, uncover_r, occupy_r, slab_id, slab_render_index, plate_render_index, hint, found, revealed, open, uncover_sent, occupied_sent } ]
var _seeking := false   # true while a "go look" search is out, so only a delegated sweep uncovers a plate
var _seek_shown := false  # whether the contextual "Go look" button is currently faded in
# Cistern gloom: while you stand in the dark chamber with its light-ward unlit, darken the whole scene
# (the cue that makes you name the need — "this place needs light"). Lifts as the brazier catches.
const CARRY_REACH := 38.0  # how near the companion must get to "arrive" at the source / the brazier
const HALL_REFRESH := 1.0   # seconds between re-issuing a Paired-Hall plate hold (before its hold lapses)
# Ambient gloom: the screen eases toward GLOOM_DARK by the player's current region's "gloom" (0 = the
# bright Wood, rising as you descend into the ruin). CISTERN_UNLIT is the extra dark its light-ward
# chamber holds until the brazier is relit. See docs/the-ruin-narrative-and-world.md.
const GLOOM_DARK := Color(0.24, 0.28, 0.28)
const CISTERN_UNLIT := 0.88
var _gloom := 0.0
var _gloom_rect := Rect2()
var _gloom_ward: Dictionary = {}
var _region_glooms: Array = []  # [ { rect: Rect2, gloom: float } ] — per-region ambient darkness
var _base_day_tint := Color.WHITE
# Cached so the slab's collider can be removed when a ward opens (rebuild Solids without it).
var _world_data: Dictionary = {}
var _border_pts: Array = []
var _collision_cfg: Dictionary = {}
var _body_radius := 6.0
var _collision_margin := 2.0
# THE HEDGE MAZE: a "reach_center" goal. Reaching the centre plaza pays coins (server-decides,
# gated on the goal type) and the way home is the portal there; a Return button bails out anytime.
var _maze_active := false        # true in a world whose goal.type is "reach_center"
var _maze_center := Vector2.ZERO # the heart of the maze (world pos)
var _maze_radius := 70.0         # how near counts as "reached"
var _maze_reached := false       # latched once reached this visit, so the reward fires once
# The companion's "point the way" hint: after standing still a while, the companion subtly points
# along the SOLVED PATH to the centre. The path direction per cell is authored in the spec's
# "maze_guide" flow field (1=N 2=E 3=S 4=W, 0=centre) — pure presentation, it never moves the player.
const MAZE_HINT_DELAY := 5.0      # seconds stood still before the companion points the way
const MAZE_HINT_STRENGTH := 0.5   # a gentle, subtle point (1.0 is the hunt's full lock-on)
const MAZE_HINT_REACH := 88.0     # how far ahead (px) to place the point target
const MAZE_MOVE_EPS := 0.6        # per-frame move (px) under which the player counts as standing still
var _maze_guide_origin := Vector2.ZERO  # world centre of cell (0,0)
var _maze_guide_pitch := 100.0          # world distance between adjacent cell centres
var _maze_guide_cols := 0
var _maze_guide_rows := 0
var _maze_guide_dirs: Array = []        # row-major (cy*cols + cx) path-direction codes
var _maze_idle := 0.0            # seconds the player has stood still
var _maze_pointing := false      # whether the companion is currently giving the hint
var _last_player_pos := Vector2.ZERO  # to measure per-frame movement for the idle timer
# The Return-to-the-Vale escape hatch: where it sends you (from the spec's "return" block), or "" if
# this world declares none (so the button stays hidden everywhere but the maze).
var _return_world := ""
var _return_portal := ""
var _return_shown := false
var _home_world := ""  # where this world's portals (incl. the completion one) lead back to
var _home_portal := ""
var _completion_hint := ""  # the hint shown when the maze ended, so the coin reward can append to it
var _transitioning := false  # true once a portal transition's fade has begun
# The content etag of the spec we actually BUILT this scene from (Net.cached_etag at build time), or
# "" if we haven't built yet (still on the loading screen). Lets _on_world_spec_arrived tell "first
# paint" and "the world changed under us" apart from "the spec we already built just got reconfirmed".
var _built_etag := ""
# False until _build_world finishes. The per-frame callbacks (_process / _unhandled_input) early-return
# while it's false, so they never run against a not-yet-built world on a cold first visit (when _ready
# defers the build until the server's spec arrives).
var _world_built := false
# The bazaar shop: the merchant's stationary companion (a puppet), and the economy snapshot the
# server pushes on join (our wallet + the color stock). Empty/absent in worlds without a shopkeeper.
var _npc_companion: CompanionView = null
var _shop_colors: Array = []     # [ { item_def_id, name, swatch, price, owned, … } ], from Net
var _shop_balance := 0
var _shop_currency := "coins"
var _examine_shown := false  # whether the touch Examine button is currently faded in
var _pet_shown := false  # whether the contextual Pet button is currently faded in
var _reset_shown := false  # whether the "new companion" button is currently faded in
var _leave_shown := false  # whether the "leave" button is currently faded in (only while connected)
var _intro_tween: Tween  # fades the opening "how to move" hint away after a few seconds
var _style: ArtStyle
var _day_enabled := false
var _day_period := 480.0
var _day_loop := true
var _day_stops: Array = []  # [ { t, tint:Color, vig:Color, vstr:float } ], sorted by t
var _day_time := 0.0

# --- Shared presence (Rung 3) -----------------------------------------------------------------
# Each connected peer's PUPPET pair, keyed by Net peer id (the player's user_id): { peer_id: { player, companion } }.
# Spawned on peer_joined, freed on peer_left, and driven entirely by transforms arriving over Net.
# An identity packet that lands before its pair exists is stashed and applied the moment it spawns.
var _remote_pairs: Dictionary = {}
var _pending_identity: Dictionary = {}
var _bounds_rect := Rect2()  # the world's walkable bounds, kept to CLAMP untrusted remote positions
var _net_accum := 0.0        # accumulates toward the next NET_SEND_INTERVAL broadcast
var _save_accum := 0.0       # accumulates toward the next server SAVE_INTERVAL push


func _ready() -> void:
	# Which world to load is owned by WorldRouter (a platform world_id; defaults to the Vale on a fresh
	# boot). The spec is SERVER-CANONICAL — there is no bundled copy — so we either build now from Net's
	# cache (revisit / warm disk cache) or, on a cold first visit, show a loading screen and build the
	# moment the spec arrives. We also stay subscribed so a world that changes on the server while we're
	# standing in it rebuilds itself, no new client build required (see _on_world_spec_arrived).
	var world_id := WorldRouter.current_world
	Net.world_spec_received.connect(_on_world_spec_arrived)
	var data := Net.cached_spec_core(world_id)
	if data.is_empty():
		_show_loading()
		Net.enter_world(world_id)  # fetch; _build_world runs from _on_world_spec_arrived when it lands
		return
	_built_etag = Net.cached_etag(world_id)
	_build_world(data)


## Build the whole world from its (server-provided) spec CORE: lay out contents, place the player and
## companion, draw it, wire collisions, regions, the UI buttons, and shared presence. Called straight
## from _ready when the spec is already cached, or from _on_world_spec_arrived on a cold first visit.
func _build_world(data: Dictionary) -> void:
	var arrival_id := WorldRouter.arrival_portal_id

	# Shared art direction (palette + light): the one place the whole look is tuned.
	_style = ArtStyle.load_style(ART_PATH)
	_player.set_style(_style)
	_companion.set_style(_style)
	_companion.setup(_player)

	# Spin up the per-mechanic directors and hand each the scene refs it drives. Created before
	# _setup_contents so they can lay out their own content (e.g. the hunt's rocks). Children of this
	# node, so their Net connections are auto-dropped when the scene reloads on a world hop.
	_create_directors()

	# If this world carries a salamander-hunt goal, lay it out (fresh + random each visit) and
	# fold its rocks — and this world's portals — into data["interactables"] so world_art draws
	# them. Populates the hunt, its rocks and _portals; leaves worlds without a goal/portals untouched.
	_setup_contents(data, arrival_id)

	# Spawn beside the arrival portal if we travelled here, else at the world's own spawn points.
	_place_arrivals(data, arrival_id)
	_last_player_pos = _player.position  # baseline for the maze idle-timer's movement check

	_world_art.render_world(data, _style)
	_apply_atmosphere(data.get("atmosphere", {}))
	_setup_daycycle(_style.daycycle())

	# Fade in from black if we arrived through a portal; otherwise start fully clear.
	_setup_fade()

	var bmin := WorldData.to_vec2(data["bounds"]["min"])
	var bmax := WorldData.to_vec2(data["bounds"]["max"])
	var bounds_rect := Rect2(bmin, bmax - bmin)
	_bounds_rect = bounds_rect
	_camera.set_bounds(bounds_rect)

	# Barriers: build the solid list once (trees incl. the procedural border ring, tall
	# props, great-trees, ponds) and hand it to both characters to collide against. The
	# border positions come from the same pure helper the renderer uses, so the drawn
	# treeline and its colliders match exactly.
	var ccfg: Dictionary = data.get("collision", {})
	var border_pts := Solids.border_positions(bounds_rect, data.get("border", {}))
	# Spawn the trees (hand-placed + this border ring + landmarks) into the y-sorted
	# Scenery layer, using the same border points as the colliders so drawing matches.
	_scenery.populate(data, border_pts, _style)
	var solids := Solids.build(data, border_pts, ccfg)
	var body_radius := float(ccfg.get("body_radius", 6.0))
	var margin := float(ccfg.get("margin", 2.0))
	_player.set_solids(solids, bounds_rect, body_radius, margin)
	_companion.set_solids(solids, bounds_rect, body_radius, margin)

	# Keep what the Ruin needs to REBUILD collisions when a slab rises (drop the slab's solid and
	# re-hand the list to both bodies — see _open_ward). Harmless to cache in worlds without a ruin.
	_world_data = data
	_border_pts = border_pts
	_collision_cfg = ccfg
	_body_radius = body_radius
	_collision_margin = margin

	# THE RUIN: build the ward logic + geometry from the spec's "ruin" block (no-op elsewhere).
	_setup_ruin(data)

	# (The examinable interactables, the portals, the hunt and the companion's points of
	# interest were all assembled in _setup_contents above, before the world was drawn.)

	# Hand the companion the world's id and named regions, so it can feel the bond of
	# reaching a new area (resolved from its own position; see WorldAreas / CompanionSelf).
	var regions: Array = []
	for r in data.get("regions", []):
		regions.append({ "id": String(r.get("id", "region")), "min": WorldData.to_vec2(r["min"]), "max": WorldData.to_vec2(r["max"]) })
	_companion.set_world_areas(String(data.get("world_id", "")), regions)

	# The bazaar's shopkeeper keeps their bonded companion at their side — spawn it as a stationary
	# puppet (no-op in worlds without one).
	_spawn_npc_companion(data)

	# Touch: tapping the on-screen button examines. Wire it up and keep its taps
	# from also spinning up the movement thumbstick underneath it.
	_examine_button.pressed.connect(_try_interact)
	_joystick.add_exclusion(_examine_button)

	# Call / whistle: always available (it's a bid for attention, not gated on a nearby prop).
	# Keep its taps off the movement thumbstick underneath. Desktop: C (see _unhandled_input).
	_call_button.pressed.connect(_try_call)
	_joystick.add_exclusion(_call_button)

	# Pet: a contextual affordance, faded in only when standing beside the companion (see
	# _process). Keep its taps off the thumbstick. Desktop: E (see _unhandled_input).
	_pet_button.pressed.connect(_try_pet)
	_joystick.add_exclusion(_pet_button)

	# Top-right "start over" button: only revealed once fully bonded (see _process).
	_reset_button.pressed.connect(_on_reset_pressed)
	_joystick.add_exclusion(_reset_button)

	# Top-right "Leave" button: the player-initiated way out of a session. Faded in only while
	# connected (see _process), so it never shows in the solo/disconnected gate state. Keep its
	# taps off the movement thumbstick underneath.
	_leave_button.pressed.connect(_on_leave_pressed)
	_joystick.add_exclusion(_leave_button)

	# "Go look": send the companion off to search (the Ruin's spine). Faded in only in a world with
	# an unsolved ward (see _process). Keep its taps off the movement thumbstick underneath.
	_seek_button.pressed.connect(_try_seek)
	_joystick.add_exclusion(_seek_button)

	# Top-left "Return to the Vale" button: an always-available escape hatch out of the maze (in case
	# you get lost or bored). Faded in only in a world that declares a "return" target (see _process).
	# Keep its taps off the movement thumbstick underneath.
	_return_button.pressed.connect(_on_return_pressed)
	_joystick.add_exclusion(_return_button)

	# Dev-only companion/bond readout. On by default; the DBG button (and F3 on
	# desktop) toggles it. Exclude its taps from the movement thumbstick underneath.
	_debug.setup(_companion, _player)
	_debug_button.pressed.connect(_debug.toggle)
	_joystick.add_exclusion(_debug_button)

	# The bazaar shop window: a buy relays to the server (Net), a close just resumes the world.
	_shop.buy_requested.connect(_on_shop_buy)
	_shop.closed.connect(_on_shop_closed)

	# Opening instruction, then let it quietly fade so the world isn't framed by UI
	# text while you wander. Any real prompt (Examine ...) cancels the fade and shows.
	if not _wards.is_empty():
		_hint.text = "An old slab bars the way deeper.  Tap Go look to send your companion searching."
	else:
		_hint.text = "Wander with arrows / WASD or drag.  Space or tap Examine to look closer."
	_hint.modulate.a = 1.0
	_intro_tween = create_tween()
	_intro_tween.tween_interval(5.0)
	_intro_tween.tween_property(_hint, "modulate:a", 0.0, 1.4)

	# Shared presence: hand Net our identity once, and listen for peers arriving/moving/leaving.
	# Everything here is a no-op until the player actually Hosts/Joins via the lobby.
	_setup_net()

	# The world is now fully assembled: let the per-frame logic (_process / _unhandled_input) run. Until
	# this point — on a cold first visit we sit on the loading screen with no companion/interactables set
	# up yet — those callbacks early-return, so they never touch half-built state.
	_world_built = true


## Create the per-mechanic directors as children of this node and hand each the scene refs it drives.
## A child is freed with this node on a world hop, which auto-drops its Net signal connections — so a
## fresh scene gets fresh directors with no stale wiring carried over.
func _create_directors() -> void:
	_hunt_dir = HuntDirector.new()
	add_child(_hunt_dir)
	_hunt_dir.setup(self, _companion, _world_art, _player)


# ── Host seam: the small set of shared-world operations the mechanic directors call back into. Kept
# public so each director can stay focused on its own mechanic and lean on the controller for the
# things that are genuinely world-wide (the hint line, the goal HUD, portals, the wallet). ──

## Show a hint at full opacity (the directors' one channel to the hint line).
func show_hint(text: String) -> void:
	_show_hint(text)


## Set the goal HUD label's text (the hunt's progress / the maze's banner).
func set_goal_label_text(text: String) -> void:
	_goal_label.text = text


## Show or hide the goal HUD label.
func show_goal_label(shown: bool) -> void:
	_goal_label.visible = shown


## A small celebratory pop of the goal counter (the hunt pops it on each find).
func bounce_goal() -> void:
	_goal_label.scale = Vector2(1.25, 1.25)
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(_goal_label, "scale", Vector2.ONE, 0.28)


## Adopt a new wallet balance pushed by a server reward (so the shop is current next time it opens).
func set_wallet_balance(balance: int) -> void:
	_shop_balance = balance


## Assemble everything the player can touch in this world: fold the salamander-hunt rocks (if
## any) and the portals into data["interactables"] so world_art draws them, and build the
## runtime lists the controller acts on — _interactables (examinable: props + rocks), _portals
## (walk-through; the HuntDirector owns the rocks themselves), and the companion's points of interest.
## Props keep their original index (== their render index in world_art); rocks then portals are appended after. The
## companion is given props as POIs but NOT rocks: it reacts to a salamander you uncover, but is
## never led to the rocks (the search stays yours). arrival_id disarms the portal we arrived at.
func _setup_contents(data: Dictionary, arrival_id: String) -> void:
	_interactables.clear()
	_portals.clear()
	_maze_active = false
	_maze_reached = false
	_maze_idle = 0.0
	_maze_pointing = false
	_maze_guide_dirs = []
	_return_world = ""
	_return_portal = ""

	var combined: Array = data.get("interactables", []).duplicate()

	var poi: Array = []
	var poi_meta: Array = []
	for i in combined.size():
		var it: Dictionary = combined[i]
		var prop_id := String(it.get("id", it.get("type", "prop_%d" % i)))
		# A "shopkeeper" prop is examinable like any other, but Examining it opens the shop window
		# instead of the cozy examine beat — keyed off this kind in _try_interact.
		var kind := "shopkeeper" if String(it.get("type", "")) == "shopkeeper" else "prop"
		var entry := {
			"pos": WorldData.to_vec2(it["position"]),
			"label": String(it.get("label", "something")),
			"id": prop_id,
			"tags": it.get("tags", []),
			"kind": kind,
			"render_index": i,
		}
		_interactables.append(entry)
		poi.append(entry["pos"])
		poi_meta.append({ "pos": entry["pos"], "id": prop_id, "tags": entry["tags"] })
	_companion.set_points_of_interest(poi, poi_meta)

	# The salamander hunt: hand its layout to the HuntDirector, which hides the salamanders + decoys
	# among the rocks (fresh, random each visit) and folds each rock into `combined` (so world_art
	# draws it) and _interactables (so it can be turned over). A no-op in worlds without the goal.
	var goal: Dictionary = data.get("goal", {})
	_hunt_dir.setup_hunt(goal, data.get("rocks", []), combined, _interactables)

	# The hedge maze: a "reach_center" goal. We only need the centre + radius here to notice when the
	# player reaches the heart (see _process); the coin reward itself is decided + minted server-side.
	if String(goal.get("type", "")) == "reach_center":
		_maze_active = true
		_maze_center = WorldData.to_vec2(goal.get("center", [0, 0]))
		_maze_radius = float(goal.get("radius", 70.0))
		# The flow field the companion points along (the solved path per cell, toward the centre).
		var guide: Dictionary = data.get("maze_guide", {})
		_maze_guide_dirs = guide.get("dirs", [])
		if not _maze_guide_dirs.is_empty():
			_maze_guide_origin = WorldData.to_vec2(guide.get("origin", [0, 0]))
			_maze_guide_pitch = float(guide.get("pitch", 100.0))
			_maze_guide_cols = int(guide.get("cols", 0))
			_maze_guide_rows = int(guide.get("rows", 0))

	# The Return-to-the-Vale escape hatch: a world may declare where its Return button leads.
	var ret: Dictionary = data.get("return", {})
	if ret.has("world"):
		_return_world = String(ret["world"])
		_return_portal = String(ret.get("portal", ""))
		if ret.has("label"):
			_return_button.text = String(ret["label"])

	# Portals: walk-through doorways (not examinable). The one we arrived at starts DISARMED so
	# we step OUT of it rather than straight back through. Remember where they lead "home" so a
	# runtime completion portal can reuse it.
	for pd in data.get("portals", []):
		var p_render_index := combined.size()
		var pos := WorldData.to_vec2(pd["position"])
		combined.append({ "id": pd["id"], "type": "portal", "position": pd["position"], "color": pd.get("color", [0.74, 0.66, 0.96]), "label": pd.get("label", "a portal") })
		_portals.append({
			"id": String(pd["id"]),
			"pos": pos,
			"target_world": String(pd["target_world"]),
			"target_portal": String(pd["target_portal"]),
			"render_index": p_render_index,
			"armed": String(pd["id"]) != arrival_id,
		})
		_home_world = String(pd["target_world"])
		_home_portal = String(pd["target_portal"])

	data["interactables"] = combined

	# Per-world companion tuning: a world may quieten the companion's wandering and keep it close
	# (e.g. the riverbank, so it stays at your side to point out salamanders). Merged over the global
	# companion.json defaults here, after the brain exists and before its first update.
	if data.has("companion"):
		_companion.apply_config_overrides(data["companion"])

	if _hunt_dir.is_active():
		_goal_label.visible = true
		_hunt_dir.show_initial_goal()
	elif _maze_active:
		_goal_label.visible = true
		_goal_label.text = String(goal.get("label", "Find the heart of the maze"))
	else:
		_goal_label.visible = false


## Put the player and companion down: beside the named arrival portal if we travelled here
## (stepping OUT of it), otherwise at the world's authored spawn points.
func _place_arrivals(data: Dictionary, arrival_id: String) -> void:
	var p_spawn := WorldData.to_vec2(data["player_spawn"])
	var c_spawn := WorldData.to_vec2(data["companion_spawn"])
	if arrival_id != "":
		for pd in data.get("portals", []):
			if String(pd["id"]) == arrival_id:
				var ppos := WorldData.to_vec2(pd["position"])
				# Default: step OUT to the south of the portal. A portal may override "arrival_offset"
				# (e.g. the Ruin drops you to the NORTH, on the ruin side, so the way in leads away from
				# the portal rather than back through it).
				var off := WorldData.to_vec2(pd["arrival_offset"]) if pd.has("arrival_offset") else Vector2(0, 44)
				p_spawn = ppos + off
				c_spawn = ppos + off + Vector2(-26, 16)
				break
	_player.position = p_spawn
	_companion.position = c_spawn


## Black transition overlay: fade IN from black if we just arrived through a portal, else start
## fully clear. (The fade-OUT to black happens in _begin_transition when stepping into a portal.)
func _setup_fade() -> void:
	var c := _fade.color
	if WorldRouter.take_pending_transition():
		c.a = 1.0
		_fade.color = c
		create_tween().tween_property(_fade, "color:a", 0.0, 0.5)
	else:
		c.a = 0.0
		_fade.color = c


## Show a hint at full opacity, cancelling the opening fade if it's still running, so
## prompts (and the reset message) are always readable even after the intro faded out.
func _show_hint(text: String) -> void:
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	_hint.text = text
	_hint.modulate.a = 1.0


## Push the world's presentation-only mood knobs into the scene nodes that render
## them: the global warm color-wash (CanvasModulate), the screen-edge vignette, and
## the drifting pollen. All data-driven from the world spec's "atmosphere" block, with
## defaults so a world without the block still looks right.
func _apply_atmosphere(atmo: Dictionary) -> void:
	if atmo.has("day_tint"):
		_day_tint.color = WorldData.to_color(atmo["day_tint"])

	var vig: Dictionary = atmo.get("vignette", {})
	var mat := _vignette.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("strength", float(vig.get("strength", 0.34)))
		mat.set_shader_parameter("tint", WorldData.to_color(vig.get("color", [0.06, 0.05, 0.10])))

	var pol: Dictionary = atmo.get("pollen", {})
	_pollen.amount = maxi(1, int(pol.get("amount", 34)))
	var pc := WorldData.to_color(pol.get("color", [1.0, 0.96, 0.74]))
	pc.a = 0.45
	_pollen.color = pc


## Parse the day→dusk cycle config into sorted stops we can interpolate between.
func _setup_daycycle(cfg: Dictionary) -> void:
	_day_enabled = bool(cfg.get("enabled", false))
	_day_period = maxf(1.0, float(cfg.get("period_sec", 480.0)))
	_day_loop = bool(cfg.get("loop", true))
	_day_stops.clear()
	for s in cfg.get("stops", []):
		_day_stops.append({
			"t": float(s.get("t", 0.0)),
			"tint": WorldData.to_color(s.get("tint", [1.0, 1.0, 1.0])),
			"vig": WorldData.to_color(s.get("vignette", [0.06, 0.05, 0.10])),
			"vstr": float(s.get("vstrength", 0.34)),
		})
	_day_stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	if _day_enabled and _day_stops.size() >= 2:
		_apply_daycycle(0.0)  # start at the first stop so a fresh load looks like "day"


## Apply the cycle at normalized progress u in [0,1]: lerp the warm wash + vignette
## between the two bracketing stops.
func _apply_daycycle(u: float) -> void:
	var a: Dictionary = _day_stops[0]
	var b: Dictionary = _day_stops[_day_stops.size() - 1]
	for i in range(_day_stops.size() - 1):
		if u >= float(_day_stops[i]["t"]) and u <= float(_day_stops[i + 1]["t"]):
			a = _day_stops[i]
			b = _day_stops[i + 1]
			break
	var span := maxf(0.0001, float(b["t"]) - float(a["t"]))
	var k := clampf((u - float(a["t"])) / span, 0.0, 1.0)
	_day_tint.color = (a["tint"] as Color).lerp(b["tint"], k)
	var mat := _vignette.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("tint", (a["vig"] as Color).lerp(b["vig"], k))
		mat.set_shader_parameter("strength", lerpf(float(a["vstr"]), float(b["vstr"]), k))


func _process(delta: float) -> void:
	# Nothing to drive until the world is built (on a cold first visit we're still waiting on the spec;
	# the lobby gate is what's on screen). Building wires up the companion, interactables and net.
	if not _world_built:
		return

	# Slow ambient day→dusk drift, if enabled, driving the warm wash + vignette.
	if _day_enabled and _day_stops.size() >= 2:
		_day_time += delta
		var u := fmod(_day_time, _day_period) / _day_period
		if _day_loop:
			u = 1.0 - absf(2.0 * u - 1.0)  # ping-pong: day → dusk → day
		_apply_daycycle(u)

	# Surface a gentle prompt — and the touch Examine button — when standing near
	# something to examine.
	var nearest := _nearest_interactable()
	if nearest >= 0:
		_show_hint("Examine %s" % _interactables[nearest]["label"])
		_set_examine_visible(true)
	else:
		_set_examine_visible(false)
		if _hint.text.begins_with("Examine "):
			_hint.text = ""

	# Surface the Pet affordance only when standing right beside the companion.
	_set_pet_visible(_player.position.distance_to(_companion.position) <= PET_RANGE)

	# Reveal the "new companion" button only once the bond is full.
	_set_reset_visible(_companion.is_fully_bonded())

	# Offer the way out only while we're actually in a session.
	_set_leave_visible(Net.is_active())

	# Offer the Return-to-the-Vale escape hatch in any world that declares one (the maze), while
	# connected — so you can always bail out if you get lost.
	_set_return_visible(_return_world != "" and Net.is_active())

	# The hedge maze: the moment the player reaches the heart, claim the reward (once per visit).
	if _maze_active and not _maze_reached and _player.position.distance_to(_maze_center) <= _maze_radius:
		_on_maze_reached()

	# "Go look" is offered only in a Ruin with a ward still to open.
	_set_seek_visible(not _wards.is_empty() and _any_ward_unopened())

	# Walk-through portals, the companion's subtle salamander glance, and the Ruin's ward referee.
	_update_portals(delta)
	_hunt_dir.update_detector(delta)
	_update_maze_hint(delta)
	_update_ruin(delta)
	_update_gloom(delta)

	# Shared presence: stream our own pair's transforms to peers at ~20 Hz (a no-op when offline).
	_broadcast_presence(delta)
	_push_save_periodic(delta)


## Gently fade the touch Examine button in or out as the player nears a prop, so
## it signals "something's here" without cluttering the screen while wandering.
func _set_examine_visible(show_button: bool) -> void:
	if show_button == _examine_shown:
		return
	_examine_shown = show_button
	if show_button:
		_examine_button.visible = true
	var tween := create_tween()
	tween.tween_property(_examine_button, "modulate:a", 1.0 if show_button else 0.0, 0.18)
	if not show_button:
		tween.tween_callback(func() -> void: _examine_button.visible = false)


## Gently fade the touch Pet button in when beside the companion, out otherwise — mirrors the
## Examine fade, so the affordance signals "you can pet it now" without cluttering the screen.
func _set_pet_visible(show_button: bool) -> void:
	if show_button == _pet_shown:
		return
	_pet_shown = show_button
	if show_button:
		_pet_button.visible = true
	var tween := create_tween()
	tween.tween_property(_pet_button, "modulate:a", 1.0 if show_button else 0.0, 0.18)
	if not show_button:
		tween.tween_callback(func() -> void: _pet_button.visible = false)


## Gently fade the "new companion" button in once fully bonded, out otherwise —
## mirrors the Examine button's fade so the screen stays uncluttered until it matters.
func _set_reset_visible(show_button: bool) -> void:
	if show_button == _reset_shown:
		return
	_reset_shown = show_button
	if show_button:
		_reset_button.visible = true
	var tween := create_tween()
	tween.tween_property(_reset_button, "modulate:a", 1.0 if show_button else 0.0, 0.18)
	if not show_button:
		tween.tween_callback(func() -> void: _reset_button.visible = false)


## Gently fade the "Leave" button in while connected, out otherwise — mirrors the other
## contextual buttons so the screen stays uncluttered, and so it's absent the moment there's
## no session to leave.
func _set_leave_visible(show_button: bool) -> void:
	if show_button == _leave_shown:
		return
	_leave_shown = show_button
	if show_button:
		_leave_button.visible = true
	var tween := create_tween()
	tween.tween_property(_leave_button, "modulate:a", 1.0 if show_button else 0.0, 0.18)
	if not show_button:
		tween.tween_callback(func() -> void: _leave_button.visible = false)


## Leave the session on purpose. Persist the companion one last time (the graceful close in
## Net.leave flushes it), then drop the link — which surfaces as disconnected() and brings the
## lobby gate back up, ready to reconnect. The remote puppets are cleaned up by _on_disconnected.
func _on_leave_pressed() -> void:
	if Net.is_active():
		_push_save()
	Net.leave()


## Gently fade the "Return to the Vale" button in while this world declares a return target (the
## maze) and we're connected, out otherwise — mirrors the other contextual buttons.
func _set_return_visible(show_button: bool) -> void:
	if show_button == _return_shown:
		return
	_return_shown = show_button
	if show_button:
		_return_button.visible = true
	var tween := create_tween()
	tween.tween_property(_return_button, "modulate:a", 1.0 if show_button else 0.0, 0.18)
	if not show_button:
		tween.tween_callback(func() -> void: _return_button.visible = false)


## The Return-to-the-Vale escape hatch: fade to black and travel back to the world/portal this world
## declared (its "return" block). Reuses the portal transition latch so it can't double-fire with a
## portal step. A no-op if there's no return target.
func _on_return_pressed() -> void:
	if _transitioning or _return_world == "":
		return
	_transitioning = true
	_show_hint("You slip back to the Vale…")
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	tw.tween_callback(func() -> void: WorldRouter.go_to(_return_world, _return_portal))


## Start a fresh companion (immediate, no confirm — the button only appears once you
## have a fully bonded companion to start over from). It hides itself again until the
## new companion bonds.
func _on_reset_pressed() -> void:
	_companion.reset()
	_set_reset_visible(false)
	_show_hint("A new companion blinks into the world beside you.")


func _unhandled_input(event: InputEvent) -> void:
	# Input does nothing until the world is built (the lobby owns the screen until then).
	if not _world_built:
		return
	if event.is_action_pressed("ui_accept"):
		_try_interact()
	# Desktop convenience keys, matching the project's physical-key convention (no InputMap):
	# C calls the companion over. Space/Enter stays Examine.
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_C:
			_try_call()
		elif event.physical_keycode == KEY_E:
			_try_pet()


## Whistle for the companion. Whether it hears, acknowledges, and actually comes is up to the
## brain and the bond (see ComeAction) — here we just issue the order and nudge the player.
func _try_call() -> void:
	_companion.issue_command("come")
	_show_hint("You whistle for your companion.")


## Pet the companion when you're beside it. Whether it leans in or shies away is up to the
## brain and the bond (see PetAction); out of range the command quietly no-ops.
func _try_pet() -> void:
	if _player.position.distance_to(_companion.position) > PET_RANGE:
		return
	_companion.issue_command("pet")
	_show_hint("You reach out to your companion.")


func _try_interact() -> void:
	var index := _nearest_interactable()
	if index < 0:
		return
	var entry: Dictionary = _interactables[index]
	if String(entry["kind"]) == "rock":
		_hunt_dir.examine_rock(entry)
		return
	if String(entry["kind"]) == "shopkeeper":
		_open_shop(entry)
		return
	_world_art.pulse_interactable(int(entry["render_index"]))
	_companion.notify_interaction(entry["pos"], String(entry["id"]), entry["tags"])
	# KINDLE the Cistern ember: examining the dead ember is the deduction — naming that this place needs
	# light. It wakes the ember (its art) and stands in for the light-ward's 'uncover' (found) on the
	# server, arming the carry. Idempotent (only the first kindle of an unlit ward does anything).
	var lw := _light_ward_for_source(String(entry["id"]))
	if not lw.is_empty() and not bool(lw["open"]) and not bool(lw["kindled"]):
		lw["kindled"] = true
		var eri := int(lw["ember_render_index"])
		if eri >= 0:
			_world_art.open_slab(eri)
		Net.send_ward_uncover(String(lw["id"]))
		_show_hint("You breathe on the old ember — it wakes, and a mote of light lifts free. Now send your companion to carry it.")
		return
	# Jam the WEDGE onto a plate (the lonely Paired-Hall workaround): examining the wedge holds the plate
	# nearest it, so your one companion is free to stand the other. _update_hall keeps the wedge's weight
	# reported even after the companion leaves.
	var hw := _paired_ward_for_wedge(String(entry["id"]))
	if not hw.is_empty() and not bool(hw["open"]):
		var key := _nearest_plate_key(hw, entry["pos"])
		if key != "":
			hw["wedged"] = key
			_show_hint("Your companion drags the wedge onto the near plate — it settles, and the stone holds it down. Now send it to stand the other.")
		return
	# Examining an unsolved Ruin slab nudges you toward the real move — sending your companion.
	var ward := _ward_for_slab(String(entry["id"]))
	if not ward.is_empty() and not bool(ward["open"]):
		_show_hint(String(ward.get("hint", "The slab won't budge. Maybe your companion can find what works it.")))
		return
	_show_hint("You examine %s. Your companion perks up." % entry["label"])


# ============================================================================================
# THE RUIN — the companion-as-actor puzzle, SHARED. The authoritative ward state now lives on the
# SERVER (Server.RuinMechanisms, per world), so everyone present converges on one truth. This client
# only: DETECTS what its OWN companion does (search nosing near a plate; weight stepping on/off) and
# reports abstract intents to the server, then RENDERS whatever ward state the server echoes back
# (reveal the plate, raise the slab). The companion's brain stays truth-blind throughout — it never
# learns where a plate is; the local detection feeds only the intent stream and the body, never the mind.
# ============================================================================================

## Build the Ruin's wards from the spec's "ruin" block: the per-ward geometry this client needs to
## DETECT its companion's actions (where the plate hides, how near to uncover/weight it, which slab it
## raises), plus local flags mirroring the server's authoritative found/open. Resolves each slab's
## render index from the interactables laid out in _setup_contents. No-op in
## worlds without a "ruin" block, so every other world is untouched.
func _setup_ruin(data: Dictionary) -> void:
	_wards.clear()
	_seeking = false
	_gloom_rect = Rect2()
	_gloom_ward = {}
	_base_day_tint = _day_tint.color
	# Per-region ambient gloom (the descent dimmer): cache each region's rect + declared darkness.
	_region_glooms.clear()
	for r in data.get("regions", []):
		if r.has("gloom"):
			var mn := WorldData.to_vec2(r["min"])
			_region_glooms.append({ "id": String(r.get("id", "")), "rect": Rect2(mn, WorldData.to_vec2(r["max"]) - mn), "gloom": float(r["gloom"]) })
	for wd in data.get("ruin", {}).get("wards", []):
		var slab_id := String(wd.get("slab_id", ""))
		# Decoy points (Warren-style wards): identical-looking gaps where the companion's nose says
		# "not here". Drive the which-one tell off these vs. the true plate. Empty for a plain ward.
		var decoys: Array = []
		for d in wd.get("decoys", []):
			decoys.append(WorldData.to_vec2(d))
		# Light-ward (Cistern): has a 'source' (the ember the player kindles) + a brazier + murals. The
		# carry is a directed fetch (source → plate), not a search; kindling stands in for 'uncover'.
		var is_light: bool = wd.has("source")
		var mural_idx: Array = []
		for mid in wd.get("murals", []):
			mural_idx.append(_render_index_for_id(String(mid)))
		# Paired ward (the Paired Hall): two plates that must bear weight AT ONCE. Build the plate list
		# (key → world pos + render index) for the hold logic and the per-plate glow feedback.
		var is_paired: bool = wd.has("plates")
		var plates: Array = []
		var occ_sent := {}
		for pkey in wd.get("plates", []):
			var k := String(pkey)
			plates.append({
				"key": k,
				"pos": WorldData.to_vec2(wd.get("plate_" + k, [0, 0])),
				"render": _render_index_for_id(String(wd.get("plate_" + k + "_id", ""))),
			})
			occ_sent[k] = false
		var ward := {
			"id": String(wd.get("id", "ward")),
			"plate": WorldData.to_vec2(wd.get("plate", [0, 0])),
			"uncover_r": float(wd.get("uncover_radius", 120.0)),
			"occupy_r": float(wd.get("occupy_radius", 34.0)),
			"slab_id": slab_id,
			"slab_render_index": _render_index_for_id(slab_id),
			"plate_render_index": -1,
			"hint": String(wd.get("hint", "")),
			"decoys": decoys,
			"is_light": is_light,
			"source": WorldData.to_vec2(wd.get("source", [0, 0])),
			"source_id": String(wd.get("source_id", "")),
			"ember_render_index": _render_index_for_id(String(wd.get("source_id", ""))),
			"brazier_render_index": _render_index_for_id(String(wd.get("brazier_id", ""))),
			"mural_render_indices": mural_idx,
			"region_rect": _region_rect(data, String(wd.get("region", ""))),
			"kindled": false,
			"carry_phase": "idle",
			# Paired Hall: the two plates, which plate our companion is assigned to hold, which (if any)
			# we've wedged, the occupy we've reported per plate, and the hold-refresh timer.
			"is_paired": is_paired,
			"plates": plates,
			"wedge_id": String(wd.get("wedge_id", "")),
			"assigned": "",
			"wedged": "",
			"occ_sent": occ_sent,
			"refresh": 0.0,
			# Local mirror of the server's authoritative state + which intents we've already sent.
			"found": false,
			"revealed": false,
			"open": false,
			"uncover_sent": false,
			"occupied_sent": false,
		}
		_wards.append(ward)
		# The dark chamber whose gloom we lift on lighting (the light-ward with a region).
		if is_light and (ward["region_rect"] as Rect2).get_area() > 0.0:
			_gloom_rect = ward["region_rect"]
			_gloom_ward = ward


## "Go look": send the companion off to search. _seeking gates the referee so ONLY a delegated
## sweep uncovers a plate — the companion merely trailing you past it does nothing (the search is
## the point). The brain (and bond) decide how the sweep actually goes; here we just issue it.
func _try_seek() -> void:
	if _wards.is_empty() or not _any_ward_unopened():
		return
	# In the Cistern (a dark light-ward chamber), "Go look" is a CARRY, not a search: it can't do anything
	# until you've named the need and woken the ember. Gated to the chamber so it never hijacks the
	# Threshold/Warren search elsewhere.
	var lw := _active_light_ward()
	if not lw.is_empty():
		if not bool(lw["kindled"]):
			_show_hint("Pitch dark — your companion casts about but finds nothing to work. Something here must be lit first.")
		elif String(lw["carry_phase"]) == "idle":
			_begin_carry(lw)
		return
	# In the Paired Hall, "Go look" sends the companion to STAND a plate (and hold it): the nearest one
	# not already wedged, so after jamming the wedge on one you naturally send it to the other.
	var hw := _active_paired_ward()
	if not hw.is_empty():
		var key := _nearest_plate_key(hw, _player.position, true)
		if key == "":
			_show_hint("Both plates are spoken for — the door should be giving way.")
		else:
			hw["assigned"] = key
			hw["refresh"] = 0.0
			_companion.issue_command("settle", _plate_pos(hw, key))
			_show_hint("Your companion crosses to a plate and sets its weight on it. Now the other must be held too.")
		return
	_seeking = true
	_companion.issue_command("seek")
	_show_hint("You send your companion off to search.")


## Run every frame: DETECT what OUR companion is doing and report abstract intents to the server (which
## holds the authoritative shared ward state). Opening is NOT decided here — it arrives via the server's
## echo (_on_ward_state), so every player sees the same gate open. For each not-yet-open ward:
##   • UNCOVER — while a search is out, once our companion's sweep noses within uncover range, predict
##     the reveal locally (so the find feels instant), send our companion to settle, and tell the server.
##   • OCCUPY — once the plate is revealed, report (edge-triggered) our companion stepping on / off it.
func _update_ruin(delta: float) -> void:
	if _wards.is_empty():
		return
	var cpos: Vector2 = _companion.position
	for w in _wards:
		if bool(w["open"]):
			continue
		# Paired ward (Paired Hall): keep our companion on its plate and report our weight per plate.
		if bool(w["is_paired"]):
			_update_hall(w, cpos, delta)
			continue
		# Light-ward (Cistern): advance the carry instead of the search-uncover detection.
		if bool(w["is_light"]):
			_update_carry(w, cpos)
			continue
		# Warren-style ward (has decoys): drive the which-gap TELL — the companion perks and turns toward
		# the TRUE gap as it nears it, so the player can read it and trust it over their own eyes.
		if not w["decoys"].is_empty():
			_drive_nook_tell(w, cpos)
		var near := cpos.distance_to(w["plate"])
		if not bool(w["uncover_sent"]) and _seeking and near <= float(w["uncover_r"]):
			w["uncover_sent"] = true
			_reveal_plate(w, true)                       # local prediction; server echo confirms
			_companion.issue_command("settle", w["plate"])
			Net.send_ward_uncover(String(w["id"]))
		if bool(w["revealed"]):
			var on := near <= float(w["occupy_r"])
			if on != bool(w["occupied_sent"]):
				w["occupied_sent"] = on
				Net.send_ward_occupy(String(w["id"]), on)


## The server's authoritative ward state arrived (on join, or whenever anyone's companion acts): adopt
## it. A ward newly FOUND reveals its plate (so you see one a friend's companion uncovered); a ward newly
## OPEN raises the slab for everyone. Idempotent — our own predicted reveal is already in, so this won't
## double it.
func _on_ward_state(wards: Array) -> void:
	for entry in wards:
		if not (entry is Dictionary):
			continue
		var w := _ward_by_id(String(entry.get("id", "")))
		if w.is_empty():
			continue
		# Paired ward (Paired Hall): light each plate that's bearing weight (the glow everyone sees), and
		# open the door once the server says both hold. No buried plate to reveal.
		if bool(w["is_paired"]):
			var plates_state: Variant = entry.get("plates", {})
			if plates_state is Dictionary:
				for p in w["plates"]:
					_world_art.set_lit(int(p["render"]), bool((plates_state as Dictionary).get(String(p["key"]), false)))
			if bool(entry.get("open", false)) and not bool(w["open"]):
				_open_ward(w)
			continue
		if bool(entry.get("found", false)) and not bool(w["found"]):
			_reveal_plate(w, false)
		if bool(entry.get("open", false)) and not bool(w["open"]):
			_open_ward(w)


## The Warren's "which gap?" TELL — presentation only. While a search is out, when the companion comes
## within (bond-scaled) sense range of the TRUE gap it perks and turns toward it (glance_toward) — a read
## the player can trust over their own eyes. Crucially this uses glance_toward, NOT the salamander point_at:
## point_at FREEZES the body (it's "stop and point out the rock"), which would strand the companion at
## sense range and never let it nose in; a glance only redirects the gaze + perks, so it keeps moving in to
## clear the gap. The decoys get no tell on purpose — its confidence landing on one of several alike gaps
## IS the moment. Scaled by bond, like every tell. The brain never learns the truth: this feeds only the body.
func _drive_nook_tell(w: Dictionary, cpos: Vector2) -> void:
	if not _seeking or bool(w["found"]):
		return
	if cpos.distance_to(w["plate"]) <= lerpf(80.0, 150.0, _companion.bond_value()):
		_companion.glance_toward(w["plate"])


## The active light-ward (Cistern) if you're standing in its dark chamber, else {}. Region-gated so
## "Go look" only means CARRY when you're actually in the Cistern — elsewhere it stays a search.
func _active_light_ward() -> Dictionary:
	for w in _wards:
		if bool(w["open"]) or not bool(w["is_light"]):
			continue
		var rect: Rect2 = w["region_rect"]
		if rect.get_area() > 0.0 and not rect.has_point(_player.position):
			continue
		return w
	return {}


## The light-ward whose ember (source) has this interactable id, or {} — for the kindle.
func _light_ward_for_source(id: String) -> Dictionary:
	for w in _wards:
		if bool(w["is_light"]) and String(w["source_id"]) == id:
			return w
	return {}


## Start the carry: send the companion to FETCH the woken light from the source. _update_carry takes
## it from there (source → brazier → deliver). One leg at a time via the Seek action's "settle".
func _begin_carry(w: Dictionary) -> void:
	w["carry_phase"] = "to_source"
	_companion.issue_command("settle", w["source"])
	_show_hint("Your companion pads off to fetch the light.")


## Advance the Cistern carry each frame: once the companion reaches the source it takes up the mote and
## bears it to the brazier; arriving there is the DELIVERY — reported to the server as the ward's
## 'occupy', which (with the kindle's 'uncover') opens it for everyone. The brazier lighting, the murals
## and the dark lifting all follow from the server's open echo (_open_ward → _light_cistern).
func _update_carry(w: Dictionary, cpos: Vector2) -> void:
	match String(w["carry_phase"]):
		"to_source":
			if cpos.distance_to(w["source"]) <= CARRY_REACH:
				w["carry_phase"] = "to_brazier"
				_companion.issue_command("settle", w["plate"])
				_show_hint("It takes up the mote of light and carries it to the brazier.")
		"to_brazier":
			if cpos.distance_to(w["plate"]) <= float(w["occupy_r"]):
				w["carry_phase"] = "delivered"
				Net.send_ward_occupy(String(w["id"]), true)


# ── The Paired Hall: a door that yields only while BOTH plates bear weight at once. Each client holds
# its OWN companion on a plate (or jams a wedge) and reports its weight PER PLATE; the server combines
# everyone's and opens when all plates hold (see Server.RuinMechanisms paired wards). Two pairs → a
# companion to each; alone → a wedge on one plate, your companion on the other. ──

## Run every frame for the hall: keep our assigned companion standing on its plate (refresh the settle
## before its hold lapses, so a brief lapse can't drop the door), and report our weight on each plate —
## our companion standing on it, OR a wedge we've jammed (which holds even when the companion leaves).
func _update_hall(w: Dictionary, cpos: Vector2, delta: float) -> void:
	if String(w["assigned"]) != "":
		w["refresh"] = float(w["refresh"]) - delta
		if float(w["refresh"]) <= 0.0:
			w["refresh"] = HALL_REFRESH
			_companion.issue_command("settle", _plate_pos(w, String(w["assigned"])))
	for p in w["plates"]:
		var key := String(p["key"])
		var on := cpos.distance_to(p["pos"]) <= float(w["occupy_r"]) or String(w["wedged"]) == key
		if on != bool(w["occ_sent"][key]):
			w["occ_sent"][key] = on
			Net.send_ward_occupy(String(w["id"]), on, key)


## The unopened paired ward whose chamber you're standing in, else {} (region-gated like the Cistern,
## so "Go look" only means "stand a plate" inside the Paired Hall).
func _active_paired_ward() -> Dictionary:
	for w in _wards:
		if bool(w["open"]) or not bool(w["is_paired"]):
			continue
		var rect: Rect2 = w["region_rect"]
		if rect.get_area() > 0.0 and not rect.has_point(_player.position):
			continue
		return w
	return {}


## The paired ward whose wedge has this interactable id, or {} — for the wedge examine.
func _paired_ward_for_wedge(id: String) -> Dictionary:
	for w in _wards:
		if bool(w["is_paired"]) and String(w["wedge_id"]) == id:
			return w
	return {}


## The world pos / render index of a paired ward's plate by key.
func _plate_pos(w: Dictionary, key: String) -> Vector2:
	for p in w["plates"]:
		if String(p["key"]) == key:
			return p["pos"]
	return Vector2.ZERO


## The key of the plate nearest the player (any), or the nearest one NOT already wedged, or "" if none.
func _nearest_plate_key(w: Dictionary, from: Vector2, skip_wedged := false) -> String:
	var best := ""
	var best_d := INF
	for p in w["plates"]:
		if skip_wedged and String(w["wedged"]) == String(p["key"]):
			continue
		var d := from.distance_to(p["pos"])
		if d < best_d:
			best_d = d
			best = String(p["key"])
	return best


## The light-flooding payoff when the great door opens — TIERED by who's present. Solo (you wedged one
## plate, your companion held the other): a muted waking, real but a little lonely. With a second pair
## (≥2 players here): the full waking — the old two glimpsed for a moment. The hint carries it; the door
## itself is opened by _open_ward.
func _wake_paired_hall(w: Dictionary) -> void:
	var present := 1 + _remote_pairs.size()
	if present >= 2:
		_show_hint("Light runs the whole length of the hall — and for a breath, two figures and their companions stand where you do, long ago. The great door swings wide.")
	else:
		_show_hint("With a grind the great door opens — just enough. A single lamp gutters alight in the dark. You did it alone, the patient way.")
	# The Waking: light floods back. Permanently lift the depths' gloom (paired_hall + the sanctum beyond),
	# so stepping through into the reward is the brightest beat since the forest — and, if you're here to
	# witness it, a one-shot warm bloom sweeps the screen (fuller/longer with a second pair present).
	_lift_gloom("paired_hall", 0.12)
	_lift_gloom("sanctum", 0.04)
	# Flash only for someone actually AT the hall to witness it — not on a far re-entry sync, and not
	# jarringly across the map when a friend's pair opens it (the spawn point is ~1340px off).
	var hall_center := _player.position
	if w.has("plate_a") and w.has("plate_b"):
		hall_center = (WorldData.to_vec2(w["plate_a"]) + WorldData.to_vec2(w["plate_b"])) * 0.5
	if _player.position.distance_to(hall_center) < 900.0:
		_play_waking_flash(present >= 2)


## Set the ambient gloom of a named region (used by the Waking to lift the depths once the great door
## opens). No-op if the region declares no gloom. The change is permanent for this visit, so the lit
## sanctum stays bright as you move through it.
func _lift_gloom(region_id: String, value: float) -> void:
	for rg in _region_glooms:
		if String(rg.get("id", "")) == region_id:
			rg["gloom"] = value


## The Waking bloom: a warm, full-screen wash that swells then fades — light flooding back the moment the
## great door opens. Built in code on its own CanvasLayer (above the world, below nothing it needs to read),
## torn down when the tween finishes. `full` (a second pair present) makes it brighter and a touch longer.
func _play_waking_flash(full: bool) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 80
	var rect := ColorRect.new()
	rect.color = Color(1.0, 0.95, 0.82, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	add_child(layer)
	var peak := 0.62 if full else 0.42
	var tw := create_tween()
	tw.tween_property(rect, "color:a", peak, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(rect, "color:a", 0.0, 1.9 if full else 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(layer.queue_free)


## The Cistern lit (server-confirmed open): light the brazier and wake the murals (their clues for the
## Paired Hall). The sealed door and the dark are handled by _open_ward / the gloom, which key off
## the ward being open.
func _light_cistern(w: Dictionary) -> void:
	var bri := int(w["brazier_render_index"])
	if bri >= 0:
		_world_art.open_slab(bri)
	for mi in w["mural_render_indices"]:
		if int(mi) >= 0:
			_world_art.open_slab(int(mi))


## Cistern gloom: while you stand in the dark chamber with its light-ward still unlit, darken the whole
## scene (the CanvasModulate day tint) — the cue that makes you NAME the need. Eases in/out, and lifts
## the moment the brazier catches (the ward opens). No-op in worlds without a Cistern, and skipped if a
## daycycle owns the tint.
func _update_gloom(delta: float) -> void:
	if _day_enabled:
		return
	if _region_glooms.is_empty() and _gloom_ward.is_empty():
		return
	# Ambient darkness of the region you're standing in (the Wood is 0, the depths darker)...
	var target := _region_gloom_at(_player.position)
	# ...and the Cistern's puzzle dark on top: near-black in its chamber until the brazier is lit.
	if not _gloom_ward.is_empty() and not bool(_gloom_ward["open"]) and _gloom_rect.get_area() > 0.0 and _gloom_rect.has_point(_player.position):
		target = maxf(target, CISTERN_UNLIT)
	_gloom = lerpf(_gloom, target, 1.0 - exp(-2.5 * delta))
	_day_tint.color = _base_day_tint.lerp(GLOOM_DARK, _gloom)


## The ambient gloom of the region containing `pos` (first match), or 0 (bright) if none declares one.
func _region_gloom_at(pos: Vector2) -> float:
	for rg in _region_glooms:
		if (rg["rect"] as Rect2).has_point(pos):
			return float(rg["gloom"])
	return 0.0


## Reveal a ward's plate: mark it found, draw the uncovered stone (once), and narrate. `mine` tells the
## finder's snappy "your companion noses it out" beat from the calmer "a plate lies uncovered" a friend's
## search produced. Idempotent on the draw, so the predicted reveal and the server echo never double up.
func _reveal_plate(w: Dictionary, mine: bool) -> void:
	w["found"] = true
	if bool(w["revealed"]):
		return
	w["revealed"] = true
	if bool(w["is_light"]):
		# A light-ward (Cistern): 'found' comes from kindling the ember (already narrated), and the brazier
		# is already drawn — there's no buried plate to reveal here.
		return
	if w["decoys"].is_empty():
		# A buried plate (Threshold-style): spawn its uncovered stone where the search found it.
		w["plate_render_index"] = _world_art.add_interactable(w["plate"], Color(0.62, 0.66, 0.60), "plate")
		_show_hint("Your companion noses through the moss and uncovers a worn stone plate." if mine
			else "A worn stone plate lies uncovered nearby.")
	else:
		# A Warren nook: the gap is already drawn; the clear (open state) is the reveal, so just narrate.
		_show_hint("Your companion noses past the look-alike gaps to the one that truly goes through." if mine
			else "A companion noses out the gap that goes through.")


## A ward opened (server-confirmed): mark it, hoist the slab into a lintel (visual), and DROP its
## collider by rebuilding the solids without it, then re-hand the list to both bodies so the doorway is
## truly walkable — for everyone present, whoever's companion opened it. Rebuilt from a deep copy so the
## (shared, cached) spec stays untouched, which is what lets the Ruin reset closed on a later revisit.
func _open_ward(ward: Dictionary) -> void:
	ward["open"] = true
	_seeking = false
	var sri := int(ward.get("slab_render_index", -1))
	if sri >= 0:
		_world_art.open_slab(sri)
	var data_copy: Dictionary = _world_data.duplicate(true)
	var slab_id := String(ward.get("slab_id", ""))
	for it in data_copy.get("interactables", []):
		if String(it.get("id", "")) == slab_id:
			it["solid"] = false
	var solids := Solids.build(data_copy, _border_pts, _collision_cfg)
	_player.set_solids(solids, _bounds_rect, _body_radius, _collision_margin)
	_companion.set_solids(solids, _bounds_rect, _body_radius, _collision_margin)
	if bool(ward.get("is_paired", false)):
		# The Paired Hall: both plates held — the great door yields. A tiered waking (full with a second
		# pair present, muted alone). Stop holding (the open gate already skips _update_hall).
		ward["assigned"] = ""
		_wake_paired_hall(ward)
	elif bool(ward.get("is_light", false)):
		# The Cistern: the carried light catches — the brazier flares, the murals wake, and the dark lifts
		# (the gloom keys off this ward being open), as the sealed door grinds aside.
		_light_cistern(ward)
		_show_hint("The brazier catches — warm light floods the chamber, the old carvings wake, and the sealed door grinds open.")
	else:
		_show_hint("Stone grinds on stone — the slab rises, and the way lies open.")


## The render index (in world_art's draw list) of the interactable with this id, or -1. Props keep
## their original index there, so this resolves a ward's slab to the thing world_art draws.
func _render_index_for_id(id: String) -> int:
	for e in _interactables:
		if String(e.get("id", "")) == id:
			return int(e.get("render_index", -1))
	return -1


## The world-space rect of the named region (for the Cistern gloom), or an empty Rect2 if none.
func _region_rect(data: Dictionary, name: String) -> Rect2:
	if name == "":
		return Rect2()
	for r in data.get("regions", []):
		if String(r.get("id", "")) == name:
			var mn := WorldData.to_vec2(r["min"])
			return Rect2(mn, WorldData.to_vec2(r["max"]) - mn)
	return Rect2()


## True if any ward is still shut (per our mirror of the server state) — gates the "Go look" affordance.
func _any_ward_unopened() -> bool:
	for w in _wards:
		if not bool(w["open"]):
			return true
	return false


## The ward whose slab has this id (empty dict if none) — for the examine-the-slab nudge.
func _ward_for_slab(slab_id: String) -> Dictionary:
	for w in _wards:
		if String(w["slab_id"]) == slab_id:
			return w
	return {}


## The ward with this id (empty dict if none) — for applying server ward-state echoes.
func _ward_by_id(id: String) -> Dictionary:
	for w in _wards:
		if String(w["id"]) == id:
			return w
	return {}


## Fade the "Go look" button in while a Ruin ward is unsolved, out otherwise — mirrors the other
## contextual buttons so the screen stays uncluttered and it's absent everywhere but the Ruin.
func _set_seek_visible(show_button: bool) -> void:
	if show_button == _seek_shown:
		return
	_seek_shown = show_button
	if show_button:
		_seek_button.visible = true
	var tween := create_tween()
	tween.tween_property(_seek_button, "modulate:a", 1.0 if show_button else 0.0, 0.18)
	if not show_button:
		tween.tween_callback(func() -> void: _seek_button.visible = false)


## Spawn the merchant's bonded companion as a STATIONARY puppet beside them: a CompanionView flagged
## remote (no brain, no save, never moves), parented into the y-sorted Scenery so it depth-sorts with
## everything else, and given its resting-look from the world data. We pin its target transform to its
## standing spot so the remote-puppet ease holds it there (a remote eases toward its target, which
## would otherwise be the origin). No-op in worlds without an "npc_companion" block.
func _spawn_npc_companion(data: Dictionary) -> void:
	var npc: Dictionary = data.get("npc_companion", {})
	if npc.is_empty():
		return
	var rc := COMPANION_SCENE.instantiate() as CompanionView
	rc.set_remote()
	rc.name = "NpcCompanion"
	rc.set_style(_style)
	_scenery.add_child(rc)
	var pos := WorldData.to_vec2(npc.get("position", [0, 0]))
	rc.position = pos
	rc.set_remote_state(pos, Vector2.DOWN)
	var look: Variant = npc.get("look", {})
	if look is Dictionary:
		rc.apply_remote_look(look)
	_npc_companion = rc


## Open the merchant's color shop. A cozy beat first — the merchant's prop pulses and your companion
## notices — then the shop window opens with the wallet + stock the server pushed on world join.
## Online-only: if the snapshot hasn't landed yet it opens empty and fills in via _on_economy_loaded.
func _open_shop(entry: Dictionary) -> void:
	if _shop == null or _shop.is_open():
		return
	_world_art.pulse_interactable(int(entry["render_index"]))
	_companion.notify_interaction(entry["pos"], String(entry["id"]), entry["tags"])
	_show_hint("You greet %s." % entry["label"])
	_shop.open(_shop_colors, _shop_balance, _shop_currency)


## The player tapped Buy: relay it to the server (the purchase is authoritative there). The outcome
## comes back via Net.purchase_succeeded / purchase_failed.
func _on_shop_buy(item_def_id: int) -> void:
	Net.buy_color(item_def_id)


## The shop closed — clear the greeting so the world reads clean again.
func _on_shop_closed() -> void:
	if _hint.text.begins_with("You greet ") or _hint.text == "A new colour for your wardrobe!":
		_hint.text = ""


## When the hunt ends, open a second portal home a little up the bank from the last rock, so the
## player needn't trek all the way back to the entry portal. Leads where this world's portals
## lead (the Vale). Serves both terminal states (a win and a run-out). Part of the host seam — the
## HuntDirector calls this once its goal resolves.
func open_completion_portal(at: Vector2) -> void:
	var pos := at + Vector2(46, -28)
	var render_index := _world_art.add_interactable(pos, Color(0.74, 0.66, 0.96), "portal")
	_portals.append({
		"id": "riverbank_exit_complete",
		"pos": pos,
		"target_world": _home_world,
		"target_portal": _home_portal,
		"render_index": render_index,
		"armed": true,
	})


## Walk-through portals: arm one once the player has stepped clear of it (so arriving on a portal
## doesn't bounce you straight back), and when the player walks into an armed portal, travel.
func _update_portals(_delta: float) -> void:
	if _transitioning:
		return
	for p in _portals:
		var d := _player.position.distance_to(p["pos"])
		if not bool(p["armed"]):
			if d > PORTAL_RANGE + PORTAL_ARM_BUFFER:
				p["armed"] = true
		elif d <= PORTAL_RANGE:
			# Travel works whether solo or connected: each world is its own channel, so the world
			# swap leaves this world's roster and joins the destination's (see Net.enter_world in
			# _setup_net). Players in different worlds simply don't see each other.
			_begin_transition(p)
			return


## Travel through a portal: fade to black, then hand off to WorldRouter to load the target world
## and set us down beside its matching portal. The _transitioning latch blocks re-triggering.
func _begin_transition(portal: Dictionary) -> void:
	_transitioning = true
	_show_hint("You step through the portal…")
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	tw.tween_callback(func() -> void: WorldRouter.go_to(String(portal["target_world"]), String(portal["target_portal"])))


## Index of the closest examinable interactable within range, or -1 if none. Already-searched
## rocks are skipped, so a turned-over rock no longer prompts "Examine"; once the hunt is over
## (won or run out) no rock prompts at all — the search is finished, the way home is open.
func _nearest_interactable() -> int:
	var best := -1
	var best_dist := INTERACT_RANGE
	for i in _interactables.size():
		var e: Dictionary = _interactables[i]
		if String(e.get("kind", "prop")) == "rock" and _hunt_dir.should_skip_rock(int(e["hunt_index"])):
			continue
		var d := _player.position.distance_to(e["pos"])
		if d <= best_dist:
			best = i
			best_dist = d
	return best


# ============================================================================================
# SHARED PRESENCE (Rung 3) — the game-side half of multiplayer: "me vs them". This decides WHAT
# to send (our pair's transforms + a one-time identity) and turns a peer's wire state into a
# spawned, smoothed puppet pair. It talks only to the Net seam in plain dictionaries, so it
# survives the planned transport swaps (ENet -> WebSockets -> authoritative server) untouched.
# The local Player/Companion (from the scene) stay fully authoritative over themselves and keep
# running their own input/brain; remotes are pure puppets, driven only by what arrives over Net.
# ============================================================================================

## Wire up to the Net seam: publish our identity once, and react to peers joining, moving, and
## leaving. Safe to call always — none of it does anything until the player Hosts or Joins.
func _setup_net() -> void:
	Net.set_local_identity(_local_identity())
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.identity_received.connect(_on_identity_received)
	Net.state_received.connect(_on_state_received)
	Net.save_loaded.connect(_on_save_loaded)
	Net.economy_loaded.connect(_on_economy_loaded)
	Net.purchase_succeeded.connect(_on_purchase_succeeded)
	Net.purchase_failed.connect(_on_purchase_failed)
	Net.maze_reward.connect(_on_maze_reward)
	Net.ward_state_received.connect(_on_ward_state)
	Net.disconnected.connect(_on_disconnected)
	# Enter this world's channel: presence + live transforms here are scoped to this world, and the
	# server sends back its canonical spec (cached by Net for next time). Queued until the socket is
	# open, so this is safe at boot before the player has connected, and on every world hop.
	Net.enter_world(WorldRouter.current_world)
	# Hopping between worlds reloads this scene with a fresh placeholder companion; if we're
	# already connected, re-dress it from the in-session save the server already gave us.
	if Net.has_session_save():
		var s := Net.session_save()
		_apply_server_save(s.get("companion"), s.get("appearance"))


## Cover the not-yet-built scene with the black fade and a gentle word while we wait for the server's
## spec on a cold first visit — but ONLY when the lobby connect-gate isn't up. The Fade is a very high
## CanvasLayer (above the lobby), so blacking it out on a fresh, disconnected boot would hide the gate
## itself and you'd be stuck on a black screen with nothing to click. In that case the lobby already
## provides the "not ready yet" visual, so we leave the fade clear. We only cover the screen when the
## lobby is hidden: a portal arrival (pending_transition) or an already-connected session.
func _show_loading() -> void:
	if not (WorldRouter.pending_transition or Net.is_active()):
		return
	var c := _fade.color
	c.a = 1.0
	_fade.color = c
	_hint.text = "Entering the world…"
	_hint.modulate.a = 1.0


## The server delivered (or re-delivered) a world's spec. Three cases, decided by comparing the just-
## cached etag to the one we built from (_built_etag):
##   • not our current world → ignore.
##   • same etag we already built → a reconfirm; nothing to do.
##   • different (we hadn't built yet → first paint; or our cached copy was stale and the server sent a
##     newer one → the world changed under us) → (re)build from the now-cached fresh spec.
## A live change rebuilds via a scene reload (the clean way to tear down the old world); a first paint
## builds in place so the loading screen flows straight into the world.
func _on_world_spec_arrived(world_id: String, _version: int, _spec: Dictionary) -> void:
	if world_id != WorldRouter.current_world:
		return
	var etag := Net.cached_etag(world_id)
	if etag == _built_etag:
		return
	if _built_etag == "":
		_built_etag = etag
		_build_world(Net.cached_spec_core(world_id))
	else:
		# The world changed on the server while we were standing in it. Rejoin cleanly (so the fresh
		# roster re-arrives after the rebuild) and reload the scene to rebuild from the now-cached spec.
		Net.leave_world()
		get_tree().reload_current_scene()


## Our one-time identity packet: who we are, for a friend to render. Pure presentation data —
## the player's worn look (already JSON) and the companion's resting-look floats (its grown self,
## with no mind attached). The friend never receives our save, our brain, or our bond — only this.
func _local_identity() -> Dictionary:
	return {
		"name": "Friend",
		"appearance": _player.appearance_dict(),
		"companion_look": _companion.resting_look_payload(),
	}


## Stream our local pair's transforms to peers at ~20 Hz. The packet stays tiny: our player's
## position+facing and our companion's position+attention (the Net seam marshals the Vector2s for
## the wire). A no-op until connected (Net.broadcast_state guards it), so it's harmless offline.
func _broadcast_presence(delta: float) -> void:
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
func _push_save_periodic(delta: float) -> void:
	if not Net.is_active():
		return
	_save_accum += delta
	if _save_accum < SAVE_INTERVAL:
		return
	_save_accum = 0.0
	_push_save()


## Send the current companion self + worn wardrobe up as the canonical save.
func _push_save() -> void:
	Net.push_save(_companion.self_dict(), _player.appearance_dict())


## Our canonical save arrived from the server (or nulls for a brand-new player).
func _on_save_loaded(companion, appearance) -> void:
	_apply_server_save(companion, appearance)


## Adopt a loaded save; if we're a brand-new player (no stored save), seed the server with the
## placeholder companion + default look we started with, so next time it loads.
func _apply_server_save(companion, appearance) -> void:
	var had_save := false
	if companion is Dictionary and not (companion as Dictionary).is_empty():
		_companion.replace_self(companion)
		had_save = true
	if appearance is Dictionary and not (appearance as Dictionary).is_empty():
		_player.apply_appearance(appearance)
		had_save = true
	if not had_save:
		_push_save()
	# Our relayed presentation identity may have changed (loaded look) — refresh it for peers.
	Net.set_local_identity(_local_identity())


## The economy snapshot arrived on world join (per-user: our wallet + the shop's color stock). Cache
## it so the shop opens instantly; if the shop is already open when a fresh snapshot lands, refresh it.
func _on_economy_loaded(currency: String, balance: int, colors: Array) -> void:
	if currency != "":
		_shop_currency = currency
	_shop_balance = balance
	_shop_colors = colors
	if _shop != null and _shop.is_open():
		_shop.open(_shop_colors, _shop_balance, _shop_currency)


## A purchase succeeded: mark the color owned in our cached stock, adopt the new balance, reflect it
## in the open shop, and celebrate. The color is now stored to the wardrobe (server-side); making it
## show on the avatar is the deferred recolor step.
func _on_purchase_succeeded(item_def_id: int, balance: int) -> void:
	_shop_balance = balance
	for c in _shop_colors:
		if c is Dictionary and int(c.get("item_def_id", 0)) == item_def_id:
			c["owned"] = true
			break
	if _shop != null:
		_shop.apply_purchase(item_def_id, balance)
	_show_hint("A new colour for your wardrobe!")


## A purchase was refused: let the shop re-enable the row and surface a gentle reason.
func _on_purchase_failed(item_def_id: int, reason: String) -> void:
	if _shop != null:
		_shop.apply_failure(item_def_id, reason)
	_show_hint(_purchase_failure_text(reason))


## Reached the heart of the hedge maze. Latch it (so it fires once this visit), celebrate, and claim
## the coin reward from the server — the amount it pays appends to this hint via _on_maze_reward. The
## way home is the portal standing right here in the plaza; the Return button is the other way out.
func _on_maze_reached() -> void:
	_maze_reached = true
	_goal_label.text = "The heart of the maze!"
	_completion_hint = "You've reached the heart of the maze!"
	_show_hint(_completion_hint)
	Net.claim_maze_reward()


## The companion as a quiet maze-guide: once you've stood still for MAZE_HINT_DELAY, it points
## subtly along the SOLVED PATH to the centre (from the spec's authored flow field), and relaxes the
## moment you move again or reach the heart. Presentation only — like the salamander tell, it feeds
## the companion's BODY (point_at), never its brain, so the companion still never *knows* the way; its
## body just leans where the path leads. A no-op outside the maze.
func _update_maze_hint(delta: float) -> void:
	if not _maze_active:
		return
	# Done hinting once you've reached the heart (or if the world carried no guide) — relax the pose.
	if _maze_reached or _maze_guide_dirs.is_empty():
		if _maze_pointing:
			_companion.point_at(Vector2.ZERO, 0.0)
			_maze_pointing = false
		return
	# Moving resets the idle timer and releases any point — the hint is only for when you've paused.
	var moved := _player.position.distance_to(_last_player_pos)
	_last_player_pos = _player.position
	if moved > MAZE_MOVE_EPS:
		_maze_idle = 0.0
		if _maze_pointing:
			_companion.point_at(Vector2.ZERO, 0.0)
			_maze_pointing = false
		return
	_maze_idle += delta
	if _maze_idle < MAZE_HINT_DELAY:
		return
	var dir := _maze_dir_at(_player.position)
	if dir == Vector2.ZERO:
		return  # at/over the centre, or off-grid — nothing to point toward
	_maze_pointing = true
	_companion.point_at(_player.position + dir * MAZE_HINT_REACH, MAZE_HINT_STRENGTH)


## The path direction (a unit Vector2) out of the cell the given world pos falls in, from the maze
## flow field — toward the centre. Vector2.ZERO at the centre cell or if there's no guide.
func _maze_dir_at(pos: Vector2) -> Vector2:
	if _maze_guide_cols <= 0 or _maze_guide_rows <= 0:
		return Vector2.ZERO
	var cx := clampi(int(round((pos.x - _maze_guide_origin.x) / _maze_guide_pitch)), 0, _maze_guide_cols - 1)
	var cy := clampi(int(round((pos.y - _maze_guide_origin.y) / _maze_guide_pitch)), 0, _maze_guide_rows - 1)
	match int(_maze_guide_dirs[cy * _maze_guide_cols + cx]):
		1: return Vector2(0, -1)
		2: return Vector2(1, 0)
		3: return Vector2(0, 1)
		4: return Vector2(-1, 0)
		_: return Vector2.ZERO


## The server resolved our maze reward. Adopt the new wallet balance (so the shop is current next
## time), and — if it paid out — append the earned coins to the celebration hint.
func _on_maze_reward(amount: int, balance: int) -> void:
	_shop_balance = balance
	if amount > 0 and _completion_hint != "":
		var coins := "coin" if amount == 1 else "coins"
		_show_hint("%s  You earned %d %s!" % [_completion_hint, amount, coins])


func _purchase_failure_text(reason: String) -> String:
	match reason:
		"insufficient_funds":
			return "You can't quite afford that one yet."
		"already_owned":
			return "That colour is already yours."
		_:
			return "The merchant shakes their head."


## Persist on the ways a session can end — now pushed to the server instead of disk: window
## close, app backgrounded, or this node leaving the tree (world hop / quit).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		if Net.is_active():
			_push_save()


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
## reconnect doesn't leave the old ghosts behind). The lobby gate
## reappears on its own (it also listens for disconnected()); our own player + companion stay put.
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
	if _bounds_rect.size == Vector2.ZERO:
		return p
	return Vector2(
		clampf(p.x, _bounds_rect.position.x, _bounds_rect.end.x),
		clampf(p.y, _bounds_rect.position.y, _bounds_rect.end.y))
