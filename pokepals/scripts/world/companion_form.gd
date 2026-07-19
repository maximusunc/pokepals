class_name CompanionForm
extends RefCounted
## The companion's DAEMON FORM — which real animal it currently wears, and TWO ways that changes:
## the slow, occasional AUTONOMOUS drift (in the spirit of a His Dark Materials daemon that shifts
## shape on its own), and a DIRECTED override the player invokes. Pure decision logic: it holds the
## current species + coat, a drift timer, and a directed-hold timer, and answers "what am I wearing
## now?" It draws nothing and knows nothing about sprites — the view hands it a plain list of drawable
## forms and renders whatever species it names. That keeps the logic/presentation split clean and the
## whole thing unit-testable.
##
## `forms` is a list of { species: String, variants: int } — the animals the presentation can
## actually draw (the view filters by which sheets imported). A fresh CompanionForm picks one at
## random; update(delta, bond, identity) counts down a randomized interval and, when it fires, picks a
## NEW form and re-arms. It never repeats the same species back-to-back unless that's the only option.
##
## THE DIRECTED LAYER (F-1). instruct(species, bond) switches immediately and HOLDS that form for a
## bond-scaled duration (low bond = short hold, "doesn't listen well"; high bond = long hold). It
## ALWAYS obeys — low bond just means brief. When the hold lapses it RELEASES back to the autonomous
## drift. And as bond grows the drift BIASES toward a SIGNATURE form derived from temperament: the
## drawable species whose authored profile (curiosity/energy/clinginess) is nearest the companion's
## grown identity. So a bonded companion, left alone, keeps returning to a self that reflects it —
## yet the player can still instruct any form. All of it is data-tuned in companion.json "daemon_form".

const DEFAULT_INTERVAL := [45.0, 120.0]  # seconds between autonomous shifts if unconfigured

var _forms: Array = []          # [{ species, variants }]
var _rng: RandomNumberGenerator
var _interval: Array = DEFAULT_INTERVAL
var _enabled := true

# Directed layer + drift-bias tunables (all default to a silent no-op so an old config — and every
# existing seeded test — behaves exactly as before).
var _profiles: Dictionary = {}  # species -> { curiosity, energy, clinginess } authored temperament
var _hold := [0.0, 0.0]         # [hold_low, hold_high] seconds an instructed form is held, by bond
var _bias := [0.0, 0.0]         # [preferred_bias_low, preferred_bias_high] drift bias, by bond

var _species := ""
var _variant := 0
var _timer := 0.0               # seconds until the next autonomous shift
var _directed := ""             # the instructed species being held ("" = free to drift)
var _hold_timer := 0.0          # seconds left on the directed hold


