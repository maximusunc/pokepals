class_name CompanionAppraisal
## APPRAISAL: turns a thing's NEUTRAL tags into how much THIS companion is drawn to it — a
## 0..1 "appeal" — via per-tag affinities (the creature's tastes, authored as data) modulated
## by its curiosity. The architectural point of the tag/appraisal split: the WORLD describes
## things neutrally ("shiny", "water", "made") and the COMPANION decides how it feels, so a
## world author tags a prop without knowing any companion's psychology. This is the cozy seed
## of the danger-era appraisal (a "predator" tag + a timid companion -> fear); here it's just
## tastes — drawn to shiny things and flowers, indifferent to made ones.
##
## Pure: same inputs -> same output, no state, no scene tree. A no-op-ish neutral result
## without "appraisal" config or tags, so untagged things degrade gently.

static func appeal(tags: Array, cfg: Dictionary, curiosity: float) -> float:
	var ap: Dictionary = cfg.get("appraisal", {})
	var neutral := float(ap.get("neutral", 0.5))
	if tags.is_empty():
		return neutral
	var affinities: Dictionary = ap.get("affinities", {})
	var total := 0.0
	for t in tags:
		total += float(affinities.get(String(t), neutral))
	var mean := total / float(tags.size())
	# A curious companion finds a little more to like in everything.
	var lo := float(ap.get("curiosity_lo", 1.0))
	var hi := float(ap.get("curiosity_hi", 1.0))
	return clampf(mean * lerpf(lo, hi, clampf(curiosity, 0.0, 1.0)), 0.0, 1.0)
