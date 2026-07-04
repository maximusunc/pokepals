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
# The three HUD zones (see scripts/presentation/{examine_prompt,companion_radial,gear_menu}.gd):
# a diegetic examine bubble over the nearby object, the bottom-right companion action radial, and
# the top-right system/meta gear menu. They replace the old scatter of free-floating buttons.
@onready var _examine_prompt: ExaminePrompt = $UI/ExaminePrompt
@onready var _radial: CompanionRadial = $UI/CompanionRadial
@onready var _gear: GearMenu = $UI/GearMenu
@onready var _debug: DebugOverlay = $DebugOverlay
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
var _maze_dir: MazeDirector
var _shop_dir: ShopDirector
var _presence_dir: PresenceDirector
var _ambient_dir: AmbientPalDirector
var _ruin: RuinController

var _interactables: Array = []  # examinable things: [ { pos, label, id, tags, kind, render_index, hunt_index? } ]
var _portals: Array = []  # walk-through doorways: [ { id, pos, target_world, target_portal, render_index, armed } ]
# Cached so a raised ward slab's collider can be dropped when it opens (RuinController calls
# rebuild_solids_dropping, which rebuilds Solids without the slab and re-hands them to both bodies).
var _world_data: Dictionary = {}
var _border_pts: Array = []
var _collision_cfg: Dictionary = {}
var _body_radius := 6.0
var _collision_margin := 2.0
# The Return-to-the-Vale escape hatch: where it sends you (from the spec's "return" block), or "" if
# this world declares none (so the button stays hidden everywhere but the maze).
var _return_world := ""
var _return_portal := ""
var _return_label := ""  # a world may override its Return item's label (its "return" block); "" = default
var _home_world := ""  # where this world's portals (incl. the completion one) lead back to
var _home_portal := ""
var _transitioning := false  # true once a portal transition's fade has begun
# The content etag of the spec we actually BUILT this scene from (Net.cached_etag at build time), or
# "" if we haven't built yet (still on the loading screen). Lets _on_world_spec_arrived tell "first
# paint" and "the world changed under us" apart from "the spec we already built just got reconfirmed".
var _built_etag := ""
# False until _build_world finishes. The per-frame callbacks (_process / _unhandled_input) early-return
# while it's false, so they never run against a not-yet-built world on a cold first visit (when _ready
# defers the build until the server's spec arrives).
var _world_built := false
# Cache for _nearest_interactable so the per-frame hint scan doesn't recompute O(N) distances
# (377 props in the Ruin) every frame. We only rescan once the player has drifted past a small
# threshold, or when an examine changes a prop's skip/opened state under a standing player.
var _nearest_cache := -1
var _nearest_anchor := Vector2.ZERO
var _nearest_dirty := true
const NEAREST_RECALC_DIST := 6.0  # px of player travel before we rescan (examine range is 60px)
var _intro_tween: Tween  # fades the opening "how to move" hint away after a few seconds
var _style: ArtStyle
var _day_enabled := false
var _day_period := 480.0
var _day_loop := true
var _day_stops: Array = []  # [ { t, tint:Color, vig:Color, vstr:float } ], sorted by t
var _day_time := 0.0

# The world's walkable bounds, computed at build. Shared: the camera frames to it, the Ruin rebuilds
# colliders against it, and the PresenceDirector clamps untrusted remote positions to it.
var _bounds_rect := Rect2()


