# Companion Direction & Forms — Working Design (Action Backlog)

A living record of the **directed, shape-shifting companion** design — the "Companion Design
Spec" broken into action items we walk through **one at a time**. Every item here is a decision
the project owner makes; nothing is pre-approved, and nothing gets built until it's confirmed in
words. Rationale gets recorded here as each item is decided, the same way
`docs/companion-design.md` (the companion *mind*) and `docs/puzzle-world-the-ruin-design.md` (the
first puzzle world) capture their decisions.

**Status legend:** ✅ Resolved (decided; ready to build or built) · 🔶 In progress · ⬜ Open /
not yet decided · 🅿️ Parked (deliberately deferred).

**Working rule (from CLAUDE.md):** never assume a decision or act before actual confirmation. If
a question doesn't reach the owner, stop and wait — no best-guessing.

---

## Where this sits (context)

- The game today is **cozy, online-only, mid-Rung-4** (networking; proximity text chat is the
  last stated step). The companion is **autonomous**, influenced by the player only through a few
  bond-gated commands (Pet / Call / "Go look").
- This spec is a **large gameplay-direction expansion**: the player *directs* a companion that
  *shape-shifts into functional forms*, and orders it to act on objects by tapping them.
- **Two tensions to resolve, not assume** (see the framing decisions): the spec **directs** the
  companion while the shipped **Ruin** deliberately **delegates** ("Go look," never steer it); and
  the spec's "finish the game / levels" language reads single-player-campaign while the game is
  online-only + cozy.

### What the current code already provides (reuse surface)

| Capability | Where it lives | Note |
|---|---|---|
| Virtual joystick + WASD/arrows | `scripts/presentation/virtual_joystick.gd`, `player_controller.gd` | Matches the spec's input table |
| Companion radial (Pet/Call/Go-look) | `scripts/presentation/companion_radial.gd` | A working contextual arc to repurpose |
| Self-contained actions on priority *bands*, with reserved `command` + `task` bands | `scripts/world/companion_actions.gd`, `companion_arbiter.gd`, `companion_brain.gd::issue_command` | Documented seam for player orders — a verb = one action + JSON |
| Interactables with stable `id`, neutral `tags`, `label`, `interactive` flag | world specs (`tests/world_fixtures/*.json`), `world_controller._setup_contents` | `tags` already feed `companion_appraisal.gd` |
| Per-object glow/pulse | `scripts/presentation/world_art.gd` | Substrate for form-keyed highlighting |
| Obstacle-routing for the companion | `scripts/world/nav_grid.gd`, `nav_agent.gd` | "Idle following paths around obstacles" is already true |
| Companion drawn AS a real animal | `scripts/world/companion_form.gd`, `pal_sprite.gd` | **Cosmetic only** today (random, ephemeral) |
| Bond-gated refusal + 2D mood sim | `companion_self.gd`, Come/Pet actions; decline beat designed in `companion-design.md` | Refusal + emotional expression foundation |

### Genuinely new machinery the spec would need

Tap-to-*target*-an-object-as-an-order · **functional** forms · form→object affordance resolution
· contextual form filtering + collection menu · form progression · form-keyed highlighting ·
general held/durational states · the autonomy curve + override · separation cost ·
recall-by-tapping-companion.

---

## Framing decisions (settle these first — they reshape everything after)

- ⬜ **D1 — Scope & timing vs. Rung 4.** Active pivot now, plan-now-build-after, or parallel
  groundwork alongside networking?
- ⬜ **D2 — Command model: direction vs. delegation.** Reconcile the spec's "tap = order" with the
  Ruin's "Go look, never steer." Direction supersedes / coexists with / defers to delegation?
  (Note: the spec's taps target *objects, not ground*, and keep autonomous idle-following — so the
  real fork is whether the player names the *verb* or the companion still chooses.)
- ⬜ **D3 — Game framing: cozy shared world vs. authored campaign.** Authored content inside the
  shared online world (no fail states, like the Ruin), or a directed single-player progression
  reconciled with online-only later?

---

## Item backlog (all open; each awaits a decision)

Each item notes *reuse* (existing code) and *new* (to build) as information for the decision —
not as a plan to act on.

### Input & targeting
- ⬜ **I-1 — Tap an interactable = an order.** Tap/click hit-tests interactables, snaps to nearest
  within a generous radius, issues a companion order; empty-ground taps do nothing.
  *Reuse:* `_interactables`, `issue_command`. *New:* object hit-testing (today: proximity +
  fixed Examine bubble, no picking).
- ⬜ **I-2 — Keyboard-only desktop path.** Tab-cycle interactables + confirm key.
- ⬜ **I-3 — Non-registering-tap tell.** A small "received, nothing to do" feedback.
  *Reuse:* `world_art.gd` pulse.
