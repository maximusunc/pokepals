class_name TypeChart
## Pure type-effectiveness lookup. The chart *data* lives in data/types.json and
## is passed in; this file only knows how to read it. No node/UI references.

## Return the damage multiplier when an attacking type hits a defending type.
## Anything not explicitly listed in the chart is neutral (1.0).
##   chart shape: { "<atk_type>": { "<def_type>": multiplier, ... }, ... }
static func effectiveness(atk_type: String, def_type: String, chart: Dictionary) -> float:
	if not chart.has(atk_type):
		return 1.0
	var row: Dictionary = chart[atk_type]
	return float(row.get(def_type, 1.0))


## Convenience label for UI/log feedback. Pure string mapping, no formatting policy.
static func describe(multiplier: float) -> String:
	if multiplier > 1.0:
		return "super_effective"
	if multiplier < 1.0:
		return "not_very_effective"
	return "neutral"
