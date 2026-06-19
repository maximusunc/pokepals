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
# Subtle salamander hints: how near a hidden salamander must be to the companion for it to
# glance, and the random pause between glances so the nudge stays occasional, never leading.
const HINT_RADIUS := 92.0
const HINT_COOLDOWN := Vector2(4.0, 7.0)

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
@onready var _debug: DebugOverlay = $DebugOverlay
@onready var _debug_button: Button = $UI/DebugButton
@onready var _day_tint: CanvasModulate = $DayTint
@onready var _vignette: ColorRect = $Vignette/Rect
@onready var _pollen: CPUParticles2D = $Camera2D/Pollen
@onready var _goal_label: Label = $UI/GoalLabel
@onready var _fade: ColorRect = $Fade/Rect

var _interactables: Array = []  # examinable things: [ { pos, label, id, tags, kind, render_index, hunt_index? } ]
var _portals: Array = []  # walk-through doorways: [ { id, pos, target_world, target_portal, render_index, armed } ]
var _hunt: SalamanderHunt = null  # the riverbank salamander hunt, or null in worlds without a goal
var _rocks: Array = []  # [ { pos, hunt_index, render_index } ] — the examinable rocks of the hunt
var _goal_active := false
var _home_world := ""  # where this world's portals (incl. the completion one) lead back to
var _home_portal := ""
var _hint_cooldown := 0.0
var _transitioning := false  # true once a portal transition's fade has begun
var _examine_shown := false  # whether the touch Examine button is currently faded in
var _pet_shown := false  # whether the contextual Pet button is currently faded in
var _reset_shown := false  # whether the "new companion" button is currently faded in
var _intro_tween: Tween  # fades the opening "how to move" hint away after a few seconds
var _style: ArtStyle
var _day_enabled := false
var _day_period := 480.0
var _day_loop := true
var _day_stops: Array = []  # [ { t, tint:Color, vig:Color, vstr:float } ], sorted by t
var _day_time := 0.0


func _ready() -> void:
	# Which world to load is owned by WorldRouter (defaults to the Vale on a fresh boot); the
	# arrival portal id, if set, says which portal we stepped out of so we can spawn beside it.
	var data := WorldData.load_json(WorldRouter.current_world)
	var arrival_id := WorldRouter.arrival_portal_id

	# Shared art direction (palette + light): the one place the whole look is tuned.
	_style = ArtStyle.load_style(ART_PATH)
	_player.set_style(_style)
	_companion.set_style(_style)
	_companion.setup(_player)

	# If this world carries a salamander-hunt goal, lay it out (fresh + random each visit) and
	# fold its rocks — and this world's portals — into data["interactables"] so world_art draws
	# them. Populates _hunt, _rocks and _portals; leaves worlds without a goal/portals untouched.
	_setup_contents(data, arrival_id)

	# Spawn beside the arrival portal if we travelled here, else at the world's own spawn points.
	_place_arrivals(data, arrival_id)

	_world_art.render_world(data, _style)
	_apply_atmosphere(data.get("atmosphere", {}))
	_setup_daycycle(_style.daycycle())

	# Fade in from black if we arrived through a portal; otherwise start fully clear.
	_setup_fade()

	var bmin := WorldData.to_vec2(data["bounds"]["min"])
	var bmax := WorldData.to_vec2(data["bounds"]["max"])
	var bounds_rect := Rect2(bmin, bmax - bmin)
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

	# (The examinable interactables, the portals, the hunt and the companion's points of
	# interest were all assembled in _setup_contents above, before the world was drawn.)

	# Hand the companion the world's id and named regions, so it can feel the bond of
	# reaching a new area (resolved from its own position; see WorldAreas / CompanionSelf).
	var regions: Array = []
	for r in data.get("regions", []):
		regions.append({ "id": String(r.get("id", "region")), "min": WorldData.to_vec2(r["min"]), "max": WorldData.to_vec2(r["max"]) })
	_companion.set_world_areas(String(data.get("world_id", "")), regions)

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

	# Dev-only companion/bond readout. On by default; the DBG button (and F3 on
	# desktop) toggles it. Exclude its taps from the movement thumbstick underneath.
	_debug.setup(_companion, _player)
	_debug_button.pressed.connect(_debug.toggle)
	_joystick.add_exclusion(_debug_button)

	# Opening instruction, then let it quietly fade so the world isn't framed by UI
	# text while you wander. Any real prompt (Examine ...) cancels the fade and shows.
	_hint.text = "Wander with arrows / WASD or drag.  Space or tap Examine to look closer."
	_hint.modulate.a = 1.0
	_intro_tween = create_tween()
	_intro_tween.tween_interval(5.0)
	_intro_tween.tween_property(_hint, "modulate:a", 0.0, 1.4)


