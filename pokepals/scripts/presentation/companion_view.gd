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

@export var config_path := "res://data/companion.json"

const SELF_SAVE_PATH := "user://companion_self.json"
const AUTOSAVE_INTERVAL := 15.0
const POINT_VIS_RATE := 8.0  # per-sec ease of the point's visual intensity toward its on/off target

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
var _solids: Array = []
var _bounds := Rect2()
var _body_radius := 6.0
var _margin := 2.0
var _collide := false
# Eased read of the brain's feeling surface, so body language glides instead of twitching.
var _mood_v := 0.0
var _mood_a := 0.0
# Active floating emotes: each { kind: String, age: float, life: float }.
var _emotes: Array = []


## Hand the avatar the world's barriers to collide against (trees, props, water, edge).
func set_solids(solids: Array, bounds: Rect2, body_radius: float, margin: float) -> void:
	_solids = solids
	_bounds = bounds
	_body_radius = body_radius
	_margin = margin
	_collide = true


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


## Called by the world when the player issues an order — a call/whistle ("come") or a pet
## ("pet"). Pure passthrough to the brain's command seam; the brain (and the bond) decide
## what actually happens.
func issue_command(command: String) -> void:
	if _brain != null:
		_brain.issue_command(command)


func _ready() -> void:
	# Crisp pixel art: nearest-neighbour sampling on this node only (matches PlayerView), so a
	# dropped-in companion sheet stays sharp when scaled, without touching the procedural world.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cfg = WorldData.load_json(config_path)
	# Carry the companion across sessions: load its saved self if there is one, so
	# it returns as the same partner the player has been shaping.
	var saved: Dictionary = SaveStore.load_json(SELF_SAVE_PATH)
	var existing_self: CompanionSelf = null
	if not saved.is_empty():
		existing_self = CompanionSelf.from_dict(saved, _cfg)
	else:
		# A brand-new companion: gently randomize its traits so this playthrough's
		# partner has its own slight leanings (a touch more wander-, prop-, or
		# follow-inclined) rather than always the exact same temperament.
		existing_self = CompanionSelf.make_random(_cfg, RandomNumberGenerator.new())
	_brain = CompanionBrain.new(_cfg, 0, existing_self)
	if _style == null:
		_style = ArtStyle.load_style()


func _process(delta: float) -> void:
	_time += delta
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
	_decay_animation(delta)
	queue_redraw()

	# Periodic autosave so a long session (or a mobile app being backgrounded)
	# never loses much of who the companion is becoming.
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_INTERVAL:
		_autosave_accum = 0.0
		_save_self()


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
	return d


## Start a whole new companion: wipe the save and spawn a freshly randomized partner
## so the bond arc can be played again from zero without reinstalling. Replacing the
## brain outright also clears every drive's internal timers, so it truly begins anew.
func reset() -> void:
	SaveStore.delete_save(SELF_SAVE_PATH)
	var fresh := CompanionSelf.make_random(_cfg, RandomNumberGenerator.new())
	_brain = CompanionBrain.new(_cfg, 0, fresh)
	_autosave_accum = 0.0


## Persist who the companion has become. Cheap and idempotent.
func _save_self() -> void:
	if _brain == null:
		return
	SaveStore.save_json(SELF_SAVE_PATH, _brain.get_self().to_dict())


## Save on the ways a session can end: window close, app backgrounded on mobile,
## or this node leaving the tree (scene change / quit).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_save_self()


func _apply_movement(intent: Dictionary, delta: float) -> void:
	var target: Vector2 = intent["move_target"]
	var speed: float = intent["desired_speed"]
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
	# Keep out of barriers; the companion slides around obstacles (no path-finding).
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
	# It faces where it walks when moving, and where it's looking (attending) when
	# still; the brain-driven hop/perk become the actor's squash/stretch, and the
	# eased eye_offset keeps the eyes tracking whatever it's attending to. The eased
	# mood becomes continuous body language: a wagging tail, ear posture and idle bounce.
	var cfg := _style.character("companion")
	var facing := _look_dir
	if velocity.length() > 6.0:
		facing = velocity.normalized()
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
		CompanionSprite.draw(self, _sprite_tex, {
			"facing": facing,
			"speed": velocity.length(),
			"time": _time,
			"squash": 0.16 * _perk - 0.12 * _hop_squash,
			"wag_rate": wag_rate,
			"wag_amp": wag_amp,
			"ear_offset": ear_offset,
			"bounce_gain": bounce_gain,
		}, cfg)
		_draw_emotes()
		_draw_point_alert()
		return
	VectorActor.draw(self, _style, {
		"facing": facing,
		"speed": velocity.length(),
		"time": _time,
		"squash": 0.16 * _perk - 0.12 * _hop_squash,
		"body_color": WorldData.to_color(cfg.get("body", [0.56, 0.62, 0.86])),
		"accent_color": WorldData.to_color(cfg.get("accent", [0.34, 0.37, 0.54])),
		"radius": 9.0,
		"ears": true,
		"eye_offset": _eye_offset,
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
