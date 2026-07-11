class_name CompanionForm
extends RefCounted
## The companion's DAEMON FORM — which real animal it currently wears, and the slow,
## occasional decision to shift into a different one, in the spirit of a His Dark Materials
## daemon that changes shape. Pure decision logic: it holds the current species + coat and a
## morph timer, and answers "is it time to become something else?" It draws nothing and knows
## nothing about sprites — the view hands it a plain list of drawable forms and renders whatever
## species it names. That keeps the logic/presentation split clean and the whole thing unit-testable.
##
## `forms` is a list of { species: String, variants: int } — the animals the presentation can
## actually draw (the view filters by which sheets imported). A fresh CompanionForm picks one at
## random; update(delta) counts down a randomized interval and, when it fires, picks a NEW form
## (a different species when more than one exists) and re-arms. It never repeats the same species
## back-to-back unless that's the only option.

const DEFAULT_INTERVAL := [45.0, 120.0]  # seconds between shifts if unconfigured

var _forms: Array = []          # [{ species, variants }]
var _rng: RandomNumberGenerator
var _interval: Array = DEFAULT_INTERVAL
var _enabled := true

var _species := ""
var _variant := 0
var _timer := 0.0               # seconds until the next shift


## forms: [{ species: String, variants: int }] the view can draw. cfg: the companion config's
## "daemon_form" block ({ enabled, morph_interval:[min,max] }). rng: an injected generator so the
## sequence is deterministic under test. With no forms (no sheets available), this is inert —
## species() stays "" and the view falls back to its procedural rig.
func _init(forms: Array, cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	_rng = rng
	for f in forms:
		if f is Dictionary and String(f.get("species", "")) != "" and int(f.get("variants", 0)) > 0:
			_forms.append({ "species": String(f["species"]), "variants": int(f["variants"]) })
	_enabled = bool(cfg.get("enabled", true))
	var mi: Variant = cfg.get("morph_interval", DEFAULT_INTERVAL)
	if mi is Array and (mi as Array).size() == 2:
		_interval = [float(mi[0]), float(mi[1])]
	if not _forms.is_empty():
		_pick(-1)          # random initial form
		_arm()


## The animal the companion currently wears; "" when there are no drawable forms.
func species() -> String:
	return _species


## Which natural coat (0-based) of that species it wears.
func variant() -> int:
	return _variant


## Advance the shift timer. Returns true on the frame it morphs (the view swaps sprite + plays a
## little "poof"). A no-op — always false — when disabled or when there are fewer than two forms
## to shift between (a lone animal simply stays itself).
func update(delta: float) -> bool:
	if not _enabled or _forms.size() < 2:
		return false
	_timer -= delta
	if _timer > 0.0:
		return false
	_pick(_species_index())  # avoid repeating the current species
	_arm()
	return true


## The index of the current species in _forms, or -1 if absent (e.g. the very first pick).
func _species_index() -> int:
	for i in _forms.size():
		if String(_forms[i]["species"]) == _species:
			return i
	return -1


## Choose a form, excluding index `avoid` when there's another option, and roll a coat for it.
func _pick(avoid: int) -> void:
	var n := _forms.size()
	var idx := _rng.randi_range(0, n - 1)
	if avoid >= 0 and n > 1:
		# Draw from the other forms so the species genuinely changes.
		idx = _rng.randi_range(0, n - 2)
		if idx >= avoid:
			idx += 1
	var form: Dictionary = _forms[idx]
	_species = String(form["species"])
	_variant = _rng.randi_range(0, maxi(1, int(form["variants"])) - 1)


## Re-arm the shift timer to a random point in the configured interval.
func _arm() -> void:
	_timer = _rng.randf_range(float(_interval[0]), float(_interval[1]))
