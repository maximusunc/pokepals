# Scaling: from a few friends to a crowd

**Status (2026-10-31):** a plan for discussion. **Every item below is open/undecided.** As with the
other design docs, we decide one item at a time, record the decision here, and only then build it.
**Since (2026-11-26):** SC-0 is decided, SC-1 has run, and SC-3 and SC-4 are built; each says so below.

**Why now:** the Bazaar felt laggy, and that raised the real question: this is meant to be a shared
world, so can it hold many hundreds or thousands of players?

## What the Bazaar lag actually was

It wasn't the server or the network. Measured on the real scene, with the same camera spot in each
world:

| | Vale | Bazaar (before) | Bazaar (after the fix) |
|---|---|---|---|
| Server: ambient sim per 10 Hz tick | 0.2 ms | 0.7 ms | 0.7 ms |
| Network: bytes per ambient update | 3.3 KB | 3.2 KB | 3.2 KB |
| Client: GPU draw calls per frame | 103 | **1,396** | 208 |
| Client: script time per frame | 1× | ~1.6× | ~1× |

The client was redrawing every wall, roof and stall each frame, and drawing every overhead bulb as
its own call. The fix (garland batching plus `StaticBake`, which draws a world's unmoving structure
into textures once) brought it to about the Vale's cost. Most of the 208 is the 78 people.

**Lesson:** "lag" has two sources, and the client one bites first. Any scaling plan has to budget
the **drawing** side as well as the server side.

## How the server works today

- **One process per world.** `Server.World` (a GenServer) holds that world's live positions. Worlds
  start on demand under a `DynamicSupervisor` and are found through a node-local `Registry`.
- **Every movement is relayed to everyone in the world.**
  1. Each client sends its pair's transform about **20 times a second**.
  2. The channel casts it to the world process.
  3. The world process broadcasts it on the world's PubSub topic.
  4. **Every** other player's channel pushes it down its socket, encoding the JSON once per socket.
- **The ambient pal sim** runs at 10 Hz and is broadcast to everyone in the world the same way.
- **The client draws every peer:** a full `PlayerView` and companion for each, with no limit.
- **It runs on one machine.** The code already flags the multi-node step (Horde and libcluster) as
  deferred. Phoenix.PubSub and Presence already work across nodes.

### What that costs as a world fills up

Each player sends 20 updates a second, and each update goes out to every other player:

| players in one world | messages in / s | pushes out / s | each client receives / s |
|---|---|---|---|
| 10 | 200 | 1,800 | 180 |
| 100 | 2,000 | 198,000 | 1,980 |
| 1,000 | 20,000 | ~20,000,000 | ~20,000 |

The outgoing work grows with the **square** of the crowd. Separately from the server, each phone
would also be drawing every one of those players.

## How shared worlds usually handle crowds

No MMO puts a thousand people in one shared view. They combine four ideas:

1. **Batched updates.** A fixed tick sends each client one bundle with everything that changed,
   instead of a message per player per move.
2. **Interest management.** You only receive the people near you, roughly a screen plus a margin.
3. **Instances (shards).** A busy world splits into copies, each capped at some number of players.
   Friends are steered into the same copy.
4. **Drawing limits.** The client fully draws the nearest K people, draws the next ring more simply,
   and hides the rest.

With all four, the cost per player stays about constant however many are online. The total grows in
a straight line with the player count, and we add machines to absorb it. That's the shape we want.

The BEAM, the Erlang VM that Elixir runs on, suits this well. A world, an instance or a region of a
world is just another lightweight process, and PubSub fan-out across machines is built in.

## The items, in a suggested order

### ✅ SC-0 — What "a crowd" means for us *(decided 2026-10-31)*
**The guiding principle:** keep pushing the boundaries of what today's technology can do. For
reference: a Roblox server usually holds up to about 100 players and a Fortnite match holds 100. Big
live events run as many parallel copies. EVE Online is the frontier, running one shared universe with
thousands in a single battle. **The targets:**
- **One world, no visible copies.** Nobody ever sees "server full", and everyone in the Vale really
  is in the same Vale. That reshapes SC-5: a big world is split **by area** across processes and
  machines, and players cross between areas without noticing, instead of being sorted into capped
  copies.
