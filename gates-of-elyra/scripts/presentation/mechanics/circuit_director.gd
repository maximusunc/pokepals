class_name CircuitDirector
extends Node
## The RIBBON BOARDS of Ohmstead: the sector that has lost its power (the world's secret) and the Arcade's two
## boards. On each, a ribbon of light has to be laid through every node, and your companion is the one who lays
## it: you DIRECT it (tap a node, it runs there) and the ribbon follows. This is the presentation half; the
## rules live in the pure CircuitBoard (scripts/world), and the state of every board is the SERVER's
## (Server.Circuit): shared by everyone in the world, so friends close a board together. It:
##
##   * turns a tap on a node into an order: an unlit node your ribbon can run straight to sends the companion
##     there (the Drifthallow `guide` order, re-issued each frame so it stays put, as on Lanternfold's stage);
##     when it arrives we tell the server, and the server tells everyone the ribbon grew. A tap on a LIT node
##     winds the ribbon back to it. A bird flies over the board and lays nothing (a cue to change shape);
##   * keeps that from being broken by what a player naturally does: a CALL ends it (and puts out a ribbon you
##     laid part of), a PET is enjoyed and the standing carries on, walking far away lets the ribbon be, and
##     the companion's own form drift is held off while it works;
##   * has the companion GLANCE at a good next node after a while, sooner with a deeper bond (the hint comes
##     from CircuitBoard.hint, worked out once per change, never per frame). The glance is a look that never
##     holds the body (listen_toward), so nothing a player does during it can leave the companion standing;
##   * hands the look to CircuitView (nodes, ribbon, the stretch behind the companion) and to the grid ground
##     (the dark sector's power, which sweeps back when its board closes);
##   * says the world's lines, and when a board closes: your time, your best (kept on this device), what it paid.
##
## With no server (a headless test) the authored boards are played locally by the same rules, so the secret's
## board works offline; dealt boards only exist when the server deals them.

## `fresh`: it closed just now, in front of us (false: it was already closed when we arrived).
signal board_closed(board_id: String, fresh: bool)
## A closed board has lost its power again (the dark sector, a while after it was closed).
signal board_opened(board_id: String)

const SETTINGS_PATH := "user://settings.json"

var _host: Node
var _companion: CompanionView
var _world_art: WorldArt
var _player: PlayerView

var _cfg: Dictionary = {}
var _lines: Dictionary = {}
var _boards: Array = []            # [{ id, kind, origin, spacing, cols, rows, model, closed, sector, seq, label }]
var _view: CircuitView = null
var _said := {}
var _spacing := 64.0

var _engaged := ""                 # the board our companion is working on ("" none)
var _target := -1                  # the node it is running to (-1: none)
var _hold := -1                    # the node it is standing on
var _waiting := false              # we told the server it arrived and haven't heard back
var _pet_pause := 0.0
var _idle := 0.0                   # seconds since the ribbon last changed, for the hint
var _hint_node := -1
var _hint_for := ""                # "<board>:<seq>" the hint was worked out for
var _hint_show := 0.0
var _release_in := -1.0
var _sweep := {}                   # board id -> the sector's power right now (0..1), while it is changing
var _notice_t := 0.0
var _best := {}                    # board id -> best time (ms), on this device
var _cam_off := Vector2.ZERO       # the camera's eased lean toward the board being worked on


func setup(host: Node, companion: CompanionView, world_art: WorldArt, player: PlayerView) -> void:
	_host = host
	_companion = companion
	_world_art = world_art
	_player = player
	Net.circuits_received.connect(_on_boards)
	Net.circuit_changed.connect(_on_board)
	Net.circuit_refused.connect(_on_refused)
	Net.circuit_reward.connect(_on_reward)


