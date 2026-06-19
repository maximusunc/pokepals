extends SceneTree
## Lightweight, dependency-free headless test runner.
##
## Run from the Godot project directory:
##   godot --headless --path . --script res://tests/run_tests.gd
## (from the repo root, use:  godot --headless --path pokepals --script res://tests/run_tests.gd)
##
## Exits with a non-zero code equal to the number of failures, so it doubles as a
## CI gate. Add more suites by calling their run_all() below.

func _init() -> void:
	var failures := 0
	failures += TestBattleLogic.run_all()
	failures += TestConsiderations.run_all()
	failures += TestArbiter.run_all()
	failures += TestCompanionBrain.run_all()
	failures += TestCompanionSelf.run_all()
	failures += TestCompanionAttention.run_all()
	failures += TestWorldAreas.run_all()
	failures += TestCompanionAppraisal.run_all()
	failures += TestSolids.run_all()

	print("")
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("TESTS FAILED: %d failure(s)" % failures)
	quit(failures)
