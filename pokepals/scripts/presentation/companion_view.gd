class_name CompanionView
extends Node2D
## The companion's BODY — the presentation side of the logic/presentation split.
## Each frame it builds a context, asks CompanionBrain what it wants, and then
## brings that intent to life: eases toward the desired point, turns its eyes
## toward whatever it's attending to (the cheap-but-huge "it's looking at me/that"
## effect), bobs and hops, and pops when it notices something.
##
## It never decides behavior itself — that's the brain's job. It only renders the
## brain's intent.

## Emitted when the LOCAL companion shifts daemon form (a new animal), so the world can
## re-broadcast our identity and friends re-render the change. Never fired by a remote puppet.
signal form_changed

@export var config_path := "res://data/companion.json"

const SELF_SAVE_PATH := "user://companion_self.json"
const AUTOSAVE_INTERVAL := 15.0
const POINT_VIS_RATE := 8.0  # per-sec ease of the point's visual intensity toward its on/off target
# How fast a REMOTE puppet eases toward its latest received transform (matches PlayerView): the
# friend's companion lands ~20 Hz and we glide toward it at 60 fps so its motion stays smooth.
const REMOTE_LERP_RATE := 14.0

var velocity := Vector2.ZERO

var _brain: CompanionBrain
var _cfg: Dictionary
var _player: PlayerView
var _events: Array = []
var _points_of_interest: Array = []
var _poi_meta: Array = []
var _world_id := ""
var _regions: Array = []
var _time := 0.0
var _autosave_accum := 0.0

var _look_dir := Vector2.DOWN
var _eye_offset := Vector2.ZERO
var _hint_look_pos := Vector2.ZERO  # a world point to briefly glance at (subtle salamander hint)
var _hint_look_t := 0.0             # seconds of glance left; overrides the brain's look while > 0
var _point_pos := Vector2.ZERO      # world point of the detector "tell" — a hidden salamander nearby
var _point_t := 0.0                 # point target, set by the controller: 1 while holding a point, else 0
var _point_vis := 0.0               # eased 0..1 visual intensity of the point (smooths the pose/"!"; motion-hold uses _point_t)
var _bob := 0.0
var _hop_squash := 0.0   # 0..1, decays; squashes the body on a "hop"
var _perk := 0.0         # 0..1, decays; pops the body on "perk"
var _style: ArtStyle
var _sprite_tex: Texture2D = null  # set if the user dropped in their own companion art
# DAEMON FORM — the companion wears a real animal (cat/fox/rabbit/bird/wolf from data/pals.json) and
# occasionally shifts into a different one, like a His Dark Materials daemon. The LOCAL companion owns
# a CompanionForm that decides WHEN to shift; a remote puppet just renders whatever form its owner
# broadcast (apply_remote_form). _form_tex non-null means "draw as this animal" and takes precedence
# over the procedural rig. _form_sheet caches that species' sheet layout for PalSprite.
var _form: CompanionForm = null
var _form_species := ""
var _form_variant := 0
var _form_tex: Texture2D = null
var _form_sheet: Dictionary = {}
var _solids: Array = []
var _bounds := Rect2()
var _body_radius := 6.0
var _margin := 2.0
var _collide := false
# Route-keeper around walls (local companion only). The brain stays geometry-blind: it
# still just names a point it wants to be at, and this is the body knowing how to get
# there — same layer as Solids collision. Null when nav is disabled in companion.json.
var _nav_agent: NavAgent = null
var _nav_grid: NavGrid = null  # the agent's grid, kept for player-anchored goal clamping
var _nav_behavior := ""      # last behavior routed for; a switch (whistle!) replans at once
var debug_draw_nav := false  # world controller flips this with the debug overlay
# Eased read of the brain's feeling surface, so body language glides instead of twitching.
var _mood_v := 0.0
var _mood_a := 0.0
# Eased RESTING LOOK — the slow mirror of who the companion is becoming (its grown identity)
# and how bonded it is. Computed each frame by CompanionLook from identity+bond and glided
# toward here so it shifts over a play session, never popping. _look_inited snaps these to
# their target on the first frame (and after reset) so a loaded companion shows its current
# self immediately instead of easing in from neutral.
var _look_inited := false
var _look_ear := 0.0     # px subtracted from ear_offset (+ perks, - relaxes)
var _look_bounce := 0.0  # added to the idle bounce gain
var _look_wag := 0.0     # resting tail-wag amplitude floor
var _look_eye := 0.0     # px of upward gaze bias (procedural rig)
var _look_coat := 0.0    # 0..1 emergent coat warming
var _look_scale := 1.0   # body size multiplier over the bond arc
# Active floating emotes: each { kind: String, age: float, life: float }.
var _emotes: Array = []

