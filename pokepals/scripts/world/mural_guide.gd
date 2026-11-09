class_name MuralGuide
extends RefCounted
## The state of Lanternfold's secret, as pure logic (state in, state out): a SHADOW MURAL with one figure
## missing, a bird in flight. Complete it and a door in the cliff opens. The companion is the key: you choose
## its FORM, stand it in the lantern's light, and its shadow, thrown by ShadowCast onto the screen, has to fill
## the gap. No nodes: the ShadowDirector feeds it where the companion stands, what it wears and how still it is.
##
## HOW A SHADOW FILLS THE GAP. The gap is where the fill species (a bird) would throw its shadow from the
## authored `spot` (a ground point), held `hover` px aloft (a bird's shadow is mid-flight; everything else
## stands on the ground). `fit_of` scores a companion's shadow against it as
##     fit = place x shape
##   place  how near the companion stands to the spot, judged on the SCREEN (where its shadow lands, x, and how
##          big it is, s: so being a little too near the lantern or a little to one side both cost, as they
##          should), forgiving near the middle and falling to nothing at `place_tol` px / `size_tol` of scale;
##   shape  how alike the animal's silhouette is to the bird's (ShadowMask.iou on the sprite's own masks, so a
##          wolf is too big and a rabbit the wrong shape without anyone saying so).
## It FILLS only for the fill species (`species`), at fit >= `fill_threshold`, while it stands still, held for
## `hold` seconds (shorter the deeper the bond). Losing the fit drains the hold gently rather than resetting it.
##
## THE SETTLE. Standing a companion on one exact spot by tapping is a pixel-hunt, so `settle_target` pulls a
## bird that is told to stand within `settle_radius` of the spot onto it: "it shuffles to the right place".
## Only the right animal is helped, so the form still matters.
##
## THE EVENTS (one-shot strings, for the first-time hints):
##   "arrive"      you have walked into the lantern's light        "shadow"  its shadow first falls on the face
##   "close"       the shadow is nearly the gap's                   "wrong"   it stands right but wears the wrong shape
##   "holding"     it is filling the gap                            "complete" the gap is filled
## THE NOTICE (`update`): as you come near the spot, the companion stops and points at the gap on the wall for
## `notice_hold` seconds, then not again for `notice_cooldown` (range and cooldown scale with bond), the
## Riverbank / Drifthallow shape. It is a hint, never a requirement, and it stops once you are making progress.

const DEFAULTS := {
	"species": "bird",
	"hover": 18.0,              # how high (px) the fill species' shadow is held aloft
	"place_tol": 26.0,          # screen px of error at which the placement is worth nothing
	"size_tol": 0.30,           # relative error in scale at which it is worth nothing
	"fill_threshold": 0.80,
	"hold_low": 2.2,            # seconds of holding the fit to fill the gap, fresh...
	"hold_high": 1.2,           # ...and bonded
	"drain_rate": 1.5,          # how fast a lost fit drains the hold, relative to filling it
	"still_speed": 12.0,        # px/s: slower than this counts as standing still
	"settle_radius": 36.0,      # a fill-species companion told to stand this near the spot is put on it
	"close_at": 0.40,
	"wrong_place": 0.60,        # place at least this good with the wrong shape reads as "wrong shape"
	"notice_range_low": 360.0,
	"notice_range_high": 700.0,
	"notice_cooldown_low": 16.0,
	"notice_cooldown_high": 6.0,
	"notice_hold": 2.5,
}

var _face: Dictionary = {}
var _lantern := Vector2.ZERO
var _spot := Vector2.ZERO
var _cfg: Dictionary = {}
var _masks: Dictionary = {}       # species -> ShadowMask
var _target: Dictionary = {}      # the fill species' shadow from the spot
var _shape_cache: Dictionary = {} # species -> shape score (masks never change)
var _said := {}
var _hold_t := 0.0
var _done := false
var _notice_cd := 0.0
var _notice_left := 0.0
var _arrived := false
var _hold_len := 2.0              # the hold's length at the bond last seen


## reveal: the secret's reveal block ({ face, lantern, spot, ...numbers }).
func _init(reveal: Dictionary) -> void:
	_face = reveal.get("face", {})
	_lantern = WorldData.to_vec2(reveal.get("lantern", [0, 0]))
	_spot = WorldData.to_vec2(reveal.get("spot", [0, 0]))
	_cfg = DEFAULTS.duplicate()
	for k in reveal:
		_cfg[k] = reveal[k]
	_target = ShadowCast.project(_face, _lantern, _spot, float(_cfg["hover"]))


## The silhouettes of the species that can be told apart: { species: ShadowMask }.
func set_masks(masks: Dictionary) -> void:
	_masks = masks
	_shape_cache = {}


func face() -> Dictionary:
	return _face


func lantern() -> Vector2:
	return _lantern


func spot() -> Vector2:
	return _spot


func fill_species() -> String:
	return String(_cfg["species"])


## The gap's shadow: what the fill species casts from the spot ({ ok, s, x, v, on_face }).
func target() -> Dictionary:
	return _target


## How high a species' shadow is held aloft: the fill species hovers (it is in flight), everything else stands.
func hover_for(species: String) -> float:
	return float(_cfg["hover"]) if species == fill_species() else 0.0


func is_done() -> bool:
	return _done


