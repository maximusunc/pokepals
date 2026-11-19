class_name ViewProjection
extends RefCounted
## A camera that looks at the flat 2D world in perspective, as pure geometry: no nodes, no rendering. The world
## stays a plain 2D plane (x east, y south); this only says where a ground point would appear on screen, and
## back. Used by a perspective world's presentation (PerspectiveView) for drawing, and by anything that turns a
## screen tap into a world point. Nothing in the world's logic needs it.
##
## The model is an ordinary pinhole camera standing on the ground plane:
##   * it looks along the heading F = (0,-1) rotated by `yaw` (0 = north, +PI/2 = east), with R = F rotated a
##     quarter turn clockwise (screen right);
##   * its foot is `back` world units behind the focus point C (the point it is framed on: the player), its eye
##     `height` units up, tilted down by `pitch` radians;
##   * focal length f is set so things AT the focus are drawn at their native size (scale 1), which keeps pixel
##     art crisp where you are;
##   * `shift` slides the whole picture down the screen (a lens shift), so the horizon and the player can be
##     framed independently of the tilt.
## Screen offsets are in canvas units at zoom 1, from the CENTRE of the view (+y down).
##
## For a ground point at forward distance a (from the camera's foot, along F) and lateral b (along R):
##   z = a cos(pitch) + h sin(pitch)        depth along the line of sight
##   screen = (f b / z,  shift + f (h cos(pitch) - a sin(pitch)) / z),  scale f / z
## The horizon (a -> infinity) sits at  shift - f tan(pitch).

var height := 53.0
var back := 220.0
var pitch := 0.0
var shift := 52.0
var yaw := 0.0
var far := 1450.0  # draw distance: ground farther than this (along F, from the focus) is sky/haze
var center := Vector2.ZERO  # the focus point C, in world space
## A fixed lens (> 0): the focal length, instead of the focus's depth. Normally the focus draws at native size;
## with a fixed lens, moving the camera along its line changes nothing but how big the near things are (Farmeadow's
## picture, which must stay put while the camera comes up behind you).
var focal_override := 0.0


## Settings from a dictionary ({height, back, pitch_deg, shift, far}); missing keys keep their values.
func configure(cfg: Dictionary) -> ViewProjection:
	height = float(cfg.get("height", height))
	back = float(cfg.get("back", back))
	pitch = deg_to_rad(float(cfg.get("pitch_deg", rad_to_deg(pitch))))
	shift = float(cfg.get("shift", shift))
	far = float(cfg.get("far", far))
	return self


## Blend two settings dictionaries (t = 0 -> a, 1 -> b) into this projection (lingering eases between them).
func blend(a: Dictionary, b: Dictionary, t: float) -> ViewProjection:
	var keys := ["height", "back", "pitch_deg", "shift", "far"]
	var mixed := {}
	for key in keys:
		if a.has(key) or b.has(key):
			var va := float(a.get(key, b.get(key, 0.0)))
			var vb := float(b.get(key, va))
			mixed[key] = lerpf(va, vb, t)
	return configure(mixed)


func forward() -> Vector2:
	return Vector2(0, -1).rotated(yaw)


func right() -> Vector2:
	return Vector2(1, 0).rotated(yaw)


## The focal length: the depth of the focus point, so the focus draws at scale 1.
func focal() -> float:
	if focal_override > 0.0:
		return focal_override
	return back * cos(pitch) + height * sin(pitch)


## Screen y (from the view's centre) of the horizon.
func horizon_y() -> float:
	return shift - focal() * tan(pitch)


## Where world point p lands: Vector3(screen x, screen y, scale). scale <= 0 means behind the camera.
func project(p: Vector2) -> Vector3:
	var foot := center - forward() * back
	var rel := p - foot
	var a := rel.dot(forward())
	var b := rel.dot(right())
	var z := a * cos(pitch) + height * sin(pitch)
	if z <= 1.0:
		return Vector3(0, 0, 0)
	var f := focal()
	return Vector3(f * b / z, shift + f * (height * cos(pitch) - a * sin(pitch)) / z, f / z)


## The ground point seen at a screen offset, or null when that pixel is sky (at or above the horizon).
func unproject(screen: Vector2) -> Variant:
	var f := focal()
	var q := (screen.y - shift) / f  # = (h cos - a sin) / (a cos + h sin)
	var den := q * cos(pitch) + sin(pitch)
	if den <= 1e-6:
		return null
	var a := height * (cos(pitch) - q * sin(pitch)) / den
	var z := a * cos(pitch) + height * sin(pitch)
	var b := screen.x * z / f
	var foot := center - forward() * back
	return foot + forward() * a + right() * b


## How far ahead of the focus a point is (along F); the draw distance compares against this.
func ahead_of_focus(p: Vector2) -> float:
	return (p - center).dot(forward())


## The four ground corners of the visible area, for a view `size` (canvas units): bottom-left, bottom-right,
## then the far right and far left at the draw distance. The bottom edge is the screen's own; the far edge is
## where the ground gives way to haze.
func ground_corners(size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	var bottom_l: Variant = unproject(Vector2(-half.x, half.y))
	var bottom_r: Variant = unproject(Vector2(half.x, half.y))
	if bottom_l == null or bottom_r == null:  # tilted up so far the bottom is sky: degenerate, use the focus
		bottom_l = center
		bottom_r = center
	# The far edge, widened to what the screen's sides see at that depth.
	var a_far := back + far
	var z_far := a_far * cos(pitch) + height * sin(pitch)
	var w_far := half.x * z_far / focal()
	var foot := center - forward() * back
	var far_mid := foot + forward() * a_far
	return PackedVector2Array([bottom_l, bottom_r, far_mid + right() * w_far, far_mid - right() * w_far])


## The world-space bounding box of the visible ground (for culling).
func visible_bounds(size: Vector2) -> Rect2:
	var c := ground_corners(size)
	var r := Rect2(c[0], Vector2.ZERO)
	for i in range(1, c.size()):
		r = r.expand(c[i])
	return r


## The visible ground between two distances ahead of the camera's foot (a_near < a_far), as a rect in the
## camera's own frame (x along R, y along -F, origin at the focus), wide enough for the screen at the far end.
func band(size: Vector2, a_near: float, a_far: float) -> Rect2:
	var half_w := size.x * 0.5 * (a_far * cos(pitch) + height * sin(pitch)) / focal()
	var y_near := back - a_near  # frame y of a point a units ahead of the foot (focus at 0, ahead is negative)
	var y_far := back - a_far
	return Rect2(Vector2(-half_w, y_far), Vector2(2.0 * half_w, y_near - y_far))


## Forward distance from the camera's foot to the ground seen at the bottom of the screen.
func near_ground(size: Vector2) -> float:
	var p: Variant = unproject(Vector2(0, size.y * 0.5))
	if p == null:
		return back
	return (p - (center - forward() * back)).dot(forward())
