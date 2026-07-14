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

### The long-term north star

Eventually this could grow into a world-of-worlds people build and visit together: a place
where the companion is the constant self you carry through many player-made worlds, and
where worlds might be experienced in 2D, 3D, or even VR. That is the destination, years
out. **Do not build the platform, multiplayer, UGC tools, 3D, or VR.** We reach it the way
Roblox and Minecraft did: by first making one small, beautiful, authored thing that proves
the core feeling is real.

-----

## Phase status — Rung 3 complete ✅ · now in Rung 4 (step 1: a minimal authoritative server)

**Where we are (2026-06):** the single-player core (Rungs 1–2) is proven and locked in, and
first two-player shared presence (Rung 3) proved out. The bar for every rung is *feel*,
validated by playtest — never a feature checklist.

**What proved out:**
- **Rung 1 ✅** — walking a small 2D world beside one living-feeling companion feels like
  *something*; it’s a place you want to linger in, not a tech demo.
- **Rung 2 ✅** — the companion subtly evolves to reflect how you play *and that evolution is
  now perceptible*: its resting look (ear/posture, idle liveliness, gaze, coat warmth, body
  size) mirrors its grown identity + bond, so the bond is felt, not just simulated. Cozy
  world interactions (examine, pet, call, shared-attention, companion-led discovery, the
  riverbank hunt) and local save (companion self + player appearance in `user://`) are in.
- **Rung 3 ✅** — two players share a space for the first time: each sees the other’s avatar
  *and* their bonded companion move through the world, with the right worn appearance and
  resting-look. Built behind a single transport seam (`scripts/net/net.gd`) over Godot’s
  built-in multiplayer (ENet listen-server), Solo play untouched.

**Deliberately deferred (not blockers):** persistent coat *mark*, favorite-place memory,
deeper behavioral legibility — pickup-able whenever we deepen the single-player loop again.

**Next — we are now in Rung 4** (a small persistent shared world). We take it one step at a time.
**Step 1 ✅:** swapped the transport for raw WebSockets and stood up a *minimal authoritative
server* (Elixir/Phoenix, Bandit + WebSock) that assigns ids and relays presence. **Step 2 ✅:**
the roster now runs on **Phoenix.Presence** (a CRDT — robust crash/disconnect detection, multi-node
ready); the server adapts Presence diffs into the unchanged client wire protocol, so the Godot
client was untouched. **Step 3 ✅ (a deliberate pivot):** the game is now **online-only** — the
companion's grown self and the wardrobe live **server-side** (PostgreSQL via Ecto), keyed by a local
identity *token* (`user://player_id.json`); there is **no local game save and no solo/offline mode**.
Connecting to a server is required to play. **Remaining Rung-4 step:** proximity text chat. The
FEEL-first philosophy still governs.

> **Ambient pals (2026-06):** the Vale now has **server-authoritative ambient pals** — set-dressing
> creatures that wander as shared atmosphere so the world reads as alive at low population. This is the
> server's *first* bit of world *simulation* (a per-world `Server.AmbientPals` sim ticked by
> `Server.World`, broadcast like presence), a small, deliberate step past the earlier "id assignment +
> relay only" scope. The sim also does **server-side obstacle avoidance** — an Elixir port of the
> client's `Solids` circle collision, so pals steer around trees/props/ponds authoritatively. The
> **border treeline is now generated server-side too** (`Server.WorldBorder`, baked into each spec as
> `border_trees`) and consumed by the client for drawing + its avatar collision — one source of truth,
> no client-side ring generation. It's atmosphere only: no bonding, no interaction. The companion
> "finding" beat (bonding to one of them) remains out of scope. Each species pal also **shifts form**
> over time (daemon-style), decided in the same server sim (`AmbientPals` owns a per-pal morph timer +
> species table) and relayed in the `s`/`v` fields of the ambient tick, so every client sees the same
> animal at the same moment; the client `PalView.apply_form` swaps the sheet (with a little pop).

> **Pixel-art pipeline (2026-07):** player wardrobe art and ambient-pal sprites are now generated
> from the hand-authored ASCII pixel maps in `pokepals/tools/pixelart/` (see its README — Pillow is a
> tools-only dependency; PNGs stay committed). `tools/gen_wardrobe.py` exports per-layer 8-frame dye
> sheets for the paper-doll wardrobe; `tools/gen_pals.py` bakes real animal species (cat/fox/rabbit/
> bird/wolf) for ambient pals, rendered client-side by `PalView` when a seed pal names a `species`
> (companion-puppet fallback otherwise).