# Networked PUPPET mode. The LOCAL companion (_is_local, the default) runs its brain, saves, and
# collides. A REMOTE puppet (set via set_remote() before it enters the tree) runs NONE of those:
# it carries no brain at all — it's a body driven purely by transforms over Net, its resting look
# pulled once from the friend's identity packet. This is exactly why the brain never needs a
# remote player's position: each brain only ever sees its own local player.
var _is_local := true
var _target_pos := Vector2.ZERO     # latest position received from the owner (remote only)
var _target_look := Vector2.DOWN    # latest attention/look direction received (remote only)


## Mark this companion a REMOTE puppet. MUST be called after instantiate() and before add_child(),
## so the flag is set before _ready runs (no brain is built, no local save is read).
func set_remote() -> void:
	_is_local = false


func is_local() -> bool:
	return _is_local


## The local companion's current attention direction, for the world to fold into its broadcast.
func look_dir() -> Vector2:
	return _look_dir


## The local companion's RESTING LOOK as plain floats (ear/bounce/tail/gaze biases, coat warmth,
## body size), for the world's identity packet — so a friend renders this companion's GROWN self
## without ever seeing its mind. Computed from the same CompanionLook mapping the local rig uses.
## Empty before the brain exists.
func resting_look_payload() -> Dictionary:
	if _brain == null:
		return {}
	var s := _brain.get_self()
	return CompanionLook.resting_look(s.identity, s.bond, _cfg)


## Apply a friend's resting-look floats to this puppet (remote only). The dict is UNTRUSTED input,
## so every value is clamped to a sane range before it touches the rig — a hostile packet can make
## the friend's companion look a little off, never break our render.
func apply_remote_look(look: Dictionary) -> void:
	_look_inited = true  # a puppet never eases this from the brain; we set it outright
	_look_ear = clampf(float(look.get("ear_rest", 0.0)), -40.0, 40.0)
	_look_bounce = clampf(float(look.get("bounce_base", 0.0)), 0.0, 20.0)
	_look_wag = clampf(float(look.get("wag_life", 0.0)), 0.0, 20.0)
	_look_eye = clampf(float(look.get("eye_lift", 0.0)), 0.0, 20.0)
	_look_coat = clampf(float(look.get("coat_warm", 0.0)), 0.0, 1.0)
	_look_scale = clampf(float(look.get("body_scale", 1.0)), 0.25, 4.0)


## This companion's current DAEMON FORM as plain data, for the world's identity packet, so a friend
## renders our companion as the same animal we see. Empty species = "no form" (procedural fallback).
func companion_form_payload() -> Dictionary:
	return { "species": _form_species, "variant": _form_variant }


## Apply a friend's daemon form to this puppet (remote only). UNTRUSTED input — an unknown or
## un-drawable species simply clears the form and falls back to the procedural rig, never crashes.
func apply_remote_form(species: String, variant: int) -> void:
	_set_form(species, variant)


## Feed a remote puppet the owner's latest transform: where it is, and where it's attending. Stored
## only; _process eases the body toward it so motion stays smooth between the ~20 Hz samples.
func set_remote_state(pos: Vector2, look: Vector2) -> void:
	_target_pos = pos
	if look.length() > 0.01:
		_target_look = look.normalized()


## Hand the avatar the world's barriers to collide against (trees, props, water, edge).
## The local companion also rasterizes them into its walkability grid here, so it can
## route AROUND walls (the maze) instead of only sliding along them. Re-calling this
## with changed solids (the Ruin's rising slabs) rebuilds the grid and drops any path
## planned against the old geometry.
func set_solids(solids: Array, bounds: Rect2, body_radius: float, margin: float) -> void:
	_solids = solids
	_bounds = bounds
	_body_radius = body_radius
	_margin = margin
	_collide = true
	if _is_local:
		var nav_cfg: Dictionary = _cfg.get("nav", {})
		if bool(nav_cfg.get("enabled", true)):
			if _nav_agent == null:
				_nav_agent = NavAgent.new(nav_cfg)
			_nav_grid = NavGrid.build(solids, bounds, body_radius, margin,
				float(nav_cfg.get("cell_size", 24.0)))
			_nav_agent.set_grid(_nav_grid)
		else:
			_nav_agent = null
			_nav_grid = null


## Called by the world to hand the companion its player to follow.
func setup(player: PlayerView) -> void:
	_player = player


## Patch the companion's tuning for THIS world, on top of the global companion.json defaults — e.g.
## the riverbank quietens wandering and keeps the companion at your side for the hunt, without
## changing how it behaves in the open Vale. A shallow overwrite of top-level keys is enough (the
## wander/follow knobs are all top-level scalars). Safe to call after _ready (the brain reads _cfg
## at decision time, not at construction) and before the first _process. No-op on an empty dict.
func apply_config_overrides(overrides: Dictionary) -> void:
	for key in overrides:
		_cfg[key] = overrides[key]