- ⬜ **I-4 — Recall by tapping the companion.** Tap the companion → release its task, resume
  following. *Reuse:* command-band order clearing the active task.
- ⬜ **I-5 — Layout guardrail.** Keep interactables out of the bottom-left stick zone / bias camera
  right-of-center. (Authoring convention more than code.)

### Form system
- ⬜ **F-1 — Reframe "form": cosmetic → functional (keystone).** Does the functional form system
  replace, extend, or run beside the cosmetic daemon-form? *Anchor:* `companion_form.gd`,
  `daemon_form` in `data/companion.json`.
- ⬜ **F-2 — Form as a verb.** Each form = one command-band `CompanionAction`. *Reuse:* the action
  seam (no arbiter change).
- ⬜ **F-3 — Contextual filtering.** Own ~20 forms, see 3 at a time, filtered by object `tags` +
  context. *Reuse:* neutral `tags` + `companion_appraisal` matching.
- ⬜ **F-4 — Tap = smart default; hold = radial of 3–4 forms.** *Reuse:* `companion_radial.gd`
  (repurpose from fixed to per-target contextual; add hold-to-open).
- ⬜ **F-5 — Collection menu.** Full roster, browsable not operational. *Reuse:* `gear_menu.gd`
  pattern.
- ⬜ **F-6 — Legibility.** Silhouette communicates capability; distinct constraints per form; no
  stats/tooltips. (Art + design guardrail per form.)

### Action & affordance system
- ⬜ **C-1 — One action per form per object.** Ambiguity = a level-design bug (split the object).
  *New:* an optional per-form affordance map on props; resolved in `world_controller._try_interact`.
- ⬜ **C-2 — Held/durational states, generalized.** tap-to-start / tap-to-release, visible
  in-world. *Reuse:* the Ruin's persistent plate-hold (re-issued `settle`) → a reusable `task`-band
  held action.
- ⬜ **C-3 — Objects highlight in the current form's color.** Switching forms changes what lights
  up (free hint layer). *Reuse:* `world_art.gd` glow.
- ⬜ **C-4 — Escape-hatch long-press radial.** Two-option fallback with a strict usage budget
  (frequent need = form vocabulary too coarse).

### Companion behavior
- ⬜ **B-1 — Idle following is load-bearing.** Step behind, path around obstacles, perch, drift to
  points of interest. *Mostly built:* Follow/Wander/Idle + nav + attention; item = tune to bar +
  add "perch."
- ⬜ **B-2 — Refusal is expressive.** Decline a tap (head shake, look back) without error UI.
  *Reuse:* bond-gated decline + the designed acknowledge→hesitate→decline beat.
- ⬜ **B-3 — Memory is visible + player override mandatory.** Forms-learned journal, confidence
  indicator, visible hesitation; auto-selection never fires against intent. *Anchor:*
  `companion_self.gd`. Ties to Q-1.
- ⬜ **B-4 — Involuntary emotional form shifts** under fear/injury (small-and-hiding /
  bristling-large). Cozy stage has no fear/injury inputs yet (deferred to the "danger era" in
  `companion-design.md`) — decide whether to introduce a mild version now or defer.

### Design principles (authoring guardrails) + one mechanic
- ⬜ **P-1..P-5 — The five principles as world-authoring guardrails:** open-ended overall / nearly
  closed at any moment; avoid lock-and-key (aim for 2–3 solutions of differing elegance);
  two-body puzzles ("what do I do while it does that"); separation has a cost; diegetic
  tutorialization (drift toward relevant objects / flicker into the right shape).
- ⬜ **P-6 — Separation cost as a real mechanic.** Distance limits with consequences (slower,
  desaturation, pain). *Reuse:* the existing `separation_valence` feeling → extend to a mechanic.
  Severity is a cozy-vs-tension call.

### The open prototyping question
- ⬜ **Q-1 — Prototype the fully-automatic autonomy end-state early.** Does manual→suggested→
  automatic feel rewarding ("my companion knows me now") or like the game playing itself? Per the
  spec: build the automatic end-state first and feel it; if boring, cap autonomy at "suggests."
  *Anchor:* bond/identity already model "knows you" (`companion_self.gd`).

---

## How we work through it

1. Settle the **framing decisions (D1–D3)** — they reshape the sequence.
2. Go **strictly one item at a time**: decide the item → record the decision here → (only then)
   build if it's a build item → play/verify → commit. No moving on, and no building, without
   explicit confirmation.
3. If a question doesn't reach the owner, **halt and wait** — never best-guess.

## Verification

The bar is **feel**, validated by playtest (per CLAUDE.md). Pure logic (form resolution,
affordance mapping, autonomy gating) lands in `scripts/world/` as node-free `RefCounted` with unit
tests in `tests/` (like `test_companion_form.gd`, `test_companion_command.gd`), run via
`tests/run_tests.gd`. Feel items: run the game, playtest the specific beat, tune before moving on.