> **Daemon form (2026-07):** the bonded companion now WEARS one of those real animals and, in the
> spirit of a His Dark Materials daemon, occasionally shifts into a different one. The species is
> cosmetic and ephemeral (re-rolled each session, never saved, never touching the brain/bond/grown
> self), decided by a small presentation-agnostic `CompanionForm` (`scripts/world`) and drawn by
> `CompanionView` through the shared `PalSprite` core (refactored out of `PalView`, so pals and the
> companion draw identically). It IS relayed over the identity packet so a shared world stays coherent
> (friends see the same animal). Tuned by `daemon_form` in `data/companion.json` (`enabled:false`
> restores the classic procedural rig, which is still the fallback when no pal art is present).

> **Pivot note (2026-06):** Rungs 1–2 were offline-first single-player. We have since chosen to make
> the companion a *server-resident* identity you carry across sessions/devices, which means dropping
> solo/offline. Treat the "offline single-player core" and "solo stays first-class" language below as
> historical — superseded by the online-only model.

### In scope now (Rung 4, step 1)

- The proven single-player world, companion, movement, camera, and cozy interactions — the
  living base everything shared is layered on top of.
- A **minimal authoritative server** (Elixir/Phoenix) and a **raw-WebSocket + JSON** client
  transport: the server assigns ids, holds the roster, and relays each player’s presentation
  state (avatar + companion transforms, identity/appearance) to the others.
- Two (or a few) players sharing the same space, seeing each other’s avatar and companion
  move — the shared-presence feel from Rung 3, now over the real client↔server topology.
- A **server-canonical companion + wardrobe** (Postgres), loaded on connect and saved back, keyed
  by a local identity token. The game is **online-only** — no solo/offline path, no local game save.

### Explicitly OUT of scope now (later Rung-4 steps, or further out)

- Phoenix **Presence**, **Postgres/Ecto persistence** (server-canonical companion/wardrobe
  save), and **proximity text chat** — these are the *next* Rung-4 steps, not this one.
- Accounts / authentication, and any server-side game simulation or world-mutation authority
  beyond id assignment + relay.
- World-building or any user-generated-content tools.
- 3D or VR anything.
- Battling, catching, collecting multiple creatures, stats, or progression systems.
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
- **Persistence:** **server-canonical** — the companion self + wardrobe live in **PostgreSQL** (Ecto,
  jsonb), keyed by a client-generated identity token. The only thing in `user://` is that token
  (`player_id.json`); there is no local game save. (Rungs 1–2 used local `user://` saves — now retired.)
- **Networking (current — Rung 4):**
  - First shared-presence tests used Godot built-in multiplayer (ENet)
  - raw WebSockets + JSON between the client and a **minimal authoritative
    Elixir/Phoenix server** (Bandit + `Phoenix.PubSub`) — id assignment + presence relay only.
  - Deepen the server: **Phoenix Presence** (proper roster) + **PostgreSQL** via Ecto for a
    server-canonical companion/wardrobe.

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
- Every rung is about *feel*, including this one. Shared presence has to feel warm and
  alive — two people and their companions simply being somewhere together — not like a
  netcode demo. Prefer iterating on that presence over piling on networked mechanics.
- Teach me the “why” behind a Godot pattern, not just code to paste.
- When something is worth running and *feeling* before moving on, tell me to go play it.

-----

## Roadmap (the ladder — context only; build only the current rung)

1. **[DONE ✅]** Single-player, offline companion + small world vertical slice. Prove the
   bond feels real.
1. **[DONE ✅]** Deepen the single-player loop: cozy world interactions, a companion that
   subtly evolves to reflect the player, local save.
1. **[DONE ✅]** Two players sharing a space for the first time — seeing each other and each
   other’s companions (Godot ENet, behind a swappable transport seam).
1. **[DONE ]** A small persistent shared world. Done: WebSockets + a minimal
   authoritative Elixir/Phoenix server (step 1), Phoenix.Presence roster (step 2), and Postgres
   persistence of a now **server-resident companion** — which made the game **online-only** (step 3).
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
