class_name CompanionSelf
extends RefCounted
## The companion's persistent IDENTITY — the part of its mind that carries across
## sessions and slowly comes to reflect the player. This is pure data plus
## serialization: no file IO and no scene-tree references, so it stays portable
## (it could be saved on a server later) and is trivially testable.
##
##   traits:       0..1 personality dimensions that DRIFT over time (curiosity,
##                 energy, clinginess, ...). They bias how the companion behaves.
##   observations: running tallies of how the player actually plays. The raw
##                 material that drift reads to nudge traits.
##   mood:         a light, fast-moving feeling (-1 subdued .. 1 excited) that
##                 eases back toward 0; reflects recent moments, not character.
##   short_term:   small working memory (e.g. the last point of interest).
##
## from_dict() always starts from make_default() and layers saved values on top,
## so older save files keep loading as the schema grows.

const SCHEMA_VERSION := 1

var traits: Dictionary = {}
var observations: Dictionary = {}
var mood: float = 0.0
var short_term: Dictionary = {}


## A fresh self seeded from the companion config. Traits come from an explicit
## "traits" block if present, otherwise from the legacy "personality" block so
## existing data files keep working unchanged.
static func make_default(cfg: Dictionary) -> CompanionSelf:
	var s := CompanionSelf.new()
	s.traits = _default_traits(cfg)
	s.observations = _default_observations()
	s.mood = 0.0
	s.short_term = {}
	return s


static func _default_traits(cfg: Dictionary) -> Dictionary:
	var out := {}
	if cfg.has("traits"):
		for key in cfg["traits"]:
			var spec: Dictionary = cfg["traits"][key]
			out[key] = clampf(float(spec.get("init", 0.5)), 0.0, 1.0)
	elif cfg.has("personality"):
		for key in cfg["personality"]:
			out[key] = clampf(float(cfg["personality"][key]), 0.0, 1.0)
	return out


static func _default_observations() -> Dictionary:
	return {
		"explored_distance": 0.0,  # total distance the player has roamed
		"time_near": 0.0,          # seconds the player spent close to us
		"time_far": 0.0,           # seconds the player spent away from us
		"interactions": 0.0,       # things the player examined nearby
		"play_seconds": 0.0,       # total observed time
	}


## Read a trait, tolerating ones that don't exist yet.
func trait_value(key: String, fallback: float = 0.5) -> float:
	return float(traits.get(key, fallback))


## Plain, JSON-serializable snapshot. Dictionaries are deep-copied so callers
## can't mutate our state by holding the returned dict.
func to_dict() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"traits": traits.duplicate(true),
		"observations": observations.duplicate(true),
		"mood": mood,
		"short_term": short_term.duplicate(true),
	}


## Rebuild a self from a saved snapshot, filling any missing fields from defaults.
static func from_dict(data: Dictionary, cfg: Dictionary) -> CompanionSelf:
	var s := make_default(cfg)
	if data.get("traits") is Dictionary:
		for key in data["traits"]:
			s.traits[key] = clampf(float(data["traits"][key]), 0.0, 1.0)
	if data.get("observations") is Dictionary:
		for key in data["observations"]:
			s.observations[key] = float(data["observations"][key])
	if data.has("mood"):
		s.mood = clampf(float(data["mood"]), -1.0, 1.0)
	if data.get("short_term") is Dictionary:
		s.short_term = (data["short_term"] as Dictionary).duplicate(true)
	return s
