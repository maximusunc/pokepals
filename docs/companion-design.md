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
| **Social referencing** | Borrow courage from a calm, advancing player | Glance at / drift toward what *you're* attending to | ✅ designed |
| **In-character gating / refusal** | Balk at the scary place; every "no" points to its remedy | Errand-readiness: hesitate when not bonded, go readily once bonded | ⬜ open |
| **Salience interruption** | A sudden threat overrides a committed plan | A player interaction overrides a wander | 🔶 mostly have (bands); spec wants a continuous salience *score* |
| **Variety-based bond** | Bond deepens by surviving danger together | Bond deepens via shared novelty / new places / time alongside — not grindable repetition | ⚠️ next thread |

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

---

## ⬜ Open threads (walkthrough queue)

In rough priority order for the cozy stage:

1. **Variety-based / un-farmable bond** (next) — fix grindable bond; tie growth to
   novelty + meaningful events (incl. shared-attention moments from #1) + habituation.
2. **Personality tiers + mood** — identity (fixed) / disposition (bounded drift,
   regresses) / mood (transient, the primary variety engine). Gives the unused `mood`
   field a job; decides whether to add regression + a fixed identity floor.
3. **In-character gating / refusal** — errand-readiness expressed as a creature that
   doesn't trust you *yet*, not a grayed-out button. Rides on the bond axis. (Uses the
   reserved `command`/`task` bands.)
4. **Appraisal model + tag vocabulary** — neutral world facts the companion
   interprets; scope depends on staying cozy. Lock the schema early but small.
5. **Memory consolidation, networking split, UGC tooling** — deferred infrastructure;
   context only until feel is proven.

---

## ⚠️ Flagged issues in current code

- **Bond is grindable.** `CompanionSelf._grow_bond` grows bond from raw presence
  (`grow_per_sec`), proximity time (`grow_per_sec_near`), and interaction count
  (`grow_per_interaction`) — all farmable by standing still or poking one prop. The
  spec wants variety + meaningful events + habituation. (Thread #1 of the open queue.)

---

## Notes / conventions

- Keep Layers 1–2 (the "mind": drives, affect, intentions) presentation-agnostic and
  headless-safe, per CLAUDE.md — no `SceneTree`/render/`AnimationPlayer` deps.
- All companion state stays **implicit** — communicated through behavior, never a
  player-facing meter. (Dev debug overlay is fine.)
- Tunables live in `data/companion.json`; behavior logic stays data-driven.
