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
## static personality fallback, else a neutral 0.5. Tolerates traits that don't exist
## yet, so adding a trait to companion.json never breaks an older saved companion.
static func value(s: CompanionSelf, cfg: Dictionary, key: String) -> float:
	var fallback := 0.5
	if cfg.has("personality") and cfg["personality"].has(key):
		fallback = float(cfg["personality"][key])
	if s == null:
		return fallback
	return s.trait_value(key, fallback)


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
