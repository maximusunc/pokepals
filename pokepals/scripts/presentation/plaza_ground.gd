class_name PlazaGround
extends Node2D
## Lingerlong's ground: a marble plaza floating in a pastel sky (assets/plaza_floor.gdshader over one quad). A
## world asks for it with a "ground" entity whose render is "plaza"; WorldArt then puts this node under
## everything in place of its own floor, the way it does GridGround for Ohmstead.
##
## The geometry comes from the spec's `plaza` block (the floors, each with its second tile colour, and the pool);
## the colours, the sky's stops and the three textures from the art direction's ground entity. This node's job
## is to hand the shader its inputs and keep the few that change:
##   * the clock (one float a frame) and where the camera is looking (only when it moved), so the sky can stay
##     put on the screen while the clouds slide a little and the sun slides most of the way;
##   * EVENING: 1 while you are on (or near) the evening terrace, 0 in the plaza, eased over about 1.5 s and
##     written only while it is changing;
##   * WADING RINGS: when someone takes a step in the pool, a ring is written into a small buffer (no prints on
##     the marble, which is far too polished to keep them).
## Pure presentation: nothing here is networked or collided with (PlazaRealm fences the plaza).

const MAX_FLOORS := 8
const MAX_RIPPLES := 10
const MARGIN := 1400.0          # how far past the bounds the quad reaches, so the sky outside is ours too
const EVENING_EASE := 1.5       # seconds from afternoon to evening

var _rect := Rect2()
var _mat: ShaderMaterial
var _time := 0.0
var _walkers: Callable
var _watch: Node2D = null
var _spacing := 22.0
var _ripples: Array[Vector4] = []
var _next := 0
var _last: Dictionary = {}      # instance_id -> the feet's last ripple position
var _pool := Rect2()
var _evening_rect := Rect2()
var _evening_from_y := -INF
var _evening := 0.0
var _view_center := Vector2(INF, INF)
var _step_clock := 0.0
const STEP_EVERY := 0.1         # how often the wading feet are looked at (a step takes a quarter second or more)


## True if the art direction asks for the plaza ground.
static func wanted(style: ArtStyle) -> bool:
	return String(style.entity("ground").get("render", "")) == "plaza"


