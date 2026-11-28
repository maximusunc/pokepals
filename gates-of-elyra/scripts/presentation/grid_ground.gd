class_name GridGround
extends Node2D
## Ohmstead's ground: a glowing grid on the dark (assets/ohm_grid.gdshader over one quad). A world asks for it
## with a "ground" entity whose render is "grid"; WorldArt then puts this node under everything in place of its
## own floor (as it does GroundLayer for the pixel worlds).
##
## This node's job is to hand the shader its inputs: the colours and spacing from the art direction, the clock,
## the last few FOOTSTEPS (a ring of light runs outward along the lines from each, and the cell underfoot
## flares: this world's footprints), and the SECTORS (rectangles with their own power level: the one that has
## lost power shows only faint, cold lines until its circuit is closed).
##
## Cost: one quad and one uniform write a frame (the clock); the footstep list is rewritten only when someone
## takes a step. Pure presentation: nothing here is networked or collided with.

const MAX_PULSES := 12
const MAX_SECTORS := 4
const MARGIN := 900.0          # how far past the bounds the quad reaches, so the dark outside is ours too

var _rect := Rect2()
var _mat: ShaderMaterial
var _time := 0.0
var _walkers: Callable
var _spacing := 26.0
var _pulses: Array[Vector4] = []
var _next := 0
var _last: Dictionary = {}     # instance_id -> the feet's last pulse position
var _sectors: Array[Vector4] = []
var _power := PackedFloat32Array()


## True if the art direction asks for the grid ground.
static func wanted(style: ArtStyle) -> bool:
	return String(style.entity("ground").get("render", "")) == "grid"


func build(bounds: Rect2, style: ArtStyle) -> void:
	show_behind_parent = true
	_rect = bounds.grow(MARGIN)
	var cfg := style.entity("ground")
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/ohm_grid.gdshader")
	for key in ["void_color", "line_color", "dead_color", "step_color", "paw_color"]:
		if cfg.has(key):
			_mat.set_shader_parameter(key, WorldData.to_color(cfg[key]))
	for key in ["cell", "major", "minor_alpha", "major_alpha", "halo", "fade", "pulse_speed", "pulse_life"]:
		if cfg.has(key):
			_mat.set_shader_parameter(key, float(cfg[key]))
	_mat.set_shader_parameter("bounds", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	_spacing = maxf(8.0, float(cfg.get("step_spacing", 26.0)))
	_pulses.clear()
	for i in MAX_PULSES:
		_pulses.append(Vector4(0, 0, -1000.0, 0))
	_sectors.clear()
	_power = PackedFloat32Array()
	for i in MAX_SECTORS:
		_sectors.append(Vector4(0, 0, 0, 0))
		_power.append(1.0)
	_push_pulses()
	_push_sectors()
	material = _mat
	queue_redraw()


## Whose footsteps pulse: a Callable returning the actors present (the same one GlowTrail is handed).
func set_walkers(walkers: Callable) -> void:
	_walkers = walkers


## A ring of light from `pos`, now. `companion` picks the colour (amber for a companion's, magenta for a person's).
func add_pulse(pos: Vector2, companion := false) -> void:
	_pulses[_next] = Vector4(pos.x, pos.y, _time, 1.0 if companion else 0.0)
	_next = (_next + 1) % MAX_PULSES
	_push_pulses()


## Give sector `index` (0..3) its rectangle and power (0 dead .. 1 live).
func set_sector(index: int, rect: Rect2, power: float) -> void:
	if index < 0 or index >= MAX_SECTORS:
		return
	_sectors[index] = Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	_power[index] = clampf(power, 0.0, 1.0)
	_push_sectors()


func sector_power(index: int) -> float:
	return _power[index] if index >= 0 and index < MAX_SECTORS else 1.0


func _push_pulses() -> void:
	if _mat != null:
		_mat.set_shader_parameter("pulses", _pulses)


func _push_sectors() -> void:
	if _mat != null:
		_mat.set_shader_parameter("sectors", _sectors)
		_mat.set_shader_parameter("sector_power", _power)


func _process(delta: float) -> void:
	if _mat == null:
		return
	_time += delta
	_mat.set_shader_parameter("now", _time)
	if not _walkers.is_valid():
		return
	var seen := {}
	for w in _walkers.call():
		if not is_instance_valid(w):
			continue
		var n := w as Node2D
		if n == null or not n.is_visible_in_tree():
			continue
		var id := n.get_instance_id()
		seen[id] = true
		var feet := n.position + Vector2(0, 6)
		if not _last.has(id):
			_last[id] = feet
			continue
		var step: Vector2 = feet - _last[id]
		var len := step.length()
		if len < _spacing:
			continue
		_last[id] = feet
		if len > _spacing * 6.0:
			continue   # a world-hop arrival or a puppet's first packet, not a step
		add_pulse(feet, n is CompanionView)
	if _last.size() > seen.size():
		for id in _last.keys():
			if not seen.has(id):
				_last.erase(id)


func _draw() -> void:
	if _rect.has_area():
		draw_rect(_rect, Color.WHITE)