func _ready() -> void:
	# Which world to load is owned by WorldRouter (a platform world_id; defaults to the Vale on a fresh
	# boot). The spec is SERVER-CANONICAL — there is no bundled copy. We stay subscribed to both spec
	# signals so the join can drive our build, and so a world that changes on the server while we're
	# standing in it rebuilds itself, no new client build required (see _on_world_spec_arrived).
	var world_id := WorldRouter.current_world
	Net.world_spec_received.connect(_on_world_spec_arrived)
	Net.world_spec_unchanged.connect(_on_world_spec_unchanged)
	# WHEN to build. Paint instantly from the cache ONLY when we're already in a live session — a world
	# hop / revisit, where the server is about to re-confirm the very spec we cached and instant paint is
	# the nice feel. On a cold, DISCONNECTED boot we must connect before we can play anyway (online-only),
	# and the SERVER's spec is the authority: building from a possibly-stale cache now would only be torn
	# down and rebuilt the moment the fresh spec lands — a wasteful double-build (and the source of the
	# connect-time reload). So we DEFER the build until the join tells us which spec is live: an unchanged
	# reply builds from cache (_on_world_spec_unchanged), a changed one from the fresh spec
	# (_on_world_spec_arrived). Either way it's a clean first paint, never a reload.
	var data := Net.cached_spec_core(world_id)
	if Net.is_active() and not data.is_empty():
		_built_etag = Net.cached_etag(world_id)
		_build_world(data)
		return
	_show_loading()
	Net.enter_world(world_id)  # _build_world runs from _on_world_spec_arrived / _on_world_spec_unchanged


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
	# fold its rocks — and this world's portals — into data["props"] so world_art draws
	# them. Populates the hunt, its rocks and _portals; leaves worlds without a goal/portals untouched.
	_setup_contents(data, arrival_id)

	# Spawn beside the arrival portal if we travelled here, else at the world's own spawn points.
	_place_arrivals(data, arrival_id)
	_maze_dir.note_player_baseline()  # baseline for the maze idle-timer's movement check

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
	_presence_dir.set_bounds(bounds_rect)  # so remote puppet positions are clamped to the world
	_ambient_dir.set_bounds(bounds_rect)  # same clamp for the server-driven ambient pals

	# Barriers: build the solid list once (trees incl. the border ring, tall props, great-trees,
	# ponds) and hand it to both characters to collide against. The border treeline is generated
	# SERVER-SIDE now (Server.WorldBorder) and shipped in the spec as "border_trees" — we draw and
	# collide against those authoritative points, the same ones the ambient-pal sim avoids, so there's
	# one source of truth (no client-side generation to drift from the server's).
	var ccfg: Dictionary = data.get("collision", {})
	var border_pts := _border_points(data)
	# Spawn the trees (hand-placed + this border ring + landmarks) into the y-sorted
	# Scenery layer, using the same border points as the colliders so drawing matches.
	_scenery.populate(data, border_pts, _style)
	var solids := Solids.build(data, border_pts, ccfg)
	var body_radius := float(ccfg.get("body_radius", 6.0))
	var margin := float(ccfg.get("margin", 2.0))
	_player.set_solids(solids, bounds_rect, body_radius, margin)
	_companion.set_solids(solids, bounds_rect, body_radius, margin)

	# Keep what the Ruin needs to REBUILD collisions when a slab rises (drop the slab's solid and
	# re-hand the list to both bodies — see rebuild_solids_dropping). Harmless to cache without a ruin.
	_world_data = data
	_border_pts = border_pts
	_collision_cfg = ccfg
	_body_radius = body_radius
	_collision_margin = margin

	# THE RUIN: build the ward logic + geometry from the spec's "ruin" block (no-op elsewhere). The
	# RuinController resolves slab/ember render indices from _interactables (laid out in _setup_contents).
	_ruin.configure(data, _interactables)

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
	_shop_dir.spawn_npc(data)

	# Ambient pals: spawn the world's set-dressing creatures as puppets the server then drives (no-op in
	# worlds without an "ambient_pals" block).
	_ambient_dir.spawn_pals(data)

	# The three HUD zones. Each is a self-contained view that reports what the player tapped; the
	# controller maps that to the SAME handlers the old free-floating buttons used. Every tap surface
	# is excluded from the movement thumbstick underneath (the components expose tap_targets() for
	# exactly this — their full-screen "tap away to dismiss" catchers cover the fanned/dropped items
	# too, so a tap on a menu never also spins up the joystick).
	#
	# Diegetic Examine bubble: floats over the nearby prop and, when tapped, examines (Space/Enter
	# still work via _unhandled_input). The contextual set is pushed each frame in _process.
	_examine_prompt.pressed.connect(_try_interact)
	# Companion radial: Pet / Call always, Go look when the Ruin has a ward to open (see _process).
	# Desktop convenience keys stay: C calls, E pets (_unhandled_input).
	_radial.action_selected.connect(_on_radial_action)
	# Gear menu: New Companion / Return / Leave / DBG, each gated in _process.
	_gear.item_selected.connect(_on_gear_item)
	# Keep the two menus mutually exclusive — opening one dismisses the other.
	_radial.opened.connect(_gear.close)
	_gear.opened.connect(_radial.close)
	for target in _examine_prompt.tap_targets() + _radial.tap_targets() + _gear.tap_targets():
		_joystick.add_exclusion(target)

	# Dev-only companion/bond readout. Toggled from the gear menu's "DBG" item (and F3 on desktop).
	_debug.setup(_companion, _player)

	# Opening instruction, then let it quietly fade so the world isn't framed by UI
	# text while you wander. Any real hint (a whistle, lore, a portal step) cancels the fade and shows.
	if _ruin.has_wards():
		_hint.text = "An old slab bars the way deeper.  Tap your companion and choose Go look to send it searching."
	else:
		_hint.text = "Wander with arrows / WASD or drag.  Step up to something and Examine to look closer."
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
## The world's border-treeline positions as Vector2s. Generated server-side (Server.WorldBorder) and
## shipped in the spec as "border_trees": [[x, y], …]; the client no longer generates them, it draws and
## collides against these. Empty in worlds without a ring (offline test fixtures included).
func _border_points(data: Dictionary) -> Array:
	var out: Array = []
	for t in data.get("border_trees", []):
		out.append(WorldData.to_vec2(t))
	return out


