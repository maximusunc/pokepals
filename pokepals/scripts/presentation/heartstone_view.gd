class_name HeartstoneView
extends Node2D
## THE UNFINISHED (Glintwold's secret) on screen: a great rose-quartz stone hanging in loose flat shards over
## the Turning Floor. A y-sorted node in the Scenery layer, its origin the stone's foot, so you walk behind it
## from the north and in front of it from the south. Pure presentation: the FacetsDirector hands it each
## shard's offset and each half's closeness (from the pure FacetJoin) and it only draws.
##
##   * each shard hovers with its own slow bob and a little tilt while it is apart, eases toward where it is
##     told to be (so nothing jumps when a friend steps onto a mark), and settles quickly when its half clicks
##     home, with a small brightening pulse;
##   * shards are tinted faintly aqua ("you") or gold ("companion"), and brighten as their half nears home;
##   * on completion: they snap shut, a flash, a band of light runs across every face, and (the first time)
##     one small bright chip drops to the ground at `chip_to` (`chip_landed`); then the whole stone stands there.
##
## Art: data/gw_heartstone.json lists each shard's file and home (world px from the foot), and
## assets/gw_heart_whole.png is the closed stone; drawn at half size with linear filtering (@2x art). Until
## that art exists, or if it goes missing, the shards are flat-shaded polygons in the same colours.
## Cost: nothing is done while the stone is off screen and still; on screen it is a dozen draw calls.

signal chip_landed(pos: Vector2)

const HEART_JSON := "res://data/gw_heartstone.json"
const TINT_YOU := Color(0.749, 0.937, 0.949)       # #BFEFF2
const TINT_COMPANION := Color(1.0, 0.890, 0.651)   # #FFE3A6
const RAMP := [Color(0.718, 0.478, 0.620), Color(0.914, 0.663, 0.753), Color(0.980, 0.816, 0.863), Color(1.0, 0.914, 0.933)]
const SHADOW := Color(0.227, 0.290, 0.420, 0.18)  # #3A4A6B at 18%
const LIGHT := Vector2(-0.70, -0.72)               # the light comes from the upper left
const SNAP_T := 0.16
const SWEEP_T := 1.3
const CHIP_AT := 0.55
const CHIP_FALL := 0.7

## The fallback stone: points (local to the foot; it floats, its lowest point 18 px up) and nine facets.
const _PTS := {
	"t": Vector2(0, -150), "a": Vector2(-30, -124), "b": Vector2(28, -128), "c": Vector2(50, -106),
	"d": Vector2(-50, -88), "e": Vector2(-4, -98), "f": Vector2(48, -78), "g": Vector2(-42, -46),
	"h": Vector2(6, -56), "i": Vector2(40, -40), "z": Vector2(0, -18),
}
const _FACETS := [
	{ "pts": ["t", "a", "e"], "owner": "companion", "depth": 0.6 },
	{ "pts": ["t", "e", "b"], "owner": "you", "depth": -0.5 },
	{ "pts": ["b", "e", "f", "c"], "owner": "companion", "depth": 0.9 },
	{ "pts": ["a", "d", "e"], "owner": "you", "depth": -0.8 },
	{ "pts": ["d", "g", "h"], "owner": "companion", "depth": 0.4 },
	{ "pts": ["e", "h", "i", "f"], "owner": "you", "depth": 1.0 },
	{ "pts": ["g", "z", "h"], "owner": "you", "depth": -0.3 },
	{ "pts": ["h", "z", "i"], "owner": "companion", "depth": -0.9 },
	{ "pts": ["d", "h", "e"], "owner": "you", "depth": 0.2 },
]
## Depths for art shards whose data file doesn't give one (by index).
const _ART_DEPTHS := [0.6, -0.5, 0.9, -0.8, 0.4, 1.0, -0.3, -0.9, 0.2]

