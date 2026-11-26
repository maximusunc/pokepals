class_name CrowdBudget
extends RefCounted
## Which other players THIS client draws, and how (docs/scaling-design.md, SC-2 "a client drawing budget").
## A phone cannot draw hundreds of people and their companions, so every peer gets a tier:
##   FULL:   drawn as today, the person and their companion (the nearest `full` peers);
##   LITE:   the person only, no companion and nothing in their hands (the next `lite`);
##   HIDDEN: in sight but past the budget, so not drawn;
##   OUT:    out of sight. In a crowd world (a `cell` size) that is anyone whose last known spot is more than
##           one interest cell from ours, since the server stops telling us about them. Everywhere, it is
##           also anyone we have never had a position for.
##
## Pure logic: positions in, tiers out, no nodes. The presentation (PresenceDirector) asks on a slow timer,
## a few times a second, and spawns or frees puppets to match. One ask sorts the peers in sight once or
## twice, so it is O(n log n), and the sort itself runs natively.
##
## Hysteresis, so a peer near a cut does not flicker between tiers as people mill about:
##   - Rank: a peer already in a tier counts as nearer than it is when that tier is filled again: its
##     distance is cut by STICKY_SHARE and then by STICKY_PX. A newcomer takes its place only when clearly
##     nearer, never for a step or two.
##   - Sight: a peer already in sight stays in sight until its spot is CELL_MARGIN_SHARE of a cell past
##     the edge of the 3 x 3 block of cells round us; a new one must be inside the block itself.
## The tier counts never exceed `full` and `lite`, whatever the hysteresis does.

const FULL := 0
const LITE := 1
const HIDDEN := 2
const OUT := 3

const DEFAULT_FULL := 40
const DEFAULT_LITE := 80
const STICKY_SHARE := 0.15
const STICKY_PX := 40.0
const CELL_MARGIN_SHARE := 0.2

## The interest cell size in px, or 0 for a world with no interest cells (everyone is in sight).
var cell := 0.0
## How many peers are drawn fully, and how many more as the person only.
var full := DEFAULT_FULL
var lite := DEFAULT_LITE

# Each peer's tier from the last ask (only peers that were passed in), for the hysteresis.
var _tiers: Dictionary = {}


func _init(settings: Dictionary = {}) -> void:
	configure(settings)


## Read a world spec's `crowd` block ({ cell, full, lite }), untrusted: anything missing or junk falls back
## to no interest cells and the default budget, so a world with no block behaves as every world did.
static func settings_from(block: Variant) -> Dictionary:
	var out := { "cell": 0.0, "full": DEFAULT_FULL, "lite": DEFAULT_LITE }
	if not (block is Dictionary):
		return out
	var b := block as Dictionary
	if _is_number(b.get("cell")) and float(b["cell"]) > 0.0:
		out["cell"] = float(b["cell"])
	if _is_number(b.get("full")):
		out["full"] = maxi(0, int(b["full"]))
	if _is_number(b.get("lite")):
		out["lite"] = maxi(0, int(b["lite"]))
	return out


## Adopt settings as settings_from returns them (or a raw `crowd` block). Keeps the tiers already given.
func configure(settings: Dictionary) -> void:
	var s := settings if settings.has("cell") and settings.has("full") and settings.has("lite") else settings_from(settings)
	cell = float(s["cell"])
	full = int(s["full"])
	lite = int(s["lite"])


## Give every peer its tier. `peers` is { id: last known position (Vector2) } for every peer we have a
## position for; a peer we have none for is simply left out (it is OUT). Returns { id: tier } for every id
## passed in, and remembers it for the next ask's hysteresis.
func rank(local: Vector2, peers: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var ids: Array = peers.keys()
	var block := Rect2()
	var block_grown := Rect2()
	if cell > 0.0:
		var c := Vector2(floorf(local.x / cell), floorf(local.y / cell))
		block = Rect2((c - Vector2.ONE) * cell, Vector2.ONE * cell * 3.0)
		block_grown = block.grow(cell * CELL_MARGIN_SHARE)
	# The peers in sight, with their distances (index-aligned with `ids`; -1 for out of sight).
	var dist := PackedFloat32Array()
	dist.resize(ids.size())
	var prev := PackedByteArray()
	prev.resize(ids.size())
	var positions: Array = peers.values()
	var in_sight := 0
	for i in ids.size():
		var p: Variant = positions[i]
		var was: int = _tiers.get(ids[i], OUT)
		prev[i] = was
		if not (p is Vector2):
			dist[i] = -1.0
			out[ids[i]] = OUT
			continue
		if cell > 0.0 and not (block_grown if was != OUT else block).has_point(p):
			dist[i] = -1.0
			out[ids[i]] = OUT
			continue
		dist[i] = local.distance_to(p)
		in_sight += 1
	# FULL: the nearest `full`, incumbents counted a little nearer.
	var rest: Array = _fill(ids, dist, prev, out, FULL, FULL, full, in_sight)
	# LITE: the nearest `lite` of the rest; anyone drawn last time (in either tier) is an incumbent.
	_fill(ids, dist, prev, out, LITE, LITE, lite, rest.size(), rest)
	for i in ids.size():
		if not out.has(ids[i]):
			out[ids[i]] = HIDDEN
	_tiers = out
	return out


## The tier a peer got on the last ask (OUT if it was not in it).
func tier_of(id: String) -> int:
	return int(_tiers.get(id, OUT))


## How many peers got each tier on the last ask: [full, lite, hidden, out].
func counts() -> Array:
	var c := [0, 0, 0, 0]
	for id in _tiers:
		c[int(_tiers[id])] += 1
	return c


## Put up to `cap` of the candidates in `tier`, nearest first, incumbents (last tier at or below `sticky`, so
## FULL counts for LITE too) counted as nearer. `candidates` are indices into ids/dist/prev (every peer in
## sight when empty and `count` is not 0). Returns the indices left over, in no particular order.
func _fill(ids: Array, dist: PackedFloat32Array, prev: PackedByteArray, out: Dictionary, tier: int, sticky: int, cap: int, count: int, candidates: Array = []) -> Array:
	var pool: Array = candidates
	if pool.is_empty() and count > 0:
		for i in ids.size():
			if dist[i] >= 0.0:
				pool.append(i)
	if pool.size() <= cap:
		for i in pool:
			out[ids[i]] = tier
		return []
	# Sort (score, index) pairs natively: Vector2 orders by x, then y, so ties fall back to the index.
	var keyed: Array = []
	keyed.resize(pool.size())
	for k in pool.size():
		var i: int = pool[k]
		var d: float = dist[i]
		if prev[i] <= sticky:
			d = d * (1.0 - STICKY_SHARE) - STICKY_PX
		keyed[k] = Vector2(d, i)
	keyed.sort()
	var rest: Array = []
	for k in keyed.size():
		var i := int((keyed[k] as Vector2).y)
		if k < cap:
			out[ids[i]] = tier
		else:
			rest.append(i)
	return rest


static func _is_number(v: Variant) -> bool:
	return v is float or v is int
