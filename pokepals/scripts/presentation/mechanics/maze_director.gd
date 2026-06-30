class_name MazeDirector
extends Node
## The hedge maze: a "reach_center" goal, lifted out of world_controller. Owns the goal state (centre +
## reach radius), latches the reward the moment you reach the heart, and drives the companion as a quiet
## maze-guide — after you've stood still a while it points subtly along the SOLVED PATH to the centre
## (from the spec's authored flow field). Reports back to the host (the World) only through its small
## public seam (show_hint / the goal HUD / the wallet).
##
## Presentation-coupled (it drives the companion's body + reads the player's position), so it lives under
## /presentation. The guide is presentation only — like the salamander tell it feeds the companion's BODY
## (point_at), never its brain, so the companion still never *knows* the way; its body just leans where
## the path leads.

# The companion's "point the way" hint: after standing still a while, the companion subtly points along
# the SOLVED PATH to the centre. The path direction per cell is authored in the spec's "maze_guide" flow
# field (1=N 2=E 3=S 4=W, 0=centre) — pure presentation, it never moves the player.
const MAZE_HINT_DELAY := 5.0      # seconds stood still before the companion points the way
const MAZE_HINT_STRENGTH := 0.5   # a gentle, subtle point (1.0 is the hunt's full lock-on)
const MAZE_HINT_REACH := 88.0     # how far ahead (px) to place the point target
const MAZE_MOVE_EPS := 0.6        # per-frame move (px) under which the player counts as standing still

var _host: Node
var _companion: CompanionView
var _player: PlayerView

var _maze_active := false        # true in a world whose goal.type is "reach_center"
var _maze_center := Vector2.ZERO # the heart of the maze (world pos)
var _maze_radius := 70.0         # how near counts as "reached"
var _maze_reached := false       # latched once reached this visit, so the reward fires once
var _banner := "Find the heart of the maze"  # the goal-label banner this world declares
var _completion_hint := ""       # the hint shown on reaching the heart, so the coin reward can append to it
var _maze_guide_origin := Vector2.ZERO  # world centre of cell (0,0)
var _maze_guide_pitch := 100.0          # world distance between adjacent cell centres
var _maze_guide_cols := 0
var _maze_guide_rows := 0
var _maze_guide_dirs: Array = []        # row-major (cy*cols + cx) path-direction codes
var _maze_idle := 0.0            # seconds the player has stood still
var _maze_pointing := false      # whether the companion is currently giving the hint
var _last_player_pos := Vector2.ZERO  # to measure per-frame movement for the idle timer


