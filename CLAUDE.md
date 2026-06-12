# CLAUDE.md

## Project: Kithbound (working title — rename freely)

A cozy, 2D, companion-centered world game, built in **Godot 4** with **GDScript**,
designed mobile-friendly from the start.

### The soul of it

Every player has a single **bonded companion creature** — not a collection, but one
partner that is an extension of *you*: it travels with you everywhere, has a personality,
and over time reflects who you are and how you play. The game is a warm, living world you
inhabit *beside* that companion. The deepest appeal is companionship, discovery, and being
together with other people — not combat or completion.

### The long-term north star (CONTEXT ONLY — we are NOT building this yet)

Eventually this could grow into a world-of-worlds people build and visit together: a place
where the companion is the constant self you carry through many player-made worlds, and
where worlds might be experienced in 2D, 3D, or even VR. That is the destination, years
out. **Do not build the platform, multiplayer, UGC tools, 3D, or VR.** We reach it the way
Roblox and Minecraft did: by first making one small, beautiful, authored thing that proves
the core feeling is real.

-----

## Current phase — Rung 1: single-player, offline “companion + world” vertical slice

**Done = a small 2D world I can walk through beside a companion that feels like it’s
genuinely *mine*, and that makes me want to keep walking around in it.**

The whole point of this rung is to answer one question: *does moving through a little
world next to a living-feeling companion feel like something?* This is a test of FEEL, not
features. Favor atmosphere, presence, and charm over systems.

### In scope now

- A small, hand-made 2D world to explore (a few connected screens or a modest tile area).
- One companion that follows the player, moves naturally, and reacts to the world and to
  the player’s actions (idle behaviors, little reactions, a sense of attention/aliveness).
- Smooth player movement and a camera that frames the player-and-companion well.
- Light, cozy interactions with the world (e.g., things to look at, touch, or trigger that
  the companion responds to) — enough to make presence feel alive.
- A simple, warm aesthetic and mood (placeholder art is fine, but the *vibe* matters here).

### Explicitly OUT of scope now (do not build these yet)

- Networking / multiplayer / other players.
- World-building or any user-generated-content tools.
- 3D or VR anything.
- Battling, catching, collecting multiple creatures, stats, or progression systems.
- Accounts, database, servers (Phoenix/Postgres).
- Art and audio polish beyond what’s needed to feel the mood.

### How we’ll know it’s working

If a playtester (or you) wanders the space, notices the companion, and lingers because it
feels nice to be there — that’s success. If it feels like a tech demo, we iterate on
presence and mood, not on adding features.

-----

## Architectural disciplines (hold these from day one — they’re cheap now, costly later)

1. **Separate logic from presentation.** Game/world logic (state, rules, companion
   behavior decisions) must not directly reference UI nodes or rendering. Logic decides
   *what* happens; the presentation layer decides *how it looks*. Keep behavior logic in
   its own scripts that could run without the visuals attached.
1. **Keep the world layer presentation-agnostic.** Think of the eventual architecture as a
   shared “world/engine layer” (state, entities, companion, rules) and a swappable
   “presentation layer” (how it’s drawn and controlled). Today there’s only a 2D
   presentation — but if the world logic never assumes 2D specifics where it doesn’t have
   to, we leave the door open for 3D/VR presentations far down the line, and for moving
   shared logic onto a server later. Don’t build for 3D/VR now; just don’t actively wall
   it out.

Why both matter: this same separation is what later lets the core move onto an
authoritative server, lets the game run on mobile/desktop/web, and keeps the door cracked
for 3D/VR worlds — all without a rewrite.

-----

## Tech stack

- **Engine / client:** Godot 4.x, **GDScript**. Target mobile + desktop (and web later).
- **Persistence (this phase):** optional local save as JSON in `user://`.
- **Later rungs (NOT now — context only):**
  - First shared-presence tests: Godot built-in multiplayer (ENet), then WebSockets.
  - Persistent shared world: authoritative server in **Elixir/Phoenix** (Channels +
    Presence) with **PostgreSQL** via Ecto.

-----

## Suggested project structure

```
/scenes        Godot scenes (.tscn): World, Player, Companion, UI
/scripts       GDScript
  /world       World/companion LOGIC — no UI/render references (portable later)
  /presentation UI + view controllers that read state and render it
/data          Companion + world definitions (Godot Resources or JSON) — data-driven
/assets        Placeholder sprites, fonts, ambient sound
```

-----

## Conventions

- GDScript: `snake_case` for variables/functions, `PascalCase` for classes/node names,
  `ALL_CAPS` for constants.
- Data-driven: define the companion’s traits/reactions and world content as data, so they
  can be tuned without code changes.
- Keep behavior logic deterministic and side-effect-light where practical (state in, state
  out) — easy to test, portable to a server later.
- Small, single-purpose commits. One bit of feel at a time.

-----

## How to work with me

- I used Godot a few years ago and have forgotten most of it. Briefly explain
  Godot-specific concepts (nodes, scenes, signals, resources, the scene tree, tweens) as
  they come up.
- This rung is about *feel*. Prefer iterating on presence, motion, and mood over adding
  mechanics. If I start drifting toward multiplayer, world-building, 3D/VR, or battle
  systems, remind me we’re proving the companion bond first.
- Teach me the “why” behind a Godot pattern, not just code to paste.
- When something is worth running and *feeling* before moving on, tell me to go play it.

-----

## Roadmap (the ladder — context only; build only the current rung)

1. **[CURRENT]** Single-player, offline companion + small world vertical slice. Prove the
   bond feels real.
1. Deepen the single-player loop: cozy world interactions, a companion that subtly evolves
   to reflect the player, local save.
1. Two players sharing a space for the first time — seeing each other and each other’s
   companions (Godot ENet, then WebSockets).
1. A small persistent shared world: WebSockets + Elixir/Phoenix Presence + proximity text
   chat.
1. World-building / UGC tools, and only much later, other presentations (3D/VR). The
   “world-of-worlds” north star.

-----

## IP & safety notes (keep in mind; nothing to act on at Rung 1)

- The “soul-bonded animal companion” is an ancient, freely-usable archetype (familiars,
  spirit-guides, etc.). Build on the archetype, but invent original creatures, original
  companion mythology, and original terminology — do not borrow specific named lore from
  His Dark Materials/The Golden Compass or from Pokémon.
- If this ever becomes a UGC platform with a young audience, content moderation and child
  safety are first-class design obligations, not afterthoughts. Not relevant at Rung 1,
  but the architecture should never make them impossible to add.

-----

## Design pillars (context for naming/structure — do NOT over-build now)

- **Companion as self:** one bonded partner, expressive, reflects the player. The
  connective tissue of everything.
- **Cozy by default, challenge by choice:** no punishing fail states required to enjoy it;
  any competition/stakes are opt-in later.
- **A place, not a task:** the world should be somewhere people *want to be*, with its own
  warm identity — not a Pokémon or Roblox look-alike.
- **Togetherness is the long game:** eventually the best thing in the world is the other
  people in it. Everything is built to make being together feel good.

These are a hypothesis to playtest, not a spec. Expect to revise them based on what
actually feels good to play.
