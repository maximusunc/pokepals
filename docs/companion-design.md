# Expressive Companion AI — Working Design (Cozy Stage)

A living record of the companion-logic decisions we make as we walk through the
full *Expressive Companion AI* spec (the north-star / MMO+UGC vision). This file
captures **what we've resolved for the cozy single-player stage (Rung 1–2)** so it
can be implemented directly. The full spec remains the long-range destination; this
doc is the slice we build now, plus the rationale.

**Status legend:** ✅ Resolved (ready to build) · 🔶 In progress · ⬜ Open / not yet
discussed · ⚠️ Flagged issue in current code.

---

## Guiding principle — cozy now, danger as a pressure-test ✅ (Decision A)

Cozy curiosity/attachment is the companion's core **now**. Fear / danger / adventure
is a **later content layer**, not something we build yet. We use the spec's danger
scenarios only as a **pressure test**: every cozy-stage mechanism must extend cleanly
to its danger version later, so we don't wall off the endgame. (This is just the
existing CLAUDE.md "keep the door open" discipline applied to the companion mind.)

**Corollary:** the danger mechanics are not separate systems — they're the same
handful of mechanisms running on scarier inputs. Build the *mechanisms* cozy now; the
danger layer is later mostly new **content/tags**, not new **architecture**.

### The four mechanisms (cozy ↔ danger)

| Mechanism | Danger version (later) | Cozy version (now) | Status |
|---|---|---|---|
| **Social referencing** | Borrow courage from a calm, advancing player | Glance at / drift toward what *you're* attending to | ✅ built |
| **In-character gating / refusal** | Balk at the scary place; every "no" points to its remedy | Errand-readiness: hesitate when not bonded, go readily once bonded | ✅ designed (cozy) |
| **Salience interruption** | A sudden threat overrides a committed plan | A player interaction overrides a wander | ✅ graded commitment inertia (within-band continuous; cross-band gradation deferred to danger era) |
| **Variety-based bond** | Bond deepens by surviving danger together | Bond deepens via shared novelty / new places / time alongside — not grindable repetition | ✅ built (prop-novelty + shared-attention + new-area + trickle) |

---

## ✅ Mechanism #1 — Social referencing

The companion takes *your* behavior as a reference frame for ambiguous situations.
Cozy version: it notices what you're paying attention to. Built only from what the
companion already perceives + one small dwell timer; no new input channels.

### Signal read
`attended_object` + `attention_strength (0..1)`, derived per nearby POI from a small
**kinematic vocabulary** about the player relative to a candidate object X:

- **Proximity** — are you near X? (necessary, not sufficient)
- **Slowness** — moving slowly / stopped (key on *slowing*, not a full dead stop)
- **Approach vs. retreat** — sign of `velocity · (X − player)` (one dot product)
- **Dwell** — how long you've been slow-and-near X (the one new piece of state: a
  small per-candidate timer)

"You're attending to X" ≈ **near + slow + (approaching or dwelling)**. Explicit
interaction stays the top of this same scale (already feeds `Investigate`); social
referencing fills the quieter band *below* an interaction.