func _create_directors() -> void:
	_hunt_dir = HuntDirector.new()
	add_child(_hunt_dir)
	_hunt_dir.setup(self, _companion, _world_art, _player)

	_maze_dir = MazeDirector.new()
	add_child(_maze_dir)
	_maze_dir.setup(self, _companion, _player)

	_shop_dir = ShopDirector.new()
	add_child(_shop_dir)
	_shop_dir.setup(self, _companion, _world_art, _scenery, _shop, _style)

	_presence_dir = PresenceDirector.new()
	add_child(_presence_dir)
	_presence_dir.setup(_player, _companion, _scenery, _style)

	_ambient_dir = AmbientPalDirector.new()
	add_child(_ambient_dir)
	_ambient_dir.setup(_scenery, _style)

	_ruin = RuinController.new()
	add_child(_ruin)
	_ruin.setup(self, _companion, _player, _world_art, _day_tint)


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
	_shop_dir.set_balance(balance)


## Read / raw-set the hint line (no fade) — the shop uses this to clear its greeting on close.
func hint_text() -> String:
	return _hint.text


func set_hint_text(text: String) -> void:
	_hint.text = text


## How many remote pairs are present (the Ruin's paired-hall waking reads this to tier its payoff).
func peer_count() -> int:
	return _presence_dir.peer_count()


## Whether an animated day→dusk cycle currently owns the day tint (so the Ruin's gloom stands down).
func is_daycycle_enabled() -> bool:
	return _day_enabled


## Rebuild the barrier list with one ward slab dropped (it just rose into a lintel) and re-hand it to
## both bodies, so the doorway is walkable for everyone present. Rebuilt from a deep copy so the (shared,
## cached) spec stays untouched — which is what lets the Ruin reset closed on a later revisit. Part of the
## host seam: the RuinController calls this when the server confirms a ward open.
func rebuild_solids_dropping(slab_id: String) -> void:
	var data_copy: Dictionary = _world_data.duplicate(true)
	for it in data_copy.get("props", []):
		if String(it.get("id", "")) == slab_id:
			it["solid"] = false
	var solids := Solids.build(data_copy, _border_pts, _collision_cfg)
	_player.set_solids(solids, _bounds_rect, _body_radius, _collision_margin)
	_companion.set_solids(solids, _bounds_rect, _body_radius, _collision_margin)