- **Thousands in one world at once:** on the order of **10,000** in the Vale, made possible by
  interest management (SC-4).
- **Hundreds in one place:** on the order of **500** gathered in the square for an event. The server
  must carry this.
- **About 100–200 drawn on a phone at once:** the nearest drawn fully, the next ring more simply
  (SC-2). The phone sets this ceiling, not the servers.

### ✅ SC-1 — Measure first: a load test with bot players *(built and run 2026-10-31)*
**The tools:** `tools/loadtest/` (see its README).
- `bots.mjs`: Node bots that speak the real client protocol. They join a world, wander, send the
  client's packet at 20 Hz, and measure how old each peer update is when it lands.
- `probe.exs`: attaches to the running server node and samples CPU, the run queue and the mailboxes.
- `run.sh`: steps the crowd up.

**The rig:** a dev server and the bots on the same 4-core cloud container, in the Vale, 40 s per step.

| bots in one world | each bot receives / s | KB / bot / s | latency p50 | p95 | p99 | server CPU | worst relay mailbox |
|---|---|---|---|---|---|---|---|
| 10 | 171 | 65 | 1 ms | 2 ms | 3 ms | 4% | 1 |
| 50 | 883 | 200 | 4 ms | 11 ms | 16 ms | 43% | 5 |
| 60 | 1,052 | 233 | 8 ms | 21 ms | 30 ms | 61% | 16 |
| 70 | 1,176 | 255 | 26 ms | 54 ms | 64 ms | 79% | 49 |
| **80** | 262 | 61 | **2.8 s** | **20.7 s** | 27 s | 100% | **8,939** |
| 100 | 158 | 38 | 12 s | 28 s | 31 s | 100% | 6,611 (358,000 queued in all) |

**What it shows:**
- **It breaks between 70 and 80 players in one world.** The cause is the N² relay. At 70 players the
  server makes about 97,000 pushes a second; at 80 it would need about 126,000, and it can't keep up.
- **Where it backs up: the per-player WebSocket connection processes.** At 100 bots they held 358,000
  unsent messages in total, memory climbed from 60 MB to 1.7 GB, and latency ran away.
  - Every movement is JSON-encoded and framed **separately for every recipient**.
  - That is N × (N − 1) × 20 encodes a second.
- **The world process itself was fine.** Its mailbox stayed small. The cost is the fan-out, not the
  simulation.
- **It's not the bots.** At 100 bots, spread over three processes, their event loops lagged at most
  25–85 ms while they received only ~140 of the ~1,980 messages a second they should have. The
  server's own process used about 2.7 of the 4 cores.
- **Bandwidth is a phone problem even before the server breaks.** At 70 players each client is pulled
  **255 KB/s (about 2 Mbit/s)** of JSON. That's too much for mobile data and battery, and it grows
  with the crowd.

**Caveats:**
- The bots shared the server's 4 cores. A dedicated server box would break somewhat later, but the N²
  shape is the same.
- This tests movement only: no friends traffic, saves or Ruin wards.
- Each step joined ~25 bots a second.

**What it means for the order of work:**
- **SC-3 (batched, compact ticks) attacks the measured bottleneck directly.** One bundle per client per
  tick, encoded once, with rounded coordinates:
  - it turns N × (N − 1) × 20 encodes into about N × 20 sends;
  - it cuts the bytes several-fold.
- **SC-4 (interest management)** then stops a client's bundle growing with the whole world.
- Re-run SC-1 after each, so every step is measured.

