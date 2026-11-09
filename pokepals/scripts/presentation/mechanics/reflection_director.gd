class_name ReflectionDirector
extends Node
## The MIRROR STONE (Stillglass's secret): a stone that only exists in the reflection. The presentation half;
## the decisions live in the pure ReflectionWalker (scripts/world) and the drawing in the ReflectionLayer.
## Each frame it hands the walker where you and your companion are and turns the answer into:
##   * the lake's picture of your companion: it mirrors it as it mirrors everything, until your companion has
##     stood settled at the water's edge; then that mirror lets go (ripples, a shimmer), the image reforms as
##     a DIFFERENT animal (it flickers through the others first), turns, and walks off along the shore;
##   * a gentle order for the companion's brain: go and stand at the edge when you linger by the water, stand
##     while the water turns, then keep beside the reflection as it walks (a "guide" order, the same one
##     Drifthallow's fox and Underroot's light use), so it reads as your companion guiding you. Its gaze is
##     turned toward the reflection throughout (CompanionView.listen_toward, a pose that never stops the body);
##   * a ripple at each of the reflection's steps, and rings round its feet when it stops;
##   * `stone_surfaced` a beat after it stops over the last waypoint, which the SecretDirector turns into the
##     stone rising on the bank (and the usual claim on examine).
## Everything is personal and display-only: a friend beside you sees their own lake, and nothing is networked.
## Natural actions don't break it (the lesson of Dozewood and Underroot): a Pet is enjoyed (we leave the
## companion alone for a moment) and a Call is answered (the companion comes to you; we stand down for a few
## seconds, then it goes back to the reflection) - the order slot holds ONE order, so ours never overwrites
## theirs. The numbers come from the secret's `reveal` block. Whether you may take the stone stays the
## server's call (it checks "this world, standing at it" on the claim).

signal stone_surfaced

const STEP_RIPPLE_EVERY := 0.55      # seconds between the steps' ripples while it walks
const FLICKER_EVERY := 0.11

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _walker: ReflectionWalker
var _reveal: Dictionary = {}
var _lines: Dictionary = {}
var _layer: ReflectionLayer
var _found := false
var _seed := 0
var _pool: Array = []
var _species := ""              # what the lake shows instead (chosen at the turn)
var _variant := 0
var _flicker := ""              # while it turns: the shape it is passing through
var _flicker_t := 0.0
var _said := {}
var _pointing := false
var _mirror_k := 1.0            # eased: how much of the companion's own mirror shows
var _walker_k := 0.0            # eased: how much of the odd reflection shows
var _prev_player := Vector2.ZERO
var _have_prev := false
var _player_speed := 0.0
var _pet_pause := 0.0
var _call_pause := 0.0
var _step_t := 0.0
var _gather_t := 0.0
var _ring_queue: Array = []     # seconds from now at which a ring is laid at the stone's place
var _stone_timer := -1.0
var _done_handled := false
var _active := true
var _time := 0.0


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player


## Lay out this world's walk from the secret ({ id, reveal: { start, trail, ... } }).
func configure(secret: Dictionary, found: bool) -> void:
	_reveal = secret.get("reveal", {})
	_lines = _reveal.get("lines", {})
	_found = found
	_seed = MirrorGeometry.seed_of(String(secret.get("id", "mirror_stone")))
	_pool = _usable_pool(_reveal.get("species_pool", []))
	var start := WorldData.to_vec2(_reveal.get("start", secret.get("position", [0, 0])))
	var trail: Array = []
	for p in _reveal.get("trail", []):
		trail.append(WorldData.to_vec2(p))
	_walker = ReflectionWalker.new(start, trail, _reveal)
	_said = {}
	_active = true


## The animals the lake may show: the pool, narrowed to those whose sheets actually exist here.
func _usable_pool(pool: Array) -> Array:
	var have: Array = []
	for f in PalView.available_forms():
		have.append(String(f["species"]))
	var out: Array = []
	for s in pool:
		if have.has(String(s)):
			out.append(String(s))
	return out


func walker() -> ReflectionWalker:
	return _walker


## The secret has been taken: the lake keeps the toy (another walk, no stone) and nothing more.
func finish() -> void:
	_found = true


func _find_layer() -> void:
	if is_instance_valid(_layer):
		return
	_layer = _world_art.get_node_or_null("ReflectionLayer") as ReflectionLayer


