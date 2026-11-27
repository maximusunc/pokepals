class_name DigPlan
extends RefCounted
## EBBMERE's buried things, as pure decisions. The flats hold a fixed set of authored DIG SPOTS; each tide
## (TideClock.cycle) a deterministic subset of them is alive and each holds something, so the same tide
## looks the same to every client with no server and no broadcast. Nothing here knows about nodes:
##   * `is_active` / `pick_outcome`  - which spots are alive this tide and what they hold (hashed, not rolled);
##   * `exposed`                      - whether the water has drawn back far enough to show a spot;
##   * `dollar_ready`                 - whether the sand-dollar's spot gives it up (lowest window, not yet found);
##   * `verb_for`                     - what the worn form does about a buried spot ("" = nothing; the cue).
## The sand-dollar's own rules are the secret's; this only says whether this dig can bring it up.


## FNV-1a over the id's bytes and the integer parts, folded to 0..1. Stable across clients and Godot versions
## (String.hash() is not promised to be), which is what "the whole world sees the same tide" needs.
static func hash01(cycle: int, id: String, salt: int = 0) -> float:
	var h := 2166136261
	for b in id.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	for part in [cycle & 0xFFFFFFFF, (cycle >> 32) & 0xFFFFFFFF, salt & 0xFFFFFFFF]:
		for shift in [0, 8, 16, 24]:
			h = ((h ^ ((int(part) >> shift) & 0xFF)) * 16777619) & 0xFFFFFFFF
	# a final avalanche so near ids/cycles do not give near values
	h ^= h >> 15
	h = (h * 2246822519) & 0xFFFFFFFF
	h ^= h >> 13
	return float(h) / 4294967296.0


## Whether the spot is alive in this tide. `always` spots (the sand-dollar's) are alive every tide.
static func is_active(cycle: int, id: String, fraction: float, always: bool = false) -> bool:
	if always:
		return true
	return hash01(cycle, id, 1) < clampf(fraction, 0.0, 1.0)


## What a spot holds this tide, from the spec's weighted `outcomes` list:
## [{ "kind": "shell", "weight": 6, "names": [...] }, { "kind": "crab", "weight": 2 }, ...]
## Returns { kind, name } ("" name when the kind lists none). An empty list gives a plain shell.
static func pick_outcome(cycle: int, id: String, outcomes: Array) -> Dictionary:
	var total := 0.0
	for o in outcomes:
		total += maxf(0.0, float((o as Dictionary).get("weight", 1.0)))
	if total <= 0.0:
		return { "kind": "shell", "name": "" }
	var r := hash01(cycle, id, 2) * total
	for o in outcomes:
		var d: Dictionary = o
		r -= maxf(0.0, float(d.get("weight", 1.0)))
		if r < 0.0:
			var names: Array = d.get("names", [])
			var pick := ""
			if not names.is_empty():
				pick = String(names[int(hash01(cycle, id, 3) * float(names.size())) % names.size()])
			return { "kind": String(d.get("kind", "shell")), "name": pick }
	return { "kind": "shell", "name": "" }


## The water has drawn back from the spot: its elevation is over the level by at least `margin`.
static func exposed(elev: float, level: float, margin: float) -> bool:
	return level < elev - margin


## Whether digging the sand-dollar's spot brings it up right now: it is THE spot, the secret is still to
## find, and it is lowest tide (client clock, with the grace the server also allows).
static func dollar_ready(is_dollar_spot: bool, found: bool, in_low_window: bool) -> bool:
	return is_dollar_spot and not found and in_low_window


## What the worn form does about a buried spot: the verb from the spec's `affordances` map (species -> verb),
## "" for a shape that cannot dig (a bird, a cat: the caller shows the cue). No form at all (the classic
## procedural rig) uses the map's "_default".
static func verb_for(species: String, affordances: Dictionary) -> String:
	if species == "":
		return String(affordances.get("_default", ""))
	return String(affordances.get(species, ""))
