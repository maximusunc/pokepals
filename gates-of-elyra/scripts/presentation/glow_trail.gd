class_name GlowTrail
extends Node2D
## Footsteps of light: on a world whose atmosphere asks for them (Nocthollow's moss), everyone who
## walks — you, your companion, and every friend and their companion — leaves a trail of small glowing
## prints that bloom where a foot lands and fade away over a few seconds. Lives under WorldArt, so the
## prints lie on the ground beneath every character and tree.
##
## It has two looks, chosen by the atmosphere's `footprints.style`: "glow" (the default, Nocthollow's prints
## of light) and "snow" (Drifthallow: a soft dent with a pale lip that slowly fills back in), and it can
## also be handed extra marks of its own: add_scent() lays one bright paw-print of a hidden trail
## (Drifthallow's hare tracks, which only the player's fox can read).
##
## Pure presentation: each frame it reads where the walkers are (a Callable the world controller
## hands it, returning the actor nodes), drops a print every `spacing` px one of them travels
## (alternating left/right foot across its heading), and draws/ages them. Nothing is networked —
## a friend's prints appear because their puppet walks across OUR ground.

const MAX_PRINTS := 320
const STYLE_GLOW := "glow"
const STYLE_SNOW := "snow"

var _walkers: Callable
var _color := Color(0.5, 1.0, 0.9)
var _life := 5.0
var _spacing := 14.0
var _style := STYLE_GLOW
var _rim := Color(0.95, 0.98, 1.0)   # snow: the pale lip of a dent
var _max_prints := MAX_PRINTS
var _scent_color := Color(0.7, 0.95, 1.0)
var _scent_life := 60.0
var _scent_size := 2.2
var _prints: Array = []        # [ { pos: Vector2, age: float, size: float, kind: String, dir: Vector2 } ]
var _last: Dictionary = {}     # instance_id -> { pos: Vector2, foot: int }


## cfg is the atmosphere's "footprints" block: { style, color, rim, life, spacing, max_prints, scent }
## where scent is { color, life, size } for add_scent(). walkers() returns the
## Node2D actors to follow (re-asked every frame, so peers who come and go are picked up).
func setup(cfg: Dictionary, walkers: Callable) -> void:
	_walkers = walkers
	_color = WorldData.to_color(cfg.get("color", [0.5, 1.0, 0.9]))
	_life = maxf(0.5, float(cfg.get("life", 5.0)))
	_spacing = maxf(4.0, float(cfg.get("spacing", 14.0)))
	_style = String(cfg.get("style", STYLE_GLOW))
	_rim = WorldData.to_color(cfg.get("rim", [0.95, 0.98, 1.0]))
	_max_prints = maxi(16, int(cfg.get("max_prints", MAX_PRINTS)))
	var scent: Dictionary = cfg.get("scent", {})
	_scent_color = WorldData.to_color(scent.get("color", [0.7, 0.95, 1.0]))
	_scent_life = maxf(1.0, float(scent.get("life", 60.0)))
	_scent_size = maxf(1.0, float(scent.get("size", 2.2)))


## Lay one bright paw-print of a hidden trail at `pos`, its toes pointing along `heading` (the way the
## trail runs). It lasts the scent's own life, far longer than a footstep, so you can follow the line.
func add_scent(pos: Vector2, heading: Vector2) -> void:
	_prints.append({ "pos": pos, "age": 0.0, "size": _scent_size, "kind": "scent",
		"dir": heading.normalized() if heading.length() > 0.01 else Vector2.RIGHT })
	if _prints.size() > _max_prints + 200:
		_prints.remove_at(0)


