class_name MistVeil
extends CanvasLayer
## STEAMHOLLOW's fog: a drifting mist over the whole view that limits how far you can see, so the
## bathhouse village is somewhere you get pleasantly lost in. assets/mist.gdshader runs on a ColorRect
## inside a SMALL off-screen SubViewport (about one texel per `texel` world px), and a TextureRect stretches
## that render over the view with smooth filtering: mist is soft, so it needs no more detail, and the
## shader runs per fog texel rather than per screen pixel. On a CanvasLayer above the world, below the
## vignette and the HUD. Pure presentation: no collision, no network.
##
## The layer FOLLOWS THE VIEWPORT (Godot's `follow_viewport_enabled`: the layer is drawn with the camera's
## transform, like the world itself), and the rect is laid over the view in world px each frame, with a
## margin. So the clear patch round the player is positioned in the same space the player is drawn in,
## and can't lag or jitter behind them when the camera eases. It also updates late in the frame
## (`process_priority`), after the player and the camera have moved.
##
## Tuned by the world's `atmosphere.fog` block (all optional, these are the defaults):
##   enabled        true            false turns it off
##   texel          4               world px per texel of the small fog render (bigger: cheaper, softer)
##   clear_radius   60              world px of clear view round you (about two steps)...
##   fade_radius    210             ...and where the mist reaches full density
##   color          [r,g,b]         the mist's colour; warm: the colour of mist lit by a lamp
##   density        0.92            the strongest the mist gets (under 1 so far silhouettes still hint)
##   swirl          0.35            how much it billows and mottles
##   noise_scale    0.011           size of the billows (cycles per world px)
##   drift          [7, 3]          the mist's slow slide, px per second
##   fade_in        2.5             seconds to thicken on arrival (a gentle start, not a slammed door)
##   light_clear    0.9             how much a lit pocket thins the mist at its heart
##   max_lights     8               MOVING pockets at once (the shader's loop): companion, friends, extras
##   companion_radius 56  friend_radius 46   the pockets round your companion and everyone else present
##   lit            { "prop_types": { type: { radius, warm, y } }, "buildings": { radius, warm, y } }
##                  what shines through the mist: lantern props, and each building's door. These never
##                  move, so they're baked ONCE into a low-res light mask over the whole world (one
##                  lookup per pixel, however many there are; none pop in as you approach), not looped.
## A caller can add moving pockets (the bell's glint) through the `extra` Callable given to setup(),
## returning [{ pos: Vector2, radius: float, warm: float }].

const SHADER := preload("res://assets/mist.gdshader")
const HARD_MAX_LIGHTS := 8
## Default world px per fog texel. The mist is soft, so it is rendered small into an off-screen
## SubViewport and stretched over the view with smooth filtering: the shader runs once per texel, not
## once per screen pixel (tens of times fewer on a phone). The atmosphere's `texel` overrides it.
const FOG_TEXEL := 4.0
## World px per texel of the static-light mask (the pockets are soft, so a coarse mask is plenty).
const MASK_TEXEL := 4.0
## World px of extra mist laid round the view, so a camera a frame behind never shows an uncovered edge.
const MARGIN := 96.0

var _rect: TextureRect         # shows the small fog render, stretched over the view in world px
var _sub: SubViewport          # where the fog is rendered, small
var _fog: ColorRect            # the shader's quad, inside _sub
var _texel := FOG_TEXEL
var _mat: ShaderMaterial
var _player: Node2D
var _walkers: Callable
var _extra: Callable
var _static: Array = []        # [{ pos: Vector2, radius: float, warm: float }] lit things in the world
var _drift_dir := Vector2(7.0, 3.0)
var _drift := Vector2.ZERO
var _time := 0.0
var _fade_in := 2.5
var _max_lights := HARD_MAX_LIGHTS
var _companion_radius := 56.0
var _friend_radius := 46.0
var _enabled := true


func _init() -> void:
	layer = 1
	follow_viewport_enabled = true
	process_priority = 1000   # after the player and the camera have moved this frame


