class_name AmbientLife
extends Node2D
## The small life in the air that makes a place feel inhabited: butterflies by day, fireflies at
## dusk, cloud shadows sliding over everything, and now and then a leaf drifting down from a tree.
## Sits above the y-sorted Scenery (so a cloud's shadow darkens the trees too, and a butterfly flits
## over a bush). Everything is cosmetic, local and seeded: nothing here is shared over the network
## or touches game logic — a friend sees their own butterflies, which is fine for atmosphere.
##
## Tuned by the art direction's "ambient_life" entity (a world's art block can override it):
##   butterflies { count, colors }   — flutter about near the camera, rest now and then; fade at dusk
##   fireflies   { count, color, always } — blink on as dusk deepens (always: a night world keeps them)
##   clouds      { count, alpha, speed }  — huge soft shadows drifting with the wind across the world
##   leaves      { rate, colors }         — leaves let go of on-screen trees, flutter down, settle, fade
## Only what's near the camera is simulated: butterflies and fireflies that wander off screen are
## quietly re-spawned at its edge, so the cost doesn't grow with the size of the world.

const VIEW_MARGIN := 60.0

var _bounds := Rect2()
var _trees: PackedVector2Array = PackedVector2Array()
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _dusk := 0.0
var _wind := Vector2(1.0, 0.25).normalized()

var _bf_cfg: Dictionary = {}
var _ff_cfg: Dictionary = {}
var _cloud_cfg: Dictionary = {}
var _leaf_cfg: Dictionary = {}
var _butterflies: Array = []  # [{ pos, ang, speed, rest, phase, color }]
var _fireflies: Array = []    # [{ pos, home, phase }]
var _clouds: Array = []       # [{ pos, r, lobes: [Vector2 offsets] }]
var _leaves: Array = []       # [{ pos, ground, phase, landed, color }]
var _shadow := Color(0.05, 0.07, 0.10)
var _quality := 1.0   # art.json's quality.detail: scales the creature counts and leaf rate


func setup(bounds: Rect2, style: ArtStyle, tree_positions: PackedVector2Array, wind_strength: float) -> void:
	_bounds = bounds
	_trees = tree_positions
	_rng.seed = 0xB0773F1 + int(bounds.size.x)
	_shadow = style.color("shadow")
	var cfg: Dictionary = style.entity("ambient_life")
	_bf_cfg = cfg.get("butterflies", {})
	_ff_cfg = cfg.get("fireflies", {})
	_cloud_cfg = cfg.get("clouds", {})
	_leaf_cfg = cfg.get("leaves", {})
	_quality = WorldArt.detail_quality(style)
	_wind = Vector2(1.0, 0.25).normalized() * clampf(wind_strength / 2.6, 0.4, 2.0)
	for i in int(_cloud_cfg.get("count", 0)):
		var r := _rng.randf_range(140.0, 240.0)
		var lobes: Array = []
		for k in 4:
			lobes.append(Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.25, 0.25)) * r)
		_clouds.append({
			"pos": Vector2(_bounds.position.x + _rng.randf() * _bounds.size.x, _bounds.position.y + _rng.randf() * _bounds.size.y),
			"r": r, "lobes": lobes,
		})


## 0 = day .. 1 = dusk (from the world controller's day cycle).
func set_dusk(v: float) -> void:
	_dusk = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var vis := ViewCull.visible_world_rect(self, VIEW_MARGIN)
	if not vis.has_area():
		return  # headless / no camera yet: nothing to look at
	_tick_clouds(delta)
	_tick_butterflies(delta, vis)
	_tick_fireflies(delta, vis)
	_tick_leaves(delta, vis)
	queue_redraw()


func _random_in(r: Rect2) -> Vector2:
	return Vector2(r.position.x + _rng.randf() * r.size.x, r.position.y + _rng.randf() * r.size.y)


## ---- clouds ----

