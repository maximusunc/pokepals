class_name ShadowCast
extends RefCounted
## The geometry of Lanternfold's shadows, as pure logic (no nodes). One great LANTERN stands on the ground in
## front of a cliff-face SCREEN. Anything standing between the lantern and the screen throws a shadow onto
## the face, exactly as a lamp on a stage floor would:
##
##   * the shadow is the sprite scaled by  s = D / d,  where D is the lantern's distance from the screen's
##     foot and d its distance from the thing casting it (so it grows as the thing nears the lantern, and
##     is life-size at the screen itself);
##   * it lands at  x = lantern.x + (thing.x - lantern.x) * s  along the face: it slides the way the thing
##     does, magnified about the lantern's own line;
##   * its feet are at  v = z * s  up the face, where z is how high the thing is held. Everything stands on
##     the ground (z = 0), so its shadow stands on the foot of the face; only something held ALOFT (a bird's
##     shadow, see `hover` in the spec) throws a shadow up the face, mid-air. That is why only the bird can
##     fill the mural's gap: the missing figure is in flight.
##
## `face` is { x0, x1, base_y, height } (world px: the face spans x0..x1 and rises `height` above base_y).
## `lantern` is the lantern's ground point; it lies south of base_y (larger y), the thing between them.
## Nothing here knows about sprites: the presentation scales whatever it draws by `s`.

## Nearer than this to the lantern (px) and a thing blocks its light outright, so no shadow is cast.
const MIN_D := 20.0
## The biggest a shadow may grow to (a thing right beside the lantern): beyond it no shadow is cast.
const MAX_SCALE := 6.0


## The shadow of a thing standing at ground point `at` held `z` px off the ground:
## { ok, s, x, v, on_face } . ok is false when it is not between lantern and screen (south of the lantern, past
## the screen's foot, or so near the lantern it would be enormous); on_face is whether the shadow's centre
## lands within the face.
static func project(face: Dictionary, lantern: Vector2, at: Vector2, z: float = 0.0) -> Dictionary:
	var base_y := float(face["base_y"])
	var big_d := lantern.y - base_y
	var d := lantern.y - at.y
	if big_d <= MIN_D or d < MIN_D or d > big_d + 0.001:
		return { "ok": false, "s": 0.0, "x": 0.0, "v": 0.0, "on_face": false }
	var s := big_d / d
	if s > MAX_SCALE:
		return { "ok": false, "s": s, "x": 0.0, "v": 0.0, "on_face": false }
	var x := lantern.x + (at.x - lantern.x) * s
	return {
		"ok": true, "s": s, "x": x, "v": z * s,
		"on_face": x >= float(face["x0"]) and x <= float(face["x1"]),
	}


## The inverse: the ground point whose shadow has scale `s` and lands at face-x `x`.
static func ground_for(face: Dictionary, lantern: Vector2, x: float, s: float) -> Vector2:
	var big_d := lantern.y - float(face["base_y"])
	var d := big_d / maxf(s, 0.001)
	return Vector2(lantern.x + (x - lantern.x) / maxf(s, 0.001), lantern.y - d)


## The face's point (world px) for a shadow's (x, v): v is up from the foot.
static func face_point(face: Dictionary, x: float, v: float) -> Vector2:
	return Vector2(x, float(face["base_y"]) - v)


## Whether `at` is in the lantern's light at all: between the lantern and the screen's foot, within the
## cone that reaches the face's two ends (a thing outside it throws its shadow off the edge).
static func in_cone(face: Dictionary, lantern: Vector2, at: Vector2) -> bool:
	var p := project(face, lantern, at, 0.0)
	return bool(p["ok"]) and bool(p["on_face"])
