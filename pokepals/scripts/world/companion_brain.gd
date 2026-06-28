class_name CompanionBrain
extends RefCounted
## The companion's MIND — a small AGENT LOOP rather than a fixed if/elif chain.
## Each frame it runs: PERCEIVE (build facts) -> REMEMBER (update its persistent
## self) -> DECIDE (the arbiter scores competing actions and picks one) -> ACT (emit
## the winner's intent). It stays pure: zero UI / render / scene-tree references,
## working in abstract Vector2 geometry, so it could later run on a server or under a
## different presentation. Decision logic is split three ways for growth: CompanionActions
## (each action scores only itself), CompanionArbiter (all cross-action priority/anti-jitter),
## and CompanionConsiderations + CompanionTraits (declarative, data-driven desire).
##
## context (Dictionary):
##   { "companion_pos": Vector2, "player_pos": Vector2, "player_velocity": Vector2,
##     "delta": float, "events": Array, "time": float }
##   events: [ { "type": "interaction", "position": Vector2 }, ... ]
##
## intent (Dictionary):
##   { "move_target": Vector2, "desired_speed": float, "look_at": Vector2,
##     "behavior": "idle"|"follow"|"wander"|"curious", "reactions": Array[String],
##     "feeling": { "valence": float, "arousal": float, "bond": float } }
##   reactions are one-shot cues for presentation: "perk", "hop", "look", "love".
##   feeling is a continuous read surface (mood -1..1, bond 0..1) for body language —
##   the presentation reads it to express how the companion feels, never to decide behavior.

var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
# Mood's random walk runs on its OWN stream so it never perturbs the action RNG — the
# companion's decisions stay reproducible from the seed; only the affective overlay moves.
var _mood_rng := RandomNumberGenerator.new()
# Social referencing keeps its own stream too: the brain pre-rolls the glance/approach
# dice here and hands them to the actions via perception, so adding this feature leaves the
# action RNG sequence (and every seeded test that depends on it) byte-for-byte unchanged.
var _ref_rng := RandomNumberGenerator.new()
# Whether to bother coming over to investigate is its own pre-rolled decision, on yet another
# dedicated stream, so adding the hesitation leaves both the action RNG and the social-
# referencing stream (and every seeded test that leans on them) byte-for-byte unchanged.
var _consider_rng := RandomNumberGenerator.new()
# Player COMMANDS (call/whistle, pet) carry a BOND-GATED chance — whether it comes when
# whistled, whether it accepts a pet or shies away. That randomness rides its OWN dedicated
# stream, pre-rolled here and handed to the command actions via perception, so adding these
# verbs leaves the action RNG and every other stream (and the seeded tests on them) untouched.
var _command_rng := RandomNumberGenerator.new()
# A one-frame latch for a player order; consumed (and cleared) by update() the next frame, so
# a command is a single edge the command-band actions can catch, exactly like an interaction.
var _pending_command := ""
# Some orders carry a world POINT (e.g. "settle" on a plate the search just revealed). Latched
# alongside the command and handed to the action via perception["command_point"]; null when the
# pending order has no point (a bare "come"/"pet"/"seek"). Cleared with the command each frame.
var _pending_command_point = null
var _attention := CompanionAttention.new()
var _self: CompanionSelf
var _actions: Array
var _arbiter: CompanionArbiter
var _behavior := "idle"
# A read-only snapshot of the last decision, for the debug overlay. Plain numbers
# and strings only — nothing here couples the brain to a presentation.
var _last_debug: Dictionary = {}


func _init(cfg: Dictionary, seed_value: int = 0, existing_self: CompanionSelf = null) -> void:
	_cfg = cfg
	if seed_value != 0:
		_rng.seed = seed_value
		_mood_rng.seed = seed_value + 1  # distinct, still deterministic
		_ref_rng.seed = seed_value + 2
		_consider_rng.seed = seed_value + 3
		_command_rng.seed = seed_value + 4
	else:
		_rng.randomize()
		_mood_rng.randomize()
		_ref_rng.randomize()
		_consider_rng.randomize()
		_command_rng.randomize()
	# A loaded self carries the companion across sessions; otherwise start fresh.
	_self = existing_self if existing_self != null else CompanionSelf.make_default(cfg)
	_actions = CompanionActions.make_all(cfg, _rng)
	_arbiter = CompanionArbiter.new()