func _tick_clouds(delta: float) -> void:
	var speed := float(_cloud_cfg.get("speed", 9.0))
	for c in _clouds:
		var p: Vector2 = c["pos"] + _wind * speed * delta
		var r: float = c["r"]
		if p.x > _bounds.end.x + r:
			p.x = _bounds.position.x - r
		if p.y > _bounds.end.y + r:
			p.y = _bounds.position.y - r
		c["pos"] = p


## ---- butterflies ----

func _tick_butterflies(delta: float, vis: Rect2) -> void:
	var want := int(float(_bf_cfg.get("count", 0)) * _quality)
	var colors: Array = _bf_cfg.get("colors", [[0.98, 0.86, 0.40]])
	while _butterflies.size() < want:
		_butterflies.append({
			"pos": _random_in(vis), "ang": _rng.randf() * TAU, "speed": _rng.randf_range(16.0, 26.0),
			"rest": 0.0, "phase": _rng.randf() * TAU,
			"color": WorldData.to_color(colors[_rng.randi() % colors.size()]),
		})
	for b in _butterflies:
		var p: Vector2 = b["pos"]
		if not vis.grow(80.0).has_point(p):
			# wandered off: come back in from the edge of the view
			p = _random_in(vis)
			if _rng.randf() < 0.5:
				p.x = vis.position.x if _rng.randf() < 0.5 else vis.end.x
			else:
				p.y = vis.position.y if _rng.randf() < 0.5 else vis.end.y
		if float(b["rest"]) > 0.0:
			b["rest"] = float(b["rest"]) - delta
		else:
			b["ang"] = float(b["ang"]) + _rng.randfn(0.0, 3.2) * delta
			p += Vector2(cos(b["ang"]), sin(b["ang"])) * float(b["speed"]) * delta
			if _rng.randf() < 0.12 * delta:
				b["rest"] = _rng.randf_range(1.0, 3.0)   # settle on a flower for a moment
		b["pos"] = p


## ---- fireflies ----

func _tick_fireflies(delta: float, vis: Rect2) -> void:
	var want := int(float(_ff_cfg.get("count", 0)) * _quality)
	while _fireflies.size() < want:
		var h := _random_in(vis)
		_fireflies.append({ "pos": h, "home": h, "phase": _rng.randf() * TAU })
	for f in _fireflies:
		var home: Vector2 = f["home"]
		if not vis.grow(80.0).has_point(home):
			home = _random_in(vis)
			f["home"] = home
		var ph: float = f["phase"]
		f["pos"] = home + Vector2(sin(_time * 0.37 + ph) * 18.0, cos(_time * 0.29 + ph * 1.3) * 10.0 + sin(_time * 1.1 + ph) * 3.0)


func _firefly_strength() -> float:
	if bool(_ff_cfg.get("always", false)):
		return 1.0
	return smoothstep(0.35, 0.9, _dusk)


## ---- leaves ----

func _tick_leaves(delta: float, vis: Rect2) -> void:
	var rate := float(_leaf_cfg.get("rate", 0.0)) * _quality
	var colors: Array = _leaf_cfg.get("colors", [[0.82, 0.62, 0.24]])
	if rate > 0.0 and _leaves.size() < 40:
		for t in _trees:
			if vis.has_point(t) and _rng.randf() < rate * 0.035 * delta:
				var start := t + Vector2(_rng.randf_range(-16.0, 16.0), _rng.randf_range(-42.0, -26.0))
				_leaves.append({
					"pos": start, "ground": t.y + _rng.randf_range(-4.0, 14.0), "phase": _rng.randf() * TAU,
					"landed": -1.0, "color": WorldData.to_color(colors[_rng.randi() % colors.size()]),
				})
	for i in range(_leaves.size() - 1, -1, -1):
		var l: Dictionary = _leaves[i]
		if float(l["landed"]) >= 0.0:
			l["landed"] = float(l["landed"]) + delta
			if float(l["landed"]) > 6.0:
				_leaves.remove_at(i)
			continue
		var p: Vector2 = l["pos"]
		p += Vector2(sin(_time * 2.3 + float(l["phase"])) * 12.0 + _wind.x * 4.0, 13.0) * delta
		if p.y >= float(l["ground"]):
			p.y = float(l["ground"])
			l["landed"] = 0.0
		l["pos"] = p


