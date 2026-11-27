class_name CompanionTraits
## The single home for reading a personality trait and applying its influence. Before
## this, every drive carried its own private _trait()/_personality() helpers and inline
## lerp(0.8, 1.2, trait) constants — so wiring a new trait (kindness, toughness, ...)
## meant hunting through every action. Now an action declares which traits color it, in
## data, and resolves them through here.
##
## Traits themselves live in CompanionSelf (they DRIFT over time toward how the player
## plays); the static "personality" block in companion.json is the legacy fallback for a
## self that predates a given trait. This registry just centralizes the read + the
## "scale a value by a trait" influence that used to be copy-pasted.


## The live value of a trait in 0..1: the drifting self value if present, else the
## static personality fallback, else a neutral 0.5, PLUS the transient mood overlay.
## Tolerates traits that don't exist yet, so adding a trait to companion.json never
## breaks an older saved companion.
##
## Mood is a fast affective OVERLAY on the slower trait: arousal rides on energy and
## valence on warmth (clinginess), so an excited companion reads as more energetic and a
## warm-feeling one as more affectionate — for THIS moment, without changing who it is.
## Because every action reads its traits through here, that one addition makes mood bias
## the whole decision (Wander pauses, Follow keenness, Idle hops, ...), not just the look.
## curiosity has no mood axis. Scale/mapping are data-driven in cfg["mood"].
static func value(s: CompanionSelf, cfg: Dictionary, key: String) -> float:
	var fallback := 0.5
	if cfg.has("personality") and cfg["personality"].has(key):
		fallback = float(cfg["personality"][key])
	if s == null:
		return fallback
	var base := s.trait_value(key, fallback)
	return clampf(base + _mood_overlay(s, cfg, key), 0.0, 1.0)


## The mood contribution to a trait this frame: arousal -> energy, valence -> clinginess,
## each scaled by overlay_scale. Zero for any trait without a mood axis (e.g. curiosity),
## or when there's no "mood" config. The axis->trait mapping is data-driven so renaming a
## trait doesn't strand the overlay.
static func _mood_overlay(s: CompanionSelf, cfg: Dictionary, key: String) -> float:
	var m: Dictionary = cfg.get("mood", {})
	if m.is_empty():
		return 0.0
	var scale := float(m.get("overlay_scale", 0.0))
	var axis_map: Dictionary = m.get("axis_map", { "arousal": "energy", "valence": "clinginess" })
	if key == String(axis_map.get("arousal", "energy")):
		return s.mood_arousal * scale
	if key == String(axis_map.get("valence", "clinginess")):
		return s.mood_valence * scale
	return 0.0


## The effective (mood-overlaid) values of the named traits, for the debug overlay so a
## playtester can see how the current mood is bending behavior. Read-only.
static func effective_snapshot(s: CompanionSelf, cfg: Dictionary, keys: Array) -> Dictionary:
	var out := {}
	for key in keys:
		out[key] = value(s, cfg, String(key))
	return out


## Apply a declared trait modifier to a base value:
##   { "trait": "clinginess", "lo": 0.8, "hi": 1.2 }  ->  base * lerp(lo, hi, trait)
## A clingier companion (trait near 1) scales toward `hi`; an aloof one toward `lo`.
static func apply_mult(base: float, mod: Dictionary, s: CompanionSelf, cfg: Dictionary) -> float:
	var t := value(s, cfg, String(mod.get("trait", "")))
	return base * lerpf(float(mod.get("lo", 1.0)), float(mod.get("hi", 1.0)), t)


## Apply a list of trait modifiers in turn.
static func apply_mults(base: float, mods: Array, s: CompanionSelf, cfg: Dictionary) -> float:
	var out := base
	for mod in mods:
		out = apply_mult(out, mod, s, cfg)
	return out