func build(bounds: Rect2, style: ArtStyle, plaza: Dictionary) -> void:
	show_behind_parent = true
	_rect = bounds.grow(MARGIN)
	var cfg := style.entity("ground")
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/plaza_floor.gdshader")

	var rects: Array[Vector4] = []
	var tiles: Array[Color] = []
	for f in plaza.get("floors", []):
		if rects.size() >= MAX_FLOORS:
			push_warning("PlazaGround: only the first %d floors are drawn" % MAX_FLOORS)
			break
		var r := PlazaRealm.rect_of(f.get("rect", []))
		rects.append(Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
		tiles.append(WorldData.to_color(f.get("tile_b", [0.95, 0.79, 0.83])))
	var count := rects.size()
	while rects.size() < MAX_FLOORS:
		rects.append(Vector4(0, 0, -1, -1))
		tiles.append(Color.WHITE)
	_mat.set_shader_parameter("floors", rects)
	_mat.set_shader_parameter("floor_b", tiles)
	_mat.set_shader_parameter("floor_count", count)
	_pool = PlazaRealm.rect_of((plaza.get("pool", {}) as Dictionary).get("rect", []))
	_mat.set_shader_parameter("pool", Vector4(_pool.position.x, _pool.position.y, _pool.end.x, _pool.end.y) if _pool.has_area() else Vector4.ZERO)
	_mat.set_shader_parameter("tile", float(plaza.get("tile", 40.0)))

	for key in ["tile_a", "vein", "grout", "rim_lit", "rim_shade"]:
		if cfg.has(key):
			_mat.set_shader_parameter(key, WorldData.to_color(cfg[key]))
	var renames := { "sun": "sun_color", "water_deep": "water_deep", "water_shallow": "water_shallow", "cloud": "cloud_color" }
	for key in renames:
		if cfg.has(key):
			_mat.set_shader_parameter(renames[key], WorldData.to_color(cfg[key]))
	for key in ["thickness", "sun_radius", "horizon_fade"]:
		if cfg.has(key):
			_mat.set_shader_parameter(key, float(cfg[key]))
	if cfg.has("sun_at"):
		_mat.set_shader_parameter("sun_at", WorldData.to_vec2(cfg["sun_at"]))
	_mat.set_shader_parameter("sky", _stops(cfg.get("sky", []), ["#8fb8e8", "#c9b6f0", "#f7b7d2", "#ffd3a8", "#fff0c9"]))
	_mat.set_shader_parameter("evening_sky", _stops(cfg.get("evening_sky", []), ["#2b2a5c", "#2b2a5c", "#6a4c93", "#e07a9a", "#ffb482"]))
	# The three textures; a missing one is skipped by the shader (a flat slab, plain water, a cloudless sky).
	for pair in [["marble", "marble_tex", "has_marble"], ["caustics", "caustics_tex", "has_caustics"], ["clouds", "clouds_tex", "has_clouds"]]:
		var path := String(cfg.get(pair[0], ""))
		var ok := path != "" and ResourceLoader.exists(path)
		if ok:
			_mat.set_shader_parameter(pair[1], load(path))
		_mat.set_shader_parameter(pair[2], 1.0 if ok else 0.0)

	var ev: Dictionary = plaza.get("evening", {})
	_evening_rect = PlazaRealm.rect_of(ev.get("rect", []))
	_evening_from_y = float(ev.get("from_y", -INF))
	_spacing = maxf(8.0, float(cfg.get("ripple_spacing", 22.0)))
	_ripples.clear()
	for i in MAX_RIPPLES:
		_ripples.append(Vector4(0, 0, -1000.0, 0))
	_mat.set_shader_parameter("ripples", _ripples)
	_evening = 0.0
	_mat.set_shader_parameter("evening", 0.0)
	material = _mat
	queue_redraw()


static func _stops(list: Array, fallback: Array) -> Array[Color]:
	var out: Array[Color] = []
	for i in 5:
		if i < list.size():
			out.append(WorldData.to_color(list[i]))
		else:
			out.append(Color(String(fallback[i])))
	return out


## Whose footsteps ring the water: a Callable returning the actors present (the same one GlowTrail is handed).
func set_walkers(walkers: Callable) -> void:
	_walkers = walkers


## Whose place decides the evening: the local player (only your own screen goes to evening on the terrace).
func set_watch(node: Node2D) -> void:
	_watch = node


## Whether `p` is somewhere the evening has come (the terrace and the sky round it).
func is_evening_at(p: Vector2) -> bool:
	return p.y < _evening_from_y or (_evening_rect.has_area() and _evening_rect.has_point(p))


func evening() -> float:
	return _evening


## Snap the evening straight to where the watched player stands (an arrival, not a walk: no easing).
func settle_evening() -> void:
	if _watch != null and is_instance_valid(_watch):
		_evening = 1.0 if is_evening_at(_watch.position) else 0.0
		if _mat != null:
			_mat.set_shader_parameter("evening", _evening)


## A ring on the water at `pos`, now.
func add_ripple(pos: Vector2, strength := 1.0) -> void:
	_ripples[_next] = Vector4(pos.x, pos.y, _time, strength)
	_next = (_next + 1) % MAX_RIPPLES
	if _mat != null:
		_mat.set_shader_parameter("ripples", _ripples)


func _process(delta: float) -> void:
	if _mat == null:
		return
	_time += delta
	_mat.set_shader_parameter("now", _time)
	var vis := ViewCull.visible_world_rect(self, 0.0)
	if vis.has_area():
		var c := vis.get_center()
		if c.distance_squared_to(_view_center) > 0.01:
			_view_center = c
			_mat.set_shader_parameter("view_center", c)
	if _watch != null and is_instance_valid(_watch):
		var target := 1.0 if is_evening_at(_watch.position) else 0.0
		if not is_equal_approx(_evening, target):
			_evening = move_toward(_evening, target, delta / EVENING_EASE)
			var eased := _evening * _evening * (3.0 - 2.0 * _evening)
			_mat.set_shader_parameter("evening", eased)
	# (In a crowd every actor present is one walker, so they are looked at ten times a second, not every frame.)
	_step_clock += delta
	if _step_clock >= STEP_EVERY and _walkers.is_valid() and _pool.has_area():
		_step_clock = 0.0
		_ring_steps()


## A step in the pool rings the water. Only actors standing in the pool are looked at past the first test.
func _ring_steps() -> void:
	var seen := {}
	for w in _walkers.call():
		if not is_instance_valid(w):
			continue
		var n := w as Node2D
		if n == null or not n.is_visible_in_tree():
			continue
		var feet := n.position + Vector2(0, 2)
		if not _pool.has_point(feet):
			continue
		var id := n.get_instance_id()
		seen[id] = true
		if not _last.has(id):
			_last[id] = feet
			add_ripple(feet, 0.7)
			continue
		var step: Vector2 = feet - _last[id]
		var len := step.length()
		if len < _spacing:
			continue
		_last[id] = feet
		if len > _spacing * 6.0:
			continue   # a world-hop arrival or a puppet's first packet, not a step
		add_ripple(feet, 0.55 if n is CompanionView else 1.0)
	if _last.size() > seen.size():
		for id in _last.keys():
			if not seen.has(id):
				_last.erase(id)


func _draw() -> void:
	if _rect.has_area():
		draw_rect(_rect, Color.WHITE)
