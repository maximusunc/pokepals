class_name PortalView
extends Node2D
## One doorway between worlds, standing in the y-sorted Scenery layer: the small mossy stone ring that
## is every world's way home ("portal"), or the Vale's grand carved arch, the Gateway ("gateway").
## Its origin is the portal's world point, at its foot, the same anchor the player and the trees use,
## so you pass in front of it on the near side and behind it on the far side. (Before, portals were
## painted flat into WorldArt underneath everyone, so a player walking behind the Gateway stood on it.)
##
## Pure presentation: it holds a colour and a clock and paints itself. Walking into it is the world
## controller's business (its _portals list), not this node's.
##
## Layers, back to front (all from one canvas baked by tools/gen_portal.py, so they line up):
##   halo (a soft light, linear-filtered, behind)  <  swirl (grayscale, tinted, animated)
##   <  frame (the stonework, untinted)  <  runes (a glow mask, tinted, breathing)  <  rising motes.
## The ground pool of light under it is WorldArt's (it must sit under the actors). With no art, a
## procedural doorway stands in so a world never loses its way home.

const GATEWAY_HUE_SPEED := 0.012  # turns of the colour wheel per second: one slow lap in ~80 s
const CULL_MARGIN := 160.0
const GROUND_Y := 8.0  # the house ground plane: sprites' feet sit this far below their origin

var kind := "portal"          # "portal" (the small ring) or "gateway" (the Vale's arch)
var color := Color(0.74, 0.66, 0.96)

var _frame_tex: Texture2D = null
var _swirl_tex: Texture2D = null
var _runes_tex: Texture2D = null
var _frames := 8
var _fps := 8.0
var _anchor_y := 57.0             # the canvas row that stands on the ground plane (origin + 8)
var _opening := Vector2(0, -18)     # the doorway's centre, relative to the foot
var _opening_r := Vector2(11.5, 18.5)
var _motes := 7
var _frame_tint := Color(1, 1, 1)
var _time := 0.0
var _phase := 0.0
var _halo: DrawProxy


## Set it up from the art style's entity for this kind. Call before adding it to the tree.
func setup(p_kind: String, p_color: Color, style: ArtStyle) -> void:
	kind = p_kind
	color = p_color
	var cfg: Dictionary = style.entity(kind) if style != null else {}
	_frame_tex = SpriteSlot.resolve(cfg, "frame")
	_swirl_tex = SpriteSlot.resolve(cfg, "swirl")
	_runes_tex = SpriteSlot.resolve(cfg, "runes")
	_frames = maxi(1, int(cfg.get("frames", 8)))
	_fps = float(cfg.get("fps", 8.0))
	var big := kind == "gateway"
	_anchor_y = float(cfg.get("anchor_y", 130.0 if big else 57.0))
	var op: Array = cfg.get("opening", [0, -46, 21, 38] if big else [0, -18, 11.5, 18.5])
	_opening = Vector2(float(op[0]), float(op[1]))
	_opening_r = Vector2(float(op[2]), float(op[3]))
	_motes = int(cfg.get("motes", 16 if big else 7))
	if cfg.has("frame_tint"):
		_frame_tint = WorldData.to_color(cfg["frame_tint"])
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The halo is drawn by a linear-filtered child BEHIND this node, so the soft light stays smooth
	# while the stonework stays crisp pixel art.
	_halo = DrawProxy.new()
	_halo.show_behind_parent = true
	_halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_halo.draw_fn = _draw_halo
	add_child(_halo)


func _ready() -> void:
	_phase = fposmod(position.x * 0.013 + position.y * 0.007, TAU)


func _process(delta: float) -> void:
	_time += delta
	var vis := ViewCull.visible_world_rect(self, CULL_MARGIN)
	if vis.has_area() and not vis.has_point(position):
		return  # off-screen: keep the clock running, skip the redraw
	queue_redraw()
	_halo.queue_redraw()


## The colour the doorway glows this instant. A small portal is its own colour; the Gateway leads
## everywhere, so it drifts slowly all the way round the colour wheel, starting from its own hue.
func current_tint() -> Color:
	return PortalView.tint_at(kind, color, _time)


static func tint_at(p_kind: String, base: Color, t: float) -> Color:
	if p_kind != "gateway":
		return base
	return Color.from_hsv(fposmod(base.h + t * GATEWAY_HUE_SPEED, 1.0), maxf(base.s, 0.32), maxf(base.v, 0.9))


func _breathe(speed: float) -> float:
	return 0.5 + 0.5 * sin(_time * speed + _phase)