## [{ home: Vector2, owner, depth, poly: PackedVector2Array (around home) | tex: Texture2D, color, phase, tilt }]
var shards: Array = []
var _whole_tex: Texture2D = null
var _whole_rect := Rect2()
var _shadow_tex: Texture2D = null
var _shadow_rect := Rect2()
var _cur: Array = []          # each shard's drawn offset now (eased toward _want)
var _want: Array = []
var _close := { "you": 0.0, "companion": 0.0 }
var _home := { "you": false, "companion": false }
var _pulse := { "you": 0.0, "companion": 0.0 }
var _time := 0.0
var _whole := false           # closed: one stone for the rest of the visit
var _anim := -1.0             # seconds into the closing (-1: not closing)
var _with_chip := false
var _chip_to := Vector2.ZERO  # world point
var _chip_done := false
var _active := false          # someone is near (the director is feeding it): worth easing every frame
var _top := -150.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if shards.is_empty():
		build()


## Load the art (or the fallback facets). Returns the shard list for FacetJoin: [{ home, depth, owner }].
func build() -> Array:
	shards = []
	var data: Dictionary = {}
	if FileAccess.file_exists(HEART_JSON):
		data = WorldData.load_json(HEART_JSON)
	var list: Array = data.get("shards", [])
	var ok := not list.is_empty()
	var art: Array = []
	# depth: the art's own numbers (bigger = nearer the camera), brought to -1..1 round their middle
	var lo := INF
	var hi := -INF
	for s in list:
		if s is Dictionary and (s as Dictionary).has("depth"):
			lo = minf(lo, float(s["depth"]))
			hi = maxf(hi, float(s["depth"]))
	_top = 0.0
	for i in list.size():
		var s: Dictionary = list[i]
		var path := _res(String(s.get("file", "")))
		if path == "" or not ResourceLoader.exists(path) or not s.has("offset") or not s.has("size"):
			ok = false
			break
		var size := WorldData.to_vec2(s["size"])
		var top_left := WorldData.to_vec2(s["offset"])
		var home := WorldData.to_vec2(s["center"]) if s.has("center") else top_left + size * 0.5
		var depth := _ART_DEPTHS[i % _ART_DEPTHS.size()] as float
		if s.has("depth") and hi > lo:
			depth = (float(s["depth"]) - (hi + lo) * 0.5) / ((hi - lo) * 0.5)
		art.append({
			"home": home, "owner": "companion" if String(s.get("half", s.get("owner", "you"))) == "companion" else "you",
			"depth": depth, "tex": load(path), "rect": Rect2(top_left - home, size),
		})
		_top = minf(_top, top_left.y)
	if ok:
		shards = art
		_whole_tex = null
		_whole_rect = Rect2()
		var whole: Variant = data.get("whole", {})
		if whole is Dictionary and ResourceLoader.exists(_res(String(whole.get("file", "")))) and whole.has("offset") and whole.has("size"):
			_whole_tex = load(_res(String(whole["file"])))
			_whole_rect = Rect2(WorldData.to_vec2(whole["offset"]), WorldData.to_vec2(whole["size"]))
		_shadow_tex = null
		var sh: Variant = data.get("shadow", {})
		if sh is Dictionary and ResourceLoader.exists(_res(String(sh.get("file", "")))) and sh.has("offset") and sh.has("size"):
			_shadow_tex = load(_res(String(sh["file"])))
			_shadow_rect = Rect2(WorldData.to_vec2(sh["offset"]), WorldData.to_vec2(sh["size"]))
	else:
		_build_fallback()
	for i in shards.size():
		var sh: Dictionary = shards[i]
		sh["phase"] = float(i) * 1.73
		sh["tilt"] = (0.05 if i % 2 == 0 else -0.04) * (1.0 + 0.25 * float(i % 3))
	_cur.resize(shards.size())
	_want.resize(shards.size())
	for i in shards.size():
		_cur[i] = Vector2.ZERO
		_want[i] = Vector2.ZERO
	queue_redraw()
	return shards.map(func(s: Dictionary) -> Dictionary: return { "home": s["home"], "depth": s["depth"], "owner": s["owner"] })


static func _res(f: String) -> String:
	if f == "":
		return ""
	return f if f.begins_with("res://") else "res://assets/" + f