## Lay out this world's boards from the spec's `circuits` block (a no-op in every other world).
func configure(data: Dictionary) -> void:
	_cfg = data.get("circuits", {})
	_boards = []
	_engaged = ""
	_target = -1
	_hold = -1
	_said = {}
	if is_instance_valid(_view):
		_view.queue_free()
	_view = null
	if _cfg.is_empty() or (_cfg.get("boards", []) as Array).is_empty():
		return
	_lines = _cfg.get("lines", {})
	_spacing = float(_cfg.get("node", 64.0))
	for b in _cfg["boards"]:
		var sector := Rect2()
		var sr: Array = b.get("sector", [])
		if sr.size() == 4:
			sector = Rect2(float(sr[0]), float(sr[1]), float(sr[2]), float(sr[3]))
		var entry := {
			"id": String(b["id"]), "kind": String(b.get("kind", "fixed")), "origin": WorldData.to_vec2(b["origin"]),
			"spacing": _spacing, "cols": int(b["cols"]), "rows": int(b["rows"]), "model": null, "closed": false,
			"sector": sector, "seq": -1, "label": String(b.get("label", "the board")),
		}
		# an authored board is known from the spec, so it can be drawn (and, offline, played) before the server speaks
		if String(entry["kind"]) == "fixed":
			entry["model"] = CircuitBoard.from_dict(b)
		_boards.append(entry)
	_view = CircuitView.new()
	_view.name = "CircuitView"
	_world_art.add_child(_view)
	_view.set_boards(_boards)
	var settings := SaveStore.load_json(SETTINGS_PATH)
	_best = (settings.get("circuit_best", {}) as Dictionary).duplicate()
	_on_boards(Net.circuit_boards())
	_push_sectors(true)


func active() -> bool:
	return not _boards.is_empty()


func board(id: String) -> Dictionary:
	for b in _boards:
		if String(b["id"]) == id:
			return b
	return {}


func is_closed(id: String) -> bool:
	return bool(board(id).get("closed", false))


func engaged_board() -> String:
	return _engaged


# ── the server's word ────────────────────────────────────────────────────────────────────────────────

func _on_boards(views: Array) -> void:
	for v in views:
		_apply(v, true)


func _on_board(v: Dictionary) -> void:
	_apply(v, false)


## Take the server's description of one board. `quiet`: a join's snapshot (no lines, no flourish).
func _apply(v: Dictionary, quiet: bool) -> void:
	var b := board(String(v.get("id", "")))
	if b.is_empty():
		return
	var id := String(b["id"])
	var old: CircuitBoard = b["model"]
	var fresh := old == null or old.source != int(v.get("source", -1)) or old.sink != int(v.get("sink", -1)) \
		or old.cols != int(v.get("cols", 0)) or old.rows != int(v.get("rows", 0)) or _holes_differ(old, v.get("holes", []))
	var was_closed := bool(b["closed"])
	if fresh:
		b["model"] = CircuitBoard.from_dict(v)
	else:
		old.set_path(v.get("path", []))
	b["closed"] = bool(v.get("closed", false))
	b["seq"] = int(v.get("seq", 0))
	b["time_ms"] = int(v.get("time_ms", 0)) if v.get("time_ms", null) != null else 0
	_idle = 0.0
	_hint_show = 0.0
	if _view != null:
		_view.set_hint(id, -1)
		_view.clear_pending(id)
		_view.refresh()
	if _engaged == id:
		_waiting = false
		var model: CircuitBoard = b["model"]
		if fresh and old != null:
			_release()                       # a new board was dealt under us
		elif _hold >= 0 and not model.is_lit(_hold):
			_hold = model.head()             # the ribbon was wound back past where it stood
			if _hold < 0:
				_release()
	if bool(b["closed"]) and not was_closed:
		_sweep_to(id)
		if quiet:
			board_closed.emit(id, false)   # closed before we came: lit, and whatever it holds is there
		else:
			_on_closed(b)
	elif not bool(b["closed"]) and was_closed:
		_sweep_to(id)
		board_opened.emit(id)
	if fresh and old != null and not quiet and String(b["kind"]) == "dealt" and _near(b, 360.0):
		_say("dealt", false)


func _holes_differ(model: CircuitBoard, holes: Array) -> bool:
	if model.live_count() != model.size() - holes.size():
		return true
	for h in holes:
		if model.is_node(int(h)):
			return true
	return false


func _on_closed(b: Dictionary) -> void:
	var id := String(b["id"])
	if _view != null:
		_view.flourish(id)
	if _engaged == id:
		_release_in = 2.0
		_companion.delight_at(_center(b))
	board_closed.emit(id, true)
	# An Arcade board we had no part in: just say it closed (our own share arrives as a reward, with the time).
	if String(b["kind"]) != "fixed" and _engaged != id and _near(b, 360.0):
		_say("closed", false)


func _on_refused(board_id: String, _node: int, _reason: String) -> void:
	if board_id == _engaged:
		_waiting = false
		_target = -1
		if _view != null:
			_view.clear_pending(board_id)
		_say("not_line", false)


func _on_reward(info: Dictionary) -> void:
	_host.set_wallet_balance(int(info.get("balance", 0)))
	var id := String(info.get("board", ""))
	var ms := int(info.get("time_ms", 0))
	var line := _format(String(_lines.get("paid", "")), ms, info)
	line += _best_note(id, ms)
	if line != "":
		_host.show_hint(line)