func _draw_halo(ci: CanvasItem) -> void:
	var c := current_tint()
	var b := _breathe(1.6)
	var r := maxf(_opening_r.x, _opening_r.y)
	SoftGlow.draw(ci, _opening, r * (1.9 + 0.15 * b), Color(c.r, c.g, c.b, 0.20 + 0.08 * b), 0.85)
	SoftGlow.draw(ci, _opening, r * 1.05, Color(c.r, c.g, c.b, 0.22 + 0.10 * b), _opening_r.y / maxf(1.0, r) * 0.9)


func _draw() -> void:
	var c := current_tint()
	if _frame_tex == null:
		_draw_procedural(c)
		_draw_motes(c)
		return
	var sz := _frame_tex.get_size()
	# Plant it like every other sprite: its foot row lands on the shared ground plane 8 px below the
	# origin (SpriteSlot.draw, the props, the player), so it stands on the ground beside the actors.
	var top_left := Vector2(-sz.x * 0.5, GROUND_Y - _anchor_y)
	# the energy: one frame of the swirl sheet, tinted, ticking round at _fps
	if _swirl_tex != null:
		# cross-fade each frame into the next, so even a slow turn glides instead of ticking
		var tf := _time * _fps + _phase
		var f := int(floor(tf)) % _frames
		var blend := tf - floor(tf)
		var dest := Rect2(top_left, sz)
		draw_texture_rect_region(_swirl_tex, dest, Rect2(Vector2(f * sz.x, 0), sz), Color(c.r, c.g, c.b, 1.0))
		var f2 := (f + 1) % _frames
		draw_texture_rect_region(_swirl_tex, dest, Rect2(Vector2(f2 * sz.x, 0), sz), Color(c.r, c.g, c.b, blend))
		# a hot, breathing heart
		var hb := _breathe(2.2)
		draw_circle(_opening, 2.0 + 1.2 * hb, Color(1, 1, 1, 0.35 + 0.25 * hb))
	draw_texture(_frame_tex, top_left, _frame_tint)
	# the runes glow in the portal's colour, lifted toward white so they read as light on stone
	if _runes_tex != null:
		var rb := _breathe(1.3)
		var lit := c.lerp(Color(1, 1, 1), 0.45)
		draw_texture(_runes_tex, top_left, Color(lit.r, lit.g, lit.b, 0.45 + 0.55 * rb))
	_draw_motes(c)


## Sparks of the portal's light rising through the doorway and a little way above it, each on its
## own loop (deterministic per index, so no state to keep): born low in the opening, drifting up and
## swaying, brightest mid-flight, gone before they leave it.
func _draw_motes(c: Color) -> void:
	var lit := c.lerp(Color(1, 1, 1), 0.6)
	var rise := _opening_r.y * 2.4
	var floor_y := _opening.y + _opening_r.y * 0.9
	for i in _motes:
		var k := float(i) * 12.9898
		var speed := 0.22 + 0.12 * fposmod(sin(k) * 43758.5453, 1.0)
		var life := fposmod(_time * speed + float(i) / float(_motes) + _phase, 1.0)
		var x0 := (fposmod(sin(k * 1.7) * 24634.6345, 1.0) * 2.0 - 1.0) * _opening_r.x * 0.75
		var x := x0 * (1.0 - 0.35 * life) + sin(_time * 1.8 + k) * 1.6
		var y := floor_y - life * rise
		var a := sin(life * PI)
		var s := 2.0 if i % 3 == 0 else 1.0
		draw_rect(Rect2(Vector2(roundf(_opening.x + x), roundf(y)), Vector2(s, s)), Color(lit.r, lit.g, lit.b, 0.85 * a))


## No baked art: a simple stone frame round a breathing oval, so the doorway still stands and glows.
func _draw_procedural(c: Color) -> void:
	var b := _breathe(2.0)
	var stone := Color(0.6, 0.6, 0.56) * _frame_tint
	draw_set_transform(_opening, 0.0, Vector2(1.0, _opening_r.y / _opening_r.x))
	draw_circle(Vector2.ZERO, _opening_r.x + 5.0, stone.darkened(0.2))
	draw_circle(Vector2.ZERO, _opening_r.x + 3.5, stone)
	draw_circle(Vector2.ZERO, _opening_r.x, Color(c.r, c.g, c.b, 0.9))
	draw_circle(Vector2.ZERO, _opening_r.x * (0.55 + 0.1 * b), c.lerp(Color(1, 1, 1), 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if kind == "gateway":
		# the lintel and steps of the old standing-stone gate
		draw_rect(Rect2(_opening + Vector2(-_opening_r.x - 10, -_opening_r.y - 12), Vector2(_opening_r.x * 2 + 20, 8)), stone)
		draw_rect(Rect2(Vector2(-_opening_r.x - 14, -4), Vector2(_opening_r.x * 2 + 28, 6)), stone.darkened(0.1))
