class_name HuntDirector
extends Node
## The salamander hunt: the Riverbank's "find_salamanders" goal, lifted out of world_controller so the
## controller stays a conductor. Owns everything hunt-specific — the hidden layout (SalamanderHunt), the
## examinable rocks, the flip budget, and the companion's living-DETECTOR tell — and reports back to the
## host (the World) only through its small public seam (show_hint / the goal HUD / a completion portal).
##
## Presentation-coupled by nature (it drives the companion's body + world_art), so it lives under
## /presentation; the hidden-truth bookkeeping it leans on is the pure SalamanderHunt in /scripts/world.
##
## The companion as a living salamander DETECTOR — the heart of the hunt — is a DISCRETE-EVENT machine,
## not a continuous readout: when a hidden, un-found salamander is within the companion's (bond-scaled)
## sense range and the cooldown has elapsed, the companion STOPS and points at it for a couple seconds,
## then releases and cools down. The cooldown scales with bond — a fresh companion points rarely, a
## bonded one often — so the help you get IS the relationship. It reads the hunt's truth but feeds it
## solely to the companion's BODY (point_at), never its brain, so the companion still never *knows* where
## the salamanders are. Decoys/empties are never sense-able, keeping the tell honest.

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _hunt: SalamanderHunt = null  # the hidden-truth bookkeeping, or null in worlds without the goal
var _rocks: Array = []  # [ { pos, hunt_index, render_index } ] — the examinable rocks of the hunt
var _goal_active := false
var _flip_budget := 0  # max rocks the player may turn over this hunt (0 = unlimited); from goal.flip_budget
var _flips_left := 0   # rocks remaining in the budget, shown on the goal label
var _hunt_over := false  # latched once the hunt ends (won or run out) so it resolves only once
var _completion_hint := ""  # the hint shown when the hunt ended, so the coin reward can append to it

# Detector tuning (companion.json "detector"), cached from the companion at setup. When a hidden
# salamander is within (bond-scaled) sense range and the cooldown has elapsed, the companion stops
# and points at it for a couple seconds, then cools down — points more often the deeper the bond.
var _sense_low := 70.0    # sense range (px) at zero bond — short when fresh
var _sense_high := 200.0  # sense range (px) at full bond — long when bonded
var _point_cooldown_low := 9.0   # seconds between points at zero bond (rare)
var _point_cooldown_high := 2.0  # seconds between points at full bond (frequent)
var _point_hold_seconds := 2.0   # how long it stops and holds a point
# Point-event state machine (driven each frame in update_detector).
var _point_active := false       # true while the companion is holding a point
var _point_hold_left := 0.0      # seconds remaining in the current point hold
var _point_cd_left := 0.0        # seconds until the next point may fire
var _point_target := Vector2.ZERO  # world pos the companion is pointing at
var _point_target_hi := -1       # hunt_index of the pointed rock (to end early if it gets flipped)


## Wire up the host seam + scene refs, and listen for the server's hunt-reward echo. The Net connection
## is auto-dropped when this node is freed on a world hop, so it never duplicates across worlds.
func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player
	Net.hunt_reward.connect(_on_hunt_reward)


## Lay out the hunt from the world spec's goal + rocks: hide salamanders + decoys among the rocks (fresh,
## random each visit), fold each rock into `combined` (so world_art draws it) and `interactables` (so the
## controller can turn it over). A no-op unless this world declares a "find_salamanders" goal with rocks.
func setup_hunt(goal: Dictionary, rock_defs: Array, combined: Array, interactables: Array) -> void:
	if String(goal.get("type", "")) != "find_salamanders" or rock_defs.is_empty():
		return
	_goal_active = true
	_hunt_over = false
	_flip_budget = int(goal.get("flip_budget", 0))
	_flips_left = _flip_budget
	_cache_detector_tuning()
	_hunt = SalamanderHunt.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_hunt.setup(rock_defs.size(), int(goal.get("count", 10)), goal.get("decoys", []), int(goal.get("decoy_count", 0)), rng, _flip_budget)
	for ri in rock_defs.size():
		var rpos := WorldData.to_vec2(rock_defs[ri])
		var render_index := combined.size()
		combined.append({ "id": "rock_%d" % ri, "type": "rock", "position": rock_defs[ri], "color": [0.60, 0.60, 0.56], "label": "a mossy rock", "tags": ["stone"] })
		_rocks.append({ "pos": rpos, "hunt_index": ri, "render_index": render_index })
		interactables.append({ "pos": rpos, "label": "a mossy rock", "id": "rock_%d" % ri, "tags": ["stone"], "kind": "rock", "render_index": render_index, "hunt_index": ri })


