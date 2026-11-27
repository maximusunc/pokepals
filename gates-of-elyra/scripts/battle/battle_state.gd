class_name BattleState
## Constructors and accessors for the battle state — the canonical shape of the
## data the pure core operates on. Everything here is plain Dictionaries/Arrays so
## the whole state serializes to JSON for free (network/save/replay) and deep-copies
## trivially. No node/UI references.
##
## State shape:
## {
##   "turn": 1,
##   "rng": { "seed": int, "state": int },          # see BattleRNG
##   "sides": {
##     "player": { "active": 0, "team": [ <creature_state>, ... ] },
##     "enemy":  { "active": 0, "team": [ <creature_state>, ... ] },
##   },
##   "phase": "choosing",                            # "choosing" | "over"
##   "winner": "",                                   # "" | "player" | "enemy"
##   "events": [ <event>, ... ],                     # produced by the last resolve_turn
## }
##
## creature_state:
## { "id","name","type","max_hp","hp","atk","def","spd","moves":[id,...],
##   "status": { "kind":"none"|"burn"|"poison", "turns":int, "dot":int },
##   "fainted": bool }

const SIDES := ["player", "enemy"]


## Build a fresh per-battle creature instance from its static definition.
static func make_creature_state(creature_id: String, creature_def: Dictionary) -> Dictionary:
	return {
		"id": creature_id,
		"name": creature_def["name"],
		"type": creature_def["type"],
		"max_hp": int(creature_def["max_hp"]),
		"hp": int(creature_def["max_hp"]),
		"atk": int(creature_def["atk"]),
		"def": int(creature_def["def"]),
		"spd": int(creature_def["spd"]),
		"moves": (creature_def["moves"] as Array).duplicate(),
		"status": { "kind": "none", "turns": 0, "dot": 0 },
		"fainted": false,
	}


## Assemble the initial battle state. Teams are lists of creature ids (Rung 1 uses
## one creature per side, but arrays keep room for teams later). defs come from
## DataLoader; seed makes the battle deterministic and replayable.
static func make_initial_state(player_team: Array, enemy_team: Array, defs: Dictionary, seed_value: int) -> Dictionary:
	return {
		"turn": 1,
		"rng": BattleRNG.make(seed_value),
		"sides": {
			"player": _make_side(player_team, defs),
			"enemy": _make_side(enemy_team, defs),
		},
		"phase": "choosing",
		"winner": "",
		"events": [],
	}


static func _make_side(team_ids: Array, defs: Dictionary) -> Dictionary:
	var creatures: Dictionary = defs["creatures"]
	var team: Array = []
	for creature_id in team_ids:
		team.append(make_creature_state(creature_id, creatures[creature_id]))
	return { "active": 0, "team": team }


## The currently-active creature_state for a side.
static func get_active(state: Dictionary, side: String) -> Dictionary:
	var side_state: Dictionary = state["sides"][side]
	return side_state["team"][side_state["active"]]


## A side is defeated when every creature on its team has fainted.
static func _side_defeated(state: Dictionary, side: String) -> bool:
	for creature in state["sides"][side]["team"]:
		if not creature["fainted"]:
			return false
	return true


static func is_over(state: Dictionary) -> bool:
	return _side_defeated(state, "player") or _side_defeated(state, "enemy")


## "" while ongoing; otherwise the winning side.
static func winner(state: Dictionary) -> String:
	if _side_defeated(state, "enemy"):
		return "player"
	if _side_defeated(state, "player"):
		return "enemy"
	return ""


## Deep copy — used by resolve_turn as a purity guard so inputs are never mutated.
static func clone(state: Dictionary) -> Dictionary:
	return state.duplicate(true)
