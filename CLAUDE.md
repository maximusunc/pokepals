# CLAUDE.md

## Project: Pokepals (working title — rename freely)

A 2D, turn-based creature-collector game built in **Godot 4** with **GDScript**.

**Long-term vision:** a cozy co-op MMO about *befriending* creatures (not capturing
them), raising them over their lifetimes, battling alongside friends, and tending a
shared, persistent world that responds to what the whole community does.

**Important:** we are NOT building the MMO yet. We are deliberately on **Rung 1** of a
staged ladder. The goal of this phase is to find out whether the core battle is *fun*,
as a single-player, offline prototype — before any networking, world, or persistence
work. Help me stay scoped to the current rung. If I start drifting toward servers,
accounts, or the open world, remind me we're proving the fun first.

---

## Current phase — Rung 1: single-player, offline turn-based battle

**Done = a playable battle between two creatures on my local machine that feels good
enough that I want to keep playing it.**

### In scope now
- A single Battle scene: two creatures face off, turn-based.
- 3–6 placeholder creatures, each with basic stats and 2–4 moves.
- A simple affinity/type system: start with 3–5 types in a rock-paper-scissors-style
  relationship. Keep it data-driven and easy to retune.
- The turn loop: choose action → resolve via pure logic → apply damage/effects/status →
  check win/lose → next turn.
- Minimal UI: HP bars, move selection, clear turn-by-turn feedback.
- Placeholder art only (colored shapes or free sprites). No art polish.

### Explicitly OUT of scope now (do not build these yet)
- Networking or multiplayer of any kind.
- The overworld, tile map, or movement.
- Catching / befriending creatures.
- Accounts, database, Phoenix server, PostgreSQL.
- Sound design and art polish beyond placeholders.

---

## The one architectural rule that matters now

Keep **battle resolution as pure logic with zero UI/engine dependencies.** Put it in its
own module under `scripts/battle/` that takes battle state in and returns new battle
state out — deterministic, no direct references to nodes or the scene tree. The UI reads
that state and renders it; it never computes outcomes itself.

Why: at a later rung this exact module moves onto an authoritative server unchanged. If
we entangle battle rules with the UI now, we pay for it with a rewrite later. This is the
single most important habit for this project.

---

## Tech stack

- **Engine:** Godot 4.x
- **Language:** GDScript
- **Persistence (this phase):** optional local save as JSON in `user://`
- **Later rungs (NOT now, listed only for context):**
  - First 2-player test: Godot built-in multiplayer (ENet)
  - Shared-world MMO phase: WebSockets transport; authoritative server in
    **Elixir/Phoenix** (Channels + Presence) with **PostgreSQL** (via Ecto)

---

## Suggested project structure

```
/scenes        Godot scenes (.tscn): Battle, UI pieces
/scripts       GDScript
  /battle      PURE battle logic — no node/UI references (portable to a server later)
  /ui          UI controllers that read battle state and render it
/data          Creature and move definitions (Godot Resources or JSON) — data-driven
/assets        Placeholder sprites, fonts, sound
```

---

## Conventions

- GDScript: `snake_case` for variables/functions, `PascalCase` for classes/node names,
  `ALL_CAPS` for constants.
- Data-driven design: define creatures and moves as data, not hardcoded logic, so I can
  rebalance by editing data, not code.
- Battle logic should be deterministic and side-effect-free where practical (pass state
  in, return state out) — easy to test, and portable to a server later.
- Small, single-purpose commits. One mechanic at a time.

---

## How to work with me

- I used Godot a few years ago and have forgotten most of it. When Godot-specific
  concepts come up (nodes, scenes, signals, resources, the scene tree), explain them
  briefly as we go.
- Favor a finished, playable slice over architectural perfection — *except* for the pure
  battle-logic separation above, which is worth getting right from day one.
- Prefer teaching me the "why" of a Godot pattern over just handing me code I paste.
- If a step is a good moment to run and feel the game, tell me to do that before moving on.

---

## Roadmap (the ladder — context only; build only the current rung)

1. **[CURRENT]** Single-player, offline turn-based battle.
2. Single-player overworld: tile movement, wild encounters, befriending, a small team,
   local save.
3. Two players, one battle, over a direct connection (Godot ENet).
4. Shared overworld for a handful of players: WebSockets, Elixir/Phoenix + Presence,
   proximity text chat.
5. Content and scale.

---

## Design north star (context for naming/structure — do NOT implement beyond Rung 1)

Differentiators we're aiming for eventually, kept in mind so names and data structures
don't paint us into a corner:
- Befriend rather than capture (no "spheres"/balls as the core verb).
- Creatures as individuals: inheritable traits, personalities, life cycles.
- A tactical/positional lean to battles rather than pure 1v1 stat-trading.
- A persistent shared world that remembers and responds to the whole player base.

These are a hypothesis to be playtested, not a spec. The battle rules especially are meant
to be torn up and retuned based on what actually feels fun.