## Assemble everything the player can touch in this world: fold the salamander-hunt rocks (if
## any) and the portals into data["props"] so world_art draws them, and build the
## runtime lists the controller acts on — _interactables (the examinable subset: interactive props +
## rocks), _portals
## (walk-through; the HuntDirector owns the rocks themselves), and the companion's points of interest.
## Props keep their original index (== their render index in world_art); rocks then portals are appended after. The
## companion is given props as POIs but NOT rocks: it reacts to a salamander you uncover, but is
## never led to the rocks (the search stays yours). arrival_id disarms the portal we arrived at.
func _setup_contents(data: Dictionary, arrival_id: String) -> void:
	_interactables.clear()
	_nearest_dirty = true  # the list is being rebuilt; drop any cached index into the old one
	_portals.clear()
	_return_world = ""
	_return_portal = ""
	_return_label = ""

	var combined: Array = data.get("props", []).duplicate()

	var poi: Array = []
	var poi_meta: Array = []
	for i in combined.size():
		var it: Dictionary = combined[i]
		# A prop is examinable only if it opts in with "interactive": true (it has a lore line, opens
		# the shop, or is a Ruin ward piece). Everything else is static scenery: world_art still draws
		# it (by 'type') and Solids still blocks movement, but it stays out of the examine scan and the
		# companion's POIs — it conveys what it is by appearance alone. Skipping it here leaves its
		# render index (== i) intact for world_art.
		if not bool(it.get("interactive", false)):
			continue
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
			# An optional fragment of the world's story (a Knot's lore line, a notice-board, the
			# wet-boots man). When present, Examining shows this instead of the generic perks-up line.
			"lore": String(it.get("lore", "")),
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

	# The hedge maze: hand the goal to the MazeDirector, which caches the centre + radius (to notice
	# when the player reaches the heart) and the companion's flow-field guide. A no-op elsewhere.
	_maze_dir.setup_goal(goal, data)

	# The Return-to-the-Vale escape hatch: a world may declare where its Return item leads, and
	# override its label (surfaced in the gear menu — see _gather_gear_items).
	var ret: Dictionary = data.get("return", {})
	if ret.has("world"):
		_return_world = String(ret["world"])
		_return_portal = String(ret.get("portal", ""))
		if ret.has("label"):
			_return_label = String(ret["label"])

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

	data["props"] = combined

	# Per-world companion tuning: a world may quieten the companion's wandering and keep it close
	# (e.g. the riverbank, so it stays at your side to point out salamanders). Merged over the global
	# companion.json defaults here, after the brain exists and before its first update.
	if data.has("companion"):
		_companion.apply_config_overrides(data["companion"])

	if _hunt_dir.is_active():
		_goal_label.visible = true
		_hunt_dir.show_initial_goal()
	elif _maze_dir.is_active():
		_goal_label.visible = true
		_maze_dir.show_initial_goal()
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

	# Diegetic Examine bubble: float it over the nearest examinable prop, pointing at it, only while
	# in range. It just reads "Examine" — the thing's identity comes from how it looks and, once
	# examined, from the hint line.
	var nearest := _nearest_interactable()
	if nearest >= 0:
		_examine_prompt.point_at(_interactables[nearest]["pos"])
	else:
		_examine_prompt.hide_prompt()

	# Companion radial: Pet and Call are core (always there); Go look joins the arc only in a Ruin
	# with a ward still to open. The chip's dot warms with the live bond.
	_radial.set_bond(_companion.bond_value())
	_radial.set_actions([
		{ "id": "pet", "label": "Pet", "enabled": true },
		{ "id": "call", "label": "Call", "enabled": true },
		{ "id": "seek", "label": "Go look", "enabled": _ruin.has_unopened_ward() },
	])

	# Gear menu: the meta actions, each shown only when it applies — New Companion once fully bonded,
	# Return-to-the-Vale in a world that declares one while connected, Leave while in a session, DBG
	# always (dev).
	_gear.set_items(_gather_gear_items())

	# Walk-through portals, the hunt detector, the maze (reach check + guide hint), the Ruin (ward
	# referee + descent gloom).
	_update_portals(delta)
	_hunt_dir.update_detector(delta)
	_maze_dir.update(delta)
	_ruin.update(delta)

	# Shared presence: stream our own pair's transforms to peers at ~20 Hz (a no-op when offline).
	_presence_dir.broadcast(delta)
	_presence_dir.push_save_periodic(delta)