## 0..1 progress of the hold (how much of the gap is filled in).
func filling() -> float:
	return clampf(_hold_t / maxf(0.01, _hold_len), 0.0, 1.0) if not _done else 1.0


## Seconds the fit must be held at a bond (0..1).
func hold_for(bond: float) -> float:
	return lerpf(float(_cfg["hold_low"]), float(_cfg["hold_high"]), clampf(bond, 0.0, 1.0))


## Where a companion told to stand at `want` in `species` actually settles: the spot, if it is the fill species
## and the order lands within `settle_radius` of it; otherwise just where it was told.
func settle_target(species: String, want: Vector2) -> Vector2:
	if species == fill_species() and want.distance_to(_spot) <= float(_cfg["settle_radius"]):
		return _spot
	return want


## The shadow a companion in `species` standing at `at` throws: ShadowCast.project with the species' hover.
func cast_of(species: String, at: Vector2) -> Dictionary:
	return ShadowCast.project(_face, _lantern, at, hover_for(species))


## How well that shadow fills the gap: { fit, place, shape, ok }. `ok` is false with no shadow at all.
func fit_of(species: String, at: Vector2) -> Dictionary:
	var c := cast_of(species, at)
	if not bool(c["ok"]) or not bool(_target["ok"]):
		return { "fit": 0.0, "place": 0.0, "shape": 0.0, "ok": false }
	# where it lands (x) and how big it is (s): the screen-side error, forgiving in the middle
	var ex := absf(float(c["x"]) - float(_target["x"])) / float(_cfg["place_tol"])
	var es := absf(float(c["s"]) / float(_target["s"]) - 1.0) / float(_cfg["size_tol"])
	var err := maxf(ex, es)
	var place := 1.0 - smoothstep(0.35, 1.0, err)
	var shape := _shape_of(species)
	return { "fit": place * shape, "place": place, "shape": shape, "ok": true }


## How alike a species' silhouette is to the fill species', 0..1 (1 for the fill species itself).
func _shape_of(species: String) -> float:
	if species == fill_species():
		return 1.0
	if _shape_cache.has(species):
		return float(_shape_cache[species])
	var a: ShadowMask = _masks.get(species)
	var b: ShadowMask = _masks.get(fill_species())
	var score := 0.0
	if a != null and b != null:
		var iou := maxf(ShadowMask.iou(a, 1.0, b, 1.0), ShadowMask.iou(a, 1.0, b, 1.0, true))
		score = smoothstep(0.10, 0.65, iou)
	_shape_cache[species] = score
	return score


func _once(events: Array, key: String) -> void:
	if not _said.has(key):
		_said[key] = true
		events.append(key)


## Advance by `delta`. `species` is the form the companion wears, `at` where it stands, `speed` how fast it
## moves (px/s), `player_pos` where you are. Returns:
##   { fit, place, shape, filling (0..1), events: [..], point: bool, target: Vector2 (the gap on the wall),
##     in_light: bool (the companion's shadow is on the face) }
func update(delta: float, species: String, at: Vector2, speed: float, player_pos: Vector2, bond: float) -> Dictionary:
	var events: Array = []
	_hold_len = hold_for(bond)
	var f := fit_of(species, at)
	var c := cast_of(species, at)
	var in_light := bool(c["ok"]) and bool(c["on_face"])
	if not _arrived and ShadowCast.in_cone(_face, _lantern, player_pos):
		_arrived = true
		_once(events, "arrive")
	if in_light:
		_once(events, "shadow")
	if not _done:
		var right := species == fill_species()
		var ok_fit := right and float(f["fit"]) >= float(_cfg["fill_threshold"]) and speed <= float(_cfg["still_speed"])
		if ok_fit:
			_hold_t += delta
			_once(events, "holding")
			if _hold_t >= hold_for(bond):
				_done = true
				_hold_t = hold_for(bond)
				_once(events, "complete")
		else:
			_hold_t = maxf(0.0, _hold_t - delta * float(_cfg["drain_rate"]))
		if right and float(f["fit"]) >= float(_cfg["close_at"]):
			_once(events, "close")
		if not right and float(f["place"]) >= float(_cfg["wrong_place"]) and in_light and speed <= float(_cfg["still_speed"]):
			_once(events, "wrong")
	var out := {
		"fit": float(f["fit"]), "place": float(f["place"]), "shape": float(f["shape"]), "filling": filling(),
		"events": events, "point": false, "target": ShadowCast.face_point(_face, float(_target["x"]), float(_target["v"])),
		"in_light": in_light,
	}
	# the companion noticing the gap as you come near: a held point at it, then a rest
	if _done or _hold_t > 0.0:
		_notice_left = 0.0
		return out
	var b := clampf(bond, 0.0, 1.0)
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left > 0.0:
			out["point"] = true
		else:
			_notice_cd = lerpf(float(_cfg["notice_cooldown_low"]), float(_cfg["notice_cooldown_high"]), b)
		return out
	if _notice_cd > 0.0:
		_notice_cd = maxf(0.0, _notice_cd - delta)
		return out
	if player_pos.distance_to(_spot) <= lerpf(float(_cfg["notice_range_low"]), float(_cfg["notice_range_high"]), b):
		_notice_left = float(_cfg["notice_hold"])
		out["point"] = true
		if not _said.has("notice"):
			_said["notice"] = true
			events.append("notice")
	return out
