class_name LinkJoinPanel
extends CozySheet
## A small card holding just the "enter a code" piece (LinkJoinBox): opened from the welcome card's
## "Already have a companion? Enter a code" and from the gate when this device was signed out. The
## Devices sheet has the same piece inside it.

## Ask before leaving this device's own companion behind (false for a newcomer or a signed-out device).
var warn_met := false

var box: LinkJoinBox


func _build() -> void:
	width = 290.0
	eyebrow("Devices")
	heading("Bring your companion here")
	note("On the device you already play on, open Menu, then Devices, and tap Get a code. Type it here.")
	box = LinkJoinBox.new()
	box.warn_met = warn_met
	body.add_child(box)
	var done := CozySheet.pill("Close", close, false, 10)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(done)
	# However it's closed, a wait in progress stops with it: nothing is left asking in the background.
	closed.connect(func() -> void:
		if Net.is_redeeming():
			Net.cancel_redeem())
