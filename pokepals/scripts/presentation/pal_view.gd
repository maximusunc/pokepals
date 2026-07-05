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
const MOVE_GATE := 4.0          # px/sec of eased motion that counts as "moving"
const FOOT_Y := 8.0             # feet sit at origin+8, like SpriteActor/SpriteSlot

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
	queue_redraw()
	return true


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
	queue_redraw()


## The right-handed facing row for a look vector, plus whether to mirror (left family).
func _facing_row(dir: Vector2) -> Array:
	var octant := roundi(dir.angle() / (PI / 4.0))  # 0=right, positive = screen-down
	match octant:
		0: return [int(_rows.get("right", 2)), false]
		1: return [int(_rows.get("down_right", 1)), false]
		2: return [int(_rows.get("down", 0)), false]
		3: return [int(_rows.get("down_right", 1)), true]
		-1: return [int(_rows.get("up_right", 3)), false]
		-2: return [int(_rows.get("up", 4)), false]
		-3: return [int(_rows.get("up_right", 3)), true]
		_: return [int(_rows.get("right", 2)), true]  # 4/-4 = left


func _draw() -> void:
	if _tex == null:
		return
	var moving := _speed > MOVE_GATE
	var rf := _facing_row(_look)
	var row := int(rf[0])
	var flip := bool(rf[1])
	if moving and _fly_row >= 0:
		# Airborne cycle reads as a profile: face strictly left/right of travel.
		row = _fly_row
		flip = _look.x < 0.0
	var col := int(_time * _fps) % _cols if moving else 0
	var region := Rect2(col * _fw, row * _fh, _fw, _fh)
	var dest := Rect2(-_fw * 0.5, FOOT_Y - _fh, _fw, _fh)
	if flip:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect_region(_tex, dest, region)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(_tex, dest, region)
