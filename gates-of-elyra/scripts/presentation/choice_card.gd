class_name ChoiceCard
extends CozySheet
## A small card with a title, a line of text and a few choices: the card you get when you tap
## another player (Befriend, Invite home, Send home, Block), and the question when someone invites you
## home (Go / Not now). Emits `chosen(id)` and closes; closing any other way emits `chosen("")`.

signal chosen(id: String)

var title := ""
var text := ""
## [{ id, label, gold?: bool, disabled?: bool }]
var choices: Array = []
var _answered := false


func _build() -> void:
	width = 280.0
	closed.connect(func() -> void:
		if not _answered:
			chosen.emit(""))
	heading(title)
	if text != "":
		var t := note(text)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 5)
	body.add_child(buttons)
	for c in choices:
		var id := String(c["id"])
		var b := CozySheet.pill(String(c["label"]), _choose.bind(id), bool(c.get("gold", false)), 10)
		b.disabled = bool(c.get("disabled", false))
		buttons.add_child(b)


func _choose(id: String) -> void:
	_answered = true
	chosen.emit(id)
	close()