## " Your best: 0:31." or " That is your best yet.", and remember a new best on this device.
func _best_note(id: String, ms: int) -> String:
	if ms <= 0:
		return ""
	var b := board(id)
	# the table deals a different board each time, so its best is per size; today's is its own
	var key := "%s:%dx%d" % [id, int(b.get("cols", 0)), int(b.get("rows", 0))]
	var prev := int(_best.get(key, 0))
	if prev <= 0 or ms < prev:
		_best[key] = ms
		if Net.in_world():   # (a reward only ever comes from the server; an offline test's must not touch real settings)
			var settings := SaveStore.load_json(SETTINGS_PATH)
			settings["circuit_best"] = _best
			SaveStore.save_json(SETTINGS_PATH, settings)
		return String(_lines.get("new_best", "")) if prev > 0 else ""
	return String(_lines.get("best", "")).replace("{best}", clock(prev))


func _format(line: String, ms: int, info: Dictionary) -> String:
	return line.replace("{time}", clock(ms)).replace("{coins}", count(int(info.get("coins", 0)), "coin")) \
		.replace("{sparks}", count(int(info.get("sparks", 0)), "spark"))


## 1 -> "1 spark", 3 -> "3 sparks".
static func count(n: int, noun: String) -> String:
	return "%d %s" % [n, noun if n == 1 else noun + "s"]


## 83500 ms -> "1:23".
static func clock(ms: int) -> String:
	var s := int(round(float(ms) / 1000.0))
	return "%d:%02d" % [s / 60, s % 60]


# ── taps ─────────────────────────────────────────────────────────────────────────────────────────────

## A tap in the world: true when it was on a board's node (the caller then treats the tap as spent).
func on_tap(world: Vector2) -> bool:
	if _boards.is_empty() or _companion == null:
		return false
	var radius := float(_cfg.get("tap_radius", 22.0))
	for b in _boards:
		var model: CircuitBoard = b["model"]
		if model == null:
			continue
		var node := model.node_near(world, b["origin"], _spacing, radius)
		if node < 0:
			continue
		_tap_node(b, node)
		return true
	return false


func _tap_node(b: Dictionary, node: int) -> void:
	var id := String(b["id"])
	var model: CircuitBoard = b["model"]
	_end_glance(b)   # you have decided: the companion stops looking at its own idea
	if bool(b["closed"]):
		_say("today_done" if String(b["kind"]) == "daily" else "closed", false)
		return
	if model.is_lit(node):
		# wind the ribbon back to here (the head itself: one node off)
		_engage(id)
		_target = -1
		if Net.in_world():
			Net.circuit_wind(id, node)
		else:
			model.wind_to(node)
			_local_changed(b)
		_say("back", false)
		return
	if _companion.current_form_species() == "bird":
		_companion.glance_toward(model.pos_of(node, b["origin"], _spacing))
		_say("bird", false)
		return
	var run := model.run_to(node)
	if run.is_empty():
		_say("first" if model.path.is_empty() else "not_line", false)
		return
	_engage(id)
	_target = node
	_waiting = false
	_pet_pause = 0.0
	_release_in = -1.0
	_issue(model.pos_of(node, b["origin"], _spacing))
	_say("start" if model.path.is_empty() else "laid", true)


func _engage(id: String) -> void:
	if _engaged != id:
		if _engaged != "" and _view != null:
			_view.clear_pending(_engaged)
		_engaged = id
		_hold = -1
		_idle = 0.0


func _release() -> void:
	if _engaged != "" and _view != null:
		_view.clear_pending(_engaged)
		_view.set_hint(_engaged, -1)
	_engaged = ""
	_target = -1
	_hold = -1
	_waiting = false
	_release_in = -1.0
	_hint_show = 0.0


func _issue(at: Vector2) -> void:
	_companion.issue_command("guide", at, { "hold": false })


## Offline (no server): a board changed by our own hand.
func _local_changed(b: Dictionary) -> void:
	var model: CircuitBoard = b["model"]
	var was := bool(b["closed"])
	b["closed"] = model.is_closed()
	b["seq"] = int(b["seq"]) + 1
	_idle = 0.0
	if _view != null:
		_view.clear_pending(String(b["id"]))
		_view.set_hint(String(b["id"]), -1)
		_view.refresh()
	if _hold >= 0 and not model.is_lit(_hold):
		_hold = model.head()
	if bool(b["closed"]) and not was:
		_sweep_to(String(b["id"]))
		_on_closed(b)