## Whether this world's hunt goal is running (drives the goal label + the controller's rock gating).
func is_active() -> bool:
	return _goal_active


## True once a rock should no longer prompt "Examine": a turned-over rock, or any rock once the hunt is
## over. Used by the controller's nearest-interactable scan so finished rocks fall silent.
func should_skip_rock(hunt_index: int) -> bool:
	return _hunt != null and (_hunt_over or _hunt.is_examined(hunt_index))


## Show the initial goal text (0 found) — called once the hunt is laid out.
func show_initial_goal() -> void:
	_set_goal_text(0, _hunt.total if _hunt != null else 0)


## Cache the companion's presentation-only "detector" tuning (sense range + point cooldown/hold by bond)
## so update_detector can drive the point-event machine without re-reading the config each frame. Defaults
## keep it working if the block is absent. Seeds the first cooldown to the long (fresh) value so the
## companion never points on the very first frame of a fresh load.
func _cache_detector_tuning() -> void:
	var det: Dictionary = _companion.detector_cfg()
	_sense_low = float(det.get("sense_range_low", 70.0))
	_sense_high = float(det.get("sense_range_high", 200.0))
	_point_cooldown_low = float(det.get("point_cooldown_low", 9.0))
	_point_cooldown_high = float(det.get("point_cooldown_high", 2.0))
	_point_hold_seconds = float(det.get("point_hold_seconds", 2.0))
	_point_active = false
	_point_hold_left = 0.0
	_point_target_hi = -1
	_point_cd_left = _point_cooldown_low


## Turn over a rock: ask the hunt what's hidden under it (this spends a flip from the budget),
## reveal it (world_art tips the rock and shows the find), let the companion appraise what
## surfaced, tick the counter, and resolve the hunt if this flip won it or spent the last flip.
func examine_rock(entry: Dictionary) -> void:
	if _hunt == null or _hunt_over:
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
	_host.show_hint("You lift the rock: %s" % result["label"])
	# Tick the counter every flip so the dwindling flip budget is always legible; pop it on a find.
	_flips_left = int(result["flips_remaining"])
	_set_goal_text(int(result["found"]), int(result["total"]))
	if kind == "salamander":
		_host.bounce_goal()
	# Resolve the hunt at most once. A win beats run-out: out_of_flips() already excludes the
	# flip that finds the last salamander, so the order here is just belt-and-suspenders.
	if bool(result["newly_complete"]):
		_on_hunt_won(entry["pos"], int(result["found"]))
	elif bool(result["out_of_flips"]):
		_on_hunt_run_out(entry["pos"], int(result["found"]))


## Won the hunt — all salamanders found. Open a way home and celebrate, with an extra flourish for
## a flawless run (every flip a salamander, none wasted) — the reward for trusting your companion.
## Claim the coin reward from the server; the amount it pays appends to this hint via _on_hunt_reward.
func _on_hunt_won(at: Vector2, found: int) -> void:
	_hunt_over = true
	_host.open_completion_portal(at)
	if _flip_budget > 0 and _hunt.flips_used == found:
		_completion_hint = "A perfect hunt — every flip a salamander! A portal shimmers open just up the bank."
	else:
		_completion_hint = "All ten salamanders found! A portal shimmers open just up the bank."
	_host.show_hint(_completion_hint)
	Net.claim_hunt_reward(found)