## forms: [{ species: String, variants: int }] the view can draw. cfg: the companion config's
## "daemon_form" block. rng: an injected generator so the sequence is deterministic under test. With
## no forms (no sheets available), this is inert — species() stays "" and the view falls back to its
## procedural rig.
func _init(forms: Array, cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	_rng = rng
	for f in forms:
		if f is Dictionary and String(f.get("species", "")) != "" and int(f.get("variants", 0)) > 0:
			_forms.append({ "species": String(f["species"]), "variants": int(f["variants"]) })
	_enabled = bool(cfg.get("enabled", true))
	var mi: Variant = cfg.get("morph_interval", DEFAULT_INTERVAL)
	if mi is Array and (mi as Array).size() == 2:
		_interval = [float(mi[0]), float(mi[1])]
	var profiles: Variant = cfg.get("species_profiles", {})
	if profiles is Dictionary:
		_profiles = profiles
	_hold = [float(cfg.get("hold_low", 0.0)), float(cfg.get("hold_high", 0.0))]
	_bias = [float(cfg.get("preferred_bias_low", 0.0)), float(cfg.get("preferred_bias_high", 0.0))]
	if not _forms.is_empty():
		_pick(-1)          # random initial form
		_arm()


## The animal the companion currently wears; "" when there are no drawable forms.
func species() -> String:
	return _species


## Which natural coat (0-based) of that species it wears.
func variant() -> int:
	return _variant


## Whether a player-instructed form is currently being held (for the view / debug overlay / tests).
func is_holding() -> bool:
	return _hold_timer > 0.0


## The species currently held by a player instruction, or "" when free to drift.
func directed_species() -> String:
	return _directed


## The SIGNATURE species — the drawable species whose authored temperament profile is nearest
## (Euclidean over curiosity/energy/clinginess) to the companion's identity traits. "" when no
## profiles are configured or none of the drawable forms has one. Ties break by _forms order (the
## first listed wins). Pure and deterministic — draws no RNG.
func preferred_species(identity: Dictionary) -> String:
	var best := ""
	var best_dist := INF
	for form in _forms:
		var sp := String(form["species"])
		if not _profiles.has(sp):
			continue
		var prof: Dictionary = _profiles[sp]
		var dist := 0.0
		for key in prof:
			var d := float(identity.get(key, 0.5)) - float(prof[key])
			dist += d * d
		if dist < best_dist:
			best_dist = dist
			best = sp
	return best


## Player instructs a specific form: switch to it immediately and HOLD it. The hold length scales
## with bond via lerp(hold_low, hold_high, bond) — the same bond→willingness shape as
## ComeAction._come_chance. It ALWAYS obeys; a low bond just makes the hold short. Returns false
## (a no-op) if the species isn't one of the drawable forms.
func instruct(species: String, bond: float) -> bool:
	if not _has_species(species):
		return false
	_wear_species(species)
	_directed = species
	_hold_timer = maxf(0.0, lerpf(float(_hold[0]), float(_hold[1]), clampf(bond, 0.0, 1.0)))
	return true


## Advance the form. Returns true on the frame the WORN species/coat changes (the view swaps sprite +
## plays a little "poof"). A directed hold takes precedence over the drift: while held it just counts
## down (the worn form persists); when the hold lapses it releases back to the drift and re-arms.
## bond + identity steer the drift's bias toward the signature form; both default so the old
## update(delta) call-sites and every seeded test stay byte-identical.
func update(delta: float, bond: float = 0.0, identity: Dictionary = {}) -> bool:
	if _hold_timer > 0.0:
		_hold_timer -= delta
		if _hold_timer > 0.0:
			return false      # still holding the instructed form
		_directed = ""        # hold lapsed: release back to autonomous drift...
		_arm()                # ...and count a fresh drift interval from here
		return false          # the worn form persists until the next drift morph
	if not _enabled or _forms.size() < 2:
		return false
	_timer -= delta
	if _timer > 0.0:
		return false
	return _drift_pick(bond, identity)


## The index of the current species in _forms, or -1 if absent (e.g. the very first pick).
func _species_index() -> int:
	for i in _forms.size():
		if String(_forms[i]["species"]) == _species:
			return i
	return -1


## Autonomous drift with a bond-scaled pull toward the signature form. When a preferred species
## exists and isn't the one already worn, take it with probability lerp(bias_low, bias_high, bond);
## otherwise fall through to the normal uniform pick. The bias randf() is drawn ONLY when a preferred
## species exists, so with no species_profiles configured the RNG stream is exactly as it was before
## this feature (guaranteeing the original seeded tests are unaffected). Re-arms the drift timer and
## returns whether the worn species actually changed.
func _drift_pick(bond: float, identity: Dictionary) -> bool:
	var before := _species
	var pref := preferred_species(identity)
	var took_pref := false
	if pref != "" and pref != _species:
		var p := clampf(lerpf(float(_bias[0]), float(_bias[1]), clampf(bond, 0.0, 1.0)), 0.0, 1.0)
		if _rng.randf() < p:
			_wear_species(pref)
			took_pref = true
	if not took_pref:
		_pick(_species_index())  # avoid repeating the current species
	_arm()
	return _species != before


## Choose a form uniformly, excluding index `avoid` when there's another option, and roll a coat.
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


## Wear a specific species: set it and roll a fresh coat. Keeps the current coat if it's already this
## species (no coat flicker on a re-instruct or a same-species drift). Shared by instruct + drift-bias.
func _wear_species(species: String) -> void:
	if species == _species:
		return
	var form := _form_for(species)
	if form == null:
		return
	_species = species
	_variant = _rng.randi_range(0, maxi(1, int(form["variants"])) - 1)


## True if `species` is one of the drawable forms.
func _has_species(species: String) -> bool:
	return _form_for(species) != null


## The _forms entry for `species`, or null if it isn't drawable.
func _form_for(species: String) -> Variant:
	for form in _forms:
		if String(form["species"]) == species:
			return form
	return null


## Re-arm the shift timer to a random point in the configured interval.
func _arm() -> void:
	_timer = _rng.randf_range(float(_interval[0]), float(_interval[1]))