# ── every frame ──────────────────────────────────────────────────────────────────────────────────────

func update(delta: float) -> void:
	if _boards.is_empty() or _companion == null or _player == null or delta <= 0.0:
		return
	_update_sweeps(delta)
	_update_camera(delta)
	_notice_t -= delta
	if _notice_t <= 0.0:
		_notice_t = 0.5
		_notice()
	if _engaged == "":
		return
	var b := board(_engaged)
	var model: CircuitBoard = b.get("model")
	if b.is_empty() or model == null:
		_release()
		return
	# What a player naturally does must not be swallowed by our per-frame order (the brain holds ONE order):
	# a Call ends the work and puts our ribbon out, a Pet is enjoyed and the standing resumes.
	var pc := _companion.pending_command()
	if pc == "come":
		var id := _engaged
		_release()
		if not bool(b["closed"]) and not model.path.is_empty():
			if Net.in_world():
				Net.circuit_clear(id)
			else:
				model.clear()
				_local_changed(b)
		_say("cleared", false)
		return
	if pc == "pet":
		_pet_pause = float(_cfg.get("pet_pause", 3.0))
	_pet_pause = maxf(0.0, _pet_pause - delta)
	if _player.position.distance_to(_companion.position) > float(_cfg.get("release_distance", 520.0)):
		_release()
		_say("let_go", false)
		return
	if _release_in > 0.0:
		_release_in -= delta
		if _release_in <= 0.0:
			_release()
			return
	_companion.postpone_form_drift(float(_cfg.get("drift_hold", 30.0)))
	var origin: Vector2 = b["origin"]
	if _target >= 0:
		var at := model.pos_of(_target, origin, _spacing)
		if _pet_pause <= 0.0 and pc != "pet":
			_issue(at)
		_update_pending(b, model, at)
		if not _waiting and _companion.position.distance_to(at) <= float(_cfg.get("arrive_radius", 7.0)):
			_arrived(b, model)
	elif _hold >= 0 and model.is_node(_hold) and not bool(b["closed"]):
		if _pet_pause <= 0.0 and pc != "pet":
			_issue(model.pos_of(_hold, origin, _spacing))
		_update_hint(delta, b, model)


## The companion has reached the node it was sent to: the ribbon runs there.
func _arrived(b: Dictionary, model: CircuitBoard) -> void:
	var node := _target
	_hold = node
	if Net.in_world():
		_waiting = true
		_target = -1
		Net.circuit_run(String(b["id"]), node)
		return
	var run := model.run_to(node)
	_target = -1
	if run.is_empty():
		_say("not_line", false)
		return
	model.extend(run)
	_local_changed(b)


## The stretch of ribbon behind the companion as it runs: from the head toward the node, as far as it has got.
func _update_pending(b: Dictionary, model: CircuitBoard, to: Vector2) -> void:
	if _view == null or model.head() < 0:
		return
	var from := model.pos_of(model.head(), b["origin"], _spacing)
	var seg := to - from
	var len2 := seg.length_squared()
	if len2 <= 0.0:
		return
	var t := clampf((_companion.position - from).dot(seg) / len2, 0.0, 1.0)
	var off := (_companion.position - (from + seg * t)).length()
	if off > 20.0:
		_view.clear_pending(String(b["id"]))   # it is coming from somewhere else: no ribbon behind it yet
	else:
		_view.set_pending(String(b["id"]), from, to, t)


## Stop glancing at the hinted node (the look relaxes by itself) and start the wait for the next glance.
func _end_glance(b: Dictionary) -> void:
	_hint_show = 0.0
	_idle = 0.0
	if _view != null and not b.is_empty():
		_view.set_hint(String(b["id"]), -1)


