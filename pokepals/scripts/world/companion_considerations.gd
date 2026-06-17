class_name CompanionConsiderations
## Pure IAUS (Infinite Axis Utility System) scoring primitives: response curves and
## consideration evaluation. This is the DECLARATIVE half of the companion's decision
## model — an action's desire is authored as a list of named considerations in
## companion.json, not as bespoke arithmetic, so adding a trait or an action is a data
## change rather than a code change.
##
## A CONSIDERATION is one axis of appeal: it reads a normalized 0..1 input by name from
## a `facts` dict and maps it through a RESPONSE CURVE to a 0..1 appeal. An action's
## within-band desire is then weight * combine(appeals).
##
## Everything here is pure (no state, no scene tree, no RNG): same inputs -> same
## outputs, so it's trivially unit-testable and portable.
##
## Consideration spec (JSON):
##   { "input": "dist_factor", "curve": { "type": "linear", "m": 1.0, "b": 0.0 }, "invert": false }
## Curve specs (all map [0,1] -> [0,1]):
##   { "type": "const",    "v": 1.0 }
##   { "type": "linear",   "m": 1.0, "b": 0.0 }            # clamp(m*x + b)
##   { "type": "power",    "k": 2.0 }                       # x^k   (k>1 convex, k<1 concave)
##   { "type": "logistic", "k": 10.0, "x0": 0.5 }           # smooth S, for soft thresholds
##   { "type": "step",     "x0": 0.5, "below": 0.0, "above": 1.0 }   # hard gate
## Any curve may carry "invert": true to return 1 - result.


## Map a single input x (expected 0..1) through a curve spec to a 0..1 appeal.
static func curve(spec: Dictionary, x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	var out := t
	match String(spec.get("type", "linear")):
		"const":
			out = float(spec.get("v", 1.0))
		"linear":
			out = float(spec.get("m", 1.0)) * t + float(spec.get("b", 0.0))
		"power":
			out = pow(t, float(spec.get("k", 1.0)))
		"logistic":
			var k := float(spec.get("k", 10.0))
			var x0 := float(spec.get("x0", 0.5))
			out = 1.0 / (1.0 + exp(-k * (t - x0)))
		"step":
			out = float(spec.get("above", 1.0)) if t >= float(spec.get("x0", 0.5)) else float(spec.get("below", 0.0))
	if bool(spec.get("invert", false)):
		out = 1.0 - out
	return clampf(out, 0.0, 1.0)


## Evaluate one consideration against the facts dict. A missing input reads 0.5 (a
## neutral, non-committal value) so a half-authored spec degrades gently rather than
## crashing.
static func consideration(spec: Dictionary, facts: Dictionary) -> float:
	var x := float(facts.get(String(spec.get("input", "")), 0.5))
	return curve(spec.get("curve", {}), x)


## Evaluate a whole list of consideration specs into their appeals.
static func appeals(specs: Array, facts: Dictionary) -> Array:
	var out: Array = []
	for spec in specs:
		out.append(consideration(spec, facts))
	return out


## Plain product of appeals — use this when the result is a PROBABILITY or a literal
## gated multiplier (e.g. a check-in's chance = pull * distance * sociability), where
## we want the honest product and a single 0 zeroes the whole thing.
static func product(values: Array) -> float:
	var acc := 1.0
	for v in values:
		acc *= float(v)
	return acc


## Compensated combine — use this for an action's DESIRE. Pure product unfairly
## punishes an action that weighs many considerations (0.8^4 ~= 0.41), so we apply Dave
## Mark's compensation factor: the more axes, the more we make up for the pile-up. A
## single 0 (a hard gate) still zeroes the result, which is how "don't even bid" is
## expressed declaratively. Returns 0..1.
static func combine(values: Array) -> float:
	var n := values.size()
	if n == 0:
		return 0.0
	var raw := product(values)
	if n == 1:
		return clampf(raw, 0.0, 1.0)
	var mod_factor := 1.0 - 1.0 / float(n)
	var make_up := (1.0 - raw) * mod_factor
	return clampf(raw + make_up * raw, 0.0, 1.0)
