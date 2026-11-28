class_name LinkJoinBox
extends VBoxContainer
## The "enter a code" piece: bringing your companion onto THIS device from another one (issue 175).
## A code field and a Join button; then "Waiting for your other device to let you in…" with a Cancel,
## until the other device answers. Used in three places: the Devices sheet, the welcome card's "Already
## have a companion?" and the gate when this device was signed out (both through LinkJoinPanel).
##
## If this device already has a companion of its own (`warn_met`), Join first asks plainly whether to
## leave it behind. Net does the asking and the waiting (start_redeem); this only shows how it goes.
## Once linked, Net says identity_changed and the gate rebuilds the world as that player.

## Show the leave-it-behind question before starting (this device's companion is met).
var warn_met := false

var _field: LineEdit
var _join: Button
var _status: Label
var _cancel: Button
var _confirm: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 5)
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 5)
	_field = CozySheet.field("Enter a code")
	_field.max_length = 12   # room for a dash or a space or two
	_field.add_theme_color_override("font_uneditable_color", UiStyle.MUTED)   # still readable while it waits
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.text_changed.connect(_on_typed)
	_field.text_submitted.connect(func(_t: String) -> void: _on_join())
	entry.add_child(_field)
	_join = CozySheet.pill("Join", _on_join, true)
	_join.disabled = true
	entry.add_child(_join)
	add_child(entry)

	_confirm = VBoxContainer.new()
	_confirm.add_theme_constant_override("separation", 5)
	_confirm.visible = false
	var warn := UiStyle.label("This device's own companion will be left behind, and you'll play here as the one from your other device. Go ahead?", 9, UiStyle.INK_STRONG, 600)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm.add_child(warn)
	var answers := HBoxContainer.new()
	answers.add_theme_constant_override("separation", 5)
	answers.add_child(CozySheet.pill("Bring it here", _start, true))
	answers.add_child(CozySheet.pill("Keep this one", func() -> void: _confirm.visible = false))
	_confirm.add_child(answers)
	add_child(_confirm)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 5)
	_status = UiStyle.label("", 9, UiStyle.MUTED, 500)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_status)
	_cancel = CozySheet.pill("Cancel", Net.cancel_redeem)
	_cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_cancel)
	add_child(foot)

	Net.redeem_changed.connect(_on_redeem)
	_show(Net.redeem_state() if Net.is_redeeming() else "")


## Put a code in the field (as if typed).
func set_code(text: String) -> void:
	_field.text = text
	_on_typed(text)


## Upper-case as they type (codes are shown that way), and only offer Join for a whole code.
func _on_typed(text: String) -> void:
	var up := text.to_upper()
	if up != text:
		var caret := _field.caret_column
		_field.text = up
		_field.caret_column = caret
	_join.disabled = not DeviceLink.is_complete(up) or Net.is_redeeming()


func _on_join() -> void:
	if not DeviceLink.is_complete(_field.text) or Net.is_redeeming():
		return
	if warn_met:
		_confirm.visible = true
		return
	_start()


func _start() -> void:
	_confirm.visible = false
	Net.start_redeem(_field.text.strip_edges())


func _on_redeem(state: String) -> void:
	if is_inside_tree():
		_show(state)


func _show(state: String) -> void:
	var waiting := state == "waiting"
	_status.text = LinkRedeem.message(LinkRedeem.WAITING if waiting else state)
	_status.add_theme_color_override("font_color", UiStyle.INK_STRONG if waiting or state == LinkRedeem.LINKED else UiStyle.MUTED)
	_cancel.visible = waiting
	_field.editable = not waiting and state != LinkRedeem.LINKED
	_join.disabled = waiting or state == LinkRedeem.LINKED or not DeviceLink.is_complete(_field.text)
	_status.visible = _status.text != ""
