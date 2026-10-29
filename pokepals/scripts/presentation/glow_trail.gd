class_name GlowTrail
extends Node2D
## Footsteps of light: on a world whose atmosphere asks for them (Nocthollow's moss), everyone who
## walks — you, your companion, and every friend and their companion — leaves a trail of small glowing
## prints that bloom where a foot lands and fade away over a few seconds. Lives under WorldArt, so the
## prints lie on the ground beneath every character and tree.
##
## Pure presentation: each frame it reads where the walkers are (a Callable the world controller
## hands it, returning the actor nodes), drops a print every `spacing` px one of them travels
## (alternating left/right foot across its heading), and draws/ages them. Nothing is networked —
## a friend's prints appear because their puppet walks across OUR ground.

const MAX_PRINTS := 320

var _walkers: Callable
var _color := Color(0.5, 1.0, 0.9)
var _life := 5.0
var _spacing := 14.0
var _prints: Array = []        # [ { pos: Vector2, age: float, size: float } ]
var _last: Dictionary = {}     # instance_id -> { pos: Vector2, foot: int }


## cfg is the atmosphere's "footprints" block: { color, life, spacing }. walkers() returns the
## Node2D actors to follow (re-asked every frame, so peers who come and go are picked up).
func setup(cfg: Dictionary, walkers: Callable) -> void:
	_walkers = walkers
	_color = WorldData.to_color(cfg.get("color", [0.5, 1.0, 0.9]))
	_life = maxf(0.5, float(cfg.get("life", 5.0)))
	_spacing = maxf(4.0, float(cfg.get("spacing", 14.0)))


func _process(delta: float) -> void:
	if not _walkers.is_valid():
		return
	for i in range(_prints.size() - 1, -1, -1):
		_prints[i]["age"] += delta
		if _prints[i]["age"] >= _life:
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
		_prints.append({ "pos": feet + side, "age": 0.0, "size": 1.6 if small else 2.2 })
		rec["pos"] = feet
		rec["foot"] = 1 - int(rec["foot"])
		if _prints.size() > MAX_PRINTS:
			_prints.remove_at(0)
	for id in _last.keys():
		if not seen.has(id):
			_last.erase(id)
	queue_redraw()


func _draw() -> void:
	var vis := ViewCull.visible_world_rect(self, 40.0)
	var cull := vis.has_area()
	for pr in _prints:
		var p: Vector2 = pr["pos"]
		if cull and not vis.has_point(p):
			continue
		var t: float = pr["age"] / _life
		# a quick bloom as the foot lands, then a long, soft fade
		var a := (1.0 - t) * (1.0 - t) * minf(1.0, pr["age"] * 8.0 + 0.4)
		var s: float = pr["size"]
		SoftGlow.draw(self, p, s * 4.5, Color(_color.r, _color.g, _color.b, 0.35 * a), 0.5)
		draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
		draw_circle(Vector2.ZERO, s, Color(_color.r, _color.g, _color.b, 0.9 * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