## A presentation-only "subtle hint": briefly glance toward a world point (a nearby rock that
## hides a salamander) with a soft perk. It does NOT touch the brain — it only overrides where
## the eyes attend for a moment, then fades back to whatever the brain is looking at. The
## decision of *when* to nudge lives in world_controller (it knows where the salamanders are).
func glance_toward(world_pos: Vector2) -> void:
	_hint_look_pos = world_pos
	_hint_look_t = 1.2
	_perk = maxf(_perk, 0.6)


## The salamander DETECTOR "tell" — a graded pointing/freeze, set every frame by the controller
## from the hunt's truth + the bond (see world_controller._update_hints). strength 0..1: 0 relaxes
## the pose, 1 is a full lock-on. Like glance_toward this is PRESENTATION ONLY — it never touches
## the brain, so the companion still never *knows* where the salamanders are or paths to them; its
## body just leans toward what it can sense nearby. The closer/more-bonded, the stronger the tell.
func point_at(world_pos: Vector2, strength: float) -> void:
	_point_t = clampf(strength, 0.0, 1.0)
	if _point_t > 0.0:
		_point_pos = world_pos
		_perk = maxf(_perk, 0.3 + 0.5 * _point_t)  # a graded alertness, stronger the surer it is


## The companion's bond (0..max), read-only, for presentation that scales with the relationship
## (the detector tell sharpens as you bond). 0 before the brain exists.
func bond_value() -> float:
	if _brain == null:
		return 0.0
	return _brain.get_self().bond


## The companion's current high-level behavior (idle/follow/wander/seek/come/...), straight from
## the brain — for mechanics that need to notice WHAT it's doing right now, e.g. the Ruin watching
## a delegated "go look" search end (whether it found a plate, gave up, or was whistled off).
## Empty for a remote puppet, which has no mind of its own.
func behavior() -> String:
	if _brain == null:
		return ""
	return _brain.behavior()


## The presentation-only "detector" tuning block from companion.json (sense range, tell ceiling,
## pose params), for the controller to read. Empty dict if unconfigured (callers default).
func detector_cfg() -> Dictionary:
	return _cfg.get("detector", {})


## Hand the avatar its shared art direction (palette + light). Called by the world.
func set_style(style: ArtStyle) -> void:
	_style = style
	_sprite_tex = SpriteSlot.resolve(style.character("companion"))


## Called by the world to tell the companion where the standing props are, so it
## can choose to wander over and investigate them on its own. `meta`, when supplied, is an
## index-aligned [{ pos, id, tags }] companion to `points` carrying each prop's identity, so
## the companion can lead the player to a specific, still-novel, appealing find.
func set_points_of_interest(points: Array, meta: Array = []) -> void:
	_points_of_interest = points
	_poi_meta = meta


## Called by the world to hand over its id and named regions, so the companion can resolve
## which area it's in (for the bond of reaching a new place). regions: [{ id, min, max }].
func set_world_areas(world_id: String, regions: Array) -> void:
	_world_id = world_id
	_regions = regions


## Called by the world when the player interacts with something — the brain may
## decide to grow curious about it. The stable prop `id` lets the companion tell one
## thing from another (habituation/memory); the neutral `tags` let it appraise how it
## feels about the thing (see CompanionAppraisal).
func notify_interaction(world_position: Vector2, id: String = "", tags: Array = []) -> void:
	_events.append({ "type": "interaction", "position": world_position, "id": id, "tags": tags })


## Called by the world when the player issues an order — a call/whistle ("come"), a pet ("pet"),
## or a "go look" search ("seek", and the controller's follow-up "settle" carrying the revealed
## plate point). Pure passthrough to the brain's command seam; the brain (and the bond) decide
## what actually happens.
func issue_command(command: String, point = null) -> void:
	if _brain != null:
		_brain.issue_command(command, point)


func _ready() -> void:
	# Crisp pixel art: nearest-neighbour sampling on this node only (matches PlayerView), so a
	# dropped-in companion sheet stays sharp when scaled, without touching the procedural world.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cfg = WorldData.load_json(config_path)
	# A REMOTE puppet has no mind of its own — it's a body driven over the wire — so it builds no
	# brain and reads no save (that save belongs to THIS machine's companion, not the friend's).
	# Its resting look arrives via apply_remote_look. The config is still loaded above, since the
	# rig (_draw) reads expression/detector/coat tuning from it for everyone.
	if _is_local:
		# The companion's grown self lives on the SERVER now (online-only). Until the server's
		# 'load' arrives (replace_self), render a fresh placeholder so the world has a body
		# immediately — and so headless/smoke runs work with no server attached.
		var placeholder := CompanionSelf.make_random(_cfg, RandomNumberGenerator.new())
		_brain = CompanionBrain.new(_cfg, 0, placeholder)
		_init_daemon_form()
	if _style == null:
		_style = ArtStyle.load_style()


