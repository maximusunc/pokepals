class_name EncounterPal
extends Node2D
## A WILD creature of the FIRST-MEETING flock (see EncounterDirector): one of the shifting animals
## milling around a brand-new player, one of which secretly IS their companion. Unlike PalView
## (a puppet eased toward server transforms) this body drives itself: WildWander (pure logic)
## decides where it's headed, this node walks there and resolves walls, a CompanionForm re-rolls
## the animal it wears every shift interval (~15 s — the whole flock shimmers between species,
## so the companion can't be told apart by its shape), and PalSprite draws whatever it currently
## is. Local-only presentation: the flock is a personal beat, never sent over the wire.
##
## Beyond milling about it knows three moves the director drives:
##   examine_rebuff(from) — looked over and unimpressed: hurries off and refuses re-examines
##                          for a cooldown.
##   begin_bond(player)   — THE ONE: freezes, runs the little bonding ceremony (notice → excited
##                          hops to your feet → an ecstatic flicker through every shape it knows →
##                          settles, hearts), then emits bond_finished(species, variant).
##   depart(from)         — the meeting is over and it wasn't the one: drifts off and fades away.

## The ceremony just finished: the animal it settled as (the form the companion wakes up wearing).
signal bond_finished(species: String, variant: int)

# The bonding ceremony's beat timings (seconds from begin_bond).
const BOND_NOTICE_END := 0.7    # goes still, meets your eye, "!"
const BOND_HOP_END := 1.7       # bounds excitedly to your feet
const BOND_FLICKER_END := 2.9   # flickers through its shapes, too delighted to hold one
const BOND_DONE := 3.7          # settles, hearts — then bond_finished
const BOND_FLICKER_STEP := 0.14 # seconds per flicker
const BOND_APPROACH_STOP := 46.0
const BOND_HOP_SPEED := 95.0

var anchor := Vector2.ZERO      # centre of the roam disc (the director aims the true one at YOU)
var wander_radius := 140.0

var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _form: CompanionForm
var _wander: WildWander
var _species := ""
var _variant := 0
var _tex: Texture2D
var _sheet: Dictionary = {}

var _time := 0.0
var _speed := 0.0
var _facing := Vector2.DOWN
var _squash := 0.0              # one-shot pop, decays; rides PalSprite's squash param
var _cooldown := 0.0            # seconds until it can be examined again after a rebuff
var _bonding := false
var _departing := false
var _anim_t := 0.0
var _flick_accum := 0.0
var _fired: Dictionary = {}     # one-shot latches for the ceremony's beats
var _player: Node2D = null      # only during the ceremony, to face/approach you
var _emotes: Array = []         # floating glyphs: [{ kind, age, life }]

var _solids: Array = []
var _bounds := Rect2()
var _body_radius := 6.0
var _margin := 2.0
var _collide := false


## forms: the drawable species pool (PalView.available_forms()). cfg: the "encounter" block from
## companion.json — shift_interval [lo,hi] drives the ~15 s shimmer; the wander speeds/pauses feed
## WildWander. Rolls its own starting animal.
func setup(forms: Array, cfg: Dictionary) -> void:
	_cfg = cfg
	_rng.randomize()
	_form = CompanionForm.new(forms, {
		"enabled": true,
		"morph_interval": cfg.get("shift_interval", [12.0, 18.0]),
	}, _rng)
	_wander = WildWander.new(cfg, _rng)
	wander_radius = float(cfg.get("wander_radius", 140.0))
	_apply_form(_form.species(), _form.variant())


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## The world's barriers, so a wild creature slides around trees/ponds like everyone else.
func set_solids(solids: Array, bounds: Rect2, body_radius: float, margin: float) -> void:
	_solids = solids
	_bounds = bounds
	_body_radius = body_radius
	_margin = margin
	_collide = true


## The animal it currently looks like ("cat", "fox", …) — for the director's hint lines.
func species_name() -> String:
	return _species


func worn_variant() -> int:
	return _variant


## Whether an Examine should land on it right now: not mid-ceremony, not fading out, not already
## hurrying off, and past the rebuff cooldown (so a walked-away creature can't be chain-poked).
func can_examine() -> bool:
	return not _bonding and not _departing and _cooldown <= 0.0 and not _wander.is_leaving()


## Looked over and found the player… fine, but not THEIRS: a polite beat, then it walks away
## (the director shows the matching "no spark" line).
func examine_rebuff(from: Vector2) -> void:
	_cooldown = float(_cfg.get("examine_cooldown", 5.0))
	_squash = 0.2  # a small acknowledging pop — it did notice you
	_wander.walk_away(position, from)


## THE ONE: start the bonding ceremony. The body freezes out of the flock's life and the little
## performance runs in _process; bond_finished fires when it settles.
func begin_bond(player: Node2D) -> void:
	if _bonding:
		return
	_bonding = true
	_player = player
	_anim_t = 0.0
	_wander.freeze()


## Not the one, and the meeting is over: drift off away from the player and fade out, then free.
func depart(from: Vector2) -> void:
	if _departing:
		return
	_departing = true
	_wander.walk_away(position, from)
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(self, "modulate:a", 0.0, 1.4)
	tw.tween_callback(queue_free)


func _process(delta: float) -> void:
	_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_squash = maxf(0.0, _squash - delta * 2.2)
	if _bonding:
		_run_bond(delta)
	else:
		_live(delta)
	_age_emotes(delta)
	queue_redraw()


