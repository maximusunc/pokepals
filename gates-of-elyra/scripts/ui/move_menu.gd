class_name MoveMenu
extends VBoxContainer
## Builds a button per move for the active creature and reports the player's
## choice via the move_chosen signal. Pure input -> signal; it contains no battle
## logic and never resolves anything.

## Emitted when the player clicks a move button. The controller listens for this.
signal move_chosen(move_id: String)

var _defs: Dictionary


func setup(defs: Dictionary) -> void:
	_defs = defs


## Rebuild the button list for the given creature_state.
func populate(creature: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	for move_id in creature["moves"]:
		var move: Dictionary = _defs["moves"][move_id]
		var button := Button.new()
		button.text = "%s   (%s · pow %d · acc %d%%)" % [
			move["name"], move["type"], int(move["power"]), int(round(float(move["accuracy"]) * 100.0))
		]
		# bind() passes move_id along when the button's pressed signal fires.
		button.pressed.connect(_on_button_pressed.bind(move_id))
		add_child(button)


func _on_button_pressed(move_id: String) -> void:
	move_chosen.emit(move_id)