## cfg: the atmosphere's fog block. data: the world spec (for the lit props and buildings). player: the
## local avatar the clear patch follows. walkers: Callable returning the actors present (as GlowTrail's).
func setup(cfg: Dictionary, data: Dictionary, player: Node2D, walkers: Callable, extra: Callable = Callable()) -> void:
	_player = player
	_walkers = walkers
	_extra = extra
	_enabled = bool(cfg.get("enabled", true))
	if not _enabled:
		visible = false
		return
	_texel = maxf(1.0, float(cfg.get("texel", FOG_TEXEL)))
	# The fog renders into a small off-screen SubViewport (a render target of its own)...
	_sub = SubViewport.new()
	_sub.name = "FogRender"
	_sub.transparent_bg = true
	_sub.disable_3d = true
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.size = Vector2i(8, 8)
	add_child(_sub)
	_fog = ColorRect.new()
	_fog.name = "Fog"
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_fog.material = _mat
	_sub.add_child(_fog)
	# ...and this rect shows it, stretched over the view with smooth filtering. The shader writes
	# premultiplied alpha (so the soft edges don't darken), so it is composited that way too.
	_rect = TextureRect.new()
	_rect.name = "Rect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.texture = _sub.get_texture()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rect.material = blend
	add_child(_rect)
	_mat.set_shader_parameter("clear_r", float(cfg.get("clear_radius", 60.0)))
	_mat.set_shader_parameter("fade_r", float(cfg.get("fade_radius", 210.0)))
	_mat.set_shader_parameter("fog_color", WorldData.to_color(cfg.get("color", [0.84, 0.84, 0.91])))
	_mat.set_shader_parameter("warm_color", WorldData.to_color(cfg.get("warm", [1.0, 0.80, 0.52])))
	_mat.set_shader_parameter("density", float(cfg.get("density", 0.92)))
	_mat.set_shader_parameter("swirl", float(cfg.get("swirl", 0.35)))
	_mat.set_shader_parameter("noise_scale", float(cfg.get("noise_scale", 0.011)))
	_mat.set_shader_parameter("light_clear", float(cfg.get("light_clear", 0.9)))
	_drift_dir = WorldData.to_vec2(cfg.get("drift", [7.0, 3.0]))
	_fade_in = maxf(0.0, float(cfg.get("fade_in", 2.5)))
	_max_lights = clampi(int(cfg.get("max_lights", HARD_MAX_LIGHTS)), 1, HARD_MAX_LIGHTS)
	_companion_radius = float(cfg.get("companion_radius", 56.0))
	_friend_radius = float(cfg.get("friend_radius", 46.0))
	_collect_static(cfg.get("lit", {}), data)
	_bake_mask(data)
	_mat.set_shader_parameter("strength", 0.0 if _fade_in > 0.0 else 1.0)
	_time = 0.0


## Everything in the world that shines through the mist, found once from the spec.
func _collect_static(lit: Dictionary, data: Dictionary) -> void:
	_static.clear()
	var types: Dictionary = lit.get("prop_types", {})
	if not types.is_empty():
		for p in data.get("props", []):
			var t := String(p.get("type", ""))
			if types.has(t):
				var c: Dictionary = types[t]
				_static.append({ "pos": WorldData.to_vec2(p["position"]) + Vector2(0.0, float(c.get("y", -16.0))),
					"radius": float(c.get("radius", 110.0)), "warm": float(c.get("warm", 1.0)) })
	var bc: Dictionary = lit.get("buildings", {})
	if not bc.is_empty():
		for b in data.get("buildings", []):
			var r: Array = b["rect"]
			_static.append({ "pos": Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3])) + Vector2(0.0, float(bc.get("y", -18.0))),
				"radius": float(bc.get("radius", 130.0)), "warm": float(bc.get("warm", 0.8)) })


