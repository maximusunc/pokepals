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

static var _registry: Dictionary = {}

var _tex: Texture2D
var _fw := 32
var _fh := 32
var _fps := 10.0
var _cols := 8
var _fly_row := -1
var _rows: Dictionary = {}
var _species := ""      # the animal currently worn — the server can shift it over time (apply_form)
var _variant := 0
var _pop := 0.0         # 0..1, decays; a little squash-pop when the pal shifts form

var _target_pos := Vector2.ZERO
var _look := Vector2.DOWN
var _target_look := Vector2.DOWN
var _speed := 0.0
var _time := 0.0


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
	_fly_row = int((reg.get("species", {}) as Dictionary).get(species, {}).get("fly_row", -1))
	_species = species
	_variant = variant
	queue_redraw()
	return true


## Shift this pal to a new server-decided form (its daemon-style rotation). A no-op when the form is
## unchanged or un-drawable (keeping the current animal), so a garbled species never blanks the pal.
## A real change pops the sprite so the shift is felt, mirroring the companion's morph beat.
func apply_form(species: String, variant: int) -> void:
	if species == _species and variant == _variant:
		return
	if not supported(species, variant):
		return
	if setup_species(species, variant):
		_pop = 1.0


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
	_pop = maxf(0.0, _pop - delta * 2.0)
	queue_redraw()


func _draw() -> void:
	# The shared animal-sheet rig (PalSprite) picks the facing row + motion frame and blits it. Apart from
	# the brief pop when it shifts form, an ambient pal passes no bounce/squash — so at rest it renders
	# exactly as the hand-rolled draw did before.
	PalSprite.draw(self, _tex, { "look": _look, "speed": _speed, "time": _time, "squash": 0.18 * _pop }, {
		"frame": [_fw, _fh],
		"fps": _fps,
		"cols": _cols,
		"rows": _rows,
		"fly_row": _fly_row,
	})
