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
- **Two tensions, now resolved** (see the framing decisions): direction vs. delegation → **they
  coexist** (D2); campaign vs. cozy-shared → **cozy shared mini-worlds, no fail states** (D3). The
  spec **directs** the companion (tap = order) while the shipped **Ruin** **delegates** ("Go look,"
  never steer) — both are valid command styles on one surface.

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

## Framing decisions (settled — these anchor everything after)

- ✅ **D1 — Scope & timing.** **Firmly out of Rung 4.** Rung 4 (the persistent shared world) is
  done and has grown past its original scope; `CLAUDE.md`'s phase status was updated to reflect
  this. This companion-direction work is the exploratory next direction (proximity text chat is
  deferred, not a blocker).
- ✅ **D2 — Command model: coexist.** Direction (tap an object = an order resolved through the
  current form) and delegation ("Go look," never steer) **both live**; neither supersedes the
  other. "Go look" reads as the form/verb with an implicit target — one point on the same
  command surface, not a rival paradigm.
- ✅ **D3 — Game framing: cozy shared world, no fail states.** Forms/puzzles are **for-fun authored
  mini-worlds people visit, like the Ruin** — content inside the shared online world, solvable
  alone / better together, challenge opt-in. **Not** a single-player campaign; the spec's
  "finish the game / levels" language is reframed as these cozy mini-worlds.

---

## Item backlog (all open; each awaits a decision)

Each item notes *reuse* (existing code) and *new* (to build) as information for the decision —
not as a plan to act on.

### Input & targeting
- 🔶 **I-1 — Tap an interactable = an order.** Decided: a **fixed bottom-left joystick** walks the
  player; a **click/tap anywhere else** commands the companion — it snaps to the nearest interactable
  within a generous radius (`TAP_PICK_RADIUS`) and the companion paths there, noses it with a perk + a
  targeting glow, then resumes (**go + acknowledge**; no world effect yet — that's F-2/C-1). **Coexists**
  with the existing player-examine (Space/bubble). Built: fixed `virtual_joystick.gd`, a new
  `VisitAction` command verb (+ config + tests), and world-tap routing via a single full-screen
  **`WorldTapCatcher`** behind the HUD (GUI picking — see the architecture note below). Non-hit taps
  (I-3) and recall-by-tapping-the-companion (I-4) deferred. **Awaiting playtest.**
- ⬜ **I-2 — Keyboard-only desktop path.** Tab-cycle interactables + confirm key.
- ⬜ **I-3 — Non-registering-tap tell.** A small "received, nothing to do" feedback.
  *Reuse:* `world_art.gd` pulse.
- ⬜ **I-4 — Recall by tapping the companion.** Tap the companion → release its task, resume
  following. *Reuse:* command-band order clearing the active task.
- ⬜ **I-5 — Layout guardrail.** Keep interactables out of the bottom-left stick zone / bias camera
  right-of-center. (Authoring convention more than code.)

> **📌 Input architecture — deferred "right" refactor (do it when a world-action multiplies).**
> Tap *routing* is solid: GUI picking against a full-screen `WorldTapCatcher` at the back of the UI
> layer cleanly answers "HUD vs world," and adding a new **HUD** action is trivial (put a `Control` in
> front — it can't leak). What's still minimal-by-design is the **world-action layer**:
> `world_controller._on_world_tap` is a single hardcoded path (press-gesture only → "visit the nearest
> interactable"). As soon as world taps do *more than one thing*, split it along two seams: **(1)** a
> small **gesture recognizer** in the catcher (tap / hold / long-press — it only knows "press" today,
> needed for F-4's hold-radial) and **(2)** a **resolver** in place of the hardcoded verb —
> `resolve(gesture, target, current_form) → intent` — so F-2/C-1 (form-as-verb), F-4 (hold-radial), and
> I-4 (tap-companion) plug in without reshaping. Deliberately deferred until F-2/C-1 tells us the actual
> gesture/verb vocabulary, so we don't abstract before we know its inputs.

### Form system
- ✅ **F-1 — Reframe "form": cosmetic → functional (keystone).** Decided: a **LAYER** over the
  autonomous drift. You *instruct* a form (via the companion radial); it holds for a **bond-scaled**
  duration (low bond = brief, always obeys), then **releases back to the drift**; and as bond grows
  the drift **biases toward a temperament-derived signature form**. This is form *control*, not yet
  form *function* (capabilities = F-2/C-1). Built in `companion_form.gd` (pure layer + tests),
  `companion_view.gd` (`instruct_form`), `world_controller.gd` (radial picker), and the `daemon_form`
  config. **Playtested and confirmed working.**
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
