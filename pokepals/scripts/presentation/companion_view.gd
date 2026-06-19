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

var velocity := Vector2.ZERO

var _brain: CompanionBrain
var _cfg: Dictionary
var _player: PlayerView
var _events: Array = []
var _points_of_interest: Array = []
var _world_id := ""
var _regions: Array = []
var _time := 0.0
var _autosave_accum := 0.0

var _look_dir := Vector2.DOWN
var _eye_offset := Vector2.ZERO
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


## Hand the avatar its shared art direction (palette + light). Called by the world.
func set_style(style: ArtStyle) -> void:
	_style = style
	_sprite_tex = SpriteSlot.resolve(style.character("companion"))


## Called by the world to tell the companion where the standing props are, so it
## can choose to wander over and investigate them on its own.
func set_points_of_interest(points: Array) -> void:
	_points_of_interest = points


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
	velocity = velocity.lerp(desired_velocity, 1.0 - exp(-float(_cfg["accel"]) * delta))
	var before := position
	position += velocity * delta
	# Keep out of barriers; the companion slides around obstacles (no path-finding).
	if _collide:
		position = Solids.resolve(position, _body_radius, _solids, _bounds, _margin)
		velocity = (position - before) / maxf(delta, 0.0001)


func _apply_attention(intent: Dictionary, delta: float) -> void:
	var to_look := (intent["look_at"] as Vector2) - position
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
	# Age out floating emotes; keep only those still alive.
	if not _emotes.is_empty():
		var alive: Array = []
		for e in _emotes:
			e["age"] = float(e["age"]) + delta
			if float(e["age"]) < float(e["life"]):
				alive.append(e)
		_emotes = alive


func _draw() -> void:
	if _sprite_tex != null:
		SpriteSlot.draw(self, _sprite_tex)
		_draw_emotes()
		return
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
	})
	_draw_emotes()


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
