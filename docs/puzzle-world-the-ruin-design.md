# The Ruin — A Companion-as-Actor Puzzle World (Working Design)

A living record of the design for our first **puzzle world**: an overgrown quiet
ruin you explore *through* your companion. This doc captures the decisions made in
the design brainstorm so the first slice can be built directly. Like every rung,
the bar is **feel**, validated by playtest — not a feature checklist.

**Status legend:** ✅ Resolved (ready to build) · 🔶 In progress · ⬜ Open / not yet
discussed.

---

## The core idea ✅

A puzzle world that *only this game could have*. Every other puzzle game has blocks,
switches, and pressure plates. We have the one thing they don't: **a bonded
companion with its own agency.** So the puzzles are solved *through* that partner,
never beside it.

The seed mechanic already exists in the salamander hunt: **only the companion
perceives the hidden truth; your skill is reading and trusting it.** The Ruin
escalates that from *sensing* to *acting*.

### The pillar fit

- **Companion as self:** the ruin literally cannot be operated by a person alone —
  it deepens the partnership instead of distracting from it.
- **Cozy by default, challenge by choice:** no fail states, no timers, no game-over.
  Being stuck just means the ruin stays quiet while you and your partner keep poking.
- **A place, not a task:** rewards are *the place responding* (light returning, a
  view opening, a warm spot to linger) — never loot or progression.
- **Togetherness is the long game:** the finale was built for **two pairs** and
  dramatizes exactly that.

---

## The fiction that justifies everything ✅

> The ruin was built by people who lived alongside bonded companions too — and they
> built the place to be **operated by pairs.** Doors are companion-height.
> Mechanisms need a creature's nose, or weight, or a carried light. A person alone
> can't work this place; a person *and their companion* can. And a few things were
> built for **two** pairs — and haven't moved since there was more than one of them
> here.

This single idea earns the whole design: companion-as-actor (the ruin *requires*
your partner to act where you can't), co-op (a poignant in-fiction reason — *"this
hasn't opened since there were two"*), and the theme (the ruin's logic *is* the
puzzle's logic).

(IP note per CLAUDE.md: the "place built for bonded pairs" mythology and all
terminology here are original — invent freely, borrow no named lore.)

---

## The verb: "go look" ✅ (the design's spine)

The player **delegates** to the companion; they do not steer it. The command is dead
simple — our existing whistle/"come," re-pointed from *"come here"* to *"go find
it."* One button (mobile-friendly). The companion then ranges out on its **own
agency** — reusing the agent loop (`PERCEIVE → DECIDE → ACT`) and the rich
wander/investigate/idle behaviors — and works the space itself.

This is a deliberate pivot away from "mark a spot, it paths there": that makes the
companion a remote-controlled tool; *delegation* makes it a trusted partner. The bond
*is* the difficulty curve — a deep-bonded companion beelines and focuses; a fresh one
wanders, distracted, doubles back (same scaling as the salamander tells).

### The spectator risk, and the fix ✅

If the companion autonomously *finds and solves*, the player becomes a spectator —
and a spectator isn't doing a puzzle. The fix is **division of labor**:

> **The companion is the nose and the small body; you are the head and the hands.**

- **It** does the creature-things you delegate (noses out the hidden hollow, squeezes
  into a gap, stands on a plate, carries a light) — on its own, once sent.
- **You** do the person-things it can't (brace the heavy thing it found, reach the
  high alcove it sniffed out) and — crucially — **figure out *what* to send it to
  find.** The deduction is yours; the search is its.

So the "puzzle" is **relational + deductive**, not spatial-mechanical. This is a
conscious dial: the Ruin is "cozy delegation with deduction," *not* a Zelda dungeon.
If we ever want it crunchier/more spatial, "no directing" is the wrong call and we
revisit.

### Keeping "no directing" without leaving the player powerless ✅

Two diegetic levers give the player influence without ever steering the companion:

1. **Where you stand and look gently biases its search.** It searches *outward from
   you* and toward what you're attending to (reusing existing proximity + attention
   systems). Walking over yourself softly suggests "around here" — accompaniment, not
   a leash.
2. **Bond is the competence curve** (as above) — the relationship is the difficulty.

---

## The difficulty curve: light-touch → genuinely puzzly ✅

The **deduction load** (figuring out *what* to send the companion for) rises room by
room. The connective tissue is the **murals** — and the loop closes on itself:
murals are dark until the companion *carries light to them*, so **the thing it
fetches reveals the clues you need to deduce the next thing to send it for.** The
delegation loop feeds itself.

| Space | Deduction | What it teaches |
|---|---|---|
| **Threshold** | **None (pure a).** You're simply stuck; you send it to look. | The whole loop in miniature: stuck → delegate the search → it finds what you couldn't see → it acts → go on. |
| **The Warren** | **Low (a).** The *what* is given ("find the way"), but several nooks look identical — you can't tell which is real; it can. | Trusting your partner over your own eyes. |
| **The Cistern** | **The hinge (a→b).** Nothing tells you what's needed — you must *infer* "this place needs light," then send it for the source. | Naming the need yourself. (Its carried light starts revealing murals = clues for the finale.) |
| **The Paired Hall** | **Full (b).** The mechanism announces nothing — you assemble its secret from murals gathered across all prior rooms. | The whole world clicking into place at once. |

No room ever hard-blocks. Stuck = the ruin stays quiet, cozy, while you keep poking.

---

## The four spaces

### 1. Threshold — the teaching room ✅

A mossy antechamber: low light, vines, a fallen arch. A heavy stone slab is lowered
across the only way deeper, with **no visible mechanism.** You're gently, immediately
stuck — by design, because the room exists to make you reach for the defining move.