func _process(delta: float) -> void:
	_time += delta
	if not _is_local:
		_process_remote(delta)
		return
	if _player == null:
		return

	var context := {
		"companion_pos": position,
		"player_pos": _player.position,
		"player_velocity": _player.velocity,
		"delta": delta,
		"events": _events,
		"time": _time,
		"points_of_interest": _points_of_interest,
		"poi_meta": _poi_meta,
		"current_area": WorldAreas.resolve(position, _world_id, _regions),
	}
	_events = []

	var intent := _brain.update(context)
	_apply_movement(intent, delta)
	_apply_attention(intent, delta)
	_apply_reactions(intent["reactions"])
	_apply_feeling(intent.get("feeling", {}), delta)
	_apply_look(delta)
	_update_daemon_form(delta)
	_decay_animation(delta)
	queue_redraw()



## A REMOTE puppet: no brain, no save, no collision. We glide toward the latest received position
## (deriving velocity so the same walk/bob animation plays) and ease the eyes toward the owner's
## reported attention direction. Its resting-look offsets were set once from the friend's identity
## packet (apply_remote_look); its mood simply rests neutral. Enough to read as alive and "theirs".
func _process_remote(delta: float) -> void:
	var before := position
	position = position.lerp(_target_pos, 1.0 - exp(-REMOTE_LERP_RATE * delta))
	velocity = (position - before) / maxf(delta, 0.0001)
	if _target_look.length() > 0.01:
		_look_dir = _look_dir.lerp(_target_look, 1.0 - exp(-6.0 * delta))
	_eye_offset = _look_dir.normalized() * 2.4
	_decay_animation(delta)
	queue_redraw()


## Whether the bond has reached its maximum — used by the world to reveal the
## "start over" affordance only once there's a fully bonded companion to reset.
func is_fully_bonded() -> bool:
	if _brain == null:
		return false
	var max_bond := float(_cfg.get("bond", {}).get("max", 1.0))
	return _brain.get_self().bond >= max_bond


## A single read surface for the debug overlay: the brain's last decision merged
## with the persistent self's state and a couple of presentation facts. Read-only —
## the overlay only displays this; it never writes back. Empty before the brain exists.
func debug_state() -> Dictionary:
	if _brain == null:
		return {}
	var d := _brain.debug_state().duplicate(true)
	var self_state := _brain.get_self().debug_state(_cfg)
	for key in self_state:
		d[key] = self_state[key]
	# The mood-overlaid trait values, so the overlay can show how the current mood is
	# bending behavior versus the underlying (raw) traits.
	d["effective"] = CompanionTraits.effective_snapshot(_brain.get_self(), _cfg, ["energy", "clinginess"])
	d["companion_pos"] = position
	d["speed"] = velocity.length()
	# The eased resting-look offsets, so the overlay can show how the grown identity + bond are
	# bending the pose (and how big the companion has grown) alongside the traits driving them.
	d["look"] = {
		"ear": _look_ear, "bounce": _look_bounce, "wag": _look_wag,
		"eye": _look_eye, "coat": _look_coat, "scale": _look_scale,
	}
	# How many corners the route-keeper is currently steering through (0 = direct line).
	d["nav_corners"] = _nav_agent.active_path().size() if _nav_agent != null else 0
	return d


## Start a whole new companion: wipe the save and spawn a freshly randomized partner
## so the bond arc can be played again from zero without reinstalling. Replacing the
## brain outright also clears every drive's internal timers, so it truly begins anew.
func reset() -> void:
	var fresh := CompanionSelf.make_random(_cfg, RandomNumberGenerator.new())
	_brain = CompanionBrain.new(_cfg, 0, fresh)
	_autosave_accum = 0.0
	# Re-snap the resting look to the fresh companion next frame (it begins small and unshaped),
	# rather than easing down from the previous, bonded partner's grown look.
	_look_inited = false


## A JSON-ready snapshot of the companion's grown self, for the world to push to the server
## (the sole save). Empty for a remote puppet (no brain of its own).
func self_dict() -> Dictionary:
	if not _is_local or _brain == null:
		return {}
	return _brain.get_self().to_dict()


## Adopt the server's canonical companion self (grown identity, bond, observations…) — on
## connect or when hopping worlds. Replacing the brain outright, the same swap reset() does,
## also re-snaps the resting look so the loaded companion shows its current self immediately.
func replace_self(data: Dictionary) -> void:
	if not _is_local or _brain == null or data.is_empty():
		return
	_brain = CompanionBrain.new(_cfg, 0, CompanionSelf.from_dict(data, _cfg))
	_autosave_accum = 0.0
	_look_inited = false