func _build_fallback() -> void:
	_whole_tex = null
	_shadow_tex = null
	_top = -150.0
	var axis := Vector2(0, -84)
	for i in _FACETS.size():
		var f: Dictionary = _FACETS[i]
		var pts := PackedVector2Array()
		var c := Vector2.ZERO
		for k in f["pts"]:
			pts.append(_PTS[k])
			c += _PTS[k]
		c /= float(pts.size())
		var local := PackedVector2Array()
		for p in pts:
			local.append(p - c)
		# shade by how the face turns to the light: its outward lean from the stone's axis, toward the upper left
		var lean := (c - axis) / 60.0
		var b := clampf(0.55 + 0.42 * lean.dot(LIGHT.normalized()) + (float(i % 3) - 1.0) * 0.09, 0.0, 1.0)
		shards.append({ "home": c, "owner": f["owner"], "depth": f["depth"], "poly": local, "color": _ramp(b) })


static func _ramp(b: float) -> Color:
	var x := clampf(b, 0.0, 1.0) * float(RAMP.size() - 1)
	var i := mini(int(x), RAMP.size() - 2)
	return (RAMP[i] as Color).lerp(RAMP[i + 1], x - float(i))


## Each shard's offset from home and each half's state (closeness 0..1, home). Called while someone is near.
func set_state(offsets: Array, closeness: Dictionary, home: Dictionary) -> void:
	if _whole:
		return
	_active = true
	for i in mini(offsets.size(), _want.size()):
		_want[i] = offsets[i]
	for half in ["you", "companion"]:
		var h := bool(home.get(half, false))
		if h and not bool(_home[half]):
			_pulse[half] = 1.0
		_home[half] = h
		_close[half] = float(closeness.get(half, 0.0))


## Where the shards hang before anyone comes near (their resting spread), set at once with no easing.
func set_rest(offsets: Array) -> void:
	for i in mini(offsets.size(), _want.size()):
		_want[i] = offsets[i]
		_cur[i] = offsets[i]
	queue_redraw()


## Nobody near: the director stops feeding it, and it rests where it was last told.
func set_idle() -> void:
	_active = false


## The stone closes. `with_chip`: the offcut drops to `chip_to` (world) at the end (not on a replay).
func complete(with_chip: bool, chip_to: Vector2) -> void:
	if _whole:
		return
	_whole = true
	_anim = 0.0
	_with_chip = with_chip
	_chip_to = chip_to
	_chip_done = not with_chip
	for half in ["you", "companion"]:
		_close[half] = 1.0
		_home[half] = true


## Already whole (no animation): for tests and a rebuilt world.
func set_whole() -> void:
	_whole = true
	_anim = -1.0
	_chip_done = true
	for i in _cur.size():
		_cur[i] = Vector2.ZERO
	queue_redraw()


func is_whole() -> bool:
	return _whole


func is_animating() -> bool:
	return _anim >= 0.0


func _on_screen() -> bool:
	var vp := get_viewport()
	if vp == null:
		return true
	var inv := vp.get_canvas_transform().affine_inverse()
	var rect := inv * Rect2(Vector2.ZERO, vp.get_visible_rect().size)
	return rect.grow(120.0).intersects(Rect2(global_position + Vector2(-90, _top - 40.0), Vector2(180, -_top + 60.0)))


func _process(delta: float) -> void:
	if _anim < 0.0 and not _on_screen():
		return
	_time += delta
	if _anim >= 0.0:
		_anim += delta
		var chip_end := CHIP_AT + CHIP_FALL
		if not _chip_done and _anim >= chip_end:
			_chip_done = true
			chip_landed.emit(_chip_to)
		if _anim >= maxf(SWEEP_T + 0.2, chip_end if _with_chip else 0.0):
			_anim = -1.0
	for half in ["you", "companion"]:
		_pulse[half] = maxf(0.0, float(_pulse[half]) - delta * 2.2)
	if _whole:
		var k := clampf(_anim / SNAP_T, 0.0, 1.0) if _anim >= 0.0 else 1.0
		for i in _cur.size():
			_cur[i] = (_cur[i] as Vector2).lerp(Vector2.ZERO, k * k)
	else:
		for i in _cur.size():
			var rate := 18.0 if bool(_home[String(shards[i]["owner"])]) else 7.0
			_cur[i] = (_cur[i] as Vector2).lerp(_want[i], 1.0 - exp(-delta * rate))
	queue_redraw()


