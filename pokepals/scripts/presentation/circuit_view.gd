class_name CircuitView
extends Node2D
## How Ohmstead's RIBBON BOARDS look: for each board, its nodes (hollow until lit), the cold lines between
## them, the amber ribbon laid so far, the live line's marks (amber where the ribbon starts, white where it has
## to end), and the Arcade boards' frames. Lives under WorldArt, so it lies on the ground beneath everyone.
##
## It draws only what CircuitDirector hands it and decides nothing. It redraws when a board changes, and each
## frame only while a ribbon is being carried to a node (the stretch behind the companion) or a board has just
## closed (a short flourish): a still board costs nothing.

const NODE_HALF := 3.5
const AMBER := Color(1.0, 0.71, 0.28)
const AMBER_HOT := Color(1.0, 0.84, 0.54)
const COLD := Color(0.24, 0.18, 0.43)
const NODE_OFF := Color(0.56, 0.53, 0.79)
const WHITE := Color(0.93, 0.98, 1.0)
const RED := Color(1.0, 0.31, 0.43)
const VOID := Color(0.02, 0.012, 0.05)

var _boards: Array = []          # [{ id, kind, origin: Vector2, spacing, model: CircuitBoard, closed, sector: Rect2 }]
var _pending := {}               # board id -> { from: Vector2, to: Vector2, t: 0..1 }
var _hint := {}                  # board id -> node the companion is glancing at
var _flourish := {}              # board id -> seconds since it closed (while < FLOURISH)

const FLOURISH := 2.2


func set_boards(boards: Array) -> void:
	_boards = boards
	queue_redraw()


## A board's state changed: draw it again.
func refresh() -> void:
	queue_redraw()


## The ribbon is being carried from the head toward a node: `t` is how far along (0..1). Null `to` ends it.
func set_pending(id: String, from: Vector2, to: Vector2, t: float) -> void:
	_pending[id] = { "from": from, "to": to, "t": clampf(t, 0.0, 1.0) }
	queue_redraw()


func clear_pending(id: String) -> void:
	if _pending.has(id):
		_pending.erase(id)
		queue_redraw()


## The node the companion is glancing at (-1: none).
func set_hint(id: String, node: int) -> void:
	if node < 0:
		if _hint.has(id):
			_hint.erase(id)
			queue_redraw()
	elif int(_hint.get(id, -1)) != node:
		_hint[id] = node
		queue_redraw()


## A board has just closed: a ring of light runs out from it for a moment.
func flourish(id: String) -> void:
	_flourish[id] = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _flourish.is_empty():
		return
	for id in _flourish.keys():
		_flourish[id] = float(_flourish[id]) + delta
		if float(_flourish[id]) >= FLOURISH:
			_flourish.erase(id)
	queue_redraw()


