class_name CreaturePanel
extends VBoxContainer
## Displays one creature: name, a placeholder colored-shape "sprite", an HP bar,
## an HP readout, and any status condition. It is pure presentation — render()
## only READS a creature_state dictionary and updates widgets. It never computes
## anything about the battle.

## Placeholder art: a flat color per type. Swap for real sprites later.
const TYPE_COLORS := {
	"ember": Color(0.90, 0.32, 0.22),
	"flora": Color(0.30, 0.74, 0.36),
	"aqua": Color(0.26, 0.56, 0.90),
	"spark": Color(0.95, 0.80, 0.26),
}

@onready var _name_label: Label = $NameLabel
@onready var _sprite: ColorRect = $Sprite
@onready var _hp_bar: ProgressBar = $HPBar
@onready var _hp_label: Label = $HPLabel
@onready var _status_label: Label = $StatusLabel


func render(creature: Dictionary) -> void:
	_name_label.text = "%s  [%s]" % [creature["name"], creature["type"]]
	_hp_bar.max_value = float(creature["max_hp"])
	_hp_bar.value = float(creature["hp"])
	_hp_label.text = "HP %d / %d" % [int(creature["hp"]), int(creature["max_hp"])]

	_sprite.color = TYPE_COLORS.get(creature["type"], Color(0.5, 0.5, 0.5))
	# Dim the shape when the creature has fainted.
	_sprite.modulate = Color(0.3, 0.3, 0.3) if creature["fainted"] else Color.WHITE

	var status: Dictionary = creature["status"]
	_status_label.text = "" if status["kind"] == "none" else status["kind"].to_upper()
