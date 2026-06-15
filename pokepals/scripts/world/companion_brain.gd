class_name CompanionBrain
extends RefCounted
## The companion's MIND — a small AGENT LOOP rather than a fixed if/elif chain.
## Each frame it runs: PERCEIVE (build facts) -> REMEMBER (update its persistent
## self) -> DECIDE (drives compete) -> ACT (emit the winner's intent). It stays
## pure: zero UI / render / scene-tree references, working in abstract Vector2
## geometry, so it could later run on a server or under a different presentation.
##
## context (Dictionary):
##   { "companion_pos": Vector2, "player_pos": Vector2, "player_velocity": Vector2,
##     "delta": float, "events": Array, "time": float }
##   events: [ { "type": "interaction", "position": Vector2 }, ... ]
##
## intent (Dictionary):
##   { "move_target": Vector2, "desired_speed": float, "look_at": Vector2,
##     "behavior": "idle"|"follow"|"wander"|"curious", "reactions": Array[String] }
##   reactions are one-shot cues for presentation: "perk", "hop", "look".

var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _self: CompanionSelf
var _drives: Array
var _behavior := "idle"


func _init(cfg: Dictionary, seed_value: int = 0, existing_self: CompanionSelf = null) -> void:
	_cfg = cfg
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	# A loaded self carries the companion across sessions; otherwise start fresh.
	_self = existing_self if existing_self != null else CompanionSelf.make_default(cfg)
	_drives = CompanionDrives.make_all(cfg, _rng)


func behavior() -> String:
	return _behavior


## The companion's persistent identity, for the presentation layer to save.
func get_self() -> CompanionSelf:
	return _self


## Decide what the companion wants this frame.
func update(context: Dictionary) -> Dictionary:
	var delta: float = context["delta"]
	var perception := CompanionPerception.perceive(context, _self, _cfg)

	# REMEMBER: fold this frame into the persistent self, then let traits drift
	# slowly toward how the player actually plays.
	_self.observe(perception, _cfg, delta)
	_self.apply_drift(_cfg, delta)

	# DECIDE: tick every drive first (so always-running timers like cooldowns
	# advance even when the drive doesn't win), then score and pick the winner.
	for drive in _drives:
		drive.tick(delta)
	var winner = null
	var best_score := -1.0
	for drive in _drives:
		var score: float = drive.evaluate(perception, _self, _cfg, _rng)
		if score > best_score:
			best_score = score
			winner = drive

	# ACT: only the winner produces the intent.
	var proposal: Dictionary = winner.act(perception, _self, _cfg, _rng, delta)
	_behavior = proposal["behavior"]
	return {
		"move_target": proposal["move_target"],
		"desired_speed": proposal["desired_speed"],
		"look_at": proposal["look_at"],
		"behavior": _behavior,
		"reactions": proposal["reactions"],
	}