func _draw() -> void:
	if shards.is_empty():
		return
	var spread := 0.0
	for o in _cur:
		spread = maxf(spread, (o as Vector2).length())
	# a flat, hard-edged shadow on the floor, wider while the pieces are apart
	var sw := 46.0 + spread * 0.9
	var shadow := PackedVector2Array()
	for k in 8:
		var a := float(k) / 8.0 * TAU + PI / 8.0
		shadow.append(Vector2(cos(a) * sw, sin(a) * sw * 0.34 + 2.0))
	if _shadow_tex != null:
		draw_texture_rect(_shadow_tex, _shadow_rect, false)
	else:
		draw_colored_polygon(shadow, SHADOW)

	var whole_bob := sin(_time * 0.8) * 1.5
	var snapped := _whole and (_anim < 0.0 or _anim >= SNAP_T)
	if snapped and _whole_tex != null:
		var g := 1.0 + _sweep_glow(_whole_rect.get_center()) * 0.4
		draw_texture_rect(_whole_tex, Rect2(_whole_rect.position + Vector2(0, whole_bob), _whole_rect.size), false, Color(g, g, g, 1.0))
	else:
		for i in shards.size():
			_draw_shard(i, whole_bob)
	if _anim >= 0.0:
		_draw_closing()


func _draw_shard(i: int, whole_bob: float) -> void:
	var sh: Dictionary = shards[i]
	var owner := String(sh["owner"])
	var apart := 0.0 if _whole else 1.0 - float(_close[owner])
	var bob := whole_bob if _whole else sin(_time * 0.9 + float(sh["phase"])) * (0.6 + 2.6 * apart)
	var at: Vector2 = (sh["home"] as Vector2) + (_cur[i] as Vector2) + Vector2(0, bob)
	var rot := float(sh["tilt"]) * apart + sin(_time * 0.5 + float(sh["phase"])) * 0.02 * apart
	var tint: Color = TINT_YOU if owner == "you" else TINT_COMPANION
	var tint_k := 0.0 if _whole or sh.has("tex") else 0.22 * apart + 0.1   # the art comes tinted already
	var bright := 0.0 if _whole else 0.22 * float(_close[owner]) + 0.35 * float(_pulse[owner])
	bright += _sweep_glow(sh["home"])
	if sh.has("tex"):
		var tex: Texture2D = sh["tex"]
		var g := 1.0 + bright * 0.6
		draw_set_transform(at, rot, Vector2.ONE)
		draw_texture_rect(tex, sh["rect"], false, Color(g, g, g, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var base: Color = (sh["color"] as Color).lerp(tint, tint_k).lerp(Color.WHITE, clampf(bright, 0.0, 1.0))
	var poly := PackedVector2Array()
	var t := Transform2D(rot, at)
	for p in sh["poly"]:
		poly.append(t * p)
	draw_colored_polygon(poly, base)


## How much the band of light running across the faces lights a point (local) right now (0..1).
func _sweep_glow(p: Vector2) -> float:
	if _anim < SNAP_T:
		return 0.0
	var u := (_anim - SNAP_T) / (SWEEP_T - SNAP_T)
	if u > 1.0:
		return 0.0
	# the band runs from the lit upper left to the lower right, across the stone's height
	var along := (p - Vector2(0, _top * 0.5)).dot(-LIGHT.normalized()) / (-_top * 0.8)   # about -0.6..0.6
	var band := lerpf(-0.8, 0.8, u)
	return exp(-pow((along - band) / 0.16, 2.0)) * 0.85


## The flash as they close, and the chip dropping to the floor.
func _draw_closing() -> void:
	var mid := Vector2(0, _top * 0.52)
	if _anim >= SNAP_T * 0.6:
		var f := clampf(1.0 - (_anim - SNAP_T * 0.6) / 0.55, 0.0, 1.0)
		SoftGlow.draw(self, mid, 110.0 * (1.2 - 0.4 * f), Color(1.0, 0.97, 0.98, 0.75 * f))
		SoftGlow.draw(self, mid, 46.0, Color(1, 1, 1, 0.9 * f * f))
	if _with_chip and _anim >= CHIP_AT and not _chip_done:
		var u := clampf((_anim - CHIP_AT) / CHIP_FALL, 0.0, 1.0)
		var from := Vector2(0, -24)
		var to := _chip_to - global_position
		var p := from.lerp(to, u)
		p.y -= sin(u * PI) * 26.0   # a little arc as it drops away from the stone
		OffcutDraw.draw_chip(self, p, 0.9, _time)