## Paint every static light's pocket into a low-res mask over the world (r: how much it thins the mist,
## g: its warmth), once. Overlaps keep the stronger. A world with none still gets a blank mask, so the
## sampler never falls back to white (which would clear the whole veil).
func _bake_mask(data: Dictionary) -> void:
	var bounds: Dictionary = data.get("bounds", {})
	var lo := WorldData.to_vec2(bounds.get("min", [0, 0])) - Vector2(256.0, 256.0)
	var hi := WorldData.to_vec2(bounds.get("max", [0, 0])) + Vector2(256.0, 256.0)
	var w := 1
	var h := 1
	if not _static.is_empty() and hi.x > lo.x and hi.y > lo.y:
		w = int(ceil((hi.x - lo.x) / MASK_TEXEL))
		h = int(ceil((hi.y - lo.y) / MASK_TEXEL))
	var img := Image.create_empty(w, h, false, Image.FORMAT_RG8)
	for l in _static:
		var pos: Vector2 = l["pos"]
		var r := float(l["radius"])
		var warm := float(l["warm"])
		var cx := (pos.x - lo.x) / MASK_TEXEL
		var cy := (pos.y - lo.y) / MASK_TEXEL
		var rt := r / MASK_TEXEL
		for ty in range(maxi(0, floori(cy - rt)), mini(h, ceili(cy + rt) + 1)):
			for tx in range(maxi(0, floori(cx - rt)), mini(w, ceili(cx + rt) + 1)):
				var d := Vector2(tx + 0.5 - cx, ty + 0.5 - cy).length() * MASK_TEXEL
				var k := 1.0 - smoothstep(0.0, r, d)
				k = k * k
				if k <= 0.0:
					continue
				var old := img.get_pixel(tx, ty)
				img.set_pixel(tx, ty, Color(maxf(old.r, k), maxf(old.g, k * warm), 0.0))
	_mat.set_shader_parameter("light_mask", ImageTexture.create_from_image(img))
	_mat.set_shader_parameter("mask_origin", lo)
	_mat.set_shader_parameter("mask_size", Vector2(w, h) * MASK_TEXEL)


func static_light_count() -> int:
	return _static.size()


func _process(delta: float) -> void:
	if not _enabled or _mat == null or _player == null or not is_instance_valid(_player):
		return
	_time += delta
	_drift += _drift_dir * delta
	var vp := get_viewport()
	var ct := vp.get_canvas_transform()
	var size := vp.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# Cover the view (in world px) plus a margin; the layer draws it with the camera's transform.
	var inv := ct.affine_inverse()
	var view := Rect2(inv * Vector2.ZERO, Vector2.ZERO).expand(inv * size).grow(MARGIN)
	# The small render's grid is pinned to the world (its origin snapped to whole texels), so the soft fog
	# texels stay put as you walk instead of shimmering; and the render only ever GROWS (with a little
	# headroom), so it is not reallocated every frame as the view's size wobbles by a fraction of a texel.
	var origin := (view.position / _texel).floor() * _texel
	var need := Vector2i(ceili((view.end.x - origin.x) / _texel) + 1, ceili((view.end.y - origin.y) / _texel) + 1)
	if need.x > _sub.size.x or need.y > _sub.size.y:
		_sub.size = Vector2i(maxi(_sub.size.x, need.x + 16), maxi(_sub.size.y, need.y + 16))
		_fog.size = Vector2(_sub.size)
	var cover := Vector2(_sub.size) * _texel
	_rect.position = origin
	_rect.size = cover
	_mat.set_shader_parameter("rect_origin", origin)
	_mat.set_shader_parameter("rect_size", cover)
	_mat.set_shader_parameter("center", _player.global_position)
	_mat.set_shader_parameter("drift", _drift)
	_mat.set_shader_parameter("time", _time)
	if _fade_in > 0.0:
		_mat.set_shader_parameter("strength", smoothstep(0.0, 1.0, clampf(_time / _fade_in, 0.0, 1.0)))
	var pockets := _gather()
	var packed := PackedVector4Array()
	packed.resize(HARD_MAX_LIGHTS)
	for i in pockets.size():
		packed[i] = pockets[i]
	_mat.set_shader_parameter("lights", packed)
	_mat.set_shader_parameter("light_count", pockets.size())


## The MOVING pockets for this frame as world-space vec4s (x, y, radius, warmth, all world px): your
## companion, everyone else, and the caller's extras. The static lights are baked into the mask.
func _gather() -> Array:
	var out: Array = []
	for w in _walkers.call():
		if w == _player or not (w is Node2D):
			continue
		var r := _companion_radius if w is CompanionView else _friend_radius
		out.append(_pocket((w as Node2D).global_position + Vector2(0.0, -6.0), r, 0.0))
		if out.size() >= _max_lights:
			return out
	if _extra.is_valid():
		for e in _extra.call():
			out.append(_pocket(e["pos"], float(e["radius"]), float(e.get("warm", 1.0))))
			if out.size() >= _max_lights:
				return out
	return out   # the static lights are in the baked mask


static func _pocket(world: Vector2, radius: float, warm: float) -> Vector4:
	return Vector4(world.x, world.y, radius, warm)