## After a while with no move, the companion glances at a good next node: sooner with a deeper bond.
func _update_hint(delta: float, b: Dictionary, model: CircuitBoard) -> void:
	_idle += delta
	var bond := clampf(_companion.bond_value(), 0.0, 1.0)
	var delay := lerpf(float(_cfg.get("hint_delay_low", 14.0)), float(_cfg.get("hint_delay_high", 4.0)), bond)
	if _hint_show > 0.0:
		_hint_show -= delta
		if _hint_node >= 0:
			# A LOOK, refreshed each frame and relaxing by itself when we stop: CompanionView.listen_toward turns
			# the gaze and never holds the body. (point_at, the hunt's tell, FREEZES the body until it is cleared;
			# used here, a tap or a change of the board during the glance left the companion unable to move.)
			_companion.listen_toward(model.pos_of(_hint_node, b["origin"], _spacing), 0.8)
		if _hint_show <= 0.0:
			_end_glance(b)
		return
	if _idle < delay:
		return
	var key := "%s:%d" % [String(b["id"]), int(b["seq"])]
	if _hint_for != key:
		_hint_for = key
		_hint_node = model.hint()          # worked out once per change of the board
	if _hint_node == -2:
		# no way on from here: it looks back along the ribbon, and we say so once per dead end
		_hint_node = model.path[-2] if model.path.size() >= 2 else model.head()
		_say("stuck", false)
	if _hint_node < 0:
		_idle = 0.0
		return
	_hint_show = float(_cfg.get("hint_hold", 1.8))
	if _view != null:
		_view.set_hint(String(b["id"]), _hint_node)


## While the companion works on a board, lean the camera toward the board's middle (as far as keeps you on
## screen), so the whole of it can be seen and tapped; ease back when the work ends. Camera2D.offset is the
## framing's own free knob (Lanternfold's stage uses it the same way).
func _update_camera(delta: float) -> void:
	var want := Vector2.ZERO
	if _engaged != "":
		var b := board(_engaged)
		if not b.is_empty():
			var d := _center(b) - _player.position
			var reach: Array = _cfg.get("camera_reach", [150.0, 80.0])
			# (plus a little downward bias, so the board sits clear of the message pill and the item bar)
			want = Vector2(clampf(d.x, -float(reach[0]), float(reach[0])), clampf(d.y, -float(reach[1]), float(reach[1])) + float(_cfg.get("camera_drop", 34.0)))
	if _cam_off == want:
		return
	_cam_off = _cam_off.move_toward(want, delta * 110.0)
	var cam: Variant = _host.get("_camera") if _host != null else null
	if cam != null and cam is Camera2D:
		(cam as Camera2D).offset = _cam_off


func _exit_tree() -> void:
	var cam: Variant = _host.get("_camera") if _host != null and is_instance_valid(_host) else null
	if cam != null and cam is Camera2D and _cam_off != Vector2.ZERO:
		(cam as Camera2D).offset = Vector2.ZERO


# ── the sector's power, and noticing ─────────────────────────────────────────────────────────────────

func _sweep_to(id: String) -> void:
	var b := board(id)
	if b.is_empty() or not (b["sector"] as Rect2).has_area():
		return
	if not _sweep.has(id):
		_sweep[id] = 0.0 if bool(b["closed"]) else 1.0


func _update_sweeps(delta: float) -> void:
	if _sweep.is_empty():
		return
	var rate := delta / maxf(0.2, float(_cfg.get("sweep_s", 2.4)))
	for id in _sweep.keys():
		var want := 1.0 if is_closed(id) else 0.0
		_sweep[id] = move_toward(float(_sweep[id]), want, rate)
		if is_equal_approx(float(_sweep[id]), want):
			_sweep.erase(id)
	_push_sectors(false)


## Hand the grid ground each sector's rectangle and power. `settle`: no sweep, straight to where it stands.
func _push_sectors(settle: bool) -> void:
	var grid := _world_art.grid_ground() if _world_art != null else null
	if grid == null:
		return
	var k := 0
	for b in _boards:
		if not (b["sector"] as Rect2).has_area():
			continue
		var id := String(b["id"])
		var power := 1.0 if bool(b["closed"]) else 0.0
		if not settle and _sweep.has(id):
			power = float(_sweep[id])
		grid.set_sector(k, b["sector"], power)
		k += 1


func _notice() -> void:
	var range := float(_cfg.get("notice_range", 300.0))
	for b in _boards:
		if bool(b["closed"]) or not _near(b, range):
			continue
		_say("near_sector" if String(b["kind"]) == "fixed" else "near_arcade", true)


func _center(b: Dictionary) -> Vector2:
	return (b["origin"] as Vector2) + Vector2(float(int(b["cols"]) - 1), float(int(b["rows"]) - 1)) * _spacing * 0.5


func _near(b: Dictionary, range: float) -> bool:
	return _player != null and _player.position.distance_to(_center(b)) <= range + float(int(b["cols"])) * _spacing * 0.5


## A hint line, once per visit when `once` (the lines are the world's; a missing one says nothing).
func _say(key: String, once: bool) -> void:
	if once:
		if _said.has(key):
			return
		_said[key] = true
	var line := String(_lines.get(key, ""))
	if line != "" and _host != null:
		_host.show_hint(line)