## Assemble everything the player can touch in this world: fold the salamander-hunt rocks (if
## any) and the portals into data["interactables"] so world_art draws them, and build the
## runtime lists the controller acts on — _interactables (examinable: props + rocks), _portals
## (walk-through), _rocks, and the companion's points of interest. Props keep their original
## index (== their render index in world_art); rocks then portals are appended after. The
## companion is given props as POIs but NOT rocks: it reacts to a salamander you uncover, but is
## never led to the rocks (the search stays yours). arrival_id disarms the portal we arrived at.
func _setup_contents(data: Dictionary, arrival_id: String) -> void:
	_interactables.clear()
	_portals.clear()
	_rocks.clear()
	_hunt = null
	_goal_active = false

	var combined: Array = data.get("interactables", []).duplicate()

	var poi: Array = []
	var poi_meta: Array = []
	for i in combined.size():
		var it: Dictionary = combined[i]
		var prop_id := String(it.get("id", it.get("type", "prop_%d" % i)))
		var entry := {
			"pos": WorldData.to_vec2(it["position"]),
			"label": String(it.get("label", "something")),
			"id": prop_id,
			"tags": it.get("tags", []),
			"kind": "prop",
			"render_index": i,
		}
		_interactables.append(entry)
		poi.append(entry["pos"])
		poi_meta.append({ "pos": entry["pos"], "id": prop_id, "tags": entry["tags"] })
	_companion.set_points_of_interest(poi, poi_meta)

	# The salamander hunt: hide its salamanders + decoys among the rocks (fresh, random each
	# visit) and make each rock an examinable interactable world_art can turn over.
	var goal: Dictionary = data.get("goal", {})
	var rock_defs: Array = data.get("rocks", [])
	if String(goal.get("type", "")) == "find_salamanders" and not rock_defs.is_empty():
		_goal_active = true
		_hunt = SalamanderHunt.new()
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_hunt.setup(rock_defs.size(), int(goal.get("count", 10)), goal.get("decoys", []), int(goal.get("decoy_count", 0)), rng)
		for ri in rock_defs.size():
			var rpos := WorldData.to_vec2(rock_defs[ri])
			var render_index := combined.size()
			combined.append({ "id": "rock_%d" % ri, "type": "rock", "position": rock_defs[ri], "color": [0.60, 0.60, 0.56], "label": "a mossy rock", "tags": ["stone"] })
			_rocks.append({ "pos": rpos, "hunt_index": ri, "render_index": render_index })
			_interactables.append({ "pos": rpos, "label": "a mossy rock", "id": "rock_%d" % ri, "tags": ["stone"], "kind": "rock", "render_index": render_index, "hunt_index": ri })

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

	if _goal_active:
		_goal_label.visible = true
		_set_goal_text(0, int(goal.get("count", 10)))
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
				p_spawn = ppos + Vector2(0, 44)
				c_spawn = ppos + Vector2(-26, 60)
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
## the drifting pollen. All data-driven from world.json's "atmosphere" block, with
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

	# Walk-through portals, and the companion's occasional subtle glance toward a hidden salamander.
	_update_portals(delta)
	_update_hints(delta)


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