### ✅ SC-2 — A client drawing budget *(built 2026-11-26)*
This is what you actually felt.
- **Per-world budget:** a draw-call and frame-time budget per world, checked by the perf harness.
- **Limit on drawn people:**
  - Fully draw the nearest K peers (for example 30) with their companions.
  - Draw the next ring as a simpler figure with no companion and a lower update rate.
  - Hide anyone farther away.
- **Phone checks:** test on a real phone, not only desktop.

**What was built:**
- **Every peer gets a tier** (`CrowdBudget`, pure logic, tested):
  - **FULL:** the nearest `full` peers (default 40), the person and their companion, as before.
  - **LITE:** the next `lite` (default 80), the person only: no companion, nothing in their hands.
  - **HIDDEN:** past the budget, not drawn.
  - **OUT:** out of sight. In a world with interest cells that is anyone more than one cell from us
    (SC-4's rule, the same 3 x 3 block the server uses). Everywhere, it is also anyone we have no
    position for yet.
- **No flicker at the cuts:**
  - Someone already in a tier counts as 15% and 40 px nearer when it is filled again, so a newcomer
    takes their place only when clearly nearer.
  - Someone in sight stays in sight until a fifth of a cell past the edge of the 3 x 3 block.
  - The counts never go over `full` and `lite`.
- **The settings** come from the world spec's `crowd` block (`{ "cell": 480, "full": 40, "lite": 80 }`).
  With no block there are no cells and the default budget, so today's small worlds draw everyone, as
  before.
- **Lazy puppets** (`PresenceDirector`):
  - The **roster** keeps everyone in the world as data: names, identities, last positions. Only
    FULL and LITE peers have nodes.
  - The budget is re-ranked every 0.3 s, and sooner when a peer's first position arrives or we jump.
  - Puppets are built nearest first, within 1.5 ms a frame (always at least one), and freed a few
    a frame, so a crowd arriving never stalls a frame.
  - A puppet near the screen is awake. Off screen it does no work at all: its node stops processing
    and each update just places it.
  - In a crowd world, stepping into a new cell forgets where we last saw people in the cells that
    just came into sight. They may have left while we could not hear, so they wait for the server's
    snapshot instead of standing there as ghosts.
- **Cheap puppets:**
  - A remote person stops processing once it has arrived and turned, until the next update.
  - A remote companion stops easing once it has arrived, and repaints 20 times a second.
  - An update more than 256 px away is a jump: the puppet is put there, not slid across the map.
  - A remote person's outfit is flattened into one picture, cached by outfit: one draw call instead
    of one per layer, and the same outfits batch.
  - Building a puppet went from about 2.6 ms to about 0.2 ms. The wardrobe sheets are now held once
    loaded, instead of being read from disk again for every avatar, and remote puppets share one
    catalog and one companion config.
- **Only changes are sent:** our own state goes out about 20 times a second while it changes (at the
  server's precision: whole pixels, directions to two decimals) and once a second otherwise. Nothing on
  the client counts on peers sending at a steady rate.
- **Counts:** `peer_count()` is still everyone in the world (the place chip, "The Vale · 501 here",
  and the Ruin). `drawn_count()` is who has puppets. Taps, footstep trails and shadows see only the
  drawn; a friend drawn LITE still lights the dark round their lantern.

**Measured** with `tests/perf_crowd.gd`: synthetic peers fed through the real Net signals, in the Vale,
half walking and half standing, spread over the whole map round where you arrive. Script time is the
median frame on this 4-core container (the best of three runs, while other work shared the machine).
Draw calls are with a renderer (Xvfb, opengl3).

| peers | before: script ms | after: script ms | before: draw calls | after: draw calls | after: drawn (full + lite) |
|---|---|---|---|---|---|
| 0 | 3.8 | 3.9 | 123 | 117 | 0 |
| 50 | 4.9 | 5.0 | 196 | 137 | 50 (40 + 10) |
| 100 | 6.0 | 5.3 | 313 | 163 | 100 (40 + 60) |
| 200 | 8.3 | 5.6 | 504 | 195 | 120 (40 + 80) |
| 500 | 16.6 | 6.0 | 956 | 206 | 120 (40 + 80) |

- **What it shows:** the cost now stops growing at the budget. 500 peers cost about what 150 did
  before, and draw calls fall almost five-fold. With everyone walking, 500 peers cost 6.5 ms; with
  interest cells (cell 480), 6.2 ms.
- **What limits a crowd on the client now:**
  - The drawn peers, about 15 µs a frame each while walking on screen. The budget sets this.
  - The incoming states themselves: Net decodes and hands over every entry, drawn or not (about
    1.3 ms a frame for 500 walkers here, before any JSON). Interest cells (SC-4) cut this at the source.
  - Building puppets: about 0.2 ms each here, several times that on the web build, so filling the
    budget takes a second or two there. Nearest come first.
  - Ranking: about 3 ms for 2,000 peers in sight, 3 times a second.
- **Not yet done:** a real phone check, and the web build measured on its own.

### ✅ SC-3 — Batched, compact world ticks *(built 2026-10-31)*
**What changed:**
- **The tick:** `Server.World` keeps each player's latest transform. Every 50 ms it broadcasts **one
  `"states"` bundle** of whoever moved.
- **Encoded once:** the bundle goes out through `Endpoint.broadcast` on the world's channel topic.
  That's Phoenix's "fastlane": the bundle is JSON-encoded **once** and the same frame goes straight to
  every socket, without passing through each player's channel process.
- **Ambient pals** ride the same tick at 10 Hz, sent the same way.
- **The bundle format** is `Server.WorldStates`: positional arrays
  `[id, px, py, fx, fy, cx, cy, lx, ly]`, with positions in whole pixels and directions to two decimals.
- **Sanitizing:** the server keeps only those four known fields, so junk a client puts in its packet
  is never stored or relayed.
- **Clients** skip their own entry. The join snapshot is one bundle too.

**Load test after SC-3** (same rig and steps as SC-1):

| bots in one world | before SC-3: p95 latency | after: p95 | after: p99 | after: server CPU | after: KB / bot / s | after: world mailbox (worst) |
|---|---|---|---|---|---|---|
| 10 | 2 ms | 49 ms | 51 ms | 2% | 49 | 0 |
| 50 | 11 ms | 52 ms | 56 ms | 6% (was 43%) | 108 (was 200) | 0 |
| 100 | **28 s (collapsed)** | 62 ms | 81 ms | 11% | 165 | 1 |
| 200 | — | 84 ms | 114 ms | 35% | 194 | 200 |
| 300 | — | 163 ms | 391 ms | 45% | 184 | 868 |
| 500 | — | 400 ms | 712 ms | 70% | 111\* | 6,005 |
| ~700 → ~900 (joining) | — | 1.4 s → 4.7 s | | 95–100% | | 39,063 |

\* Averaged over the whole step, including the join ramp, and the bots were starting to fall behind.
The bots' own event-loop lag stayed under 90 ms through 500.

**What it shows:**
- **Capacity:** one world now holds about **500 players** before latency gets bad, up from **about 75**.
  At 100 it's comfortable: 11% CPU where the old code had collapsed.
- **Small crowds pay a little latency:** about 25 ms more on average, since an update now waits for
  the next 50 ms tick. The client's easing hides this.
- **The new limit is the single world process:**
  - it takes in 20 packets a second from every player (10,000 a second at 500);
  - it builds an N-entry bundle 20 times a second;
  - its mailbox is what backs up past ~500.
- **Join storms are N² too.** Each arrival sends a presence update to every channel, so the channels'
  mailboxes grew while ~900 bots were joining.
- **Bandwidth is still too high for phones in a crowd.** Every client still receives every player:
  about 165 KB/s each at 100 players. That's SC-4's job.

**Next:**
- **SC-4 (interest management)** fixes both the bandwidth and the bundle size.
- **SC-5 (splitting a world by area)** fixes the single-process limit. Each area's process handles
  only its own players' packets.

### ✅ SC-4 — Interest management *(built 2026-11-26, opt-in per world; for Lingerlong, issue #158)*
**Opt-in:** a world turns it on with a crowd block in its spec, `core.crowd`, for example
`{"cell": 480, "full": 40, "lite": 80}`. The server reads only `cell`; `full` and `lite` are the client's
drawing budget (SC-2). Worlds without the block behave exactly as before. The world process reads the
block from the spec's `core`, the same map the ambient pals are started from (`World.ensure_started/3`).

**Only changes are sent** (every world):
- The world process marks a player dirty only when their cleaned transform differs from the stored one.
- The load-test send stamp `t` is left out of the comparison: a pose that hasn't changed isn't a
  change, whatever its stamp. A changed pose is stored and relayed with its own, latest `t`.
- A packet that changes nothing isn't relayed, but its sender stays stored, so still present.
- The client rule: send at 20 Hz while your pose changes, otherwise once a second (a keepalive). The
  keepalive is what refills a restarted world.
- Snapshots (on join, or when cells come into view) leave `t` out, since a standing player's stamp can
  be seconds old.

**Interest cells** (crowd worlds only):
- **Grid:** the world is cut into `cell` × `cell` px squares. A player's cell is
  `{floor(px / cell), floor(py / cell)}` of the player position, rounded to whole pixels first, the way
  it's stored. The pure maths is `Server.Interest` (tested).
- **What you hear:** only the players in the 3 × 3 cells around your own, your neighbourhood. The wire
  format of `"states"` doesn't change.
- **One bundle per cell:** each tick the world process places every mover in its cell, then sends ONE
  bundle per occupied cell (a cell someone stands in), holding the movers in that cell's neighbourhood.
  It goes out on that cell's PubSub topic, `world:<id>:cell:<cx>,<cy>`, as a channel broadcast on the
  world's channel topic. So Phoenix's fastlane still encodes it once for every socket in that cell, and
  the client sees an ordinary `"states"` frame. Nothing goes out on the world-wide topic.
- **One subscription per player:** each channel follows exactly one cell topic, its player's own,
  subscribed with the same fastlane sender Phoenix uses for the channel topic.
- **Changing cell:** the channel works out the cell from each state packet. On a change it:
  1. subscribes to the new cell first, so no tick falls between the two;
  2. asks the world, without waiting, for the players in the cells that just came into view;
  3. when the answer comes, pushes it as one snapshot and only then leaves the old cell.
  While an answer is on its way it can hear both cells, so an entry may arrive twice. That's harmless.
- **World-wide still:** the presence roster (join, identity, leave), ambient pals, Ruin wards, flares
  and howls. Lingerlong has no pals.

**Edge cases, decided** (also in `Server.World`'s moduledoc):
- **A mover crossing a cell border:** its entry for that tick goes to the old cell's neighbourhood AND
  the new one's. Watchers it's leaving see the position it left to, now more than a cell from them, so
  their client stops drawing it. From the next tick only the new neighbourhood hears it.
- **Walking away from someone standing still:** the server sends nothing. Your client knows where you
  are and hides peers whose last known position is more than one cell from your cell (Chebyshev
  distance over 1). Walking back brings them in again through the snapshot.
- **Before your first state:** the channel follows the cell of your spawn (or resume) point from the
  join, and the join snapshot is that neighbourhood only. With neither, you receive nothing until your
  first state names your cell, then the whole neighbourhood as a snapshot.
- **A packet with no player position** leaves you in the cell you were in, or none.
- **Leaving:** you're dropped from your cell. An emptied cell isn't occupied, so it costs nothing.
  Your peers learn of the leave from presence.
- **A world restart:** the process starts empty with the same spec. Channels keep their cell
  subscriptions (they live in PubSub). Within a second every client's keepalive arrives, which counts
  as a change against an empty store, so everyone is placed and re-sent again.
- **A known small gap:** a snapshot is read at one moment and pushed by the channel; a tick sent a
  moment later can reach the socket first. A peer who moved in that instant and then stood still shows
  up to one tick (a few px) behind until they next move. The same was true of SC-3's join snapshot.

**Cheap fixes the measurements led to** (all worlds):
- **Encoded once, shared by reference:** every live bundle is now built from entries encoded once per
  tick, joined into ONE binary (`WorldStates.encoded_bundle`, a JSON fragment). A mover sits in up to
  nine cell bundles, so encoding plain bundles cost about nine times the JSON work, all in the one world
  process. And a frame that is one large binary is shared by every socket process that sends it, where
  a deep list of small pieces was copied into each one. The bytes on the wire are unchanged.
- **The world's mailbox off its heap:** every player's packets land in it from every core. On the heap,
  a backlog made each of its garbage collections slower, so a momentary backlog never drained.
- **Channels never wait on the world:** the cell snapshot is asked for without waiting (above), and a
  join asks the world for pals and wards only where there are some. A busy world used to block
  channels, which then queued their own clients' packets, and a 5 s timeout crashed joining channels.
- **Memory:** with default garbage-collection settings a channel's heap only grows: about 1.8 MB per
  channel with 1,000 players in one world, 0.2 MB of it live, and its WebSocket process the same. Memory
  grew with the square of the crowd (8 GB at 2,000). Every 15 s a channel now hibernates and asks its
  socket process to collect: the channels' share at 1,000 fell from 1.4 GB to 0.26 GB.

**Load test** (`tools/loadtest/`, extended):
- Bots send only changes plus a 1 Hz keepalive, read the spawn from the spec, can spread their homes
  over an area (`--spread`), and report how many different peers each heard (`peers`).
- A **hangout** profile: groups mostly standing about (each stands 4 to 20 s, then takes a few steps),
  10% strolling anywhere.
- `crowd_world.exs` makes an unlisted load-test-only world with a crowd block (cell 480 px, spawn in the
  middle of a cell). `run.sh crowd` uses it.
- `--parse-frac`: only some bots parse the live bundles. With 1,000 in one cell, parsing everything cost
  the bot processes more CPU than the server spent (their lag reached 500 ms and showed up as latency).

**The rig:** the same kind of 4-core container as SC-1 and SC-3, with the server AND every bot on it,
so the bots take 1 to 2 of the 4 cores. Joins at 25 a second. Latency is send to receive, including
the up-to-50 ms wait for the next tick. CPU is the server's scheduler utilisation (1.0 = all 4 cores).

**(a) The Vale (no crowd block), everyone wandering**, 40 s steps, the same bots before and after:

| bots | before p95 | after p95 | after p99 | before CPU | after CPU | after KB / bot / s | world mailbox before → after |
|---|---|---|---|---|---|---|---|
| 100 | 56 ms | 53 ms | 60 ms | 10% | 7% | 177 | 1 → 0 |
| 300 | 126 ms | 82 ms | 119 ms | 43% | 20% | 333 | 291 → 19 |
| 500 | 257 ms | 187 ms | 269 ms | 71% | 35% | 310 | 2,236 → 95 |
| 700 | 482 ms | 408 ms | 507 ms | 90% | 54% | 246 | 5,568 → 454 |

- Change-only alone made no difference here (wanderers always move), as expected: no regression.
- The shared one-binary bundle halved the server's CPU. KB per bot went UP because the bots now get
  everything they should: before, at 500, each received about 1,500 entries a second of the ~10,000
  sent its way; now about 3,200. Past 300 the bots' own parsing is part of the latency.
- Bandwidth is still the SC-3 problem in a world without cells: 250 to 330 KB/s per client.

**(b) A crowd world, everyone wandering, homes spread over 8,000 × 8,000 px** (about 280 cells),
130 s steps:

| bots | p50 | p95 | p99 | server CPU | KB / bot / s | world mailbox (worst) | peers heard (avg / max) |
|---|---|---|---|---|---|---|---|
| 500 | 39 ms | 62 ms | 69 ms | 33% | 23 | 276 | 38 / 65 |
| 1,000 | 58 ms | 91 ms | 109 ms | 59% | 29 | 647 | 74 / 120 |
| 1,500 | 101 ms | 191 ms | 1.3 s | 75% | 22 | 2,804 | 111 / 196 |
| 2,000 | collapsed (p95 26 s) | | | 92% | | 806,515 | |

- Before the cheap fixes above, 1,000 already had a p99 of 2.5 s and 1,500 collapsed (p95 37 s).
- Each client hears its neighbourhood only: 23 to 29 KB/s, where the Vale's wanderers get 250+.

**(c) A crowd world, the hangout profile**, 130 s steps (170 s at 3,000), 10% or 25% of bots parsing:

Everyone in one cell ("500 in the square" and beyond):

| bots | p50 | p95 | p99 | server CPU | KB / bot / s | world mailbox (worst) | peak memory |
|---|---|---|---|---|---|---|---|
| 500 | 34 ms | 56 ms | 60 ms | 16% | 149 | 0 | 0.7 GB |
| 1,000 | 47 ms | 71 ms | 80 ms | 30% | 232 | 83 | 1.6 GB |
| 2,000 | 91 ms | 192 ms | 687 ms | 61% | 187 | 14,758 | 3.9 GB |
| 3,000 | collapsed while joining (p95 21 s) | | | 83% | | 197,729 | 6.0 GB |

Spread out, 24 groups over 8,000 × 8,000 px:

| bots | p50 | p95 | p99 | server CPU | KB / bot / s | world mailbox (worst) | peers heard (avg / max) |
|---|---|---|---|---|---|---|---|
| 1,000 | 38 ms | 62 ms | 68 ms | 28% | 13 | 66 | 98 / 353 |
| 2,000 | 52 ms | 96 ms | 323 ms | 61% | 13 | 755 | 174 / 414 |
| 3,000 | collapsed while joining (p95 21 s) | | | 83% | | 147,838 | |

**What it shows:**
- **500 in the square is comfortable:** p95 56 ms at 16% CPU. 1,000 in one cell is too (71 ms, 30%), and
  2,000 holds with a ragged p99.
- **Spread out, interest cells do their job:** a client's traffic depends on its neighbourhood, not the
  world. 2,000 standing about cost each client 13 KB/s.
- **A crowd in ONE cell is still a bandwidth problem for phones:** everyone hears everyone who moves,
  150 to 230 KB/s at 500 to 2,000. Change-only is what keeps it that low (most stand still).
- **What breaks first, on this rig: the one world process, starved or full.**
  - Past about 2,000 joining at 25 a second, the whole machine saturates WHILE people are joining (run
    queue over 1,000), even though few are moving. Each arrival is a presence diff that EVERY channel
    handles and encodes for its own socket (the N² join storm SC-3 noted). The one world process is then
    one runnable process among thousands, gets its fair share and no more, falls behind, and its
    mailbox never recovers.
  - With everyone moving all the time, the one world process is the limit at about 1,500 to 2,000: it
    takes every player's 20 packets a second (30,000 a second at 1,500) and places and groups every mover
    each tick.
  - **An experiment, not built:** running the world process at high priority (`Process.flag(:priority,
    :high)`) let it keep up through the storm. 3,000 spread out then held (p95 202 ms, p99 385 ms, world
    mailbox 31) and 1,500 wanderers' p99 fell from 1.3 s to 321 ms. Left out on purpose: the rest of the
    server then gets less, and more joins failed (150 of 3,000) on database timeouts. It needs a decision,
    and a guard if several busy worlds share a machine.
  - Joins themselves read the database (profile, friends, wallet, inventory). At 2,000 to 3,000 joining
    on this rig, 1 to 2% of joins failed on the 10-connection pool. The periodic whereabouts save (about
    200 writes a second at 3,000) used to crash a player's channel the same way; it's now skipped instead.
  - Bots and server share 4 cores, so a real server box would go further, but the order is the same.
- **Memory still grows faster than the crowd** (3.9 GB at 2,000 in one cell): most of it is now the
  WebSocket processes and the join-time roster, and the next item touches both.

**Next (not built):**
- **Keep the world process ahead (cheap, needs a decision):** the priority experiment above, or a smaller
  step with the same aim: do the cleaning and the change check in each channel (on every core) so the
  world gets only real changes, already cleaned.
- **Roster fan-out (the next real item):** today every channel intercepts every presence diff and encodes
  its own `join` / `identity` / `leave` frames: N² work and N² bytes while a crowd arrives. Options:
  turn the diff into frames ONCE per world and send them through the fastlane (the client would then
  have to ignore a join for a peer it already knows, which the server guards against today), and in a
  crowd world send identities only for the neighbourhood
  (the client keeps the roster as data, and would ask for an identity when a peer comes into view).
  The `welcome` roster (every player, on every join) has the same shape.
- **SC-5 (splitting a world by area)** is what lifts the single world process limit: each area's process
  takes only its own players' packets.
- **A rate for the far part of the neighbourhood:** in one packed cell, entries for peers the client
  draws as "lite" or not at all could go out less often than 20 Hz. That's what would bring the square's
  bandwidth down for phones.

### SC-5 — Instances *(open; reshaped by SC-0 into seamless splitting by area, see below)*
- **Cap:** each world can run several copies, each capped (for example at 80 players).
- **Which copy you join:** joining picks:
  1. the copy your friends or invitees are in;
  2. otherwise, the fullest copy that isn't full, so places feel alive;
  3. otherwise, a new copy.
- **Per copy:** shared state like Ruin wards and flares belongs to one copy.
- **Gateway count:** the Gateway's live count adds up all copies.
- **Homes** are already one per player; visiting friends land in that home's single copy.
- **Open questions:** should the player see which copy they're in? Can they hop to a friend's copy
  directly?
- **After SC-0:** capped, visible copies are out. What's left of this item is **seamless splitting by
  area**:
  - A world's map is divided into areas, each owned by its own process (and later, its own machine).
  - Players near an area's edge see across the seam, and walking over it hands them to the next area
    without a visible join.
  - Capped copies may still be a safety valve for a world that's overfull even when split, but never
    the normal path.

### SC-6 — More than one machine *(open)*
- **Cluster:** the step the code already flags: libcluster to join nodes, and Horde (a cluster-wide
  registry and supervisor) so each world or instance has exactly one home in the cluster.
- **Already ready:** PubSub and Presence already span nodes.
- **To size later:** the Postgres connection pool, and where the database lives.
- **Load balancing:** sticky sessions aren't needed, since a socket can land on any node and reach its
  world process wherever it runs.

## What's already in place

- **Per-world isolation:** players in different worlds already cost each other nothing.
- **Presence:** robust disconnect detection, and multi-node ready.
- **Server-side ambient sims:** cheap at today's numbers. Nocthollow's 60 pals take about 7 ms of a
  100 ms tick, which would need watching if many Nocthollow instances ran at once.
- **The client:** it already eases remote movement between updates, so a lower or batched tick rate
  won't look jerky.

## How we work through it

One item at a time. SC-0 is decided, SC-1 has run, SC-3 is built (one world went from about 75 players
to about 500), and SC-4 is built as an opt-in per world: a crowd world holds 2,000 standing about (one
cell or spread out) and 1,500 always on the move on a shared 4-core box. Next is keeping the one world
process ahead and the roster fan-out (both under SC-4's "Next"), then SC-5 (splitting a world by area),
re-running the load test after each.