## The flock's ordinary life: mill about per WildWander, and shimmer into a new animal when the
## shift timer fires (a little pop sells the change — same beat the companion's daemon drift plays).
func _live(delta: float) -> void:
	var d := _wander.update(delta, position, anchor, wander_radius)
	var speed := float(d["speed"])
	if speed > 0.0:
		var to_target: Vector2 = (d["target"] as Vector2) - position
		if to_target.length() > 0.5:
			_facing = _facing.lerp(to_target.normalized(), 0.35).normalized()
			_step(to_target.normalized() * speed * delta, delta)
	else:
		_speed = 0.0
	if _form.update(delta):
		_apply_form(_form.species(), _form.variant())
		_squash = 0.3
		_spawn_emote("delight")


## Move by `motion`, resolve the world's barriers, and derive the drawn speed from what actually
## happened (so walking into a trunk reads as stopped, not as running on the spot).
func _step(motion: Vector2, delta: float) -> void:
	var before := position
	position += motion
	if _collide:
		position = Solids.resolve(position, _body_radius, _solids, _bounds, _margin)
	_speed = (position - before).length() / maxf(delta, 0.0001)


## The bonding ceremony, beat by beat. It keeps facing you throughout — the sudden, held eye
## contact is the first tell that this one is different.
func _run_bond(delta: float) -> void:
	_anim_t += delta
	var to_player := Vector2.ZERO
	if _player != null:
		to_player = _player.position - position
		if to_player.length() > 1.0:
			_facing = _facing.lerp(to_player.normalized(), 0.5).normalized()
	if _anim_t < BOND_NOTICE_END:
		# It stops mid-wander and just… looks at you.
		if _fire_once("notice"):
			_spawn_emote("alert")
		_speed = 0.0
	elif _anim_t < BOND_HOP_END:
		# Then it can't help itself: excited bounds straight to your feet.
		if _fire_once("hop"):
			_squash = 0.35
		if to_player.length() > BOND_APPROACH_STOP:
			_step(_facing * BOND_HOP_SPEED * delta, delta)
		else:
			_speed = 0.0
	elif _anim_t < BOND_FLICKER_END:
		# Too delighted to hold a shape: it flickers through every animal it knows.
		_speed = 0.0
		_flick_accum += delta
		if _flick_accum >= BOND_FLICKER_STEP:
			_flick_accum = 0.0
			_flicker_form()
	elif _anim_t < BOND_DONE:
		# It settles — as whatever it lands on; the shape was never the point — and the
		# hearts say the rest.
		_speed = 0.0
		if _fire_once("settle"):
			_squash = 0.55
			_spawn_emote("love")
		if _anim_t >= BOND_FLICKER_END + 0.3 and _fire_once("love2"):
			_spawn_emote("love")
		if _anim_t >= BOND_FLICKER_END + 0.6 and _fire_once("love3"):
			_spawn_emote("love")
	elif _fire_once("done"):
		bond_finished.emit(_species, _variant)


## One ecstatic flicker: jump to a random OTHER drawable species (tiny pop, the odd sparkle).
func _flicker_form() -> void:
	var pool: Array = []
	for f in PalView.available_forms():
		if String(f["species"]) != _species:
			pool.append(f)
	if pool.is_empty():
		return
	var pick: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
	_apply_form(String(pick["species"]), _rng.randi_range(0, maxi(1, int(pick["variants"])) - 1))
	_squash = 0.22
	if _rng.randf() < 0.4:
		_spawn_emote("delight")


## Wear a species + coat (validated + clamped by PalView.sheet_info; draws nothing if un-drawable —
## the director never spawns a flock without art, so this is belt-and-braces).
func _apply_form(species: String, variant: int) -> void:
	var info := PalView.sheet_info(species, variant)
	if info.is_empty():
		return
	_species = species
	_variant = int(info["variant"])
	_tex = info["tex"]
	_sheet = info["sheet"]


func _fire_once(key: String) -> bool:
	if _fired.has(key):
		return false
	_fired[key] = true
	return true


func _spawn_emote(kind: String) -> void:
	if _emotes.size() >= 4:
		_emotes.pop_front()
	_emotes.append({ "kind": kind, "age": 0.0, "life": 1.6 })


func _age_emotes(delta: float) -> void:
	if _emotes.is_empty():
		return
	var alive: Array = []
	for e in _emotes:
		e["age"] = float(e["age"]) + delta
		if float(e["age"]) < float(e["life"]):
			alive.append(e)
	_emotes = alive


func _draw() -> void:
	if _tex == null:
		return
	# Same body language as the companion's daemon draw: a soft breathing bob at rest, a busier
	# one on the move, plus the one-shot squash pops (shift shimmer, ceremony beats).
	var moving := _speed > 6.0
	var bounce := -absf(sin(_time * 8.0)) * 1.6 if moving else sin(_time * 2.4) * 0.6
	PalSprite.draw(self, _tex, {
		"look": _facing,
		"speed": _speed,
		"time": _time,
		"bounce": bounce,
		"squash": _squash,
	}, _sheet)
	for e in _emotes:
		var life := maxf(float(e["life"]), 0.0001)
		var p := clampf(float(e["age"]) / life, 0.0, 1.0)
		var fade_in := clampf(p / 0.15, 0.0, 1.0)
		var fade_out := 1.0 - clampf((p - 0.6) / 0.4, 0.0, 1.0)
		var rise := -18.0 - p * 16.0
		var pop := 0.7 + 0.5 * clampf(p / 0.25, 0.0, 1.0)
		EmoteGlyphs.draw(self, String(e["kind"]), Vector2(0.0, rise), fade_in * fade_out, pop)
