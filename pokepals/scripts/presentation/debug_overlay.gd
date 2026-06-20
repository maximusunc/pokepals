class_name DebugOverlay
extends CanvasLayer
## A dev-only on-screen readout of the companion's inner life, so a playtester can
## correlate what they SEE (it's trailing me / wandering off / came to say hi) with
## what the companion is actually thinking (bond, traits, which drive is winning and
## by how much). Pure presentation: it only READS state the logic exposes via
## debug_state() and renders it — it never decides or mutates anything.
##
## On by default (this is a dev build). Toggle by tapping the on-screen DBG button
## (wired by the world controller) or pressing F3 on desktop.

@onready var _label: Label = $Readout

var _companion: CompanionView
var _player: PlayerView


## Handed its subjects by the world controller after the scene is wired.
func setup(companion: CompanionView, player: PlayerView) -> void:
	_companion = companion
	_player = player


func toggle() -> void:
	visible = not visible


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		toggle()


func _process(_delta: float) -> void:
	if not visible or _companion == null:
		return
	var d := _companion.debug_state()
	if d.is_empty():
		_label.text = "companion: waking up..."
		return
	_label.text = _format(d)


func _format(d: Dictionary) -> String:
	var lines: Array = []

	var bond := float(d.get("bond", 0.0))
	lines.append("BOND %4.2f %s" % [bond, _bar(bond)])
	lines.append("behavior: %s" % str(d.get("behavior", "?")))
	lines.append("dist %d   comfort %d   speed %d" % [
		int(round(float(d.get("dist_to_player", 0.0)))),
		int(round(float(d.get("follow_near", 0.0)))),
		int(round(float(d.get("speed", 0.0)))),
	])

	var t: Dictionary = d.get("traits", {})
	lines.append("dispos  cur %.2f  ene %.2f  cli %.2f" % [
		float(t.get("curiosity", 0.0)),
		float(t.get("energy", 0.0)),
		float(t.get("clinginess", 0.0)),
	])
	# The slow identity anchor beneath the live disposition — watch it learn toward how you
	# play and then lock as the bond deepens.
	var idn: Dictionary = d.get("identity", {})
	if not idn.is_empty():
		lines.append("identy  cur %.2f  ene %.2f  cli %.2f" % [
			float(idn.get("curiosity", 0.0)),
			float(idn.get("energy", 0.0)),
			float(idn.get("clinginess", 0.0)),
		])
	# The resting LOOK those slow traits + bond are bending into — the presentation mirror of the
	# evolution (ear perk/relax, idle liveliness, gaze lift, coat warmth, and the size it's grown to).
	var lk: Dictionary = d.get("look", {})
	if not lk.is_empty():
		lines.append("look    ear %+.2f  bnc %+.2f  tail %.2f  eye %.2f  size %.2f  coat %.2f" % [
			float(lk.get("ear", 0.0)),
			float(lk.get("bounce", 0.0)),
			float(lk.get("wag", 0.0)),
			float(lk.get("eye", 0.0)),
			float(lk.get("scale", 1.0)),
			float(lk.get("coat", 0.0)),
		])

	# Mood (2D): the fast feeling overlaying the traits. Signed bars (centered at the
	# resting point's sign), with the trait values mood is actually bending shown beneath.
	var val := float(d.get("mood_valence", 0.0))
	var aro := float(d.get("mood_arousal", 0.0))
	lines.append("mood  val %+.2f %s  aro %+.2f %s" % [
		val, _signed_bar(val), aro, _signed_bar(aro),
	])
	var eff: Dictionary = d.get("effective", {})
	if not eff.is_empty():
		lines.append("  -> eff ene %.2f (raw %.2f)   eff cli %.2f (raw %.2f)" % [
			float(eff.get("energy", 0.0)), float(t.get("energy", 0.0)),
			float(eff.get("clinginess", 0.0)), float(t.get("clinginess", 0.0)),
		])

	# Each drive's bid this frame, strongest-first, winner starred — the "why".
	var scores: Dictionary = d.get("scores", {})
	var winner := str(d.get("winner", ""))
	var order := ["investigate", "checkin", "follow", "wander", "idle"]
	var parts: Array = []
	for id in order:
		if scores.has(id):
			var mark := "*" if id == winner else ""
			parts.append("%s %.1f%s" % [_label_for(id), float(scores[id]), mark])
	lines.append("drives  " + "  ".join(parts))

	# Social referencing: when the player seems focused on something, show how strong that
	# read is — the cue that drives the companion's glances and (once bonded) its approach.
	if bool(d.get("has_attended", false)):
		var att := float(d.get("attention_strength", 0.0))
		lines.append("attending to you  %4.2f %s" % [att, _bar(att)])

	var s: Dictionary = d.get("signals", {})
	lines.append("you  explore %.2f  together %.2f  engage %.2f" % [
		float(s.get("explore", 0.0)),
		float(s.get("together", 0.0)),
		float(s.get("engage", 0.0)),
	])
	lines.append("play %s   interactions %d" % [
		_clock(float(d.get("play_seconds", 0.0))),
		int(d.get("interactions", 0)),
	])
	var area := str(d.get("current_area", ""))
	if area != "":
		lines.append("area %s   places known %d" % [area, int(d.get("areas_found", 0))])
	# How much it liked the last thing you showed it (appraisal); -1 until it examines one.
	var appeal := float(d.get("last_appeal", -1.0))
	if appeal >= 0.0:
		lines.append("last appeal %4.2f %s" % [appeal, _bar(appeal)])

	return "\n".join(lines)


func _bar(value: float, cells: int = 10) -> String:
	var filled := int(round(clampf(value, 0.0, 1.0) * cells))
	return "[" + "#".repeat(filled) + "-".repeat(cells - filled) + "]"


# A bar for a -1..1 value with the zero point in the middle: fills left of center for
# negatives, right for positives, so you can read the sign and size of a mood at a glance.
func _signed_bar(value: float, half: int = 6) -> String:
	var v := clampf(value, -1.0, 1.0)
	var mag := int(round(absf(v) * half))
	if v >= 0.0:
		return "[" + "-".repeat(half) + "|" + "#".repeat(mag) + "-".repeat(half - mag) + "]"
	return "[" + "-".repeat(half - mag) + "#".repeat(mag) + "|" + "-".repeat(half) + "]"


func _clock(seconds: float) -> String:
	var total := int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]


func _label_for(id: String) -> String:
	match id:
		"investigate":
			return "invstg"
		"checkin":
			return "checkin"
		_:
			return id
