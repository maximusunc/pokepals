class_name CompanionBrain
extends RefCounted
## The companion's MIND — pure behavior logic with zero UI/render/scene-tree
## references. It decides *what* the companion wants (move toward a point, attend
## to something, idle, react); the presentation layer decides *how* that looks.
## It works in abstract geometry (Vector2) so it isn't welded to 2D rendering and
## could later run on a server or under a different presentation.
##
## Per frame, presentation calls update(context) and gets back an intent.
##
## context (Dictionary):
##   { "companion_pos": Vector2, "player_pos": Vector2, "player_velocity": Vector2,
##     "delta": float, "events": Array, "time": float }
##   events: [ { "type": "interaction", "position": Vector2 }, ... ]
##
## intent (Dictionary):
##   { "move_target": Vector2, "desired_speed": float, "look_at": Vector2,
##     "behavior": "idle"|"follow"|"curious", "reactions": Array[String] }
##   reactions are one-shot cues for presentation: "perk", "hop", "look".

var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()

var _behavior := "idle"
var _look_at := Vector2.ZERO
var _has_look := false
var _curiosity_target := Vector2.ZERO
var _has_curiosity := false
var _curiosity_timer := 0.0
var _curiosity_cooldown := 0.0
var _idle_look_timer := 0.0


func _init(cfg: Dictionary, seed_value: int = 0) -> void:
	_cfg = cfg
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_idle_look_timer = _roll_idle_interval()


func _roll_idle_interval() -> float:
	var interval: Array = _cfg["idle_look_interval"]
	return _rng.randf_range(float(interval[0]), float(interval[1]))


func behavior() -> String:
	return _behavior


## Decide what the companion wants this frame.
func update(context: Dictionary) -> Dictionary:
	var delta: float = context["delta"]
	var companion_pos: Vector2 = context["companion_pos"]
	var player_pos: Vector2 = context["player_pos"]
	var reactions: Array = []

	_curiosity_cooldown = maxf(0.0, _curiosity_cooldown - delta)
	_maybe_trigger_curiosity(context, reactions)

	var intent := {}
	if _has_curiosity:
		_update_curious(companion_pos, delta, intent)
	else:
		var dist := companion_pos.distance_to(player_pos)
		if dist > float(_cfg["follow_near"]):
			_update_follow(context, dist, intent)
		else:
			_update_idle(context, delta, intent, reactions)

	intent["behavior"] = _behavior
	intent["reactions"] = reactions
	return intent


## A nearby interaction (within curiosity range, off cooldown) draws the
## companion's attention — the core "it noticed what I did" moment.
func _maybe_trigger_curiosity(context: Dictionary, reactions: Array) -> void:
	var companion_pos: Vector2 = context["companion_pos"]
	for e in context["events"]:
		if e["type"] != "interaction":
			continue
		var pos: Vector2 = e["position"]
		if companion_pos.distance_to(pos) <= float(_cfg["curiosity_radius"]) and _curiosity_cooldown <= 0.0:
			_curiosity_target = pos
			_has_curiosity = true
			_curiosity_timer = float(_cfg["curiosity_linger"])
			_curiosity_cooldown = float(_cfg["curiosity_cooldown"])
			reactions.append("perk")


func _update_curious(companion_pos: Vector2, delta: float, intent: Dictionary) -> void:
	_behavior = "curious"
	_curiosity_timer -= delta
	var stop_at: float = float(_cfg["curiosity_stop_distance"])
	if companion_pos.distance_to(_curiosity_target) > stop_at:
		intent["move_target"] = _curiosity_target
		intent["desired_speed"] = float(_cfg["walk_speed"])
	else:
		intent["move_target"] = companion_pos
		intent["desired_speed"] = 0.0
	intent["look_at"] = _curiosity_target
	if _curiosity_timer <= 0.0:
		_has_curiosity = false


func _update_follow(context: Dictionary, dist: float, intent: Dictionary) -> void:
	_behavior = "follow"
	intent["move_target"] = _follow_point(context)
	# Hustle when far behind; stroll when just trailing.
	intent["desired_speed"] = float(_cfg["run_speed"]) if dist > float(_cfg["follow_far"]) else float(_cfg["walk_speed"])
	intent["look_at"] = context["player_pos"]


func _update_idle(context: Dictionary, delta: float, intent: Dictionary, reactions: Array) -> void:
	_behavior = "idle"
	var companion_pos: Vector2 = context["companion_pos"]
	intent["move_target"] = companion_pos
	intent["desired_speed"] = 0.0

	_idle_look_timer -= delta
	if _idle_look_timer <= 0.0:
		_idle_look_timer = _roll_idle_interval()
		# Mostly glance back at the player (clinginess); sometimes look around.
		if _rng.randf() < float(_cfg["personality"]["clinginess"]):
			_look_at = context["player_pos"]
		else:
			_look_at = companion_pos + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * 48.0
		_has_look = true
		reactions.append("look")
		# Energetic companions hop more often when idling.
		if _rng.randf() < float(_cfg["personality"]["energy"]) * 0.5:
			reactions.append("hop")

	intent["look_at"] = _look_at if _has_look else context["player_pos"]


## A resting point a comfortable follow_near from the player, on the side the
## companion should occupy: directly behind the player's heading when moving, or
## on its current side when the player is still. This makes it trail rather than
## overlap.
func _follow_point(context: Dictionary) -> Vector2:
	var player_pos: Vector2 = context["player_pos"]
	var companion_pos: Vector2 = context["companion_pos"]
	var velocity: Vector2 = context["player_velocity"]
	var behind: Vector2
	if velocity.length() >= 1.0:
		behind = -velocity.normalized()
	else:
		behind = companion_pos - player_pos
		if behind.length() < 1.0:
			behind = Vector2.DOWN
		behind = behind.normalized()
	return player_pos + behind * float(_cfg["follow_near"])
