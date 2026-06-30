class_name ViewCull
extends RefCounted
## The on-screen world rectangle, derived once per frame so the world's draw loops and the
## scenery layer can skip whatever the camera can't see. Pure presentation geometry: it reads
## the viewport's canvas transform (which already bakes in the camera's eased follow, the
## look-ahead lead, and the animating intro zoom) and inverts it to get world-space bounds —
## so it tracks the live framing with no coupling to CameraRig.
##
## FAIL-SAFE: when there's no real framing (a headless SceneTree stepping frames, a viewport
## with no size), it returns an empty rect. Callers treat "no area" as "draw everything", so
## the headless smoke tests keep rendering the whole world and never go blank.


## World-space rect the camera can currently see, grown by `margin` (so tall motifs whose feet
## sit just off-screen still draw their canopy). Returns an empty Rect2 when the framing is
## degenerate — callers should check `rect.has_area()` and skip culling when it's false.
static func visible_world_rect(ci: CanvasItem, margin: float) -> Rect2:
	if ci == null or not ci.is_inside_tree():
		return Rect2()
	var screen: Vector2 = ci.get_viewport_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return Rect2()
	# get_viewport_transform() maps world (canvas) -> screen; invert to map screen -> world.
	var inv := ci.get_viewport_transform().affine_inverse()
	# Expand over all four screen corners so the bounds stay correct even if the camera ever
	# rotates or zooms (today it only eases position + zoom, but this costs nothing extra).
	var r := Rect2(inv * Vector2.ZERO, Vector2.ZERO)
	r = r.expand(inv * Vector2(screen.x, 0.0))
	r = r.expand(inv * Vector2(0.0, screen.y))
	r = r.expand(inv * screen)
	return r.grow(margin)