## Per frame (SecretDirector.update drives it).
func update(delta: float) -> void:
	if not _active or _walker == null or _player == null or _companion == null or delta <= 0.0:
		return
	if _stone_timer > 0.0:
		_stone_timer -= delta
		if _stone_timer <= 0.0:
			_stone_timer = -1.0
			if not _found:
				stone_surfaced.emit()
	_find_layer()
	if _layer == null or not _layer.has_water():
		return
	_time += delta
	if _have_prev:
		_player_speed = _player.position.distance_to(_prev_player) / delta
	_prev_player = _player.position
	_have_prev = true

	# What a player naturally does must not be swallowed by our own orders (the brain's slot holds ONE).
	var pc := _companion.pending_command()
	if pc == "pet":
		_pet_pause = float(_reveal.get("pet_pause", 3.0))
	elif pc == "come":
		_call_pause = float(_reveal.get("call_pause", 4.0))
	_pet_pause = maxf(0.0, _pet_pause - delta)
	_call_pause = maxf(0.0, _call_pause - delta)
	var free_to_order := _pet_pause <= 0.0 and _call_pause <= 0.0 and pc != "pet" and pc != "come"

	var was := _walker.phase
	var r := _walker.update(delta, _companion.position, _companion.velocity.length(), _player.position, _player_speed)
	for e in r["events"]:
		_on_event(String(e))

	# The orders to the companion.
	var cmd := String(r["command"])
	if free_to_order and cmd != "":
		match cmd:
			"approach":
				_companion.issue_command("guide", r["target"], { "hold": false })
			"hold":
				_companion.issue_command("guide", _companion.position, { "hold": true })
			"follow":
				var beside: Vector2 = (r["target"] as Vector2) + Vector2(0.0, -float(_reveal.get("beside", 26.0)))
				var sp := float(r["speed"])
				# keep up: a companion that has fallen behind the reflection hurries to catch it
				if sp > 0.0 and _companion.position.distance_to(beside) > float(_reveal.get("catch_up_distance", 90.0)):
					sp *= float(_reveal.get("catch_up_pace", 1.6))
				_companion.issue_command("guide", beside, { "hold": sp <= 0.0, "speed": maxf(sp, 1.0) })
	if _walker.phase != ReflectionWalker.Phase.MIRROR:
		_companion.postpone_form_drift(float(_reveal.get("drift_hold", 30.0)))

	_update_species(delta)
	_update_visuals(delta, bool(r["moving"]), was)
	_update_gaze(delta)
	_update_notice(delta)
	_update_stone(delta)


func _on_event(event: String) -> void:
	match event:
		"gather":
			_say_once("gather")
		"turn":
			_species = MirrorGeometry.pick_species(_companion.current_form_species(), _pool, _seed)
			_variant = _seed % 3
			_flicker_t = 0.0
			_say_once("turn")
		"set_off":
			_say_once("set_off")
			_say_once("follow")
		"wait":
			_say_once("wait")
		"lost":
			# every time: it is the cue that the walk can be picked up again
			if _host != null and String(_lines.get("lost", "")) != "":
				_host.show_hint(String(_lines["lost"]))
		"reached":
			pass
		"done":
			_done_handled = false


func _say_once(key: String) -> void:
	if _said.has(key):
		return
	_said[key] = true
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)


## The lake must never show the animal your companion is wearing: if it drifts into the reflection's own shape
## mid-walk, the reflection becomes another.
func _update_species(delta: float) -> void:
	if _walker.phase == ReflectionWalker.Phase.WALK or _walker.phase == ReflectionWalker.Phase.WAIT:
		if _species == "" or _species == _companion.current_form_species():
			_species = MirrorGeometry.pick_species(_companion.current_form_species(), _pool, _seed + 7)
			_flicker_t = 0.0