## Build the LOCAL companion's daemon form from the pal registry: the animals whose sheets are
## actually imported become the pool it shifts between. With none available (no art in a bare
## headless run), _form is inert and the companion keeps its procedural rig. Tuned by the
## "daemon_form" block in companion.json.
func _init_daemon_form() -> void:
	_form = CompanionForm.new(_available_forms(), _cfg.get("daemon_form", {}), RandomNumberGenerator.new())
	if _form.species() != "":
		_set_form(_form.species(), _form.variant())


## The drawable animal forms: each pal-registry species whose sheet(s) imported, with how many
## coat variants are available. Empty when no pal art is present.
func _available_forms() -> Array:
	var out: Array = []
	var species: Dictionary = PalView.registry().get("species", {})
	for sp in species:
		var declared := int(species[sp].get("variants", 1))
		var n := 0
		while n < declared and PalView.supported(sp, n):
			n += 1
		if n > 0:
			out.append({ "species": String(sp), "variants": n })
	return out


## Tick the local form's shift timer; on a shift, wear the new animal and sell it with a little
## perk pop + a delight glyph, then tell the world so friends re-render us as the new form.
func _update_daemon_form(delta: float) -> void:
	if _form == null:
		return
	if _form.update(delta):
		_set_form(_form.species(), _form.variant())
		_perk = 1.0
		_spawn_emote("delight")
		form_changed.emit()


## Wear a species + coat: validate it's drawable, load the sheet, and cache that species' layout for
## PalSprite. An unknown/un-drawable species clears the form so the procedural rig takes over again.
func _set_form(species: String, variant: int) -> void:
	if species == "" or not PalView.supported(species, variant):
		_form_species = ""
		_form_variant = 0
		_form_tex = null
		_form_sheet = {}
		return
	var reg := PalView.registry()
	# Clamp the coat to the species' real range (mirrors PalView._sheet_path), so an out-of-range or
	# untrusted remote variant lands on a valid sheet instead of a missing file.
	var declared := int((reg.get("species", {}) as Dictionary).get(species, {}).get("variants", 1))
	_form_species = species
	_form_variant = clampi(variant, 0, maxi(1, declared) - 1)
	_form_tex = load("res://assets/pals/%s_%d.png" % [species, _form_variant]) as Texture2D
	var frame: Array = reg.get("frame", [32, 32])
	_form_sheet = {
		"frame": frame,
		"fps": float(reg.get("fps", 10.0)),
		"cols": int(reg.get("move_frames", 8)),
		"rows": reg.get("rows", {}),
		"fly_row": int((reg.get("species", {}) as Dictionary).get(species, {}).get("fly_row", -1)),
	}


func _apply_movement(intent: Dictionary, delta: float) -> void:
	var target: Vector2 = intent["move_target"]
	var speed: float = intent["desired_speed"]
	# Route the brain's wish through the nav agent: while the straight line is clear this
	# returns the target untouched (open-field behavior is byte-identical to before); when
	# a wall is in the way it returns the next corner of a path around it instead. Not
	# while deliberately still (idle intent, or the point-hold below) — a frozen body that
	# "means to move" would trip the stuck detector into pointless replanning — and a
	# behavior switch (a whistle mid-route!) drops the old goal's route the same frame.
	if _nav_agent != null and _collide:
		var behavior := String(intent.get("behavior", ""))
		if behavior != _nav_behavior:
			_nav_behavior = behavior
			_nav_agent.reset()
		# The follow point is picked geometry-blind behind the player (perception), so in
		# a maze it can land across a hedge — a phantom goal in a neighboring corridor.
		# Clamp it to the PLAYER's walled region first: the companion then trails to the
		# hedge on the player's side instead of setting off around the maze. Only follow
		# is player-anchored like this (come/checkin target the player's own position).
		if behavior == "follow" and _player != null:
			target = _nav_grid.clamp_to_visible(_player.position, target)
		if speed > 0.0 and _point_t <= 0.0:
			target = _nav_agent.steer_target(position, target, delta)
		elif not _nav_agent.active_path().is_empty():
			_nav_agent.reset()
	var to_target := target - position
	var desired_velocity := Vector2.ZERO
	if to_target.length() > 2.0 and speed > 0.0:
		desired_velocity = to_target.normalized() * speed
	# Hold still while pointing: the companion stops to point out a salamander. We zero the DESIRED
	# velocity (not the velocity itself) so the body decelerates to a stop through the same accel ease
	# — settling onto point rather than snapping — and re-accelerates from ~0 on release, no lurch.
	# Keyed off the crisp binary _point_t (the controller's stop/go), not the eased _point_vis.
	if _point_t > 0.0:
		desired_velocity = Vector2.ZERO
	velocity = velocity.lerp(desired_velocity, 1.0 - exp(-float(_cfg["accel"]) * delta))
	var before := position
	position += velocity * delta
	# Keep out of barriers. With the nav agent steering around walls this is the last-inch
	# safety net (residual clearance the grid doesn't model); without it, it's the old
	# slide-along-obstacles behavior.
	if _collide:
		position = Solids.resolve(position, _body_radius, _solids, _bounds, _margin)
		velocity = (position - before) / maxf(delta, 0.0001)


