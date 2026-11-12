class_name TankDirector
extends Node
## The fish TANK at home (usable items, step 3; docs/usable-items-design.md). In a home whose spec has a tank
## prop (`"tank": true`, by the journal), it puts a TankView there with the fish the spec says are swimming,
## keeps it current as fish go in and out (the server broadcasts the tank to everyone in the home), opens the
## tank's window when it's examined, and now and then your companion wanders over to watch the fish.
## No-op in every other world.

const WATCH_EVERY := Vector2(40.0, 80.0)   # s between the companion's visits (a random time in this range)
const WATCH_NEAR := 260.0                   # it only goes when you're about, in the glade near the tank
const WATCH_HOLD := 6.0                     # s it gazes at the fish once it's there

var _host: Node
var _companion: CompanionView
var _player: PlayerView
var _scenery: Node2D

var _view: TankView = null
var _pos := Vector2.ZERO
var _owner_id := ""
var _owner_name := ""
var _capacity := 3
var _fish: Array = []
var _watch_in := 0.0
var _watching := 0.0
var _rng := RandomNumberGenerator.new()


func setup(host: Node, companion: CompanionView, player: PlayerView, scenery: Node2D) -> void:
	_host = host
	_companion = companion
	_player = player
	_scenery = scenery
	_rng.randomize()
	_watch_in = _rng.randf_range(WATCH_EVERY.x * 0.5, WATCH_EVERY.y * 0.5)  # the first visit comes a little sooner
	Net.tank_received.connect(_on_tank)


## Find the tank in this world's spec (a home's), and put it there with its fish.
func configure(data: Dictionary) -> void:
	for it in data.get("props", []):
		if it is Dictionary and bool((it as Dictionary).get("tank", false)):
			_pos = WorldData.to_vec2(it["position"])
			_view = TankView.new()
			_view.name = "FishTank"
			_view.position = _pos
			_scenery.add_child(_view)
	if _view == null:
		return
	var home: Dictionary = data.get("home", {})
	_owner_id = String(home.get("owner_id", ""))
	_owner_name = String(home.get("owner_name", ""))
	_capacity = int(home.get("tank_capacity", 3))
	var fish: Variant = home.get("tank", [])
	_fish = (fish as Array).duplicate(true) if fish is Array else []
	_view.set_fish(_fish)


func has_tank() -> bool:
	return _view != null


## The tank was examined: open its window (to change it, if it's ours; to look, if it's a friend's).
func examine(_entry: Dictionary) -> void:
	_companion.glance_toward(_pos)
	var panel := TankPanel.new()
	panel.owner_mine = _owner_id == "" or _owner_id == Net.local_id()
	panel.owner_name = _owner_name
	panel.capacity = _capacity
	panel.fish = _fish.duplicate(true)
	_host.open_sheet(panel)


func update(delta: float) -> void:
	if _view == null:
		return
	# Now and then, while you're about, your companion wanders over to watch the fish for a while.
	if _watching > 0.0:
		_watching -= delta
		if _companion.position.distance_to(_pos) < 60.0:
			_companion.listen_toward(_pos + Vector2(0, -16), 0.7)
		return
	if _view.fish_count() == 0:
		return
	_watch_in -= delta
	if _watch_in <= 0.0:
		_watch_in = _rng.randf_range(WATCH_EVERY.x, WATCH_EVERY.y)
		if _player.position.distance_to(_pos) < WATCH_NEAR:
			_companion.notify_interaction(_pos, "home_tank", ["water", "alive"])
			_watching = WATCH_HOLD + 6.0   # time to walk over, then to watch


func _on_tank(owner_id: String, fish: Array) -> void:
	if _view == null or (owner_id != "" and _owner_id != "" and owner_id != _owner_id):
		return
	_fish = fish.duplicate(true)
	_view.set_fish(_fish)