func _process(delta: float) -> void:
	if not _walkers.is_valid():
		return
	for i in range(_prints.size() - 1, -1, -1):
		_prints[i]["age"] += delta
		if _prints[i]["age"] >= _life_of(_prints[i]):
			_prints.remove_at(i)
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
			_last[id] = { "pos": feet, "foot": 0 }
			continue
		var rec: Dictionary = _last[id]
		var step: Vector2 = feet - rec["pos"]
		if step.length() < _spacing:
			continue
		# Big jumps (a world-hop arrival, a puppet snapping to its first packet) aren't steps.
		if step.length() > _spacing * 6.0:
			rec["pos"] = feet
			continue
		var side := step.normalized().orthogonal() * (3.0 if int(rec["foot"]) == 0 else -3.0)
		var small := n is CompanionView
		_prints.append({ "pos": feet + side, "age": 0.0, "size": 1.6 if small else 2.2, "kind": "step", "dir": step.normalized() })
		rec["pos"] = feet
		rec["foot"] = 1 - int(rec["foot"])
		if _prints.size() > _max_prints:
			_prints.remove_at(0)
	for id in _last.keys():
		if not seen.has(id):
			_last.erase(id)
	queue_redraw()


func _life_of(pr: Dictionary) -> float:
	return _scent_life if String(pr["kind"]) == "scent" else _life


func _draw() -> void:
	var vis := ViewCull.visible_world_rect(self, 40.0)
	var cull := vis.has_area()
	for pr in _prints:
		var p: Vector2 = pr["pos"]
		if cull and not vis.has_point(p):
			continue
		var t: float = pr["age"] / _life_of(pr)
		if String(pr["kind"]) == "scent":
			_draw_scent(pr, p, t)
		elif _style == STYLE_SNOW:
			_draw_dent(pr, p, t)
		else:
			_draw_glow(pr, p, t)


func _draw_glow(pr: Dictionary, p: Vector2, t: float) -> void:
	# a quick bloom as the foot lands, then a long, soft fade
	var a := (1.0 - t) * (1.0 - t) * minf(1.0, pr["age"] * 8.0 + 0.4)
	var s: float = pr["size"]
	SoftGlow.draw(self, p, s * 4.5, Color(_color.r, _color.g, _color.b, 0.35 * a), 0.5)
	draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
	draw_circle(Vector2.ZERO, s, Color(_color.r, _color.g, _color.b, 0.9 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A print in snow: a soft shadowed dent with a pale lip along its sunlit (upper-left) edge. It sets
## at once, then slowly fills back in: the dent shallows and softens over its whole life.
func _draw_dent(pr: Dictionary, p: Vector2, t: float) -> void:
	var s: float = pr["size"]
	var depth := (1.0 - t) * (1.0 - t)
	var a := depth * minf(1.0, pr["age"] * 10.0 + 0.5)
	draw_set_transform(p, 0.0, Vector2(1.0, 0.62))
	draw_circle(Vector2(0.5, 0.7), s * (1.0 + 0.25 * t), Color(_color.r, _color.g, _color.b, 0.62 * a))
	draw_circle(Vector2(-0.4, -0.6), s * 0.6, Color(_rim.r, _rim.g, _rim.b, 0.55 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One paw of the hidden trail: a pad and four toes, bright and faintly glowing, easing in as it is laid
## and fading out slowly at the end of its long life.
func _draw_scent(pr: Dictionary, p: Vector2, t: float) -> void:
	var a := minf(1.0, pr["age"] * 1.5) * (1.0 - smoothstep(0.55, 1.0, t))
	if a <= 0.01:
		return
	var s: float = pr["size"]
	var dir: Vector2 = pr["dir"]
	var side := dir.orthogonal()
	var c := Color(_scent_color.r, _scent_color.g, _scent_color.b, 0.9 * a)
	SoftGlow.draw(self, p, s * 5.0, Color(_scent_color.r, _scent_color.g, _scent_color.b, 0.3 * a), 0.5)
	draw_circle(p, s * 0.9, c)
	for k in 4:
		var f := float(k) - 1.5
		draw_circle(p + dir * (s * 1.7 - absf(f) * 0.5) + side * (f * s * 0.75), s * 0.45, c)