func _apply_attention(intent: Dictionary, delta: float) -> void:
	# The detector tell (strongest) and the legacy hint glance both take the eyes over from the
	# brain's chosen target while active — a pointing companion locks onto the rock it senses.
	var look_target := intent["look_at"] as Vector2
	if _point_t > 0.0:
		look_target = _point_pos
	elif _hint_look_t > 0.0:
		look_target = _hint_look_pos
	var to_look := look_target - position
	if to_look.length() > 1.0:
		_look_dir = _look_dir.lerp(to_look.normalized(), 1.0 - exp(-6.0 * delta))
	_eye_offset = _look_dir.normalized() * 2.4


func _apply_reactions(reactions: Array) -> void:
	for r in reactions:
		match r:
			"hop":
				_hop_squash = 1.0
			"perk":
				_perk = 1.0
			"love":
				_spawn_emote("love")
			"delight":
				_spawn_emote("delight")


## Ease the eased mood toward the brain's current feeling (frame-rate independent). The
## mood already moves slowly in the sim; this just smooths per-frame jitter so the tail,
## ears and bounce glide rather than snap.
func _apply_feeling(feeling: Dictionary, delta: float) -> void:
	if feeling.is_empty():
		return
	var ease := 1.0 - exp(-float(_cfg.get("expression", {}).get("ease_rate", 3.0)) * delta)
	_mood_v += (float(feeling.get("valence", 0.0)) - _mood_v) * ease
	_mood_a += (float(feeling.get("arousal", 0.0)) - _mood_a) * ease


## Glide the eased RESTING LOOK toward who the companion is becoming. CompanionLook turns its
## grown identity + bond into small pose offsets (ear/bounce/tail/gaze biases, a coat warming,
## and a size that grows over the bond arc); we ease toward them slowly so the change is felt
## across a session, not seen frame to frame. The eased values are threaded into the rig in
## _draw(). The first frame (and after reset) snaps, so a loaded companion shows its current
## self at once rather than easing in from neutral on every launch.
func _apply_look(delta: float) -> void:
	if _brain == null:
		return
	var s := _brain.get_self()
	var target := CompanionLook.resting_look(s.identity, s.bond, _cfg)
	if not _look_inited:
		_look_inited = true
		_look_ear = float(target["ear_rest"])
		_look_bounce = float(target["bounce_base"])
		_look_wag = float(target["wag_life"])
		_look_eye = float(target["eye_lift"])
		_look_coat = float(target["coat_warm"])
		_look_scale = float(target["body_scale"])
		return
	var k := 1.0 - exp(-float(_cfg.get("identity_look", {}).get("ease_rate", 0.6)) * delta)
	_look_ear += (float(target["ear_rest"]) - _look_ear) * k
	_look_bounce += (float(target["bounce_base"]) - _look_bounce) * k
	_look_wag += (float(target["wag_life"]) - _look_wag) * k
	_look_eye += (float(target["eye_lift"]) - _look_eye) * k
	_look_coat += (float(target["coat_warm"]) - _look_coat) * k
	_look_scale += (float(target["body_scale"]) - _look_scale) * k


## The emergent coat warming as a node self_modulate tint, for the pixel rig. White when the
## warming is off (the common case), easing toward a gentle warm/bright tint built from the
## same RGB delta the procedural rig adds to its body color. _look_coat gates how far in it is.
func _coat_modulate() -> Color:
	if _look_coat <= 0.0:
		return Color.WHITE
	var warm: Array = _cfg.get("identity_look", {}).get("coat", {}).get("warm", [0.0, 0.0, 0.0])
	var tint := Color(1.0 + float(warm[0]), 1.0 + float(warm[1]), 1.0 + float(warm[2]))
	return Color.WHITE.lerp(tint, _look_coat)


## Warm a base coat color by the emergent coat tint, for the procedural rig: adds the configured
## RGB delta over the body color, eased in by _look_coat. A no-op (returns the input) when off.
func _warm_coat(base: Color) -> Color:
	if _look_coat <= 0.0:
		return base
	var warm: Array = _cfg.get("identity_look", {}).get("coat", {}).get("warm", [0.0, 0.0, 0.0])
	var target := Color(
		clampf(base.r + float(warm[0]), 0.0, 1.0),
		clampf(base.g + float(warm[1]), 0.0, 1.0),
		clampf(base.b + float(warm[2]), 0.0, 1.0))
	return base.lerp(target, _look_coat)