### Response — decomposes, doesn't scale uniformly
Two dials: **bond** (how much it cares about your cue) × **attention_strength** (how
hard you're signaling). The response splits in two:

- **Glance** toward `attended_object` — has a **low bond floor**: rare but possible
  even when fresh (an animal flicks its eyes to what you peer at). Partly
  curiosity-driven. Lives in `look_at` (Idle/Wander).
- **Acting on it** (drift a step closer → come over to *share/investigate alongside*)
  — **bond-gated**, scales with `bond × strength`. Lives as a player-cue bias in
  `WanderAction`'s target pick (alongside the existing `curiosity` POI bias).

Net effect: as you bond, **your attention gradually steers where it explores** — the
cozy version of "leading it through content," with no UI and no command.

### Deliberate imperfection (believability + cheaper)
- A **beat of latency** — it catches your attention just *after* you do.
- **Hysteresis** — once locked on X, hold briefly so it doesn't flicker between props.
- **Occasionally wrong** — may glance at the wrong rock, then self-correct. A feature;
  don't over-engineer precision.

### Anti-mirroring guard
Term-1 independent curiosity never switches off; response is stochastic (sometimes
just a glance even when it could come over); it still gets caught by things you
ignored. The moments it *doesn't* follow your lead are what prove it has a self.

### Code touchpoints (for implementation)
- New perception facts in `companion_perception.gd`: `attended_object`,
  `attention_strength` (+ per-candidate dwell state — note: perception is currently
  stateless, so the dwell timer needs a home — likely a small state object or moved
  into the brain/self).
- New consideration input(s) consumed by `WanderAction` target pick and Idle/Wander
  `look_at`, with a **bond-scaled weight**.
- Reuses existing `points_of_interest`, `player_velocity`, `bond`, `curiosity` trait.

### Danger pressure-test
Same `trust × signal` product later gates whether it borrows your courage (barely
bonded won't, bonded will). Same shape — door stays open.

### Implementation status
- ✅ **Built.** New stateful `CompanionAttention` (owned by the brain, since the dwell
  timer needs cross-frame memory; perception stays pure) infers `attended_object` +
  `attention_strength` from near + slow + (approaching ∨ dwelling), with hysteresis and a
  dwell-driven latency beat. The **glance** lives in `IdleAction` (low bond floor,
  curiosity-tinted); the bond-gated **approach cue** lives in `WanderAction._pick_target`,
  layered on top of the independent target logic (anti-mirroring preserved). Glance/approach
  dice are pre-rolled in the brain on a **dedicated `_ref_rng`** and passed via perception,
  so the action RNG stream — and every seeded test — is byte-for-byte unchanged. On the
  debug overlay as "attending to you". Unit-tested in `TestCompanionAttention`.
- ✅ **Payoffs wired.** Shared-attention now feeds **bond** (`grow_per_shared_attention`,
  novelty-gated in the familiarity map — co-attending the same spot fades) and **mood**
  (a warming valence lift). Added a **being-noticed** read (`noticed_strength`: the player
  turning toward and easing up to the companion) that also lifts valence. A shared moment
  is counted when attention is strong enough *and* the companion is beside what you're
  focused on; suppressed on a frame you actually examined something (that moment counts
  once). Tested in `TestCompanionSelf` (+ being-noticed reads in `TestCompanionAttention`).

---

## ✅ Mechanism #4 — Variety-based ("un-farmable") bond

Bond growth should track genuine play — variety + meaningful events — not repetition
or idle time. Replaces the grindable model in current code.

### Source changes (rewrite `CompanionSelf._grow_bond`)
- **Raw presence — dropped.** No more passive growth just from the game running.
- **Proximity time — kept, but only as a slow trickle.** The gentle long-tail
  finisher; deliberately slow so parking next to the companion isn't the optimal play.
- **Interactions — novelty-weighted** (see habituation), not flat-per-poke.

### Meaningful-event sources (all novelty-gated unless noted)
- **New-prop interaction** — first real encounter with a prop.
- **New-area discovery** ✅ — reaching a new region. Area id = `world_id:region_id`
  (`WorldAreas.resolve`), resolved from the companion's position against rectangles authored
  in `world.json`; a position in no region is the world default ("wilds"). **Binary**, not
  decayed: a place you've been earns nothing on return (also makes it immune to
  boundary-jitter farming). The spawn area is recorded as "home" — known, no bump. Because
  ids are **world-namespaced** and familiarity persists, this scales straight to the
  world-of-worlds north star: a brand-new world is all-novel, a revisited one is silent. A
  discovery also feeds the mood discovery spike.
- **Shared-attention moment** (from #1) — you and it attended to the same thing;
  novelty-gated per object (sharing the same rock twice doesn't keep paying).
- **Proximity trickle** — the only non-novelty, time-based source; small.

**Rough priority (tuning, not code):** shared-attention ≈ new-area > new-prop >
proximity-trickle. Doing/discovering *together* matters most; passive proximity least.

### Habituation (the un-grindable mechanism + a memory seed)
- **Granularity:** per-**individual-object id** (start). A weak per-type component is a
  possible later refinement.
- **Discount:** each meaningful encounter bumps `familiarity[id]`; bond gain *and*
  reaction strength scale by a novelty factor that decays from ~1 to a **hard floor of
  0**.
- **No fade:** familiarity never decays — a familiar prop goes (and stays) quiet.
- This is the cozy seed of the spec's memory system: kills the grind *and* makes the
  companion stop reacting to repeated stimuli (reads as presence; the next novel thing
  pops harder).

### No decay
Bond is **monotonic** in the cozy stage. Trust-damage / regression is a danger-era
mechanic, deferred.

### Consequences (accepted)
- **Mood (#2) is now load-bearing for freshness.** With object-novelty at a zero floor
  and no fade, day-to-day variety must come from the mood layer + stochastic
  expression, not from the (small, fixed) world.
- **Bond curve front-loads on discovery, then tapers to the proximity trickle**, and how
  far novelty can carry bond is gated by world content. Fine for the current slice
  (proving the early fresh→bonding arc). The real game will need enough novel content +
  non-object shared experiences for bond to *complete* without a stand-around grind.
  Later tuning dependency.

### Code touchpoints
- Rewrite `CompanionSelf._grow_bond`; add a persistent `familiarity` map to
  `CompanionSelf` (part of the saved mind), keyed by stable prop/area ids.
- **World must hand props/areas stable ids** (POIs are currently bare `Vector2`s).
- New `companion.json` tunables for per-source weights + the novelty curve; retire
  `grow_per_sec` (raw presence).

---

## ✅ Personality model — identity / disposition / mood (structure)

Three layers of the **same** personality dimensions (curiosity, energy, clinginess, …),
distinguished by **job**, not just timescale. Behavior reads **disposition**; mood
modulates the *how*; identity is the slow anchor disposition orbits.

### Identity (slow core / anchor)
- Starts **somewhat randomized** (birth seed).
- **Learns toward the player's long-run play style, paced by bond**, and **crystallizes**
  (drift rate tapers) as bond → 1, so a deeply bonded companion's core is stable.
- Converges to **within a threshold** of play style but **retains a slight variance toward
  its birth inclination** — never an exact match, so two identically-playing players still
  get faintly distinct companions. (Fixes "stuck timid by bad luck" without erasing
  individuality.)
- Preserves the spec's "never feels lost": movement is slow, directed toward you, and
  locks in when bond is deepest. Deliberately shifts the fantasy toward "**raise a creature
  that grows into a reflection of you**" — consistent with the "companion as self" pillar.

### Disposition (live personality / medium-term, reversible)
- The value behavior actually reads. **Orbits identity**, nudged by recent events/play,
  **regresses toward identity** over time, **bounded to identity ± band**.
- Home for **lingering states like "upset"** — too meaningful for mood, not deep enough to
  rewrite identity. Reversible.
- **Separate from bond** (key architectural point): bond (attachment) is monotonic;
  disposition holds the *current* relational state incl. wariness. Separation is what
  produces **"wounded but loyal"** — deeply bonded *and* currently wary. The spec's later
  "damaged-trust → mild, recoverable regression" is a disposition-layer effect.
- Our existing drifting `traits` become this layer (now regressing toward identity +
  bounded near it, rather than toward play-style directly / the wide global min-max).

### Mood (fast affective overlay) — ✅
- **Representation:** 2D — **valence** (withdrawn ↔ warm) + **arousal** (calm ↔ energized).
  Dominance (confidence) reserved for the danger era.
- **Baseline:** decays toward a **disposition-derived** resting point (energetic disposition
  → higher resting arousal; warm → higher resting valence), not flat neutral — so each
  companion's moods orbit a different center (different emotional "weather").
- **Drivers** (all reuse existing signals; no new perception):
  - *Event spikes:* novel discovery (valence + arousal ↑; habituated props barely move it),
    shared-attention (valence ↑), being-noticed by the player (valence ↑), separation
    (valence ↓, **bond-scaled** — a fresh companion likes its independence).
  - *Continuous couplings:* **arousal contagion** (your movement energy nudges its arousal;
    light, slightly bond-scaled), **boredom** (a stretch without novelty drifts arousal
    down — mild, so the next novel thing pops).
  - *Autonomous random walk:* small per-tick nudges relaxing toward the disposition
    baseline. **The primary variety source** — makes "today" differ from "yesterday" even
    with no events (essential since object-novelty no longer refreshes). Events are spikes
    on top.
  - *Cozy asymmetry:* mood leans positive (calm-content ↔ excited-delight, only mild
    listless/lonely dips). Strong negatives (fear, hurt) arrive with danger/upset later.
- **Expression / integration:** each mood axis is the transient overlay of a disposition
  trait — **arousal ↔ energy**, **valence ↔ warmth (clinginess)**; curiosity has no mood
  axis. Integrate as a **bounded additive overlay in `CompanionTraits`**:
  `effective_energy = clamp(disposition.energy + arousal_overlay)`, likewise warmth. Every
  action already reading those traits (Wander pauses, Idle hop/look, CheckIn eagerness,
  Follow keenness) then responds **for free**; `companion_view` reads mood for animation
  polish. Mood thus biases the **decision**, not just the look. Variety stays stochastic
  (mood shifts probabilities; existing RNG picks the beat) and smooth (continuous/decaying
  → behavior reads as weather, not switches).
- **Full chain:** identity → disposition → (+ mood overlay) → effective trait → arbiter +
  animation.

### Scope note
No "upset-the-companion" interactions are built in the cozy slice yet — we only establish
disposition as the layer so such states slot in later without restructuring.

### Code touchpoints
- `CompanionSelf`: split current `traits` into `identity` (slow) + `disposition` (the live,
  drifting/regressing value); give `mood` real dynamics. Persist all.
- Drift rewrite: identity learns slowly + bond-crystallizes + keeps a birth residual;
  disposition regresses toward identity, bounded to identity ± band, bumped by events.

### Implementation status
- ✅ **Mood dynamics built.** 2D `mood_valence`/`mood_arousal` on `CompanionSelf`
  (`update_mood`, called from the brain on its own RNG so action decisions stay
  reproducible): trait-derived resting point, novel-discovery spike (novelty-weighted via
  the habituation map), bond-scaled separation dip, arousal contagion, boredom, random
  walk, cozy negative floor — all data-tuned in `companion.json` `"mood"`. Integrated as a
  bounded additive overlay in `CompanionTraits.value` (arousal→energy, valence→clinginess),
  so every action that reads those traits responds for free. Mood is on the debug overlay
  (signed valence/arousal bars + effective-vs-raw traits). Tests cover resting derivation,
  discovery spike, habituation dampening, and the effective-trait overlay.
- ✅ **Identity/disposition split built.** `CompanionSelf` now carries three layers:
  `birth` (fixed inclination, set at creation), `identity` (slow anchor — learns toward
  play style, target pulled slightly back toward birth via `birth_residual`, learning rate
  crystallizes as `(1-bond)^crystallize_exp` so a bonded core locks), and `traits` (the
  live **disposition** behavior reads, which regresses toward identity bounded to
  `identity ± band`). Mood overlays the disposition. In the cozy slice disposition simply
  tracks identity (no events push it yet) — the machinery is in place so a later "upset"
  push relaxes back on its own, and bond stays separate so "wounded but loyal" is possible.
  Old saves seed identity/birth from their saved disposition (no snap). Both layers shown
  on the debug overlay; tested in `TestCompanionSelf` (crystallization, birth individuality,
  disposition relaxation, round-trip, migration).
- ⬜ **Deferred mood drivers:** the "being-noticed by the player" valence bump and the
  shared-attention valence lift both wait on Mechanism #1 (social referencing); only the
  discovery spike is wired now (it doubles as the shared-examine moment).

---

## ✅ Mechanism #2 — In-character gating / refusal

The *capability* this gates (errands / commands) is a **future** feature — we have nothing
to command yet. This beat locks the **principle** and the **shape of how it will use the
reserved `command`/`task` band**, and confirms our affect stack can already render it.
Two of the spec's four refusal causes are expressible with current state (bond, mood); two
need the danger/upset layer.

### The principle (locked)
- Capabilities are gated on **hidden state** (bond), **never a meter or a grayed-out
  button** — consistent with our implicit-state ethos.
- An unmet gate is shown **in character**: hesitation, looking between you and the task,
  reluctant body language. The player **infers** the cause — that inference *is* the
  storytelling.
- **Partial states are the teacher.** Just-below-threshold = goes a short way and hurries
  back, or does it nervously. The gradient teaches the mechanic with no UI.
- **Every "no" points to its remedy**, and always includes an **acknowledgment beat**
  ("I heard you, and… no") — a refusal *without* acknowledgment reads as a bug, not a
  feeling.

### The mechanism (reuses the affect stack)
A refusal is **not** a dedicated "refuse" animation. It is: *don't execute the task, and
let current affect show, so the emotional **temperature** communicates why.* Sequence:
1. **Acknowledge** — perk / look at you ("heard you").
2. **Hesitate** — the beat of delay (same believability lever as social referencing).
3. **Decline + express** — doesn't go; body language colored by the **dominant blocking
   emotion**, read straight off mood / disposition / bond.

Same base beat, different temperature → different cause. Plus **stochastic surface
variation** so it's never the identical shuffle twice.

### The seam
Rides the reserved **`command`/`task` band**: a commanded task whose gate is unmet
**routes to this decline beat at command-band priority** instead of running the task; the
decline reads the affect stack for its temperature; near-threshold → partial compliance.
No new arbitration — it's the seam we already left open.

### Causes (resolved for cozy)

**Bond gates; mood only modulates manner.** Bond decides *whether* it goes; mood decides
*how willingly*. This keeps cozy cozy — a bad-mood day never hard-blocks the player.

- **Not-bonded-enough** — the one true cozy refusal cause. Bond below the gate → a genuine
  decline, temperature **warm / hopeful / bashful**: attention keeps **returning to you**
  (looks between you and the task, half-step toward it then back, leans *in* not away —
  approaching, never retreating). Near-threshold → **partial compliance** (goes a short way
  and hurries back). Points to its remedy (*more time together*), which arrives on its own
  as bond grows over a normal playthrough.
- **Wrong-mood** — **not a gate**; a **manner modifier**. Low arousal/valence → it still
  goes, just **reluctantly**: longer hesitation beat, slower, less zest. Reads off the mood
  overlay → effective energy/warmth, which **already** biases eagerness across every action,
  so this is nearly free. Never a flat "no" in the cozy stage.

**Priority when both apply:** bond-reluctance is **dominant** (it's the real gate); mood
colors the *manner* of that decline. Express the dominant cause purely.

**Forward-compat:** build *not-bonded* unmistakably **warm/approaching** now, so the
deferred **cool/guarded/withdrawing** *damaged-trust* cause can never be confused with it —
both are "wary of you," opposite temperatures by construction.

**Deferred (need danger/upset):** *afraid-of-target* (directional fear at the world) and
*damaged-trust* (withdrawal with edge — a disposition-layer effect). **Mood escalating to a
true refusal** (fear, hurt overriding willingness) also belongs to this strong-negative
layer; cozy mood dips only dampen.

---

## ⬜ Open threads (walkthrough queue)

In rough priority order for the cozy stage:

1. **Memory consolidation, networking split, UGC tooling** — deferred infrastructure;
   context only until feel is proven.

---

## ✅ Appraisal model + tag vocabulary (locked small)

The architecture the spec wants: the **world** describes things with NEUTRAL tags; the
**companion** decides how it feels. Authors tag a prop `shiny`/`water`/`made` without
knowing any companion's psychology — the danger-era version (a `predator` tag + a timid
companion → fear) is the same shape, just scarier inputs.

**Built (small):**
- **Schema:** `tags: [String]` on each interactable in `world.json` (neutral descriptors).
- **Pure appraisal:** `CompanionAppraisal.appeal(tags, cfg, curiosity)` → 0..1, from
  data-driven per-tag **affinities** (the creature's tastes, in `companion.json`
  `"appraisal"`) modulated by curiosity. Unknown/absent tags read neutral. Computed once in
  `perception` (as `interaction_appeal`) so consumers share it.
- **Two felt wirings:** the **mood** discovery spike on examine scales by appeal (lights up
  for a loved find, barely stirs for a plain one — composes as `novelty × appeal`); and
  `InvestigateAction` **lingers longer** admiring liked things. On the debug overlay as
  "last appeal".
- Tested: `TestCompanionAppraisal` + a delight-scaling test in `TestCompanionSelf`.

**Deferred (noted, not needed to lock the schema):**
- **Per-companion taste individuality** — tastes are species-shared for now (only curiosity
  varies appeal per companion). Born-jittered + persisted affinities (like birth traits) are
  a small fast-follow for "my companion loves crystals, yours loves water."
- **Appraisal-biased wandering** — being drawn to *roam toward* high-appeal props needs POI
  tags threaded through perception (a bigger perception change); examine-time appraisal only
  for now.
- **Affinity drift** — coming to love what you engage with together.

---

## ✅ Salience interruption — graded commitment inertia

The spec asked to refine fixed-band preemption toward a continuous salience *score*. The
load-bearing idea turned out to be **commitment inertia**, not "make priority continuous":
a continuous score that's still a function of the same signals would just re-cross and
dither (this is what the wander↔follow limit cycle was — `commit_bonus`, a temporal
id-hysteresis, couldn't damp a feedback loop where the decision drives the deciding signal).

**Resolution.** The arbiter's two ad-hoc within-band mechanisms — the fixed `commit_bonus`
and the binary `interruptible()` flag — are unified into one continuous quantity,
`CompanionAction.commitment(cfg)`: the desire-units resistance the running action adds to
its own desire. A same-band rival must clear `desire + commitment` to take over. Default is
the small universal nudge (`commit_bonus`); a committed beat (a roam underway, a visit, a
look) returns `commit_bonus + committed_inertia`, a value deliberately larger than any
same-band rival's plausible desire — so a committed beat is released only by its **own
state** (e.g. a roam giving up its target → bids 0 → ineligible), never by a desire
crossover, which is what stops the cycle from re-forming at a higher threshold. Preemption
*within* a band is now one smooth comparison; the binary flag is gone.

**Bands stay as structure.** Band is still compared before desire, so a higher band always
preempts — commitment is within-band only. Grading preemption *across* bands (a mild vs a
sudden threat) is a **danger-era** concern, deferred: in the cozy slice the cross-band beats
are the sacred "it noticed me" moments (a look, a check-in), which *should* hard-preempt.
`commitment()` is also the natural seam where a future graded danger salience generalizes.

---

## ⚠️ Flagged issues in current code

- **Bond is grindable.** `CompanionSelf._grow_bond` grew bond from raw presence
  (`grow_per_sec`), proximity time, and a flat per-interaction bump — all farmable by
  standing still or poking one prop.
  → **✅ Resolved in code.** Raw presence dropped; per-examine bump is now
  **novelty-weighted** via a persistent per-prop `familiarity` map (geometric decay to
  ~0, never fades); proximity kept only as a slow trickle. Stable prop ids now flow
  world → view → perception → self. Tests cover idle-presence-flat, per-prop habituation,
  and round-trip. **Still deferred** (need their prerequisites): new-area discovery
  (needs area ids) and shared-attention (needs Mechanism #1). Reaction-strength scaling by
  novelty also deferred to a later increment.

---

## Notes / conventions

- Keep Layers 1–2 (the "mind": drives, affect, intentions) presentation-agnostic and
  headless-safe, per CLAUDE.md — no `SceneTree`/render/`AnimationPlayer` deps.
- All companion state stays **implicit** — communicated through behavior, never a
  player-facing meter. (Dev debug overlay is fine.)
- Tunables live in `data/companion.json`; behavior logic stays data-driven.
