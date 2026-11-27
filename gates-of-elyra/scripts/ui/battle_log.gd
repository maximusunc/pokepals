class_name BattleLog
extends RichTextLabel
## Turn-by-turn feedback. It converts the structured events emitted by the pure
## battle core into human-readable lines. The logic owns the facts (events); the
## log owns presentation. It never inspects creatures to compute anything.

func clear_log() -> void:
	clear()


func append_line(text: String) -> void:
	append_text(text + "\n")


## Render a batch of events. `names` maps side -> display name (the controller
## supplies the current active creatures' names); `defs` is used for move names.
func append_events(events: Array, names: Dictionary, defs: Dictionary) -> void:
	for e in events:
		var line := _format(e, names, defs)
		if line != "":
			append_line(line)


func _format(e: Dictionary, names: Dictionary, defs: Dictionary) -> String:
	match e["type"]:
		"move_used":
			return "%s used %s." % [names[e["side"]], defs["moves"][e["move_id"]]["name"]]
		"move_missed":
			return "%s's attack missed!" % names[e["side"]]
		"damage":
			var suffix := ""
			var eff := float(e["effectiveness"])
			if eff > 1.0:
				suffix = "  It's super effective!"
			elif eff < 1.0:
				suffix = "  It's not very effective..."
			return "%s took %d damage.%s" % [names[e["side"]], int(e["amount"]), suffix]
		"status_applied":
			return "%s was afflicted with %s!" % [names[e["side"]], e["status"]]
		"status_tick":
			return "%s is hurt by %s (%d)." % [names[e["side"]], e["status"], int(e["amount"])]
		"status_faded":
			return "%s recovered from %s." % [names[e["side"]], e["status"]]
		"fainted":
			return "%s fainted!" % names[e["side"]]
		"battle_over":
			return "=== %s wins! ===" % names[e["winner"]]
		_:
			return ""