## Float a fresh emote glyph above the companion. Capped so a pathological burst can't grow
## the list without bound (in practice these are rare, earned beats).
func _spawn_emote(kind: String) -> void:
	if _emotes.size() >= 4:
		_emotes.pop_front()
	_emotes.append({ "kind": kind, "age": 0.0, "life": float(_cfg.get("expression", {}).get("emote_life", 1.8)) })


func _decay_animation(delta: float) -> void:
	_bob = sin(_time * 3.0)
	_hop_squash = maxf(0.0, _hop_squash - delta * 2.5)
	_perk = maxf(0.0, _perk - delta * 2.0)
	_hint_look_t = maxf(0.0, _hint_look_t - delta)
	# Ease the point's VISUAL intensity toward its on/off target so the lean/freeze/"!" glide,
	# while the motion-hold below keys off the crisp binary _point_t for an exact stop/go.
	_point_vis += (_point_t - _point_vis) * (1.0 - exp(-POINT_VIS_RATE * delta))
	# Age out floating emotes; keep only those still alive.
	if not _emotes.is_empty():
		var alive: Array = []
		for e in _emotes:
			e["age"] = float(e["age"]) + delta
			if float(e["age"]) < float(e["life"]):
				alive.append(e)
		_emotes = alive


func _draw() -> void:
	# Dev-only: the route the nav agent is currently steering through, drawn as a faint
	# polyline from the body to the goal — so a playtester can see WHY it's cutting
	# around a hedge. Only visible alongside the debug overlay.
	if debug_draw_nav and _nav_agent != null:
		var route: Array = _nav_agent.active_path()
		var prev := Vector2.ZERO  # local origin = the body itself
		for p in route:
			var lp := to_local(p)
			draw_line(prev, lp, Color(0.45, 0.9, 1.0, 0.45), 1.5)
			draw_circle(lp, 2.5, Color(0.45, 0.9, 1.0, 0.55))
			prev = lp
	# It faces where it walks when moving, and where it's looking (attending) when
	# still; the brain-driven hop/perk become the actor's squash/stretch, and the
	# eased eye_offset keeps the eyes tracking whatever it's attending to. The eased
	# mood becomes continuous body language: a wagging tail, ear posture and idle bounce.
	var cfg := _style.character("companion")
	var facing := _look_dir
	if velocity.length() > 6.0:
		facing = velocity.normalized()
	# DAEMON FORM takes precedence over every other rig: the companion IS a real animal right now, so
	# draw its pal sheet (shared with the ambient pals). The rich per-part mood language of the
	# procedural rig doesn't map onto a flat sheet, but the reaction beats still read — a perk pops it
	# up, a hop dips it — and the idle/walk bounce keeps it breathing. Emergent coat warmth still tints
	# the whole sprite at a high bond, exactly as the pixel-rig path does.
	if _form_tex != null:
		var spd := velocity.length()
		var moving := spd > 6.0
		var bounce := -absf(sin(_time * 8.0)) * 1.6 if moving else sin(_time * 2.4) * 0.6
		self_modulate = _coat_modulate()
		PalSprite.draw(self, _form_tex, {
			"look": facing,
			"speed": spd,
			"time": _time,
			"bounce": bounce,
			"squash": 0.16 * _perk - 0.12 * _hop_squash,
		}, _form_sheet)
		_draw_emotes()
		_draw_point_alert()
		return
	var expr: Dictionary = _cfg.get("expression", {})
	var arousal01 := clampf((_mood_a + 1.0) * 0.5, 0.0, 1.0)
	var pos_valence := clampf(_mood_v, 0.0, 1.0)   # only positive valence reads as "happy"
	var neg_valence := clampf(-_mood_v, 0.0, 1.0)  # withdrawn → tucked tail, drooping ears
	var wag_range: Array = expr.get("tail_wag_rate", [3.0, 11.0])
	var wag_rate := lerpf(float(wag_range[0]), float(wag_range[1]), arousal01)
	var wag_amp := pos_valence * float(expr.get("tail_wag_amp", 0.9)) * (0.4 + 0.6 * arousal01)
	var ear_offset := float(expr.get("ear_droop", 3.0)) * neg_valence - float(expr.get("ear_raise", 4.0)) * pos_valence * (0.5 + 0.5 * arousal01)
	var bounce_range: Array = expr.get("idle_bounce_gain", [0.6, 2.2])
	var bounce_gain := lerpf(float(bounce_range[0]), float(bounce_range[1]), arousal01)
	# Identity RESTING LOOK: a slow bias toward the companion's grown self, layered onto the
	# mood-derived pose (see CompanionLook / _apply_look). Subtle and additive — a curious
	# companion rests with ears a touch perked and eyes carried higher, an energetic one with a
	# livelier idle and a little resting tail-life, a clingy one softer. Applied BEFORE the
	# detector freeze below so an on-point companion still freezes regardless of temperament.
	ear_offset -= _look_ear
	bounce_gain += _look_bounce
	wag_amp = maxf(wag_amp, _look_wag)
	# The detector "point": as the point eases in, freeze the idle body language — a still body and a
	# stiff (un-wagging) tail, the classic on-point hold — and prick the ears forward (a negative
	# ear_offset raises/forwards them). Driven by the EASED _point_vis so the pose glides on/off.
	var det: Dictionary = _cfg.get("detector", {})
	var freeze := 1.0 - float(det.get("point_freeze", 0.85)) * _point_vis
	wag_amp *= freeze
	bounce_gain *= freeze
	ear_offset -= float(det.get("point_ear_forward", 5.0)) * _point_vis
	# Direction toward the rock it senses, in the actor's local space (the node isn't rotated, so the
	# world-delta is the local-delta). VectorActor leans the upper body this way while pointing.
	var point_dir := Vector2.ZERO
	if _point_vis > 0.001:
		point_dir = (_point_pos - position).normalized()
	# Expressive pixel-art rig (e.g. the foxlike-kit sheet): the same mood signals drive a
	# wagging tail, perking/drooping ears and an idle bounce, just rendered as sprite layers.
	if _sprite_tex != null:
		# Emergent coat warmth on the pixel rig: there's no per-pixel recolor path, so warm the
		# whole sprite via the node's self_modulate — a gentle warm/bright tint that only appears
		# at a high bond. White (no tint) until then; the warm delta brightens-and-warms toward it.
		self_modulate = _coat_modulate()
		CompanionSprite.draw(self, _sprite_tex, {
			"facing": facing,
			"speed": velocity.length(),
			"time": _time,
			"squash": 0.16 * _perk - 0.12 * _hop_squash,
			"wag_rate": wag_rate,
			"wag_amp": wag_amp,
			"ear_offset": ear_offset,
			"bounce_gain": bounce_gain,
			"body_scale": _look_scale,
		}, cfg)
		_draw_emotes()
		_draw_point_alert()
		return
	VectorActor.draw(self, _style, {
		"facing": facing,
		"speed": velocity.length(),
		"time": _time,
		"squash": 0.16 * _perk - 0.12 * _hop_squash,
		"body_color": _warm_coat(WorldData.to_color(cfg.get("body", [0.56, 0.62, 0.86]))),
		"accent_color": WorldData.to_color(cfg.get("accent", [0.34, 0.37, 0.54])),
		"radius": 9.0 * _look_scale,
		"ears": true,
		"eye_offset": _eye_offset + Vector2(0.0, -_look_eye),
		"width": float(cfg.get("width", 1.0)),
		"tail": true,
		"wag_rate": wag_rate,
		"wag_amp": wag_amp,
		"ear_offset": ear_offset,
		"bounce_gain": bounce_gain,
		"point": _point_vis,
		"point_dir": point_dir,
	})
	_draw_emotes()
	_draw_point_alert()