## The gear menu's items for this frame, each gated exactly as its old free-floating button was: New
## Companion only once fully bonded, Return-to-the-Vale only where a world declares one (while
## connected), Leave only in a live session, DBG always (dev). The GearMenu dedupes an unchanged set,
## so rebuilding this list every frame is cheap.
func _gather_gear_items() -> Array:
	var items: Array = []
	if _companion.is_fully_bonded():
		items.append({ "id": "new_companion", "label": "New Companion" })
	if _return_world != "" and Net.is_active():
		items.append({ "id": "return", "label": _return_item_label() })
	if Net.is_active():
		items.append({ "id": "leave", "label": "Leave game" })
	items.append({ "id": "dbg", "label": "DBG" })
	return items


## The Return item's label — the world may override it via its "return" block (see _setup_contents),
## defaulting to "Return to the Vale".
func _return_item_label() -> String:
	return _return_label if _return_label != "" else "Return to the Vale"


## Map a companion-radial tap to the SAME handler its old button used.
func _on_radial_action(id: String) -> void:
	match id:
		"pet": _try_pet()
		"call": _try_call()
		"seek": _ruin.try_seek()


## Map a gear-menu tap to the SAME handler its old button used.
func _on_gear_item(id: String) -> void:
	match id:
		"new_companion": _on_reset_pressed()
		"return": _on_return_pressed()
		"leave": _on_leave_pressed()
		"dbg": _debug.toggle()


## Leave the session on purpose. Persist the companion one last time (the graceful close in
## Net.leave flushes it), then drop the link — which surfaces as disconnected() and brings the
## lobby gate back up, ready to reconnect. The remote puppets are cleaned up by the PresenceDirector.
func _on_leave_pressed() -> void:
	if Net.is_active():
		_presence_dir.push_save()
	Net.leave()


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


## Start a fresh companion (immediate, no confirm — the item only appears once you have a fully bonded
## companion to start over from, and drops out of the gear menu again the next frame after reset).
func _on_reset_pressed() -> void:
	_companion.reset()
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


## Pet the companion when you're beside it. Whether it leans in or shies away is up to the brain and
## the bond (see PetAction). Pet is a core radial action (always offered), so out of range we nudge
## the player to close the gap rather than silently no-op — a visible action should never feel dead.
func _try_pet() -> void:
	if _player.position.distance_to(_companion.position) > PET_RANGE:
		_show_hint("Your companion is too far to reach — step closer.")
		return
	_companion.issue_command("pet")
	_show_hint("You reach out to your companion.")


func _try_interact() -> void:
	var index := _nearest_interactable()
	if index < 0:
		return
	var entry: Dictionary = _interactables[index]
	# Examining can flip this prop's skip/opened state (a turned-over rock, an opened ward) while
	# the player stands still — so refresh the cached hint on the next frame.
	_invalidate_nearest()
	if String(entry["kind"]) == "rock":
		_hunt_dir.examine_rock(entry)
		return
	if String(entry["kind"]) == "shopkeeper":
		_shop_dir.open_shop(entry)
		return
	_world_art.pulse_interactable(int(entry["render_index"]))
	_companion.notify_interaction(entry["pos"], String(entry["id"]), entry["tags"])
	# Ruin fixtures (kindle the Cistern ember, jam the Paired-Hall wedge, nudge on an unsolved slab) are
	# handled by the RuinController; if it claims this prop, we're done.
	if _ruin.try_examine(entry):
		return
	# A prop carrying a story fragment (a Knot's lore signpost, a Knuckle notice-board, the wet-boots
	# man) reads out that line; everything else gets the cozy generic beat.
	var lore := String(entry.get("lore", ""))
	if lore != "":
		_show_hint(lore)
		return
	_show_hint("You examine %s. Your companion perks up." % entry["label"])


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


