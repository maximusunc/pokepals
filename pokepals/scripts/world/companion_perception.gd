class_name CompanionPerception
## The PERCEIVE step of the companion's agent loop. It turns the raw per-frame
## context into the handful of plain facts the drives reason over (how far the
## player is, whether they're moving, where to trail them, anything nearby worth
## noticing). Pure and stateless: same context in, same facts out — no side
## effects, no scene-tree references.

static func perceive(context: Dictionary, s: CompanionSelf, cfg: Dictionary) -> Dictionary:
	var companion_pos: Vector2 = context["companion_pos"]
	var player_pos: Vector2 = context["player_pos"]
	var player_velocity: Vector2 = context["player_velocity"]

	# The comfortable distance for THIS frame, scaled by how bonded we are: wide when
	# fresh, snug once bonded. Computed once here so the deadzone, the trailing point,
	# and the "near" bubble that feeds bond growth all agree on a single number.
	var bond := s.bond if s != null else 0.0
	var follow_near := effective_follow_near(cfg, bond)

	# How far it notices the player's pokes, widened a little for a curious companion
	# and narrowed for an incurious one — so the "interactable-inclined" trait is felt.
	var curiosity := s.trait_value("curiosity", 0.5) if s != null else 0.5
	var curiosity_radius := float(cfg["curiosity_radius"]) * lerpf(0.7, 1.3, curiosity)

	# The first interaction event that happened close enough to be worth noticing.
	var has_interaction := false
	var interaction_point := Vector2.ZERO
	var interaction_id := ""
	var interaction_tags: Array = []
	for e in context["events"]:
		if e["type"] == "interaction" and companion_pos.distance_to(e["position"]) <= curiosity_radius:
			has_interaction = true
			interaction_point = e["position"]
			interaction_id = String(e.get("id", ""))
			interaction_tags = e.get("tags", [])
			break

	# How drawn the companion is to that thing, from its neutral tags appraised through this
	# companion's tastes + curiosity. Neutral when there's nothing to appraise.
	var interaction_appeal := CompanionAppraisal.appeal(interaction_tags, cfg, curiosity) if has_interaction else 1.0

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
		"follow_near": follow_near,
		"follow_point": _follow_point(companion_pos, player_pos, player_velocity, follow_near),
		"has_interaction": has_interaction,
		"interaction_point": interaction_point,
		"interaction_id": interaction_id,
		"interaction_tags": interaction_tags,
		"interaction_appeal": interaction_appeal,
		"current_area": String(context.get("current_area", "")),
		"has_poi": has_poi,
		"nearest_poi": nearest_poi,
	}


## The companion's comfortable distance for a given bond. A fresh companion keeps a
## wide berth (follow_near_low) — its own creature, barely seeming tied to you — and
## as the bond deepens this shrinks to the snug, at-your-side follow_near. So the
## "leash" you come to feel is really the relationship itself drawing closer: the
## same step away that a fresh companion ignores is the one a bonded one hurries to
## close. A no-op (just follow_near) if follow_near_low isn't configured.
static func effective_follow_near(cfg: Dictionary, bond: float) -> float:
	var snug := float(cfg["follow_near"])
	var loose := float(cfg.get("follow_near_low", snug))
	# Shape the shrink with a curve exponent: k < 1 tightens early and steadily so the
	# closing-in is FELT across the whole bond arc, rather than staying wide and then
	# snapping in only at the very end. k = 1 is the old linear behavior.
	var k := float(cfg.get("follow_near_curve", 1.0))
	var t := pow(clampf(bond, 0.0, 1.0), k)
	return lerpf(loose, snug, t)


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
