class_name GridRunners
extends Node2D
## Ohmstead's RUNNERS: small wireframe creatures that carry packets of light along the grid's bright lines. A
## world asks for them with a `runners` block (closed routes, a pace, a sprite sheet). Where each one is, is a
## pure function of the shared clock (RunnerRoutes), so everyone sees them in the same places with nothing
## simulated on the server and nothing sent.
##
## This node only draws them: a 4-frame trot facing the way it runs, a short fading streak behind it, and a
## polite lean off its line when someone is standing close (a local nicety: it never leaves its route). Lives
## under WorldArt, so they run on the ground beneath everyone. One node, one small draw per runner in view.

var _routes: Array = []            # Array of Array[Vector2]
var _per_route := 2
var _speed := 42.0
var _sheet: Texture2D = null
var _frame := 16
var _frames := 4
var _fps := 8.0
var _shy := 46.0
var _trail := 22.0
var _walkers: Callable
var _color := Color(0.49, 1.0, 0.69)


## cfg is the spec's `runners` block. walkers: a Callable returning the actors present (as GlowTrail's).
func setup(cfg: Dictionary, walkers: Callable) -> void:
	_walkers = walkers
	_routes = []
	for r in cfg.get("routes", []):
		var pts: Array = []
		for p in r:
			pts.append(WorldData.to_vec2(p))
		if pts.size() >= 2:
			_routes.append(pts)
	_per_route = maxi(1, int(cfg.get("per_route", 2)))
	_speed = float(cfg.get("speed", 42.0))
	_frame = maxi(1, int(cfg.get("frame", 16)))
	_frames = maxi(1, int(cfg.get("frames", 4)))
	_fps = float(cfg.get("fps", 8.0))
	_shy = float(cfg.get("shy_radius", 46.0))
	_trail = float(cfg.get("trail", 22.0))
	var path := String(cfg.get("sheet", ""))
	_sheet = ResourceLoader.load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(not _routes.is_empty())


## Where every runner is right now: [{ pos, dir }] (tests, and anything that wants to know).
func positions() -> Array:
	var t := float(Net.server_unix_ms()) / 1000.0
	var out: Array = []
	for ri in _routes.size():
		for k in _per_route:
			out.append(RunnerRoutes.runner(_routes[ri], k, _per_route, _speed, t, ri % 2 == 1))
	return out


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _routes.is_empty():
		return
	var vis := ViewCull.visible_world_rect(self, 40.0)
	var cull := vis.has_area()
	var t := float(Net.server_unix_ms()) / 1000.0
	var near: Array = []
	if _walkers.is_valid():
		for w in _walkers.call():
			if is_instance_valid(w) and w is Node2D:
				near.append((w as Node2D).position)
	var index := 0
	for ri in _routes.size():
		for k in _per_route:
			index += 1
			var r := RunnerRoutes.runner(_routes[ri], k, _per_route, _speed, t, ri % 2 == 1)
			var pos: Vector2 = r["pos"]
			if cull and not vis.has_point(pos):
				continue
			var dir: Vector2 = r["dir"]
			var lean := Vector2.ZERO
			for who in near:
				var s := RunnerRoutes.sidestep(pos, dir, who, _shy, 11.0)
				if s.length_squared() > lean.length_squared():
					lean = s
			var p := pos + lean
			# the streak it leaves on the line
			draw_line(pos - dir * 6.0, pos - dir * (6.0 + _trail * 0.5), Color(_color.r, _color.g, _color.b, 0.55), 1.0)
			draw_line(pos - dir * (6.0 + _trail * 0.5), pos - dir * (6.0 + _trail), Color(_color.r, _color.g, _color.b, 0.22), 1.0)
			if _sheet == null:
				draw_rect(Rect2(p - Vector2(4, 8), Vector2(8, 6)), _color, false, 1.0)
				continue
			var f := int(t * _fps + float(index) * 1.7) % _frames
			var src := Rect2(float(f * _frame), 0.0, float(_frame), float(_frame))
			var dst := Rect2(p - Vector2(float(_frame) * 0.5, float(_frame) - 3.0), Vector2(float(_frame), float(_frame)))
			if dir.x < -0.5:
				dst.position.x += dst.size.x
				dst.size.x = -dst.size.x          # a negative width mirrors it: facing west
			draw_texture_rect_region(_sheet, dst, src)
