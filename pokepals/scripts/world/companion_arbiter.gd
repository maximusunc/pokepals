class_name CompanionArbiter
extends RefCounted
## The DECIDE step: it holds ALL cross-action logic so the actions themselves can stay
## mutually ignorant. Each action only ever scores its OWN desire; the arbiter is the
## one place that compares them, applies priority bands, and keeps the choice from
## flip-flopping. This is what replaces the old design's two big maintenance hazards:
##   * the magic-number priority line (Idle 1, Wander 7, CheckIn 9, Investigate 20) ->
##     explicit priority BANDS, with desire compared only WITHIN a band;
##   * the bespoke anti-jitter scattered through every drive (and Wander reaching into
##     Follow's scoring math to find a "crossover") -> ONE commitment/hysteresis rule.
##
## Selection each frame:
##   1. tick() every action (timers advance even when an action won't win).
##   2. score() every action -> its own desire (0 = "don't bid"). An action scoring 0 is
##      INELIGIBLE and cannot win, whatever its band — this is essential, e.g. a fresh
##      companion's Follow bids 0, so a lower-band Wander rightly wins instead of an
##      empty high band stealing the frame.
##   3. The running action (last frame's winner) carries its COMMITMENT — a continuous
##      desire-units resistance to being abandoned right now — added to its own desire. A
##      same-band rival must clear desire + commitment to take over. Commitment is graded:
##      the default is a small universal anti-jitter nudge (commit_bonus), while a committed
##      beat (a roam underway, a visit, a look) returns a large value so it FINISHES rather
##      than being yanked at a score crossover. This single continuous quantity replaces both
##      the old fixed commit_bonus AND the old binary "interruptible" flag — preemption WITHIN
##      a band is now one smooth comparison, not a magic flag. (Commitment is desire-only; it
##      never lifts an action into another band.)
##   4. Winner = highest band among eligible actions, then highest (commitment-adjusted)
##      desire within that band, ties broken by array order (so e.g. Follow, listed
##      before Wander, wins an exact tie — the leash backstop never loses a coin flip).
##
## Band is compared BEFORE desire, so any eligible higher-band action outranks any
## lower-band one no matter how keen the lower one (or how committed the running one) is.
## So Investigate (a player look) and a future player COMMAND band interrupt instantly, by
## structure rather than by a hand-tuned big number — commitment is a WITHIN-band quantity.
## Desire (+ commitment) only decides things within a single band — which is exactly where
## the old shared 1..20 number line did its real work (Follow vs Wander vs Idle). Grading
## preemption ACROSS bands (a mild vs a sudden threat) is a danger-era concern, deferred:
## in the cozy slice the cross-band beats are the sacred "it noticed me" moments, which
## SHOULD hard-preempt.

const EPS := 0.0001

var _running_id: String = ""


## Decide the winner. Returns { winner, scores, running_id } where `scores` maps each
## action id to a readable comparable score for the debug overlay (0 for ineligible).
func decide(actions: Array, facts: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# Score everyone first (score() may latch internal state, so do it once up front).
	var desires := {}
	for a in actions:
		desires[a.id] = a.score(facts, s, cfg, rng)

	# Pick the best eligible candidate by (band, commitment-adjusted desire), array order
	# breaking ties. The running action carries its commitment as extra within-band desire,
	# so a committed beat (large commitment) simply out-bids same-band rivals — no separate
	# interruptibility pass, and an action bidding 0 is skipped, so a give-up releases cleanly.
	var winner = null
	var best_band := -1
	var best_desire := -1.0
	for a in actions:
		var desire := float(desires[a.id])
		if desire <= EPS:
			continue
		if a.id == _running_id:
			desire += a.commitment(cfg)
		if a.band > best_band or (a.band == best_band and desire > best_desire):
			best_band = a.band
			best_desire = desire
			winner = a

	# Nothing bid at all (shouldn't happen — Idle always bids — but stay safe).
	if winner == null:
		winner = actions[actions.size() - 1]

	if winner.id != _running_id:
		_running_id = winner.id

	# Each action's raw desire this frame for the debug overlay (0 = didn't bid). Within
	# a band these compare directly; across bands the winner star shows who actually won,
	# since a higher band wins regardless of a lower band's larger desire.
	var scores := {}
	for a in actions:
		scores[a.id] = float(desires[a.id])

	return { "winner": winner, "scores": scores, "running_id": _running_id }
