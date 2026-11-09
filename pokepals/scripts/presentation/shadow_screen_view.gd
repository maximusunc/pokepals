class_name ShadowScreenView
extends BuildingView
## LANTERNFOLD's SCREEN: a great pale cliff face standing at the north end of the stage, on which everything in
## the lantern's light throws its shadow. A BuildingView (so it is a y-sorted, solid mass like the other
## cliffs), chosen by a spec's `"view": "shadow_screen"` (Scenery.add_buildings). The face carries the MURAL:
## a night sky of paper clouds, a moon, a village on cut hills, and a flock of birds crossing it, one of them
## missing. Spec keys read here (beyond BuildingView's rect / h):
##   lantern [x, y]      the great lantern's ground point (for how the face is lit)
##   door {x, w, h}      a door in the cliff's foot, x relative to the centre: a hairline seam until the mural is
##                       complete, then it opens on warm light
## Everything on it is flat, cut-paper and dark umber on warm cream:
##   * the STATIC face (this node's _draw): the cliff mass, the paper face lit from the lantern's side, the
##     hills, houses, trees, moon, clouds and stars. Drawn once; it never queues a redraw;
##   * the FLOCK (a child): the mural's birds, drawn from the bird's own sheet so they are the very shape the
##     bird form's shadow has, flapping slowly; plus the GHOST of the missing one, a pale bird-shaped hole in the
##     paper with a halo that warms as a shadow comes close to filling it (`set_fit`);
##   * the SHADOWS (children, one per caster): ShadowPuppets, silhouetted and clipped to the face by the
##     silhouette shader (assets/silhouette.gdshader);
##   * the DOOR and the burst of light when the gap is filled.
## Pure presentation: whether a shadow fills the gap is MuralGuide's call; the director tells this node.

const MASS := Color(0.16, 0.075, 0.065)
const MASS_LIT := Color(0.34, 0.17, 0.12)
const PAPER := Color(0.97, 0.84, 0.60)
const INK := Color(0.19, 0.085, 0.07)
const SHADOW_SHADER := preload("res://assets/silhouette.gdshader")
const FLAP_FPS := 4.0

var _guide: MuralGuide = null
var _bird: Dictionary = {}              # { tex, sheet } of the bird sheet (drawn for the flock and the ghost)
var _lantern := Vector2.ZERO            # the lantern's ground point, world px
var _face: Dictionary = {}
var _door := Rect2()                    # the door, in local px
var _ink_mat: ShaderMaterial
var _ghost_mat: ShaderMaterial
var _flock_fx: Node2D
var _ghost_fx: Node2D
var _door_fx: Node2D
var _puppets: Dictionary = {}           # caster instance id -> ShadowPuppet
var _fit := 0.0                         # eased 0..1 how nearly a shadow fills the gap
var _fit_target := 0.0
var _filling := 0.0                     # 0..1 hold progress
var _done := false
var _done_t := 0.0                      # seconds since the gap was filled (drives the burst and the door)
var _door_open := 0.0                   # 0..1
var _clock := 0.0
var _flap_col := -1
var _fx_dirty := true
var _gap_world := Vector2.ZERO          # the gap's centre on the face, world px


func setup(s: Dictionary, style: ArtStyle) -> void:
	super.setup(s, style)
	_lantern = WorldData.to_vec2(s.get("lantern", [position.x, position.y + 190.0]))
	var d: Dictionary = s.get("door", {})
	if not d.is_empty():
		var dw := float(d.get("w", 30.0))
		var dh := float(d.get("h", 46.0))
		_door = Rect2(float(d.get("x", 0.0)) - dw * 0.5, -dh, dw, dh)
	_ink_mat = _make_mat(INK)
	_ghost_mat = _make_mat(Color(1.0, 0.96, 0.80))
	_flock_fx = Node2D.new()
	_flock_fx.name = "Flock"
	_flock_fx.material = _ink_mat
	_flock_fx.draw.connect(_draw_flock)
	add_child(_flock_fx)
	_ghost_fx = Node2D.new()
	_ghost_fx.name = "Ghost"
	_ghost_fx.material = _ghost_mat
	_ghost_fx.draw.connect(_draw_ghost)
	add_child(_ghost_fx)
	_door_fx = Node2D.new()
	_door_fx.name = "DoorFx"
	_door_fx.draw.connect(_draw_door_fx)
	add_child(_door_fx)
	var r: Array = s["rect"]
	# the face in world px: x0..x1 across, base_y at the foot, `h` up
	_face = { "x0": float(r[0]), "x1": float(r[0]) + float(r[2]), "base_y": position.y, "height": wall_h }
	var clip := Vector4(_face["x0"], position.y - wall_h, _face["x1"], position.y + 2.0)
	_ink_mat.set_shader_parameter("clip", clip)
	_ghost_mat.set_shader_parameter("clip", clip)


