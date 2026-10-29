class_name PalView
extends Node2D
## An AMBIENT PAL puppet with a real animal species — the sprite-sheet sibling of the
## brainless CompanionView puppet AmbientPalDirector spawns. Same contract, different
## body: the server's ambient sim owns the motion; this node only eases toward the
## latest authoritative spot (set_remote_state) and draws the right frame. Purely
## presentation — no brain, no collision, no interaction, exactly like the puppet path.
##
## Sheet convention (data/pals.json + tools/gen_pals.py; art in tools/pixelart):
##   cols = 8 motion frames, col 0 = idle; rows = the RIGHT-handed facing family
##   (down, down_right, right, up_right, up) — the left family is this row mirrored,
##   the same derivation directions.py uses. A bird carries an extra 'fly_row' it
##   switches to while moving, so birds flutter between spots while the others hop.

const REMOTE_LERP_RATE := 14.0  # match CompanionView's remote easing so pals move alike
const LOOK_LERP_RATE := 6.0
# A world's native creatures notice someone walking up (see react_to): within NOTICE_RANGE a "shy" one
# shrinks back (up to SHY_BACKOFF px, purely a drawn nudge — the server still owns where it really is)
# and a "friendly" one turns to face you and bobs. REACT_RATE is how fast either eases in and out.
const NOTICE_RANGE := 80.0
const SHY_BACKOFF := 16.0
const REACT_RATE := 5.0

static var _registry: Dictionary = {}

var _tex: Texture2D
var _fw := 32
var _fh := 32
var _fps := 10.0
var _cols := 8
var _fly_row := -1
var _rows: Dictionary = {}

var _target_pos := Vector2.ZERO
var _look := Vector2.DOWN
var _target_look := Vector2.DOWN
var _speed := 0.0
var _time := 0.0
# Native-creature extras from the registry (all off for the meadow animals): a soft halo of light,
# a motion cycle that keeps running while it hovers, and how it reacts to people.
var _glow := Color(0, 0, 0, 0)
var _animate_idle := false
var _temperament := ""
var _lore := ""
var _species := ""
# Eased reaction state: 0..1 how strongly it's reacting, the nudge it has backed off by, and where the
# person it noticed stands (local space-free: a world position).
var _react := 0.0
var _shy_off := Vector2.ZERO
var _notice_pos := Vector2.ZERO
var _pulse := 0.0  # a brief brightening when examined


static func registry() -> Dictionary:
	if _registry.is_empty():
		_registry = WorldData.load_json("res://data/pals.json")
	return _registry


## Whether a seed's species can be drawn: the registry knows it AND its sheet imported.
## Anything else falls back to the companion puppet, keeping old seeds valid.
static func supported(species: String, variant: int) -> bool:
	var reg := registry()
	if not (reg.get("species", {}) as Dictionary).has(species):
		return false
	return ResourceLoader.exists(_sheet_path(reg, species, variant))


static func _sheet_path(reg: Dictionary, species: String, variant: int) -> String:
	var n := int((reg.get("species", {}) as Dictionary).get(species, {}).get("variants", 1))
	return "res://assets/pals/%s_%d.png" % [species, clampi(variant, 0, n - 1)]


## Everything needed to DRAW a species as pal art: its sheet texture, the (registry-clamped) coat
## variant actually worn, and the PalSprite layout dict. {} when the species/variant can't be drawn.
## The one home of the sheet convention for every non-PalView renderer of pal art — the companion's
## daemon form and the first-meeting flock both draw through this.
static func sheet_info(species: String, variant: int) -> Dictionary:
	var reg := registry()
	if not supported(species, variant):
		return {}
	var declared := int((reg.get("species", {}) as Dictionary).get(species, {}).get("variants", 1))
	return {
		"tex": load(_sheet_path(reg, species, variant)),
		"variant": clampi(variant, 0, maxi(1, declared) - 1),
		"sheet": {
			"frame": reg.get("frame", [32, 32]),
			"fps": float(reg.get("fps", 10.0)),
			"cols": int(reg.get("move_frames", 8)),
			"rows": reg.get("rows", {}),
			"fly_row": int((reg.get("species", {}) as Dictionary).get(species, {}).get("fly_row", -1)),
		},
	}


## The drawable animal forms — each registry species whose sheet(s) actually imported, with how
## many coat variants are available: [{ species: String, variants: int }]. The shared pool both the
## companion's daemon form and the first-meeting flock shift between. Empty with no pal art present.
## A world's NATIVE creatures ("form": false — Nocthollow's) are pals only, never forms: the companion
## stays the familiar animal it is, a visitor on another planet like you.
static func available_forms() -> Array:
	var out: Array = []
	var species: Dictionary = registry().get("species", {})
	for sp in species:
		if not bool(species[sp].get("form", true)):
			continue
		var declared := int(species[sp].get("variants", 1))
		var n := 0
		while n < declared and supported(sp, n):
			n += 1
		if n > 0:
			out.append({ "species": String(sp), "variants": n })
	return out


var _seeded := false


func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	_target_pos = position