## ---- drawing (everything snapped to whole pixels) ----

func _draw() -> void:
	var vis := ViewCull.visible_world_rect(self, 300.0)
	if not vis.has_area():
		return
	var calpha := float(_cloud_cfg.get("alpha", 0.10))
	for c in _clouds:
		var cp: Vector2 = c["pos"]
		var r: float = c["r"]
		if not vis.grow(r).has_point(cp):
			continue
		for o in c["lobes"]:
			SoftGlow.draw(self, cp + o, r * 0.7, Color(_shadow.r, _shadow.g, _shadow.b, calpha), 0.62)

	for l in _leaves:
		var a := 1.0 - clampf((float(l["landed"]) - 4.5) / 1.5, 0.0, 1.0) if float(l["landed"]) >= 0.0 else 1.0
		var lc: Color = l["color"]
		var p: Vector2 = (l["pos"] as Vector2).round()
		var tumble := sin(_time * 4.0 + float(l["phase"])) > 0.0 and float(l["landed"]) < 0.0
		draw_rect(Rect2(p, Vector2(1, 2) if tumble else Vector2(2, 1)), Color(lc.r, lc.g, lc.b, a))

	var day := 1.0 - smoothstep(0.55, 0.95, _dusk)
	if day > 0.01:
		for b in _butterflies:
			_draw_butterfly(b, day)

	var ff := _firefly_strength()
	if ff > 0.01:
		var fc := WorldData.to_color(_ff_cfg.get("color", [0.86, 1.0, 0.52]))
		for f in _fireflies:
			var blink := maxf(0.0, sin(_time * 1.7 + float(f["phase"]) * 2.0))
			var k := ff * blink * blink
			if k < 0.02:
				continue
			var fp: Vector2 = (f["pos"] as Vector2).round()
			SoftGlow.draw(self, fp, 7.0, Color(fc.r, fc.g, fc.b, 0.45 * k))
			draw_rect(Rect2(fp, Vector2.ONE), Color(fc.r, fc.g, fc.b, k).lightened(0.5))


func _draw_butterfly(b: Dictionary, alpha: float) -> void:
	var p: Vector2 = (b["pos"] as Vector2).round()
	var resting := float(b["rest"]) > 0.0
	var bob := 0.0 if resting else roundf(sin(_time * 7.0 + float(b["phase"])) * 1.5)
	var c: Color = b["color"]
	c.a = alpha
	var body := Color(0.18, 0.13, 0.12, alpha)
	# a tiny shadow on the ground below it (it flies a few pixels up)
	draw_rect(Rect2(p + Vector2(-1, 6), Vector2(3, 1)), Color(_shadow.r, _shadow.g, _shadow.b, 0.18 * alpha))
	var q := p + Vector2(0, bob)
	var open := sin(_time * (5.0 if resting else 19.0) + float(b["phase"])) > (0.6 if resting else 0.0)
	if open:
		draw_rect(Rect2(q + Vector2(-3, -1), Vector2(3, 2)), c)
		draw_rect(Rect2(q + Vector2(1, -1), Vector2(3, 2)), c)
		draw_rect(Rect2(q + Vector2(-2, 1), Vector2(2, 1)), c.darkened(0.2))
		draw_rect(Rect2(q + Vector2(1, 1), Vector2(2, 1)), c.darkened(0.2))
	else:
		draw_rect(Rect2(q + Vector2(-1, -3), Vector2(1, 3)), c)
		draw_rect(Rect2(q + Vector2(1, -3), Vector2(1, 3)), c)
	draw_rect(Rect2(q + Vector2(0, -1), Vector2(1, 3)), body)
