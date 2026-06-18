class_name TestConsiderations
## Tests for the IAUS scoring primitives: response curves and how appeals combine.
## Pure functions, so these are exact-value checks.

static func run_all() -> int:
	var fails := 0
	print("TestConsiderations")
	fails += _test_curves()
	fails += _test_invert()
	fails += _test_product_gates()
	fails += _test_combine_compensates()
	fails += _test_consideration_reads_facts()
	return fails


static func _ok(cond: bool, label: String) -> int:
	if cond:
		print("  PASS  ", label)
		return 0
	print("  FAIL  ", label)
	return 1


static func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


static func _test_curves() -> int:
	var fails := 0
	fails += _ok(_approx(CompanionConsiderations.curve({ "type": "const", "v": 0.3 }, 0.9), 0.3), "const ignores input")
	fails += _ok(_approx(CompanionConsiderations.curve({ "type": "linear" }, 0.5), 0.5), "linear identity")
	fails += _ok(_approx(CompanionConsiderations.curve({ "type": "power", "k": 2.0 }, 0.5), 0.25), "power squares")
	fails += _ok(_approx(CompanionConsiderations.curve({ "type": "logistic", "k": 10.0, "x0": 0.5 }, 0.5), 0.5), "logistic midpoint is 0.5")
	fails += _ok(CompanionConsiderations.curve({ "type": "step", "x0": 0.5 }, 0.4) == 0.0, "step below threshold -> 0")
	fails += _ok(CompanionConsiderations.curve({ "type": "step", "x0": 0.5 }, 0.6) == 1.0, "step at/above threshold -> 1")
	fails += _ok(_approx(CompanionConsiderations.curve({ "type": "linear" }, 1.7), 1.0), "input is clamped to 0..1")
	return fails


static func _test_invert() -> int:
	return _ok(_approx(CompanionConsiderations.curve({ "type": "linear", "invert": true }, 0.3), 0.7), "invert flips the result")


static func _test_product_gates() -> int:
	var fails := 0
	fails += _ok(_approx(CompanionConsiderations.product([0.5, 0.5, 0.5]), 0.125), "product multiplies")
	fails += _ok(CompanionConsiderations.product([0.0, 0.9]) == 0.0, "a single 0 zeroes the product (a hard gate)")
	return fails


static func _test_combine_compensates() -> int:
	var fails := 0
	fails += _ok(CompanionConsiderations.combine([]) == 0.0, "empty combine -> 0")
	fails += _ok(_approx(CompanionConsiderations.combine([0.8]), 0.8), "single value passes through")
	# Two 0.5s: raw 0.25, modFactor 0.5, makeup (1-0.25)*0.5=0.375, result 0.25 + 0.375*0.25.
	fails += _ok(_approx(CompanionConsiderations.combine([0.5, 0.5]), 0.34375), "compensation lifts a multi-axis product")
	fails += _ok(CompanionConsiderations.combine([0.0, 0.9]) == 0.0, "a gate still zeroes a compensated combine")
	return fails


static func _test_consideration_reads_facts() -> int:
	var fails := 0
	var facts := { "dist_factor": 0.25 }
	var spec := { "input": "dist_factor", "curve": { "type": "power", "k": 2.0 } }
	fails += _ok(_approx(CompanionConsiderations.consideration(spec, facts), 0.0625), "consideration reads facts and applies curve")
	# A missing input reads the neutral 0.5 rather than crashing.
	fails += _ok(_approx(CompanionConsiderations.consideration({ "input": "nope", "curve": { "type": "linear" } }, facts), 0.5), "missing input -> neutral 0.5")
	return fails
