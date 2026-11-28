class_name BattleLogic
## THE pure battle core. resolve_turn takes the current state plus both sides'
## chosen actions and returns a NEW state — deterministic, side-effect-free, with
## zero UI/node/scene-tree references. Randomness comes only from the seeded RNG
## carried inside the state, so the same inputs always produce the same outputs.
## This is the module that later moves onto an authoritative server unchanged, so
## keep it free of engine dependencies.
##
## action shape: { "side": "player"|"enemy", "kind": "move", "move_id": <id> }
## actions arg:  { "player": <action>, "enemy": <action> }
## defs arg:     { "types": {...}, "moves": {...}, "creatures": {...} }  (from DataLoader)

const _VARIANCE_MIN := 0.85   # damage roll lower bound (inclusive)
const _VARIANCE_SPAN := 0.15  # roll spans [_VARIANCE_MIN, _VARIANCE_MIN + _VARIANCE_SPAN)
const _DEF_SOFTENER := 5      # added to defence so low-def creatures aren't one-shot


## Resolve one full turn: both sides act in speed order, then status effects tick.
## Returns a brand-new state; the input is never mutated.
static func resolve_turn(state: Dictionary, actions: Dictionary, defs: Dictionary) -> Dictionary:
	var s: Dictionary = BattleState.clone(state)
	s["events"] = []
	var rng: Dictionary = s["rng"]

	var ordering: Dictionary = _order_by_speed(s, rng)
	rng = ordering["rng"]

	for side in ordering["order"]:
		if BattleState.is_over(s):
			break
		var attacker: Dictionary = BattleState.get_active(s, side)
		if attacker["fainted"]:
			continue
		var res: Dictionary = _apply_move(s, side, _other(side), actions[side], defs, rng)
		rng = res["rng"]
		for e in res["events"]:
			s["events"].append(e)

	if not BattleState.is_over(s):
		var tick: Dictionary = _apply_status_ticks(s, rng)
		rng = tick["rng"]
		for e in tick["events"]:
			s["events"].append(e)

	s["rng"] = rng
	s["turn"] = int(s["turn"]) + 1

	if BattleState.is_over(s):
		s["phase"] = "over"
		s["winner"] = BattleState.winner(s)
		s["events"].append({ "type": "battle_over", "winner": s["winner"] })

	return s


static func _other(side: String) -> String:
	return "enemy" if side == "player" else "player"


## Decide who acts first this turn. Higher speed goes first; ties are broken by a
## seeded coin flip so the outcome stays deterministic and reproducible.
static func _order_by_speed(state: Dictionary, rng: Dictionary) -> Dictionary:
	var p_spd: int = int(BattleState.get_active(state, "player")["spd"])
	var e_spd: int = int(BattleState.get_active(state, "enemy")["spd"])
	if p_spd > e_spd:
		return { "order": ["player", "enemy"], "rng": rng }
	if e_spd > p_spd:
		return { "order": ["enemy", "player"], "rng": rng }
	var flip: Dictionary = BattleRNG.chance(rng, 0.5)
	var order: Array = ["player", "enemy"] if flip["value"] else ["enemy", "player"]
	return { "order": order, "rng": flip["rng"] }


## Apply one creature's move against the opposing active creature, mutating the
## (already-cloned) working state. Returns { "events": Array, "rng": new_rng }.
static func _apply_move(state: Dictionary, attacker_side: String, defender_side: String, action: Dictionary, defs: Dictionary, rng: Dictionary) -> Dictionary:
	var events: Array = []
	var attacker: Dictionary = BattleState.get_active(state, attacker_side)
	var defender: Dictionary = BattleState.get_active(state, defender_side)
	var move: Dictionary = defs["moves"][action["move_id"]]

	events.append({ "type": "move_used", "side": attacker_side, "move_id": action["move_id"], "target": defender_side })

	# Accuracy check.
	var hit: Dictionary = BattleRNG.chance(rng, float(move["accuracy"]))
	rng = hit["rng"]
	if not hit["value"]:
		events.append({ "type": "move_missed", "side": attacker_side, "move_id": action["move_id"] })
		return { "events": events, "rng": rng }

	# Type effectiveness + damage.
	var mult: float = TypeChart.effectiveness(move["type"], defender["type"], defs["types"]["chart"])
	var dmg_res: Dictionary = _calc_damage(attacker, defender, move, mult, rng)
	rng = dmg_res["rng"]
	var dmg: int = dmg_res["amount"]
	defender["hp"] = max(0, int(defender["hp"]) - dmg)
	events.append({ "type": "damage", "side": defender_side, "amount": dmg, "effectiveness": mult })

	# Faint check — a fainted target takes no status.
	if int(defender["hp"]) <= 0 and not defender["fainted"]:
		defender["fainted"] = true
		events.append({ "type": "fainted", "side": defender_side })
		return { "events": events, "rng": rng }

	# Optional status application.
	if move.has("status"):
		var st: Dictionary = move["status"]
		var roll: Dictionary = BattleRNG.chance(rng, float(st["chance"]))
		rng = roll["rng"]
		if roll["value"] and defender["status"]["kind"] == "none":
			defender["status"] = { "kind": st["kind"], "turns": int(st["turns"]), "dot": int(st["dot"]) }
			events.append({ "type": "status_applied", "side": defender_side, "status": st["kind"] })

	return { "events": events, "rng": rng }


## Damage = power * (atk / (def + softener)) * type_mult * variance, floored, min 1.
static func _calc_damage(attacker: Dictionary, defender: Dictionary, move: Dictionary, mult: float, rng: Dictionary) -> Dictionary:
	var ratio: float = float(attacker["atk"]) / float(int(defender["def"]) + _DEF_SOFTENER)
	var base: float = float(move["power"]) * ratio
	var roll: Dictionary = BattleRNG.next_float(rng)
	rng = roll["rng"]
	var variance: float = _VARIANCE_MIN + _VARIANCE_SPAN * float(roll["value"])
	var amount: int = max(1, int(floor(base * mult * variance)))
	return { "amount": amount, "rng": rng }


## End-of-turn damage-over-time for each living active creature with a status.
static func _apply_status_ticks(state: Dictionary, rng: Dictionary) -> Dictionary:
	var events: Array = []
	for side in BattleState.SIDES:
		var c: Dictionary = BattleState.get_active(state, side)
		if c["fainted"]:
			continue
		var status: Dictionary = c["status"]
		if status["kind"] == "none" or int(status["turns"]) <= 0:
			continue
		var dot: int = int(status["dot"])
		c["hp"] = max(0, int(c["hp"]) - dot)
		events.append({ "type": "status_tick", "side": side, "status": status["kind"], "amount": dot })
		status["turns"] = int(status["turns"]) - 1
		if int(status["turns"]) <= 0:
			events.append({ "type": "status_faded", "side": side, "status": status["kind"] })
			c["status"] = { "kind": "none", "turns": 0, "dot": 0 }
		if int(c["hp"]) <= 0 and not c["fainted"]:
			c["fainted"] = true
			events.append({ "type": "fainted", "side": side })
	return { "events": events, "rng": rng }