## Ran out of flips before finding them all — no hard loss. Flip every rock still face-down so the
## player sees what they missed (dimmed), open the way home, and gently invite them back: as the
## bond deepens, the companion's tell sharpens and the next visit goes better.
func _on_hunt_run_out(at: Vector2, found: int) -> void:
	_hunt_over = true
	for r in _rocks:
		var hi := int(r["hunt_index"])
		if not _hunt.is_examined(hi):
			_world_art.reveal_rock(int(r["render_index"]), _hunt.content_kind(hi), true)
	_host.open_completion_portal(at)
	_completion_hint = "Out of flips. Here's what the river was hiding — come back and let your companion help you find them."
	_host.show_hint(_completion_hint)
	# Even a partial hunt can earn a few coins (six or more); the server decides — see _on_hunt_reward.
	Net.claim_hunt_reward(found)


## Run every frame: drive the companion's discrete-event salamander point. See the class doc for the
## why; presentation only — reads the hunt's truth but feeds it solely to the companion's body.
func update_detector(delta: float) -> void:
	if not _goal_active or _hunt == null:
		return
	if _hunt_over:
		if _point_active:
			_point_active = false
			_point_target_hi = -1
		_companion.point_at(Vector2.ZERO, 0.0)  # hunt's done — relax the pose
		return
	var bond := _companion.bond_value()

	# Holding a point: keep it full-strength until the timer runs out (or the player flips the very
	# rock it's pointing at), then release and roll the next cooldown, shorter the deeper the bond.
	if _point_active:
		_point_hold_left -= delta
		if _point_target_hi >= 0 and _hunt.is_examined(_point_target_hi):
			_point_hold_left = 0.0
		if _point_hold_left <= 0.0:
			_point_active = false
			_point_target_hi = -1
			_point_cd_left = lerpf(_point_cooldown_low, _point_cooldown_high, bond)
			_companion.point_at(Vector2.ZERO, 0.0)
		else:
			_companion.point_at(_point_target, 1.0)
		return

	# Cooling down between points — stand easy.
	if _point_cd_left > 0.0:
		_point_cd_left = maxf(0.0, _point_cd_left - delta)
		return

	# Ready: if a sense-able salamander is near, start a point hold. Otherwise leave the cooldown at
	# zero so it fires the instant one comes into range (the companion's closeness, set by bond, is
	# what decides how often that happens).
	var sense := lerpf(_sense_low, _sense_high, bond)
	var best := Vector2.ZERO
	var best_d := sense
	var best_hi := -1
	for r in _rocks:
		var hi := int(r["hunt_index"])
		if _hunt.is_examined(hi):
			continue
		if _hunt.content_kind(hi) != "salamander":
			continue
		var d := _companion.position.distance_to(r["pos"])
		if d <= best_d:
			best_d = d
			best = r["pos"]
			best_hi = hi
	if best_hi >= 0:
		_point_active = true
		_point_hold_left = _point_hold_seconds
		_point_target = best
		_point_target_hi = best_hi
		_companion.point_at(best, 1.0)


func _set_goal_text(found: int, total: int) -> void:
	if _flip_budget > 0:
		_host.set_goal_label_text("Salamanders  %d / %d\nFlips left  %d" % [found, total, _flips_left])
	else:
		_host.set_goal_label_text("Salamanders  %d / %d" % [found, total])


## The server resolved our salamander-hunt reward. Adopt the new wallet balance (so it's current next
## time we open the shop), and — if it actually paid out — append the earned coins to the completion
## hint. Below the reward threshold (fewer than six found) the amount is 0 and the hint is left alone.
func _on_hunt_reward(_found: int, amount: int, balance: int) -> void:
	_host.set_wallet_balance(balance)
	if amount > 0 and _completion_hint != "":
		var coins := "coin" if amount == 1 else "coins"
		_host.show_hint("%s  You earned %d %s!" % [_completion_hint, amount, coins])