## The detector "!" — floats over the companion's head while it's stopped and pointing at a hidden
## salamander, at FULL opacity (it's a discrete event, not a proximity readout). Driven by the eased
## _point_vis so it fades in/out cleanly with the pose but holds full while on-point. Not the one-shot
## _emotes queue — it holds for exactly as long as the point does, then releases. Presentation only.
func _draw_point_alert() -> void:
	if _point_vis <= 0.01:
		return
	var alpha := _point_vis                    # eases to full (1.0) during the hold, fades on release
	var scale := 0.85 + 0.5 * _point_vis
	var bob := sin(_time * 6.0) * 1.2 * _point_vis  # a little excited quiver while it holds
	EmoteGlyphs.draw(self, "alert", Vector2(0.0, -30.0 + bob), alpha, scale)


## Render the floating emotes: each fades in fast, drifts upward, then fades out, drawn
## above the companion's head. Pure presentation over the brain-supplied cue.
func _draw_emotes() -> void:
	for e in _emotes:
		var life := maxf(float(e["life"]), 0.0001)
		var p := clampf(float(e["age"]) / life, 0.0, 1.0)
		var fade_in := clampf(p / 0.15, 0.0, 1.0)
		var fade_out := 1.0 - clampf((p - 0.6) / 0.4, 0.0, 1.0)
		var alpha := fade_in * fade_out
		var rise := -18.0 - p * 16.0
		var pop := 0.7 + 0.5 * clampf(p / 0.25, 0.0, 1.0)
		EmoteGlyphs.draw(self, String(e["kind"]), Vector2(0.0, rise), alpha, pop)
