class_name SteamPuffs
extends Node2D
## Steam rising off the hot springs (Steamhollow): soft white puffs that bloom low over a pool, climb,
## widen and thin out. A pool gets a handful of rising columns in proportion to its size; a vent prop
## breathes one thicker plume. Drawn above the y-sorted scenery (steam passes in front of a bather's
## shoulder) and below the mist. Only the puffs near the camera are drawn, so the cost follows the
## screen, not the world. Cosmetic and local: nothing here is networked or touches game logic.
##
## Tuned by the world's `atmosphere.steam` block (all optional):
##   color [r,g,b]  alpha 0.2  rise 34 (px a puff climbs)  life 4.5 (seconds)  size 13 (starting radius)
##   per_radius 22 (one column per this many px of pond radius, at least 2)  vent_types ["sh_steam_vent"]
##   vent_puffs 3 (columns a vent breathes)

const MAX_COLUMNS := 400

var _columns: Array = []        # [{ pos: Vector2, phase: float, life: float, size: float, spread: float }]
var _color := Color(1.0, 0.98, 0.96)
var _alpha := 0.2
var _rise := 34.0
var _life := 4.5
var _size := 13.0
var _time := 0.0


func setup(cfg: Dictionary, data: Dictionary) -> void:
	_color = WorldData.to_color(cfg.get("color", [1.0, 0.98, 0.96]))
	_alpha = float(cfg.get("alpha", 0.2))
	_rise = float(cfg.get("rise", 34.0))
	_life = maxf(1.0, float(cfg.get("life", 4.5)))
	_size = float(cfg.get("size", 13.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x57EA3
	_columns.clear()
	var per := maxf(8.0, float(cfg.get("per_radius", 22.0)))
	for pd in data.get("ponds", []):
		var c := WorldData.to_vec2(pd["center"])
		var r := float(pd["radius"])
		for i in maxi(2, int(r / per)):
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * r * 0.85
			_columns.append({ "pos": c + Vector2(cos(a), sin(a) * 0.7) * d, "phase": rng.randf(), "life": _life * rng.randf_range(0.8, 1.25),
				"size": _size * rng.randf_range(0.8, 1.3), "spread": rng.randf_range(-1.0, 1.0) })
			if _columns.size() >= MAX_COLUMNS:
				return
	var vents: Array = cfg.get("vent_types", ["sh_steam_vent"])
	for p in data.get("props", []):
		if vents.has(String(p.get("type", ""))):
			for k in int(cfg.get("vent_puffs", 3)):
				_columns.append({ "pos": WorldData.to_vec2(p["position"]) + Vector2(rng.randf_range(-3.0, 3.0), -2.0), "phase": rng.randf(),
					"life": _life * rng.randf_range(0.7, 1.0), "size": _size * rng.randf_range(0.6, 0.9), "spread": rng.randf_range(-1.0, 1.0) })
	set_process(not _columns.is_empty())


func column_count() -> int:
	return _columns.size()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var vis := ViewCull.visible_world_rect(self, _size + _rise)
	var cull := vis.has_area()
	for c in _columns:
		var p: Vector2 = c["pos"]
		if cull and not vis.has_point(p):
			continue
		# three puffs per column, a third of a life apart, so the column is always breathing
		for k in 3:
			var t := fposmod(_time / float(c["life"]) + float(c["phase"]) + float(k) / 3.0, 1.0)
			var up := t * _rise
			var sway := sin(t * 5.0 + float(c["phase"]) * TAU) * 5.0 * t + float(c["spread"]) * 8.0 * t
			var radius := float(c["size"]) * (0.5 + 0.9 * t)
			var a := _alpha * sin(t * PI) * (1.0 - 0.4 * t)
			SoftGlow.draw(self, p + Vector2(sway, -up - 4.0), radius, Color(_color.r, _color.g, _color.b, a), 0.8)
