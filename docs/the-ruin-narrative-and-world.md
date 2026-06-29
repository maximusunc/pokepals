# The Ruin — Narrative & World Design

A senior-design pass turning the Ruin from a puzzle gauntlet into a *place with a story*.
The mechanics already exist (see `puzzle-world-the-ruin-design.md`); this doc is about
**fiction, space, mood, and pacing** — what the player feels, in what order, and why.

Status: **vision + in-progress build.** Names/terms are deliberate **placeholders** (called
out as such) meant to be replaced later — including the art, which is procedural placeholder
geometry ready to swap for Claude Design assets.

---

## 1. The story (the fiction the place embodies)

> **The Sanctuary of Two**, raised by the **Wardens** *(placeholder name)* — people who lived
> beside bonded companions, as you do. They believed a bond was only *whole* once it had been
> **shared with another pair**. So deep in the wood they built a sanctuary that was also a
> **rite**: pairs came here and walked it together, and every mechanism in it was made to be
> worked by a person *and* their companion — you simply cannot pass it alone. At its heart
> stood the **Hall of Two**, a great door that no single pair could ever open — only **two
> pairs, together**. To pass it was to be joined into the wider kith; to no longer be alone.

> Then the Wardens dwindled. Pairs stopped coming. The **last Warden** and their old companion
> kept the lamps lit as long as they could — but the Hall of Two cannot be opened by one. So
> the last Warden lived out their years before a door they could not pass, and when they were
> gone the lamps guttered out, the forest crept in over the stones, and a place built for
> *togetherness* ended in **solitude**, and was forgotten.

You and your companion wander into that wood and come upon it.

**Why this story is the right one:** it *is* the game's thesis (a companion is an extension of
you; togetherness is the long game) rendered as place and history. The mechanics don't
illustrate the theme — they **are** it: every device needs your companion, and the climax needs
*another person*. The emotional payoff is already built (the muted solo waking vs. the full
two-pair waking) — the story just gives it a hundred years of weight.

**Terms (all placeholders, swap freely):** the Wardens · the Sanctuary of Two · the Hall of
Two · *kith* (a bonded companion / the bond) · the Rite of Two (the passage).

---

## 2. The journey (space = story = pacing)

The fix for "you just jump from one puzzle to the next" is **distance and descent**: you should
travel *between* beats, and the travel should tell the story and turn the screw on mood. The
world reads top-to-bottom as **outside → down → in → deep → and back into light**:

| Beat | Space | Mood | Story it tells | Puzzle |
|---|---|---|---|---|
| **0. The Wood** | A forest clearing; dappled light, drifting motes, birdsong *(audio later)*. A path leads off. | Warm, alive, unhurried. | *You're nowhere yet.* The portal sets you down in living forest, not on a doorstep. | — |
| **1. The Approach** | The path winds; trees crowd; you start passing **fallen stones, a toppled pillar, roots prying up flagstones** — then a **broken arch** half-swallowed by the wood. | Curiosity, a hush. | *You happen upon it.* The forest has eaten a made thing. Your companion notices first (it leads/perks). | — |
| **2. The Mouth** | A **ruined facade**; broken **steps down** into the dark. The day-light falls away behind you. | The threshold of unease. | Crossing from world into underworld; from now into then. | — |
| **3. Entrance Hall** | A **narrow, carved corridor**, torchlit *(placeholder torches)*. First **carving**: the Wardens and their kith, in better days. | Close, creepy, intimate. | Story beat 1 — *who built this, and how they lived.* | — |
| **4. The Threshold** | The first chamber: the buried weight-plate + slab. | Tentative. | The place only answers to a *pair*. | Seek → plate → slab |
| **5. The Gallery of Two** *(in-between)* | A **grand colonnade** — standing and toppled columns you walk *among* (not a corridor); torchlit; the **Rite of Two** carvings. | Faded grandeur. | *What this place was for* — pairs walking it in procession. | — |
| **6. The Warren** | The caved-in gallery; four alike gaps. | Decay. | The wood and time breaking in. | Read the nose → true gap |
| **7. The Rockfall** *(in-between)* | A **collapsed chamber choked with great rubble piles** — you weave a winding path between mounds. The **dwindling** carving on a leaning slab. | Claustrophobic, the wood's weight pressing down. | The ruin visibly *broken*; the slow loss. | — |
| **8. The Cistern** | Pitch dark; the dead ember, the cold brazier, the murals. | Bleak, then a kindled warmth. | The lamps *can* be relit — by a pair. | Kindle → carry light |
| **9. The Sunken Grove** *(in-between)* | The ceiling has fallen in: a **shaft of daylight**, a **still dark pool** you skirt, roots and moss and pale flowers. The **last Warden** carving. | A breath of light, grief-tinged, before the climax. | The wood breaks *in*; the heart of the sadness. | — |
| **10. The Hall of Two** | The great door; two plates; the wedge. | Reverence / weight. | *Do what the last Warden could not.* | Two plates at once |
| **11. The Waking** | Beyond the door: light returns; flowers; the way home. | Release. **Muted** (alone) or **full** (two pairs). | Solitude echoed, or togetherness restored. | — |

