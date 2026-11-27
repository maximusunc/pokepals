class_name SoftGlow
extends RefCounted
## A soft pool of light: one small radial-gradient texture, baked once and shared, stretched over a
## circle (or a squashed ellipse) and tinted by the caller. Cheaper and far softer than stacking
## draw_circle rings, which is what lets a whole bioluminescent world (every glowing tree, bloom,
## creature and footprint) breathe light without a lighting engine. Pure presentation.

static var _tex: GradientTexture2D


## The shared white radial falloff (opaque centre → transparent rim). Tint it with draw modulate.
static func texture() -> Texture2D:
	if _tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		# A knee partway out keeps the centre bright but lets the rim fade long and gentle.
		g.add_point(0.35, Color(1, 1, 1, 0.42))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_tex = t
	return _tex


## Draw a glow of `radius` at `center` in `color` (its alpha is the glow's strength). `squash` < 1
## flattens it into a ground-hugging ellipse (a pool of light on the moss rather than a ball).
static func draw(ci: CanvasItem, center: Vector2, radius: float, color: Color, squash := 1.0) -> void:
	if radius <= 0.0 or color.a <= 0.0:
		return
	var half := Vector2(radius, radius * squash)
	ci.draw_texture_rect(texture(), Rect2(center - half, half * 2.0), false, color)