func _draw() -> void:
	# (No culling by the camera here: this node redraws only when a board changes, so what it drew has to be
	# the whole of every board, wherever the camera was at the time. Three boards; the engine clips the rest.)
	for b in _boards:
		var model: CircuitBoard = b.get("model")
		var origin: Vector2 = b["origin"]
		var spacing := float(b["spacing"])
		var kind := String(b["kind"])
		var cols := int(b["cols"])
		var rows := int(b["rows"])
		var area := Rect2(origin, Vector2(float(cols - 1), float(rows - 1)) * spacing).grow(30.0)
		var closed := bool(b["closed"])
		if kind == "fixed":
			if not closed and (b["sector"] as Rect2).has_area():
				_dashed_rect(b["sector"], Color(RED.r, RED.g, RED.b, 0.75), 9.0, 5.0)
		else:
			# an Arcade board: a dark table with a bright double edge
			draw_rect(area, Color(VOID.r, VOID.g, VOID.b, 0.72))
			draw_rect(area, Color(WHITE.r, WHITE.g, WHITE.b, 0.9), false, 1.0)
			draw_rect(area.grow(-3.0), Color(WHITE.r, WHITE.g, WHITE.b, 0.35), false, 1.0)
		if model == null:
			continue
		var id := String(b["id"])
		var line_col := Color(AMBER.r, AMBER.g, AMBER.b, 0.35) if closed else COLD
		# the lines between neighbouring nodes
		for i in model.size():
			if not model.is_node(i):
				continue
			var p := model.pos_of(i, origin, spacing)
			if i % cols < cols - 1 and model.is_node(i + 1):
				draw_line(p, model.pos_of(i + 1, origin, spacing), line_col, 1.0)
			if i / cols < rows - 1 and model.is_node(i + cols):
				draw_line(p, model.pos_of(i + cols, origin, spacing), line_col, 1.0)
		# where the live line comes in (amber) and where the ribbon has to end (white): a stub off the board
		_stub(model, model.source, origin, spacing, AMBER, true)
		_stub(model, model.sink, origin, spacing, WHITE, false)
		# the ribbon
		if model.path.size() >= 1:
			var pts := PackedVector2Array()
			for n in model.path:
				pts.append(model.pos_of(n, origin, spacing))
			if _pending.has(id):
				var pd: Dictionary = _pending[id]
				pts.append((pd["from"] as Vector2).lerp(pd["to"], float(pd["t"])))
			if pts.size() >= 2:
				draw_polyline(pts, Color(AMBER.r, AMBER.g, AMBER.b, 0.22), 6.0)
				draw_polyline(pts, AMBER, 2.0)
		# the nodes
		for i in model.size():
			if not model.is_node(i):
				continue
			var p := model.pos_of(i, origin, spacing)
			var box := Rect2(p - Vector2(NODE_HALF, NODE_HALF), Vector2(NODE_HALF, NODE_HALF) * 2.0)
			if model.is_lit(i):
				SoftGlow.draw(self, p, 11.0, Color(AMBER.r, AMBER.g, AMBER.b, 0.38))
				draw_rect(box, AMBER_HOT)
			else:
				draw_rect(box, VOID)
				var c := NODE_OFF
				if i == model.source:
					c = AMBER
				elif i == model.sink:
					c = WHITE
				draw_rect(box, c, false, 1.0)
		if _hint.has(id) and model.is_node(int(_hint[id])):
			var hp := model.pos_of(int(_hint[id]), origin, spacing)
			draw_arc(hp, 9.0, 0.0, TAU, 20, Color(WHITE.r, WHITE.g, WHITE.b, 0.8), 1.0)
		if _flourish.has(id):
			var k := float(_flourish[id]) / FLOURISH
			var c := area.get_center()
			var r := lerpf(20.0, area.size.length() * 0.75, k)
			draw_arc(c, r, 0.0, TAU, 48, Color(AMBER_HOT.r, AMBER_HOT.g, AMBER_HOT.b, (1.0 - k) * 0.8), 2.0)


## A short line from node `i` off the edge of the lattice it sits on, with an arrowhead: pointing IN at the
## node where the live line arrives (`inward`), OUT from the node the ribbon has to leave by.
func _stub(model: CircuitBoard, i: int, origin: Vector2, spacing: float, col: Color, inward: bool) -> void:
	if not model.is_node(i):
		return
	var c := i % model.cols
	var r := i / model.cols
	var dir := Vector2.ZERO
	if c == 0:
		dir = Vector2.LEFT
	elif c == model.cols - 1:
		dir = Vector2.RIGHT
	elif r == 0:
		dir = Vector2.UP
	elif r == model.rows - 1:
		dir = Vector2.DOWN
	else:
		return
	var p := model.pos_of(i, origin, spacing)
	var near := p + dir * (NODE_HALF + 2.0)
	var far := p + dir * 28.0
	draw_line(near, far, col, 1.0)
	var side := dir.orthogonal() * 3.0
	if inward:
		draw_colored_polygon(PackedVector2Array([near, near + dir * 5.0 + side, near + dir * 5.0 - side]), col)
	else:
		draw_colored_polygon(PackedVector2Array([far + dir * 1.0, far - dir * 4.0 + side, far - dir * 4.0 - side]), col)


func _dashed_rect(r: Rect2, col: Color, dash: float, gap: float) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var c := r.end
	var d := Vector2(r.position.x, r.end.y)
	for seg in [[a, b], [b, c], [c, d], [d, a]]:
		draw_dashed_line(seg[0], seg[1], col, 1.0, dash + gap, true)