**The in-betweens are the connective tissue, and each one is a *different kind* of space** —
deliberately not three identical corridors. They share three jobs (turn the mood screw, hold one
story carving, and make you *travel* between beats) but each does them with its own geometry and
way of moving: you **walk among** the Gallery's columns, **weave between** the Rockfall's piles,
and **skirt around** the Grove's pool under its shaft of light. The one genuinely *narrow* hallway
is kept where it belongs — the **Entrance Hall** at the mouth (beat 3), the "creepy descent in."
Each in-between darkens the descent another notch, except the Grove, which *lifts* it for a beat —
the light returning just before the Hall.

---

## 3. Mood & light (the descent as a dimmer)

One continuous idea ties the space together: **light leaves you as you go down, and you bring it
back at the end.** Implemented as **per-region ambient gloom** — each region declares how dark
it is, and the screen eases toward that as you cross into it:

- **The Wood:** bright, warm wash (gloom 0).
- **Approach → Mouth:** the light drains (gloom rises).
- **Entrance → Threshold → Warren:** ruin-dark, torch-pooled.
- **The Cistern:** near-black until you relight it (its puzzle *is* the dark — already built).
- **Hall of Two → Waking:** dark, then — on the waking — **light floods back** (gloom drops),
  the brightest beat since the forest. The arc closes.

Torches/braziers give **local pools of warm, flickering light** (placeholder glow); dust/spores
drift in the still air; the deeper rooms get colder color and heavier vignette.

---

## 4. Look & animation direction (placeholders, swappable)

All new art is **procedural placeholder geometry** — readable silhouettes that establish the
*mood and staging*, built to be replaced 1:1 with Claude Design assets later (each is its own
`type` in `world_art.gd`, drawn by one small function, easy to swap for a sprite).

New placeholder prop **types**:

- `facade` — a broken stone archway/wall-front: the ruin's mouth.
- `stairs` — a flight of broken steps descending into dark.
- `carving` — a wall relief panel; **lit/unlit** state; examinable to read its story line.
- `torch` — a wall sconce with a **flickering** warm glow (animation).
- `roots` / `vines` — the wood prying into the stone (overgrowth).
- `rubble_pile`, `broken_pillar` — scattered ruin debris; the Rockfall's piles are `rubble_pile`s at scale.
- `pool` — a still, dark body of water (the Sunken Grove); solid.
- `light_shaft` — a soft column of daylight with drifting motes, falling through a broken ceiling.
- (existing, reused: `slab`, `nook`, `ember`, `brazier`, `mural`, `plate`, `wedge`, `column`.)
- The **Gallery** reuses `column`/`broken_pillar`/`carving`/`torch`; the **Rockfall** reuses `rubble_pile`.

Animation polish (procedural, cheap, immersive):

- **Torch/brazier flicker** — warm glow that breathes and jitters.
- **Drifting dust/spores** — slow motes in the still rooms (denser deep, airier in the wood).
- **The waking** — a light-bloom sweep when the Hall opens.
- Companion **leads you in** at the Approach (reuse LeadAction toward the ruin mouth) — *it*
  finds the place first.

> **Hand-off note for Claude Design:** every placeholder is a single `type` + one draw function.
> A replacement asset just needs to occupy the same footprint (a `facade` ~120×80, a `carving`
> ~32×40 panel, a `torch` a small wall fixture, etc.). The *staging* (where things sit, how the
> light pools, the descent's darkening) is the part this pass locks in; the *surface* is yours.

---

## 5. Build order (this is incremental)

1. **Arrival reframe** *(done)* — the Wood, the Approach, the Mouth, the Entrance Hall;
   reposition the portal into the forest; per-region gloom; the first placeholder art (facade,
   stairs, carving, torch, roots) + dust/flicker; carving 1.
2. **Deepen the descent** *(done)* — the rooms pulled apart and three **varied** in-betweens
   dropped into the gaps (the Gallery of Two, the Rockfall, the Sunken Grove), each with its own
   geometry and one carving; new placeholder art (`pool`, `light_shaft`); the grove lifts the
   gloom for a beat before the climax. *(Wards/ids untouched — coords shifted rigidly with their room.)*
3. **The waking** *(next)* — the light-bloom + the brighter sanctum on the Hall opening.
4. **Audio + Claude Design art swap** *(later)* — ambience, footsteps, the carving reveals; real
   assets over the placeholders.

Nothing here touches the **puzzle logic or the server** — the wards, ids, and relationships are
all preserved. This is world, mood, and story layered *around* the working machine.