## Start a fresh companion (immediate, no confirm — the button only appears once you
## have a fully bonded companion to start over from). It hides itself again until the
## new companion bonds.
func _on_reset_pressed() -> void:
	_companion.reset()
	_set_reset_visible(false)
	_show_hint("A new companion blinks into the world beside you.")


func _unhandled_input(event: InputEvent) -> void:
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
		_examine_rock(entry)
		return
	_world_art.pulse_interactable(int(entry["render_index"]))
	_companion.notify_interaction(entry["pos"], String(entry["id"]), entry["tags"])
	_show_hint("You examine %s. Your companion perks up." % entry["label"])


## Turn over a rock: ask the hunt what's hidden under it, reveal it (world_art tips the rock and
## shows the find), let the companion appraise what surfaced, tick the counter on a salamander,
## and on the very last one open a second way home a little up the bank.
func _examine_rock(entry: Dictionary) -> void:
	if _hunt == null:
		return
	var result: Dictionary = _hunt.examine(int(entry["hunt_index"]))
	if bool(result["already_examined"]):
		return
	var kind := String(result["kind"])
	_world_art.reveal_rock(int(entry["render_index"]), kind)
	# Let the companion feel about what surfaced — high appeal for a salamander, mild for a decoy,
	# little for bare sand. A kind-keyed id so repeated finds habituate gently rather than each
	# rock being a brand-new wonder.
	_companion.notify_interaction(entry["pos"], "rock_" + kind, result["tags"])
	_show_hint("You lift the rock: %s" % result["label"])
	if kind == "salamander":
		_set_goal_text(int(result["found"]), int(result["total"]))
		_bounce_goal_label()
	if bool(result["newly_complete"]):
		_open_completion_portal(entry["pos"])
		_show_hint("All ten salamanders found! A portal shimmers open just up the bank.")


## When the last salamander is found, open a second portal home a little up the bank from the
## rock, so the player needn't trek all the way back to the entry portal. Leads where this
## world's portals lead (the Vale).
func _open_completion_portal(at: Vector2) -> void:
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


## Subtle salamander hints: every few seconds, if an un-turned salamander rock is near the
## companion, have it glance that way — a warm nudge, never a giveaway (it doesn't walk over).
func _update_hints(delta: float) -> void:
	if not _goal_active or _hunt == null:
		return
	_hint_cooldown -= delta
	if _hint_cooldown > 0.0:
		return
	var best := Vector2.ZERO
	var best_d := HINT_RADIUS
	var found := false
	for r in _rocks:
		if _hunt.is_examined(int(r["hunt_index"])):
			continue
		if _hunt.content_kind(int(r["hunt_index"])) != "salamander":
			continue
		var d := _companion.position.distance_to(r["pos"])
		if d <= best_d:
			best_d = d
			best = r["pos"]
			found = true
	if found:
		_companion.glance_toward(best)
		_hint_cooldown = randf_range(HINT_COOLDOWN.x, HINT_COOLDOWN.y)
	else:
		_hint_cooldown = 0.6  # nothing near; check again shortly


func _set_goal_text(found: int, total: int) -> void:
	_goal_label.text = "Salamanders  %d / %d" % [found, total]


## A small celebratory pop of the counter each time you find one.
func _bounce_goal_label() -> void:
	_goal_label.scale = Vector2(1.25, 1.25)
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(_goal_label, "scale", Vector2.ONE, 0.28)


## Index of the closest examinable interactable within range, or -1 if none. Already-searched
## rocks are skipped, so a turned-over rock no longer prompts "Examine".
func _nearest_interactable() -> int:
	var best := -1
	var best_dist := INTERACT_RANGE
	for i in _interactables.size():
		var e: Dictionary = _interactables[i]
		if String(e.get("kind", "prop")) == "rock" and _hunt != null and _hunt.is_examined(int(e["hunt_index"])):
			continue
		var d := _player.position.distance_to(e["pos"])
		if d <= best_dist:
			best = i
			best_dist = d
	return best