func _update_visuals(delta: float, moving: bool, _was: int) -> void:
	var ph := _walker.phase
	var turn := _walker.turn_fraction()
	# Where the eased visibilities are headed.
	var mirror_target := 1.0
	var walker_target := 0.0
	var boost := 0.0
	match ph:
		ReflectionWalker.Phase.MIRROR:
			mirror_target = 1.0
		ReflectionWalker.Phase.TURN:
			mirror_target = 1.0 - clampf(turn * 2.2, 0.0, 1.0)
			walker_target = clampf((turn - 0.4) * 2.5, 0.0, 1.0)
			boost = sin(turn * PI)
		ReflectionWalker.Phase.WALK, ReflectionWalker.Phase.WAIT:
			mirror_target = 0.0
			walker_target = 1.0
		ReflectionWalker.Phase.DONE:
			var linger := float(_reveal.get("done_hold", 6.0))
			var fading := _walker.done_time > linger
			mirror_target = 1.0 if fading else 0.0
			walker_target = 0.0 if fading else 1.0
			if fading and _found and _walker.done_time > linger + 2.0:
				_walker.reset()   # a found secret keeps the toy: another walk from the start
	var rate := 3.0 if ph == ReflectionWalker.Phase.TURN else 1.6
	_mirror_k = move_toward(_mirror_k, mirror_target, delta * rate)
	_walker_k = move_toward(_walker_k, walker_target, delta * rate)
	# A shape-shift flickers through the other animals before it settles (as the first-meeting flock does).
	var shown := _species
	if ph == ReflectionWalker.Phase.TURN and turn > 0.35 and turn < 0.9 and not _pool.is_empty():
		_flicker_t -= delta
		if _flicker_t <= 0.0:
			_flicker_t = FLICKER_EVERY
			_flicker = String(_pool[randi() % _pool.size()])
		shown = _flicker
	if _layer != null:
		_layer.set_companion_mirror(_mirror_k)
		_layer.set_walker({
			"on": _walker.is_independent() or _walker_k > 0.01, "species": shown if shown != "" else _species, "variant": _variant,
			"pos": _walker.pos, "face": _walker.face, "moving": moving, "k": _walker_k, "boost": boost,
		})
		# The water stirs while your companion settles, and the odd reflection leaves a ripple at each step.
		if ph == ReflectionWalker.Phase.MIRROR and _walker.gather_fraction() > 0.25:
			_gather_t -= delta
			if _gather_t <= 0.0:
				_gather_t = 0.7
				var foot := _companion.position + Vector2(0.0, 8.0)
				var axis := _layer.waterline_below(foot)
				if not is_nan(axis):
					_layer.add_ripple(Vector2(foot.x, axis), 1.3, 20.0)
		if ph == ReflectionWalker.Phase.TURN and turn > 0.45 and _step_t <= 0.0:
			_step_t = 0.45
			_layer.add_ripple(_walker.pos, 1.4, 26.0)
		if moving:
			_step_t -= delta
			if _step_t <= 0.0:
				_step_t = STEP_RIPPLE_EVERY
				_layer.add_ripple(_walker.pos + Vector2(0.0, 2.0), 1.1, 14.0, Color(0.92, 0.97, 1.0, 0.5))
		elif ph != ReflectionWalker.Phase.TURN:
			_step_t = 0.0
		# Rings at the stone's place once it has stopped there.
		if not _ring_queue.is_empty():
			var left: Array = []
			for t in _ring_queue:
				var nt := float(t) - delta
				if nt <= 0.0:
					_layer.add_ripple(_walker.end_point() + Vector2(0.0, 2.0), 1.8, 40.0, Color(0.95, 0.98, 1.0, 0.8))
				else:
					left.append(nt)
			_ring_queue = left


## Your companion looks where the lake's attention is: down at its own image as the water stirs, then
## along the shore after the reflection that is walking off. Held by refreshing every frame.
func _update_gaze(_delta: float) -> void:
	var ph := _walker.phase
	var strength := float(_reveal.get("gaze", 1.0))
	if ph == ReflectionWalker.Phase.TURN or ph == ReflectionWalker.Phase.WALK or ph == ReflectionWalker.Phase.WAIT or ph == ReflectionWalker.Phase.DONE:
		if _walker_k > 0.05:
			_companion.listen_toward(_walker.pos + Vector2(0.0, 14.0), strength)
	elif ph == ReflectionWalker.Phase.MIRROR and _walker.gather_fraction() > 0.25:
		var foot := _companion.position + Vector2(0.0, 8.0)
		var axis := _layer.waterline_below(foot)
		if not is_nan(axis):
			_companion.listen_toward(Vector2(foot.x, axis + 26.0), strength)


## The companion noticing the water where the walk resumes as you come near: a held point toward it.
func _update_notice(delta: float) -> void:
	var n := _walker.notice(delta, _player.position, _companion.bond_value())
	if n["point"]:
		_companion.point_at((n["target"] as Vector2) + Vector2(0.0, 18.0), 1.0)
		_pointing = true
		if n["started"]:
			_say_once("notice")
	elif _pointing:
		_companion.point_at(Vector2.ZERO, 0.0)
		_pointing = false


## When it stops over the last waypoint: rings, then the stone.
func _update_stone(delta: float) -> void:
	if _walker.phase != ReflectionWalker.Phase.DONE or _done_handled:
		return
	_done_handled = true
	_ring_queue = [0.0, 0.5, 1.0]
	_stone_timer = float(_reveal.get("stone_delay", 1.0))
	if _found:
		return
	if _stone_timer <= 0.0:
		stone_surfaced.emit()
		_stone_timer = -1.0
