extends Control
## Orchestrates the turn loop and is the ONE boundary between the pure battle core
## and the UI. It holds the current state, gathers the player's action (via the
## move menu's signal), picks a simple enemy action, calls BattleLogic.resolve_turn,
## then asks the panels and log to render the returned state. It performs NO battle
## math itself — every number shown was computed by the pure core.

@onready var _player_panel: CreaturePanel = $MainLayout/Arena/PlayerPanel
@onready var _enemy_panel: CreaturePanel = $MainLayout/Arena/EnemyPanel
@onready var _move_menu: MoveMenu = $MainLayout/MoveMenu
@onready var _battle_log: BattleLog = $MainLayout/BattleLog
@onready var _prompt_label: Label = $MainLayout/PromptLabel
@onready var _restart_button: Button = $MainLayout/RestartButton

var _defs: Dictionary
var _state: Dictionary
var _ai_rng: Dictionary  # enemy move choice — kept SEPARATE from the battle RNG so
                         # the core stays the single source of outcome randomness.


func _ready() -> void:
	_defs = DataLoader.load_all("res://data/")
	_move_menu.setup(_defs)
	_move_menu.move_chosen.connect(_on_move_chosen)
	_restart_button.pressed.connect(_start_battle)
	_start_battle()


func _start_battle() -> void:
	var seed_value := int(Time.get_ticks_usec())  # fresh battle each time we play
	var matchup := _pick_matchup(seed_value)
	_state = BattleState.make_initial_state([matchup[0]], [matchup[1]], _defs, seed_value)
	_ai_rng = BattleRNG.make(seed_value ^ 0x9e3779b9)

	_battle_log.clear_log()
	_battle_log.append_line("%s faces a wild %s!" % [
		BattleState.get_active(_state, "player")["name"],
		BattleState.get_active(_state, "enemy")["name"],
	])
	_restart_button.hide()
	_render()
	_enter_choosing()


## Pick two distinct creatures for the matchup, seeded for reproducibility.
func _pick_matchup(seed_value: int) -> Array:
	var ids: Array = _defs["creatures"].keys()
	var rng := BattleRNG.make(seed_value)
	var first := BattleRNG.next_int(rng, ids.size())
	rng = first["rng"]
	var player_id: String = ids[first["value"]]
	var enemy_id := player_id
	while enemy_id == player_id:
		var pick := BattleRNG.next_int(rng, ids.size())
		rng = pick["rng"]
		enemy_id = ids[pick["value"]]
	return [player_id, enemy_id]


func _enter_choosing() -> void:
	_prompt_label.text = "Choose a move:"
	_move_menu.populate(BattleState.get_active(_state, "player"))
	_move_menu.show()


func _on_move_chosen(move_id: String) -> void:
	_move_menu.hide()
	var actions := {
		"player": { "side": "player", "kind": "move", "move_id": move_id },
		"enemy": _choose_enemy_action(),
	}
	# The one call across the pure boundary: state in -> new state out.
	_state = BattleLogic.resolve_turn(_state, actions, _defs)

	_battle_log.append_events(_state["events"], _names(), _defs)
	_render()

	if BattleState.is_over(_state):
		_prompt_label.text = "%s wins! Play again?" % _names()[BattleState.winner(_state)]
		_restart_button.show()
	else:
		_enter_choosing()


## Simple enemy AI: pick a random move from its set. Uses the controller's own RNG
## so it never disturbs the deterministic battle RNG.
func _choose_enemy_action() -> Dictionary:
	var moves: Array = BattleState.get_active(_state, "enemy")["moves"]
	var pick := BattleRNG.next_int(_ai_rng, moves.size())
	_ai_rng = pick["rng"]
	return { "side": "enemy", "kind": "move", "move_id": moves[pick["value"]] }


func _names() -> Dictionary:
	return {
		"player": BattleState.get_active(_state, "player")["name"],
		"enemy": BattleState.get_active(_state, "enemy")["name"],
	}


func _render() -> void:
	_player_panel.render(BattleState.get_active(_state, "player"))
	_enemy_panel.render(BattleState.get_active(_state, "enemy"))