## Index of the closest examinable interactable within range, or -1 if none. Cached: the full
## scan only reruns once the player has moved past NEAREST_RECALC_DIST since the last scan (or
## an examine marked it dirty), so a dense world doesn't pay the O(N) distance loop every frame.
func _nearest_interactable() -> int:
	var p: Vector2 = _player.position
	if not _nearest_dirty and p.distance_to(_nearest_anchor) <= NEAREST_RECALC_DIST:
		return _nearest_cache
	_nearest_dirty = false
	_nearest_anchor = p
	_nearest_cache = _scan_nearest_interactable()
	return _nearest_cache


## Force the next _nearest_interactable() to rescan even if the player hasn't moved — used after
## an examine, which can flip a prop's skip/opened state (and thus the hint) while standing still.
func _invalidate_nearest() -> void:
	_nearest_dirty = true


## Already-searched rocks are skipped, so a turned-over rock no longer prompts "Examine"; once the
## hunt is over (won or run out) no rock prompts at all — the search is finished, the way home is open.
func _scan_nearest_interactable() -> int:
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
# NETWORK + SESSION — the controller's own Net wiring. Shared presence ("me vs them"), the save, the
# economy, and the Ruin's ward state now live in their own directors, which connect their Net signals
# themselves. What's left here is world-scoped: entering the world channel and the cold-spec handshake
# (_show_loading / _on_world_spec_arrived).
# ============================================================================================

## Wire up the controller's own Net seam: enter this world's channel. Shared presence + the save (the
## PresenceDirector) and the Ruin's ward state (the RuinController) connect their own Net signals in their
## setup; here we just kick the join and let presence re-dress from any in-session save. Safe to call
## always — none of it does anything until the player Hosts or Joins.
func _setup_net() -> void:
	# Enter this world's channel: presence + live transforms here are scoped to this world, and the
	# server sends back its canonical spec (cached by Net for next time). Queued until the socket is
	# open, so this is safe at boot before the player has connected, and on every world hop.
	Net.enter_world(WorldRouter.current_world)
	# Hopping between worlds reloads this scene with a fresh placeholder companion; if we're
	# already connected, re-dress it from the in-session save the server already gave us.
	_presence_dir.apply_session_save_if_any()


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


## The server shipped a world's spec (it differed from the known_etag we sent, or we had none). Three
## cases, decided by comparing the just-cached etag to the one we built from (_built_etag):
##   • not our current world → ignore.
##   • same etag we already built → a reconfirm; nothing to do.
##   • different → either we hadn't built yet (a fresh/deferred boot → FIRST PAINT, in place, so the
##     loading screen flows straight into the world) or our cached copy was stale and the server sent a
##     newer one while we stood in the world (→ the world changed under us → a scene reload, the clean way
##     to tear down the old world and rebuild from the now-cached spec).
## Its sibling _on_world_spec_unchanged handles the case where the server confirmed our cache instead of
## re-shipping — a deferred boot builds from cache there.
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


## The server confirmed our cached spec is still current (we sent a matching known_etag on join, so it
## didn't re-ship the spec). If we DEFERRED the build — a cold, disconnected boot waiting for this
## confirmation — build now from the cache: a clean first paint. If we already built (a live revisit that
## painted from cache before joining), there's nothing to do.
func _on_world_spec_unchanged(world_id: String) -> void:
	if world_id != WorldRouter.current_world or _built_etag != "":
		return
	var data := Net.cached_spec_core(world_id)
	if not data.is_empty():
		_built_etag = Net.cached_etag(world_id)
		_build_world(data)


## Persist on the ways a session can end — pushed to the server (the sole save): window close, app
## backgrounded, or this node leaving the tree (world hop / quit). Delegated to the PresenceDirector,
## which may not exist yet on a cold first visit (before the world is built), hence the guard.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		if _presence_dir != null:
			_presence_dir.flush_save_on_exit()
