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
##   3. The running action (last frame's winner) gets a small commitment BONUS to its
##      desire — a marginally-keener rival can't unseat a beat already in progress, which
##      is what kills jitter at a score crossover. The bonus is desire-only; it never
##      lifts an action into another band.
##   4. Winner = highest band among eligible actions, then highest (bonus-adjusted)
##      desire within that band, ties broken by array order (so e.g. Follow, listed
##      before Wander, wins an exact tie — the leash backstop never loses a coin flip).
##   5. Interruptibility: if the running action declares itself non-interruptible (a
##      committed beat — a check-in visit underway, a curiosity linger), only a STRICTLY
##      HIGHER band may take over. Same- or lower-band rivals wait their turn.
##
## Band is compared BEFORE desire, so any eligible higher-band action outranks any
## lower-band one no matter how keen the lower one is. So Investigate (and a future
## player COMMAND band) interrupt instantly, by structure rather than by a hand-tuned
## big number. Desire only decides things WITHIN a single band — which is exactly where
## the old shared 1..20 number line did its real work (Follow vs Wander vs Idle).

const EPS := 0.0001

var _running_id: String = ""


## Decide the winner. Returns { winner, scores, running_id } where `scores` maps each
## action id to a readable comparable score for the debug overlay (0 for ineligible).
func decide(actions: Array, facts: Dictionary, s: CompanionSelf, cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var commit_bonus := float(cfg.get("arbiter", {}).get("commit_bonus", 0.0))

	# Score everyone first (score() may latch internal state, so do it once up front).
	var desires := {}
	for a in actions:
		desires[a.id] = a.score(facts, s, cfg, rng)

	# Identify the still-running action and whether it's mid-commitment.
	var running = null
	for a in actions:
		if a.id == _running_id:
			running = a
			break
	var running_eligible: bool = running != null and float(desires[running.id]) > EPS

	# Pick the best eligible candidate by (band, bonus-adjusted desire), array order
	# breaking ties. The commitment bonus is applied here, desire-only.
	var winner = null
	var best_band := -1
	var best_desire := -1.0
	for a in actions:
		var desire := float(desires[a.id])
		if desire <= EPS:
			continue
		if a.id == _running_id:
			desire += commit_bonus
		if a.band > best_band or (a.band == best_band and desire > best_desire):
			best_band = a.band
			best_desire = desire
			winner = a

	# A committed (non-interruptible) running action holds the beat against anything
	# that isn't a strictly higher band.
	if running_eligible and not running.interruptible():
		if winner == null or winner.band <= running.band:
			winner = running

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