## Pick the species + coat. Returns false (draws nothing) if the sheet is missing —
## the director checks supported() first, so this is belt-and-braces.
func setup_species(species: String, variant: int) -> bool:
	var reg := registry()
	if not supported(species, variant):
		return false
	_tex = load(_sheet_path(reg, species, variant))
	var frame: Array = reg.get("frame", [32, 32])
	_fw = int(frame[0])
	_fh = int(frame[1])
	_fps = float(reg.get("fps", 10.0))
	_cols = int(reg.get("move_frames", 8))
	_rows = reg.get("rows", {})
	var entry: Dictionary = (reg.get("species", {}) as Dictionary).get(species, {})
	_fly_row = int(entry.get("fly_row", -1))
	_species = species
	_animate_idle = bool(entry.get("animate_idle", false))
	_temperament = String(entry.get("temperament", ""))
	_lore = String(entry.get("lore", ""))
	var glows: Array = entry.get("glows", [])
	if not glows.is_empty():
		_glow = WorldData.to_color(glows[clampi(variant, 0, glows.size() - 1)])
	queue_redraw()
	return true


## What Examining this creature reads ("" for the meadow animals, which aren't examinable).
func lore() -> String:
	return _lore


func species_name() -> String:
	return _species


## Where it's DRAWN right now (its eased spot plus any shy back-off) — what the examine prompt points at.
func shown_position() -> Vector2:
	return position + _shy_off


## Tell it where the nearest person stands (or pass far away / call with no one near). Drives the
## presentation-only reaction: a shy creature eases back from them, a friendly one turns and bobs.
## Ignored for creatures without a temperament (the meadow animals).
func react_to(person: Vector2, distance: float) -> void:
	if _temperament == "":
		return
	_notice_pos = person
	var want := clampf(1.0 - distance / NOTICE_RANGE, 0.0, 1.0)
	_react = want if want > _react else _react  # rises at once; _process eases it back down


## Examined: a little flare of its light and (friendly or not) a happy hop toward the attention.
func pulse() -> void:
	_pulse = 1.0


## The server's latest authoritative spot for this pal (same contract as the puppet).
func set_remote_state(pos: Vector2, look: Vector2) -> void:
	_target_pos = pos
	if look.length() > 0.01:
		_target_look = look.normalized()


func _process(delta: float) -> void:
	if not _seeded:
		# Desync motion phase between pals (by home spot, which is set after _ready)
		# so a cluster doesn't hop in lockstep.
		_time = absf(position.x) * 0.017 + absf(position.y) * 0.031
		_seeded = true
	var before := position
	position = position.lerp(_target_pos, 1.0 - exp(-REMOTE_LERP_RATE * delta))
	_speed = (position - before).length() / maxf(delta, 0.0001)
	_look = _look.lerp(_target_look, 1.0 - exp(-LOOK_LERP_RATE * delta)).normalized()
	_time += delta
	_pulse = maxf(0.0, _pulse - delta * 0.9)
	# Reactions ease out on their own; react_to() pushes them back up each frame someone stays near.
	_react = maxf(0.0, _react - delta * REACT_RATE * 0.25)
	var away := Vector2.ZERO
	if _temperament == "shy" and _react > 0.0:
		away = (position - _notice_pos).normalized() * SHY_BACKOFF * _react
	_shy_off = _shy_off.lerp(away, 1.0 - exp(-REACT_RATE * delta))
	queue_redraw()


func _draw() -> void:
	# A native creature's own light: a soft breathing halo under it (higher for a floater, which hovers),
	# flaring when examined. The meadow animals carry no glow and skip this entirely.
	if _glow.a > 0.0:
		var breathe := 0.85 + 0.15 * sin(_time * 1.7 + position.x * 0.01)
		var lift := -16.0 if _animate_idle else -8.0
		var g := Color(_glow.r, _glow.g, _glow.b, 0.30 + 0.35 * _pulse)
		SoftGlow.draw(self, _shy_off + Vector2(0, lift), (22.0 + 16.0 * _pulse) * breathe, g)
	# A friendly creature that's noticed someone turns to them and bobs; a shy one crouches as it backs
	# off. Both are drawn-only — the server's sim still owns where it actually is.
	var look := _look
	var bounce := 0.0
	var squash := 0.0
	if _react > 0.01:
		if _temperament == "friendly":
			var to_them := _notice_pos - position
			if to_them.length() > 0.5:
				look = _look.lerp(to_them.normalized(), _react).normalized()
			bounce = -absf(sin(_time * 7.0)) * 2.5 * _react
		elif _temperament == "shy":
			squash = -0.14 * _react
	if _pulse > 0.0:
		bounce -= absf(sin(_pulse * PI * 2.0)) * 4.0 * _pulse
	# The shared animal-sheet rig (PalSprite) picks the facing row + motion frame and blits it. A meadow
	# ambient pal passes no bounce/squash/offset, so it renders exactly as the hand-rolled draw did before.
	PalSprite.draw(self, _tex, { "look": look, "speed": _speed, "time": _time, "bounce": bounce, "squash": squash, "offset": _shy_off }, {
		"frame": [_fw, _fh],
		"fps": _fps,
		"cols": _cols,
		"rows": _rows,
		"fly_row": _fly_row,
		"animate_idle": _animate_idle,
	})