func behavior() -> String:
	return _behavior


## The companion's persistent identity, for the presentation layer to save.
func get_self() -> CompanionSelf:
	return _self


## A player ORDER for the next decision — the implementation of the reserved `command`-band
## seam. The presentation calls this (e.g. from a Call or Pet button); it's latched and folded
## into the next frame's perception, where a command-band action may catch it. Whether the
## companion actually obeys is up to that action and the bond — issuing a command never forces
## the outcome, it just offers one (see ComeAction / PetAction).
func issue_command(command: String, point = null) -> void:
	_pending_command = command
	_pending_command_point = point


## A snapshot of the last frame's decision for diagnostics: the winning behavior,
## the spatial facts that drove it, and every drive's score this frame. Read-only;
## the brain never reads this back, so it can't affect behavior.
func debug_state() -> Dictionary:
	return _last_debug


## Decide what the companion wants this frame.
func update(context: Dictionary) -> Dictionary:
	var delta: float = context["delta"]
	var perception := CompanionPerception.perceive(context, _self, _cfg)

	# SOCIAL REFERENCING: read what the player seems focused on and pre-roll the glance /
	# approach dice on the dedicated stream, merging both into perception. Actions consume
	# these rolls instead of drawing from the action RNG, so the decision stream is intact.
	var attention := _attention.update(context, _cfg, delta)
	perception["has_attended"] = attention["has_attended"]
	perception["attended_object"] = attention["attended_object"]
	perception["attention_strength"] = attention["attention_strength"]
	perception["noticed_strength"] = attention["noticed_strength"]
	perception["glance_roll"] = _ref_rng.randf()
	perception["cue_roll"] = _ref_rng.randf()
	perception["investigate_roll"] = _consider_rng.randf()

	# PLAYER COMMAND: hand this frame's pending order (if any) to the command-band actions,
	# along with their pre-rolled bond-gated dice on the dedicated stream, then clear the latch
	# so the order is a single edge (caught this frame or not at all). Both dice are rolled every
	# frame so the stream advances uniformly whether or not a command is pending — the command
	# action consumes the current value when it latches.
	perception["command"] = _pending_command
	perception["command_point"] = _pending_command_point
	perception["command_roll"] = _command_rng.randf()
	perception["pet_roll"] = _command_rng.randf()
	_pending_command = ""
	_pending_command_point = null

	# REMEMBER: fold this frame into the persistent self, advance the fast mood (reads the
	# discovery novelty observe just recorded), then let traits drift slowly toward how the
	# player actually plays.
	_self.observe(perception, _cfg, delta)
	_self.update_mood(perception, _cfg, delta, _mood_rng)
	_self.apply_drift(_cfg, delta)

	# DECIDE: tick every action first (so always-running timers like cooldowns advance
	# even when the action doesn't win), then let the arbiter score them and pick a
	# winner — bands, tie-breaks, anti-jitter and interruption all live in there.
	for action in _actions:
		action.tick(delta)
	var decision: Dictionary = _arbiter.decide(_actions, perception, _self, _cfg, _rng)
	var winner = decision["winner"]

	# ACT: only the winner produces the intent.
	var proposal: Dictionary = winner.act(perception, _self, _cfg, _rng, delta)
	_behavior = proposal["behavior"]
	# Affective cues ride alongside the winner's reactions: a bond milestone crossed this
	# frame (set during observe) becomes a one-off "love" beat. Duplicate first so we never
	# mutate the action's own reactions array.
	var reactions: Array = (proposal["reactions"] as Array).duplicate()
	if _self.bond_event == "milestone":
		reactions.append("love")
	_last_debug = {
		"behavior": _behavior,
		"dist_to_player": perception["dist_to_player"],
		"follow_near": perception["follow_near"],
		"scores": decision["scores"],
		"winner": winner.id,
		"has_attended": perception["has_attended"],
		"attention_strength": perception["attention_strength"],
		"current_area": perception["current_area"],
	}
	return {
		"move_target": proposal["move_target"],
		"desired_speed": proposal["desired_speed"],
		"look_at": proposal["look_at"],
		"behavior": _behavior,
		"reactions": reactions,
		"feeling": {
			"valence": _self.mood_valence,
			"arousal": _self.mood_arousal,
			"bond": _self.bond,
		},
	}
