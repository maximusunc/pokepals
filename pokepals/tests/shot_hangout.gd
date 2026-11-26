extends SceneTree
## Dev tool: screenshots of Lingerlong's hangout features, to LOOK at them (sitting, the fountain's coins).
## Needs a real renderer (not --headless):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path pokepals --resolution 1280x720 \
##     --script res://tests/shot_hangout.gd -- <out_dir> [stage ...]
## Stages: "bench" (you on a fountain bench, your companion resting, friends in other outfits on the benches round
## it, a coin in the air and the fountain swelling), "lounger" (the Palm Court's loungers), "pool" (the pool's edge
## and the deck loungers), "side" (the benches either side of the fountain, sitting side-on).

const LINGERLONG_ID := "18181818-1818-1818-1818-181818181818"
const LOOKS := [
	{ "equipped": { "outfit": "base:tank", "hair": "base:hair_long" }, "colors": { "top_color": "clay", "hair_color": "wheat", "skin_tone": "umber" } },
	{ "equipped": { "hair": "base:hair_spiky", "headwear": "base:headband", "accessory": "base:glasses" }, "colors": { "top_color": "moss", "hair_color": "ember", "skin_tone": "fair" } },
	{ "equipped": { "outfit": "base:tank", "hair": "base:hair_short" }, "colors": { "top_color": "violet", "hair_color": "slate", "skin_tone": "rose", "legwear_color": "river" } },
	{ "equipped": { "hair": "base:hair_long" }, "colors": { "top_color": "gold", "hair_color": "chestnut", "skin_tone": "golden" } },
]

var _world: Node
var _frames := 0
var _out := "user://"
var _stages: Array = []
var _at := -1
var _start := 0
var _peers := 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _world == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_out = args[0]
		for i in range(1, args.size()):
			_stages.append(String(args[i]))
		if _stages.is_empty():
			_stages = ["bench", "coin", "lounger", "pool", "side"]
		var router := root.get_node("/root/WorldRouter")
		var net := root.get_node("/root/Net")
		net.prime_world_spec(LINGERLONG_ID, WorldData.load_json("res://tests/world_fixtures/lingerlong.json"))
		router.current_world = LINGERLONG_ID
		router.arrival_portal_id = ""
		_world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
		root.add_child(_world)
		net.emit_signal("world_spec_unchanged", LINGERLONG_ID)
		paused = false
		return false
	paused = false
	var gate := _world.get_node_or_null("UI/Lobby") as CanvasItem
	if gate != null and gate.visible:
		gate.visible = false
	if _frames < 100:
		return false
	if _frames == 100:
		for n in ["DebugOverlay"]:
			var layer := _world.get_node_or_null(n) as CanvasLayer
			if layer != null:
				layer.visible = false
		_world._companion._brain.get_self().bond = 1.0
		_next()
		return false
	var t := _frames - _start
	var stage := String(_stages[_at])
	if stage == "coin" and t == 140:
		# a friend standing south of the basin tosses a coin, and the fountain has been busy
		_world._wish_dir._coin_from(Vector2(-60, 366))
		_world._wish_dir._coin_from(Vector2(10, 380))
		for k in 3:
			_world._fountain_view.swell(0.55)
	if stage == "bench" and t == 150:
		# a friend standing at the basin tosses a coin, and a few more go in from the benches
		_world._wish_dir._coin_from(Vector2(40, 330))
		for k in 4:
			_world._fountain_view.swell(0.55)
	if t == (144 if stage == "coin" else 162):
		_shot(stage)
	if t == 166:
		if _at + 1 >= _stages.size():
			quit(0)
			return true
		_next()
	return false


func _next() -> void:
	_at += 1
	_start = _frames
	var seats: SeatLogic = PlayerView.seats
	match String(_stages[_at]):
		"bench":
			_sit_me("fountain_bench_6_a")
			_peer_on(seats, "fountain_bench_6_b", 0)
			_peer_on(seats, "fountain_bench_5_a", 1)
			_peer_on(seats, "fountain_bench_7_b", 2)
			_peer_on(seats, "fountain_bench_3_b", 3)
			_peer_standing(Vector2(40, 330), 0, Vector2(0, -1))
		"lounger":
			_sit_me("palm_lounger_1w")
			_peer_on(seats, "palm_lounger_1e", 1)
			_peer_on(seats, "palm_lounger_2w", 2)
		"pool":
			_sit_me("pool_edge_4")
			_peer_on(seats, "pool_edge_3", 0)
			_peer_on(seats, "deck_lounger_3w", 3)
		"coin":
			_sit_me("fountain_bench_2_a")
			_peer_standing(Vector2(-60, 380), 1, Vector2(0, -1))
			_peer_standing(Vector2(10, 394), 3, Vector2(0, -1))
		"side":
			_sit_me("fountain_bench_1_a")
			_peer_on(seats, "fountain_bench_1_b", 2)
			_peer_on(seats, "fountain_bench_4_b", 1)


func _index(id: String) -> int:
	var seats: SeatLogic = PlayerView.seats
	for i in seats.size():
		if String(seats.seat(i)["id"]) == id:
			return i
	push_error("no seat " + id)
	return 0


func _sit_me(id: String) -> void:
	if _world._player.is_sitting():
		_world._player.stand_up()
	var i := _index(id)
	_world._companion.position = PlayerView.seats.stand_point(i) + Vector2(-20, 6)
	_world._seat_dir.sit_on(i)


func _peer_on(seats: SeatLogic, id: String, look: int) -> void:
	var at: Vector2 = seats.seat(_index(id))["at"]
	_peer_standing(at, look, Vector2.DOWN)


func _peer_standing(at: Vector2, look: int, face: Vector2) -> void:
	_peers += 1
	var pid := "peer-%d" % _peers
	var pd = _world._presence_dir
	pd._on_peer_joined(pid)
	var app: Dictionary = (LOOKS[look] as Dictionary).duplicate(true)
	pd._apply_remote_identity(pid, { "appearance": app })
	var pair: Dictionary = pd._remote_pairs[pid]
	var rp = pair["player"]
	rp.position = at
	rp.set_remote_state(at, face)
	var rc = pair["companion"]
	rc.position = at + Vector2(26, 12)
	rc.set_remote_state(at + Vector2(26, 12), Vector2.DOWN)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/hangout_%s.png" % [_out, tag]
	img.save_png(path)
	print("SHOT saved ", path)
