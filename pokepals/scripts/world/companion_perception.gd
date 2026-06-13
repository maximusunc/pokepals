class_name CompanionPerception
## The PERCEIVE step of the companion's agent loop. It turns the raw per-frame
## context into the handful of plain facts the drives reason over (how far the
## player is, whether they're moving, where to trail them, anything nearby worth
## noticing). Pure and stateless: same context in, same facts out — no side
## effects, no scene-tree references.

static func perceive(context: Dictionary, _s: CompanionSelf, cfg: Dictionary) -> Dictionary:
	var companion_pos: Vector2 = context["companion_pos"]
	var player_pos: Vector2 = context["player_pos"]
	var player_velocity: Vector2 = context["player_velocity"]

	# The first interaction event that happened close enough to be worth noticing.
	var has_interaction := false
	var interaction_point := Vector2.ZERO
	for e in context["events"]:
		if e["type"] == "interaction" and companion_pos.distance_to(e["position"]) <= float(cfg["curiosity_radius"]):
			has_interaction = true
			interaction_point = e["position"]
			break

	# The nearest standing point of interest in the world (a prop it could wander to
	# on its own), within wander range. Defaults to curiosity_radius if unset.
	var wander_radius := float(cfg.get("wander_radius", cfg["curiosity_radius"]))
	var has_poi := false
	var nearest_poi := Vector2.ZERO
	var best := INF
	for p in context.get("points_of_interest", []):
		var d := companion_pos.distance_to(p)
		if d <= wander_radius and d < best:
			best = d
			nearest_poi = p
			has_poi = true

	return {
		"companion_pos": companion_pos,
		"player_pos": player_pos,
		"player_velocity": player_velocity,
		"delta": float(context.get("delta", 0.0)),
		"dist_to_player": companion_pos.distance_to(player_pos),
		"player_moving": player_velocity.length() >= 1.0,
		"follow_point": _follow_point(companion_pos, player_pos, player_velocity, float(cfg["follow_near"])),
		"has_interaction": has_interaction,
		"interaction_point": interaction_point,
		"has_poi": has_poi,
		"nearest_poi": nearest_poi,
	}


## A resting point a comfortable follow_near from the player, on the side the
## companion should occupy: directly behind the player's heading when moving, or on
## its current side when the player is still. This makes it trail rather than
## overlap.
static func _follow_point(companion_pos: Vector2, player_pos: Vector2, velocity: Vector2, follow_near: float) -> Vector2:
	var behind: Vector2
	if velocity.length() >= 1.0:
		behind = -velocity.normalized()
	else:
		behind = companion_pos - player_pos
		if behind.length() < 1.0:
			behind = Vector2.DOWN
		behind = behind.normalized()
	return player_pos + behind * follow_near