func _make_mat(col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADOW_SHADER
	m.set_shader_parameter("shadow_color", col)
	return m


## Nothing walkable lies behind a screen, so it never hides anyone.
func occludes(_p: Vector2) -> bool:
	return false


## The face, in world px: { x0, x1, base_y, height }.
func face_rect() -> Dictionary:
	return _face


## Hand the screen the mural's logic and the bird sheet its birds are drawn from.
func bind_mural(guide: MuralGuide, bird_sheet: Dictionary) -> void:
	_guide = guide
	_bird = bird_sheet
	var t: Dictionary = guide.target()
	if bool(t.get("ok", false)):
		_gap_world = ShadowCast.face_point(_face, float(t["x"]), float(t["v"]))
	_fx_dirty = true


## Where the door is, in world px: the middle of its foot.
func door_foot() -> Vector2:
	return position + Vector2(_door.position.x + _door.size.x * 0.5, 0.0)


func gap_world() -> Vector2:
	return _gap_world


## How nearly a shadow fills the gap (0..1) and how far through the hold it is (0..1), from the guide.
func set_fit(fit: float, filling: float) -> void:
	_fit_target = clampf(fit, 0.0, 1.0)
	_filling = clampf(filling, 0.0, 1.0)


## The gap is filled: ink spreads into it, a burst of light, the door opens. `snap`: it was filled on an earlier
## visit, so it is simply so.
func complete(snap: bool = false) -> void:
	if _done:
		return
	_done = true
	_done_t = 99.0 if snap else 0.0
	if snap:
		_door_open = 1.0
	_fx_dirty = true


func is_done() -> bool:
	return _done


func door_open_amount() -> float:
	return _door_open


## One shadow per caster (a player or a companion): add the ones we do not yet have, drop the ones that went.
## `casters` is [{ node: Node2D, kind: "player" | "companion" }].
func sync_casters(casters: Array) -> void:
	var seen := {}
	for c in casters:
		var node: Node2D = c["node"]
		if not is_instance_valid(node):
			continue
		var id := node.get_instance_id()
		seen[id] = true
		if not _puppets.has(id):
			var p := ShadowPuppet.new()
			p.caster = node
			p.kind = String(c["kind"])
			p.material = _ink_mat
			p.visible = false
			add_child(p)
			_puppets[id] = p
	for id in _puppets.keys():
		if not seen.has(id):
			var p: ShadowPuppet = _puppets[id]
			if is_instance_valid(p):
				p.queue_free()
			_puppets.erase(id)


## How many shadows are being cast right now (tests, the smoke check).
func shadows_cast() -> int:
	var n := 0
	for p in _puppets.values():
		if is_instance_valid(p) and (p as ShadowPuppet).visible:
			n += 1
	return n


## The shadow node of a caster, for the checks.
func puppet_of(node: Node) -> ShadowPuppet:
	return _puppets.get(node.get_instance_id())


func tick(delta: float, t: float, want_fade: bool) -> void:
	super.tick(delta, t, want_fade)
	if delta <= 0.0:
		return
	_clock += delta
	_update_puppets(delta)
	_fit = move_toward(_fit, _fit_target, delta * 3.0)
	if _done:
		_done_t += delta
		_door_open = clampf((_done_t - 1.0) / 2.4, 0.0, 1.0)
	var col := int(_clock * FLAP_FPS)
	if col != _flap_col or _fx_dirty:
		_flap_col = col
		_flock_fx.queue_redraw()
		_ghost_fx.queue_redraw()
	# the ghost breathes; its fade-out as the gap fills is a modulate, so it costs no redraw
	_ghost_fx.modulate.a = (0.80 + 0.20 * sin(_clock * 2.0)) * (1.0 - (smoothstep(0.0, 1.0, _done_t / 1.5) if _done else 0.0))
	if _fit > 0.01 or _fit_target > 0.01 or _done or _fx_dirty:
		_door_fx.queue_redraw()
	_fx_dirty = false


## Project every caster onto the face and place its shadow (hidden when it is not in the lantern's light).
func _update_puppets(delta: float) -> void:
	if _guide == null:
		return
	for id in _puppets:
		var p: ShadowPuppet = _puppets[id]
		if not is_instance_valid(p) or p.caster == null or not is_instance_valid(p.caster):
			continue
		p.observe(delta)
		var c := _guide.cast_of(p.species if p.kind == "companion" else "player", p.caster.position)
		var ok := bool(c["ok"]) and bool(c["on_face"]) and (p.kind != "companion" or not p.species.is_empty())
		p.visible = ok
		if not ok:
			continue
		var s := float(c["s"])
		# the sprite's origin sits 8 px above its feet: put the FEET at (x, -v) on the face
		p.position = Vector2(float(c["x"]) - position.x, -float(c["v"]) - 8.0 * s)
		p.scale = Vector2(s, s)
		p.queue_redraw()


# ── the static face ───────────────────────────────────────────────────────────────────────────────────
func _draw() -> void:
	var hh := wall_h
	# the cliff mass round the face, with a lit rim along its top and a ragged crown
	draw_rect(Rect2(-hw - 12.0, -hh - depth - 10.0, hw * 2.0 + 24.0, hh + depth + 10.0), MASS)
	draw_rect(Rect2(-hw - 12.0, -hh - depth - 10.0, hw * 2.0 + 24.0, 3.0), MASS_LIT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7117
	var x := -hw - 12.0
	while x < hw + 12.0:
		var w := rng.randf_range(10.0, 26.0)
		var h := rng.randf_range(2.0, 9.0)
		draw_rect(Rect2(x, -hh - depth - 10.0 - h, w, h + 1.0), MASS)
		x += w
	# the paper face: the world's face tile, tinted warm, lit brightest along the lantern's line and
	# falling off toward the edges and the top
	var lx := _lantern.x - position.x
	var strip := 10.0
	var sx := -hw
	while sx < hw:
		var w2 := minf(strip, hw - sx)
		var mid := sx + w2 * 0.5
		var k := clampf(1.0 - absf(mid - lx) / (hw * 1.5), 0.0, 1.0)
		var col := Color(PAPER.r * (0.78 + 0.22 * k), PAPER.g * (0.76 + 0.24 * k), PAPER.b * (0.72 + 0.28 * k))
		if _wall_tex != null:
			draw_texture_rect(_wall_tex, Rect2(sx, -hh, w2, hh), true, col)
		else:
			draw_rect(Rect2(sx, -hh, w2, hh), col)
		sx += strip
	for i in 6:                                         # a darkening toward the top, in a few soft steps
		draw_rect(Rect2(-hw, -hh + float(i) * 5.0, hw * 2.0, 5.0), Color(0.30, 0.12, 0.06, 0.20 - float(i) * 0.034))
	draw_rect(Rect2(-hw, -hh, 3.0, hh), Color(0.30, 0.12, 0.06, 0.28))              # the frame's inner shade
	draw_rect(Rect2(hw - 3.0, -hh, 3.0, hh), Color(0.30, 0.12, 0.06, 0.28))
	draw_rect(Rect2(-hw, -hh, hw * 2.0, 2.0), Color(0.30, 0.12, 0.06, 0.40))
	_draw_sky(hh)
	_draw_hills(hh)
	draw_rect(Rect2(-hw - 12.0, -2.0, hw * 2.0 + 24.0, 3.0), MASS)                  # the lip at the foot
	_draw_door_seams()


func _face_color_at(x: float) -> Color:
	var lx := _lantern.x - position.x
	var k := clampf(1.0 - absf(x - lx) / (hw * 1.5), 0.0, 1.0)
	return Color(PAPER.r * (0.78 + 0.22 * k), PAPER.g * (0.76 + 0.24 * k), PAPER.b * (0.72 + 0.28 * k))


func _draw_sky(hh: float) -> void:
	# the moon: a pale disc with a bite taken out of it
	var mp := Vector2(-hw * 0.72, -hh * 0.74)
	draw_circle(mp, 17.0, Color(1.0, 0.95, 0.74))
	draw_circle(mp + Vector2(7.0, -3.0), 14.5, _face_color_at(mp.x + 7.0))
	# paper clouds: rows of dark scallops, the way a shadow-theatre sky is cut
	for row in [[-26.0, -hh * 0.86, 5, 6.0], [hw * 0.34, -hh * 0.72, 4, 5.0], [-hw * 0.5, -hh * 0.52, 3, 4.5]]:
		var cx: float = row[0]
		var cy: float = row[1]
		for i in int(row[2]):
			var r: float = float(row[3]) * (1.0 + 0.25 * sin(float(i) * 1.9))
			draw_circle(Vector2(cx + float(i) * r * 1.5, cy - r * 0.2 * float(i % 2)), r, INK)
		draw_rect(Rect2(cx - 2.0, cy, float(row[2]) * float(row[3]) * 1.5 + 4.0, 2.0), INK)
	# stars: four-point specks of gold
	var rng := RandomNumberGenerator.new()
	rng.seed = 313
	for i in 14:
		var p := Vector2(rng.randf_range(-hw + 12.0, hw - 12.0), -rng.randf_range(hh * 0.45, hh - 10.0))
		var s := rng.randf_range(1.2, 2.4)
		var c := Color(0.96, 0.66, 0.16, 0.9)
		draw_rect(Rect2(p.x - s, p.y - 0.5, s * 2.0, 1.0), c)
		draw_rect(Rect2(p.x - 0.5, p.y - s, 1.0, s * 2.0), c)


func _hill_v(x: float) -> float:
	return 13.0 + 7.0 * sin(x * 0.031 + 0.5) + 5.0 * sin(x * 0.093 + 1.7)


func _draw_hills(hh: float) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(-hw, 0.0))
	var x := -hw
	var dx0 := _door.position.x - 4.0
	var dx1 := _door.position.x + _door.size.x + 4.0
	while x <= hw:
		var v := _hill_v(x)
		if _door.size.x > 0.0 and x > dx0 and x < dx1:
			v = 0.0       # a notch of bare paper where the door is
		pts.append(Vector2(x, -v))
		x += 4.0
	pts.append(Vector2(hw, 0.0))
	draw_colored_polygon(pts, INK)
	# the little village on the hills: cut houses with a lit window each, and a few pines and a tower
	var seeds := [[-hw * 0.84, 0], [-hw * 0.64, 1], [-hw * 0.36, 2], [hw * 0.30, 1], [hw * 0.56, 0], [hw * 0.80, 2]]
	for sd in seeds:
		var bx: float = sd[0]
		if _door.size.x > 0.0 and absf(bx - (_door.position.x + _door.size.x * 0.5)) < 30.0:
			continue
		var by := -_hill_v(bx) + 1.0
		match int(sd[1]):
			0:   # a house
				draw_rect(Rect2(bx - 8.0, by - 11.0, 16.0, 12.0), INK)
				draw_colored_polygon(PackedVector2Array([Vector2(bx - 10.0, by - 11.0), Vector2(bx, by - 21.0), Vector2(bx + 10.0, by - 11.0)]), INK)
				draw_rect(Rect2(bx - 3.0, by - 8.0, 4.0, 4.0), Color(1.0, 0.82, 0.38))
			1:   # a pine, three paper tiers
				for tier in 3:
					var ty := by - float(tier) * 7.0
					var tw := 9.0 - float(tier) * 2.5
					draw_colored_polygon(PackedVector2Array([Vector2(bx - tw, ty), Vector2(bx, ty - 11.0), Vector2(bx + tw, ty)]), INK)
				draw_rect(Rect2(bx - 1.0, by, 2.0, 3.0), INK)
			_:   # a tower with a lit window
				draw_rect(Rect2(bx - 5.0, by - 26.0, 10.0, 27.0), INK)
				draw_colored_polygon(PackedVector2Array([Vector2(bx - 7.0, by - 26.0), Vector2(bx, by - 36.0), Vector2(bx + 7.0, by - 26.0)]), INK)
				draw_rect(Rect2(bx - 1.5, by - 20.0, 3.0, 4.0), Color(1.0, 0.82, 0.38))


## The door's hairline seams, drawn in the paper's own colour a shade darker: easy to miss, easy to find.
func _draw_door_seams() -> void:
	if _door.size.x <= 0.0:
		return
	var c := Color(0.55, 0.30, 0.16, 0.55)
	var r := _door
	var arch := r.size.x * 0.5
	var pts := PackedVector2Array()
	pts.append(Vector2(r.position.x, 0.0))
	pts.append(Vector2(r.position.x, r.position.y + arch))
	for i in 9:
		var a := PI + PI * float(i) / 8.0
		pts.append(Vector2(r.position.x + arch + cos(a) * arch, r.position.y + arch + sin(a) * arch))
	pts.append(Vector2(r.position.x + r.size.x, 0.0))
	draw_polyline(pts, c, 1.0)
	draw_line(Vector2(r.position.x + arch, r.position.y), Vector2(r.position.x + arch, 0.0), Color(c.r, c.g, c.b, 0.35), 1.0)


# ── the flock and the ghost ───────────────────────────────────────────────────────────────────────────
## The mural's other birds, relative to the gap: [dx, dv, scale relative to the gap bird].
const FLOCK := [
	[-148.0, -18.0, 0.42], [-108.0, -8.0, 0.52], [-70.0, 2.0, 0.66], [-34.0, 8.0, 0.84],
	[36.0, 6.0, 0.84], [74.0, 14.0, 0.66], [112.0, 24.0, 0.52], [146.0, 36.0, 0.42],
	[-84.0, 46.0, 0.36], [22.0, 54.0, 0.40], [96.0, 62.0, 0.34],
]


func _bird_frame() -> int:
	var cols := maxi(1, int((_bird.get("sheet", {}) as Dictionary).get("cols", 8)))
	return int(_clock * FLAP_FPS) % cols


## One bird of the bird sheet's fly row at world-relative face point (x, v) (feet), at `s` times its size.
func _put_bird(ci: CanvasItem, x: float, v: float, s: float, col: int, flip: bool = false) -> void:
	var tex: Texture2D = _bird.get("tex")
	if tex == null:
		return
	var sheet: Dictionary = _bird["sheet"]
	var frame: Array = sheet.get("frame", [32, 32])
	var fw := float(frame[0])
	var fh := float(frame[1])
	var row := maxi(0, int(sheet.get("fly_row", 5)))
	ci.draw_set_transform(Vector2(x, -v - 8.0 * s), 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture_rect_region(tex, Rect2(-fw * 0.5 * s, 8.0 * s - fh * s, fw * s, fh * s), Rect2(float(col) * fw, float(row) * fh, fw, fh))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _target_local() -> Array:
	# the gap bird's (x, v, s) in the face's own space
	if _guide == null or not bool(_guide.target().get("ok", false)):
		return []
	var t: Dictionary = _guide.target()
	return [float(t["x"]) - position.x, float(t["v"]), float(t["s"])]


func _draw_flock() -> void:
	var t := _target_local()
	if t.is_empty() or _bird.is_empty():
		return
	var base_col := _bird_frame()
	for i in FLOCK.size():
		var f: Array = FLOCK[i]
		var s: float = float(t[2]) * float(f[2])
		_put_bird(_flock_fx, float(t[0]) + float(f[0]), float(t[1]) + float(f[1]), s, (base_col + i * 3) % 8, i % 5 == 4)
	if _done:
		# ink spreads into the gap: the missing bird is part of the flock now
		_put_bird(_flock_fx, float(t[0]), float(t[1]), float(t[2]), base_col)


func _draw_ghost() -> void:
	var t := _target_local()
	if t.is_empty() or _bird.is_empty():
		return
	# the hole in the paper: a warm halo-bird a touch bigger behind, then the pale bird-shape itself
	_put_bird(_ghost_fx, float(t[0]), float(t[1]), float(t[2]) * 1.0, _bird_frame())


# ── the glow, the door and the burst ──────────────────────────────────────────────────────────────────
func _draw_door_fx() -> void:
	var t := _target_local()
	if not t.is_empty():
		var centre := Vector2(float(t[0]), -float(t[1]) - 12.0 * float(t[2]))
		var size := 14.0 * float(t[2])
		var warm := Color(1.0, 0.68, 0.22)
		var amount := _fit if not _done else 0.0
		# a halo that warms as a shadow nears the gap, and swells a little while it is being held
		SoftGlow.draw(_door_fx, centre, size * (1.9 + 0.5 * _filling), Color(warm.r, warm.g, warm.b, 0.10 + 0.55 * amount), 0.9)
		if _filling > 0.0 and not _done:
			SoftGlow.draw(_door_fx, centre, size * 1.2, Color(1.0, 0.9, 0.55, 0.5 * _filling), 0.9)
		if _done and _done_t < 3.0:
			var k := 1.0 - _done_t / 3.0
			SoftGlow.draw(_door_fx, centre, size * (2.0 + 2.6 * (1.0 - k)), Color(1.0, 0.86, 0.42, 0.7 * k), 0.9)
			for m in 10:
				var a := float(m) / 10.0 * TAU + 0.4
				var d := (1.0 - k) * size * 3.0
				_door_fx.draw_rect(Rect2(centre + Vector2(cos(a), sin(a)) * d - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.92, 0.6, k))
	if _door.size.x > 0.0 and _door_open > 0.0:
		var r := _door
		var o := smoothstep(0.0, 1.0, _door_open)
		var arch := r.size.x * 0.5
		var half := r.size.x * 0.5 * o
		var cx := r.position.x + arch
		var pts := PackedVector2Array()
		pts.append(Vector2(cx - half, 0.0))
		pts.append(Vector2(cx - half, r.position.y + arch))
		for i in 9:
			var a := PI + PI * float(i) / 8.0
			pts.append(Vector2(cx + cos(a) * half, r.position.y + arch + sin(a) * arch))
		pts.append(Vector2(cx + half, r.position.y + arch))
		pts.append(Vector2(cx + half, 0.0))
		_door_fx.draw_colored_polygon(pts, Color(1.0, 0.84, 0.46))
		_door_fx.draw_colored_polygon(PackedVector2Array([Vector2(cx - half * 0.55, 0.0), Vector2(cx - half * 0.55, r.position.y + arch + 6.0),
			Vector2(cx + half * 0.55, r.position.y + arch + 6.0), Vector2(cx + half * 0.55, 0.0)]), Color(1.0, 0.96, 0.78))
		SoftGlow.draw(_door_fx, Vector2(cx, -r.size.y * 0.5), r.size.y * 1.4 * o, Color(1.0, 0.8, 0.36, 0.30 * o), 0.8)
		draw_dark_leaves(o, r, cx, half)


## The door's two leaves, dark slivers at its sides, standing open.
func draw_dark_leaves(o: float, r: Rect2, cx: float, half: float) -> void:
	var edge := r.size.x * 0.5
	_door_fx.draw_rect(Rect2(cx - edge, r.position.y + edge, edge - half, -r.position.y - edge), INK)
	_door_fx.draw_rect(Rect2(cx + half, r.position.y + edge, edge - half, -r.position.y - edge), INK)