## Wire up the host seam + scene refs, and listen for the server's maze-reward echo. The Net connection
## is auto-dropped when this node is freed on a world hop, so it never duplicates across worlds.
func setup(host: Node, companion: CompanionView, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_player = player
	Net.maze_reward.connect(_on_maze_reward)


## Read the goal: in a "reach_center" world cache the centre + radius (to notice when the player reaches
## the heart) and the companion's flow-field guide. A no-op in worlds with a different (or no) goal.
func setup_goal(goal: Dictionary, data: Dictionary) -> void:
	if String(goal.get("type", "")) != "reach_center":
		return
	_maze_active = true
	_maze_center = WorldData.to_vec2(goal.get("center", [0, 0]))
	_maze_radius = float(goal.get("radius", 70.0))
	_banner = String(goal.get("label", "Find the heart of the maze"))
	# The flow field the companion points along (the solved path per cell, toward the centre).
	var guide: Dictionary = data.get("maze_guide", {})
	_maze_guide_dirs = guide.get("dirs", [])
	if not _maze_guide_dirs.is_empty():
		_maze_guide_origin = WorldData.to_vec2(guide.get("origin", [0, 0]))
		_maze_guide_pitch = float(guide.get("pitch", 100.0))
		_maze_guide_cols = int(guide.get("cols", 0))
		_maze_guide_rows = int(guide.get("rows", 0))


## Whether this world is a maze (drives the goal label + the Return affordance gating).
func is_active() -> bool:
	return _maze_active


## Show the maze's goal banner — called once the world is laid out.
func show_initial_goal() -> void:
	_host.set_goal_label_text(_banner)


## Capture the player's placed position as the idle-timer baseline (called after _place_arrivals, since
## the player isn't placed yet when setup_goal runs during content layout).
func note_player_baseline() -> void:
	_last_player_pos = _player.position


## Run every frame: notice the moment the player reaches the heart (claim the reward, once), then drive
## the quiet maze-guide hint. A no-op outside a maze.
func update(delta: float) -> void:
	if not _maze_active:
		return
	# The moment the player reaches the heart, claim the reward (once per visit).
	if not _maze_reached and _player.position.distance_to(_maze_center) <= _maze_radius:
		_on_maze_reached()
	_update_maze_hint(delta)


## Reached the heart of the hedge maze. Latch it (so it fires once this visit), celebrate, and claim
## the coin reward from the server — the amount it pays appends to this hint via _on_maze_reward. The
## way home is the portal standing right here in the plaza; the Return button is the other way out.
func _on_maze_reached() -> void:
	_maze_reached = true
	_host.set_goal_label_text("The heart of the maze!")
	_completion_hint = "You've reached the heart of the maze!"
	_host.show_hint(_completion_hint)
	Net.claim_maze_reward()


## The companion as a quiet maze-guide: once you've stood still for MAZE_HINT_DELAY, it points subtly
## along the SOLVED PATH to the centre (from the spec's authored flow field), and relaxes the moment you
## move again or reach the heart. See the class doc for the why. A no-op outside the maze.
func _update_maze_hint(delta: float) -> void:
	if not _maze_active:
		return
	# Done hinting once you've reached the heart (or if the world carried no guide) — relax the pose.
	if _maze_reached or _maze_guide_dirs.is_empty():
		if _maze_pointing:
			_companion.point_at(Vector2.ZERO, 0.0)
			_maze_pointing = false
		return
	# Moving resets the idle timer and releases any point — the hint is only for when you've paused.
	var moved := _player.position.distance_to(_last_player_pos)
	_last_player_pos = _player.position
	if moved > MAZE_MOVE_EPS:
		_maze_idle = 0.0
		if _maze_pointing:
			_companion.point_at(Vector2.ZERO, 0.0)
			_maze_pointing = false
		return
	_maze_idle += delta
	if _maze_idle < MAZE_HINT_DELAY:
		return
	var dir := _maze_dir_at(_player.position)
	if dir == Vector2.ZERO:
		return  # at/over the centre, or off-grid — nothing to point toward
	_maze_pointing = true
	_companion.point_at(_player.position + dir * MAZE_HINT_REACH, MAZE_HINT_STRENGTH)


## The path direction (a unit Vector2) out of the cell the given world pos falls in, from the maze
## flow field — toward the centre. Vector2.ZERO at the centre cell or if there's no guide.
func _maze_dir_at(pos: Vector2) -> Vector2:
	if _maze_guide_cols <= 0 or _maze_guide_rows <= 0:
		return Vector2.ZERO
	var cx := clampi(int(round((pos.x - _maze_guide_origin.x) / _maze_guide_pitch)), 0, _maze_guide_cols - 1)
	var cy := clampi(int(round((pos.y - _maze_guide_origin.y) / _maze_guide_pitch)), 0, _maze_guide_rows - 1)
	match int(_maze_guide_dirs[cy * _maze_guide_cols + cx]):
		1: return Vector2(0, -1)
		2: return Vector2(1, 0)
		3: return Vector2(0, 1)
		4: return Vector2(-1, 0)
		_: return Vector2.ZERO


## The server resolved our maze reward. Adopt the new wallet balance (so the shop is current next
## time), and — if it paid out — append the earned coins to the celebration hint.
func _on_maze_reward(amount: int, balance: int) -> void:
	_host.set_wallet_balance(balance)
	if amount > 0 and _completion_hint != "":
		var coins := "coin" if amount == 1 else "coins"
		_host.show_hint("%s  You earned %d %s!" % [_completion_hint, amount, coins])
