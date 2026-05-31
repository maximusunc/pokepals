extends SceneTree
## Headless UI smoke test: loads the real Battle scene, then drives it by pressing
## the first move button every frame until the battle concludes (the Play-again
## button appears). It proves the controller, panels, move menu, and log wire up
## and run a full turn loop without errors — complementary to the pure-logic tests
## in run_tests.gd. Needs the scene tree, so run it on its own:
##   godot --headless --path pokepals --script res://tests/smoke_ui.gd

var _battle: Node
var _frames := 0
var _turns := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/battle.tscn")
	_battle = scene.instantiate()
	root.add_child(_battle)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:  # let _ready / @onready settle
		return false

	var menu: Node = _battle.get_node("MainLayout/MoveMenu")
	var restart: Button = _battle.get_node("MainLayout/RestartButton")

	if restart.visible:
		print("SMOKE: battle concluded after %d player turns" % _turns)
		print("ALL SMOKE CHECKS PASSED")
		quit(0)
		return true

	if _turns > 300:
		print("SMOKE FAIL: battle did not conclude within turn cap")
		quit(1)
		return true

	if menu.visible and menu.get_child_count() > 0:
		(menu.get_child(0) as Button).pressed.emit()
		_turns += 1

	return false