**You send your companion to look.** It ranges out, noses the mossy floor (its
sense — the salamander-detector pattern, *only it perceives the hidden truth*), and
paws away moss to **uncover a buried companion-plate you never saw.** It settles its
weight; an old latch catches; the slab grinds up and *stays.* You walk through
together.

Teaches the entire game in ~90 seconds with **zero deduction**. Textures:
- **Bond shows immediately** — bonded noses straight to it and settles; fresh one
  wanders and doubles back. The tutorial already *feels* like your relationship.
- **Your presence softly guides** — it searches outward from you, so drifting toward
  the slab nudges it the right way.
- **Deliberately saved for the Hall:** the cruel detail that holding a plate *slips*
  when the companion leaves. The Threshold latch just stays. Clean escalation.

### 2. The Warren — trust over your own eyes 🔶

Several collapsed nooks look identical; you can't tell which hides the way through.
*It* can. Send it to search; read its tells as it noses; it clears the true passage.
First taste of believing your partner against the evidence of your own eyes.

### 3. The Cistern — name the need 🔶

Dark. Nothing tells you what's missing — you must *infer* the place needs light
(e.g. a cold, unlit sconce; foreshadowing from the Threshold). You deduce it, send
the companion to find/carry a mote of light, and place what it reveals. The carried
light begins lighting **murals** — your first clues for the Paired Hall.

### 4. The Paired Hall — the heart ✅ (design), 🔶 (build staging)

The mechanism was built for **two** companions searching/holding at once, and it
announces nothing. You assemble its secret from murals gathered across all prior
rooms (the two figures in the Cistern, the paired marks in the Warren) — realize it
was *built for two* — and only then understand both solutions.

**The lonely path (chosen design):** with one companion it can still be done, but
only in **slow, patient sequence** — it finds and holds one side, but the old
mechanism *slips* the moment it leaves to work the other. So you improvise the long
way: send it to find something to *wedge* the first side (a mini-search of its own),
then send it to the second, ferrying back and forth while the hall stays dim and
hushed. It **works** — no fail state — but it's solitary, patient labor, and the
quiet is the point.

**Tiered payoff:**
- **Alone:** a *muted* waking — one lamp catches, a single chime, the door opens just
  enough. Real, earned, a little melancholy.
- **With a second pair:** the *full* waking — light runs the whole hall, the old two
  who lived here glimpsed for a moment, a shared bond-bump for **both** pairs. The
  thing the lonely last inhabitant never got to feel again.

Finding a friend feels like *relief and warmth*, not a checkbox — "togetherness is
the long game," dramatized.

---

## How it sits on the architecture ✅

Solo-first, this is entirely in-architecture today.

- **World:** a new spec `the-ruin.json` (the `WorldRouter` + JSON pattern), with a
  portal in from an existing world, the four spaces as **regions**, and
  slab/plate/sconce/mural/mechanism as **interactables**.
- **Logic:** a pure module `ruin_mechanisms.gd`, sibling to `salamander_hunt.gd` —
  holds the hidden truths (where the plate is, what each search resolves to, slab
  up/down), state in → state out, **no node/scene-tree references.**
- **Companion:** one new command — **Seek** — in `companion_actions.gd` +
  considerations in `companion.json`. A command-band action like Come, but its target
  is "go work the current goal" instead of "come to me," reusing the Investigate/Lead
  machinery.
- **Presentation:** `world_controller` wires the new button → brain goal and renders
  the mechanism's reported state via `WorldArt`/`Scenery`. The brain never sees the
  scene tree.

### Co-op build staging ✅ (honest about scope)

Co-op puzzles need **shared world state**, which is *server-side world mutation* —
explicitly out of scope this rung per CLAUDE.md ("beyond id assignment + relay"), and
the stated next step is proximity chat with shared *presence* landing first. So:

1. **Now (in-architecture):** the whole ruin + all verbs, **every puzzle solvable
   solo**, single-player. The right way to find out if "send my partner to search" is
   as warm as we hope, before any netcode.
2. **Medium (relay, not authority):** make co-op state shared by *relaying puzzle
   events through the existing `world:<id>` channel* — the same seam as presence
   relay, not new server simulation. Honest cost: no persistence, late-joiners see
   partial state, it trusts the client. Fine for cozy; the world resets when empty
   (like the hunt reshuffles).
3. **Later (authority):** if it sings, move puzzle state server-side for real
   consistency/persistence. The out-of-scope-now step.

**Recommended order:** build solo-first, prove the verbs feel good, *then* decide
whether relay-coop comes before or after chat.

---

## Decisions locked in this brainstorm ✅

- Puzzle spine: **companion-as-actor**, expressed as **delegated autonomous search**
  ("go look," no directing).
- Co-op: **cozy co-op** (solvable alone, better together) — built **solo-first**,
  co-op via **relay** later, authority last.
- Theme: **overgrown quiet ruin**, with the "built for bonded pairs" fiction.
- Player agency: **division of labor** (companion = nose + small body; player = head
  + hands + deduction).
- Difficulty: **start light-touch (a), edge toward genuinely puzzly (b)** across the
  four rooms.
- Paired Hall solo route: a **longer, lonelier path** with a muted (vs. full) waking.

## Open / next ⬜

- Build the **Threshold** solo-first as the first feel-test ("send my partner to
  search, and watch it come through").
- Nail the **Seek** command's read-out: how the player *sees* the search is working
  (getting warmer / found it) via the existing tell system, so it reads as alive, not
  a loading bar.
- Original naming for the ruin, the companion-plates, and the "pairs" mythology.
- Decide relay-coop timing relative to proximity chat.
