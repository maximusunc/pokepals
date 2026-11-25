class_name CircuitBoard
extends RefCounted
## One RIBBON BOARD (Ohmstead): a lattice of nodes, some missing, and one ribbon of light that has to be laid
## through every node that is there, from the `source` (where a live line comes in) to the `sink` (the outlet).
## It is a one-stroke puzzle with no way to lose: a ribbon can always be wound back.
##
## The rules, which the server's twin (Server.Circuit.Board) holds to the same test vectors:
##   * a node's index is row * cols + col; `holes` are indices with no node;
##   * the ribbon (`path`) starts on the source and nowhere else;
##   * from its head it runs STRAIGHT along a row or a column to the node you name, lighting every node it
##     passes; none of them may be a hole or already lit (so a ribbon never crosses or touches itself);
##   * naming a lit node winds the ribbon back to it; naming the head itself takes one node off;
##   * the board is CLOSED when every node is lit and the head is on the sink.
##
## Pure logic: no nodes, no drawing, no network. State in, state out.

var cols := 1
var rows := 1
var source := 0
var sink := 0
var path: Array[int] = []
var _holes := {}
var _lit := {}


## Build one from a dict: { cols, rows, holes: [i...], source, sink, path?: [i...] }.
static func from_dict(d: Dictionary) -> CircuitBoard:
	var b := CircuitBoard.new()
	b.cols = maxi(1, int(d.get("cols", 1)))
	b.rows = maxi(1, int(d.get("rows", 1)))
	b.source = int(d.get("source", 0))
	b.sink = int(d.get("sink", 0))
	for h in d.get("holes", []):
		b._holes[int(h)] = true
	b.set_path(d.get("path", []))
	return b


## Replace the ribbon wholesale (the server's word on where it is).
func set_path(p: Array) -> void:
	path.clear()
	_lit.clear()
	for n in p:
		path.append(int(n))
		_lit[int(n)] = true


func size() -> int:
	return cols * rows


func is_node(i: int) -> bool:
	return i >= 0 and i < cols * rows and not _holes.has(i)


func is_lit(i: int) -> bool:
	return _lit.has(i)


func live_count() -> int:
	return cols * rows - _holes.size()


func head() -> int:
	return path[-1] if not path.is_empty() else -1


## The nodes a ribbon run to `node` would light, in order (empty if the run isn't allowed).
func run_to(node: int) -> Array[int]:
	var out: Array[int] = []
	if not is_node(node) or _lit.has(node):
		return out
	if path.is_empty():
		if node == source:
			out.append(node)
		return out
	var h := path[-1]
	var hc := h % cols
	var hr := h / cols
	var nc := node % cols
	var nr := node / cols
	if hc != nc and hr != nr:
		return out
	var step := 0
	if hr == nr:
		step = 1 if nc > hc else -1
	else:
		step = cols if nr > hr else -cols
	var i := h + step
	while true:
		if not is_node(i) or _lit.has(i):
			out.clear()
			return out
		out.append(i)
		if i == node:
			return out
		i += step
	return out


## Light `nodes` (as run_to returned them).
func extend(nodes: Array) -> void:
	for n in nodes:
		path.append(int(n))
		_lit[int(n)] = true


## Wind the ribbon back so `node` is its head (the head itself: one node comes off). False if it isn't lit.
func wind_to(node: int) -> bool:
	var at := path.find(node)
	if at < 0:
		return false
	var keep := at if at == path.size() - 1 else at + 1
	while path.size() > keep:
		_lit.erase(path[-1])
		path.pop_back()
	return true


func clear() -> void:
	path.clear()
	_lit.clear()


func is_closed() -> bool:
	return path.size() == live_count() and not path.is_empty() and path[-1] == sink


## Nowhere left to go, and not closed: the ribbon has to be wound back.
func is_stuck() -> bool:
	if path.is_empty() or is_closed():
		return false
	for n in _neighbours(path[-1]):
		if is_node(n) and not _lit.has(n):
			return false
	return true


## A good next node: the first step of a way to close the board from here. -1: none found in the budget (or
## the board is closed). -2: there is no way on from here, so the ribbon should be wound back. With no ribbon
## yet it is the source. `budget` caps the search (steps tried), so this never costs more than a blink.
func hint(budget := 2500) -> int:
	if path.is_empty():
		return source
	if is_closed():
		return -1
	var left := [budget]
	var first := _solve(path[-1], path.size(), left)
	if first >= 0:
		return first
	return -1 if int(left[0]) <= 0 else -2


func _neighbours(i: int) -> Array[int]:
	var out: Array[int] = []
	var c := i % cols
	var r := i / cols
	if c > 0:
		out.append(i - 1)
	if c < cols - 1:
		out.append(i + 1)
	if r > 0:
		out.append(i - cols)
	if r < rows - 1:
		out.append(i + cols)
	return out


func _free(i: int) -> bool:
	return is_node(i) and not _lit.has(i)


## Depth-first, fewest-ways-on first. Returns the first node of a closing path from `at`, or -1.
func _solve(at: int, lit_count: int, left: Array) -> int:
	var total := live_count()
	if lit_count == total:
		return at if at == sink else -1
	if int(left[0]) <= 0:
		return -1
	left[0] = int(left[0]) - 1
	if not _reachable(at, total - lit_count):
		return -1
	var opts: Array = []
	for n in _neighbours(at):
		if _free(n) and (n != sink or lit_count == total - 1):
			var ways := 0
			for m in _neighbours(n):
				if _free(m):
					ways += 1
			opts.append([ways, n])
	opts.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	for o in opts:
		var n := int(o[1])
		_lit[n] = true
		var found := _solve(n, lit_count + 1, left)
		_lit.erase(n)
		if found >= 0:
			return n
	return -1


## Whether every unlit node can still be reached from `at` through unlit nodes (a cut-off pocket means no).
func _reachable(at: int, want: int) -> bool:
	var seen := {}
	var stack: Array[int] = [at]
	var count := 0
	while not stack.is_empty():
		var i: int = stack.pop_back()
		for n in _neighbours(i):
			if _free(n) and not seen.has(n):
				seen[n] = true
				count += 1
				stack.append(n)
	return count == want


## Where node `i` stands in the world, for a board whose top-left node is at `origin` with `spacing` between nodes.
func pos_of(i: int, origin: Vector2, spacing: float) -> Vector2:
	return origin + Vector2(float(i % cols), float(i / cols)) * spacing


## The node within `radius` of `world` (-1 if none).
func node_near(world: Vector2, origin: Vector2, spacing: float, radius: float) -> int:
	var c := roundi((world.x - origin.x) / spacing)
	var r := roundi((world.y - origin.y) / spacing)
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return -1
	var i := r * cols + c
	if not is_node(i):
		return -1
	return i if pos_of(i, origin, spacing).distance_to(world) <= radius else -1
