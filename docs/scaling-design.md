# Scaling: from a few friends to a crowd

**Status (2026-10-31):** a plan for discussion. **Every item below is open/undecided.** As with the
other design docs, we decide one item at a time, record the decision here, and only then build it.

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

### SC-2 — A client drawing budget *(open)*
This is what you actually felt.
- **Per-world budget:** a draw-call and frame-time budget per world, checked by the perf harness.
- **Limit on drawn people:**
  - Fully draw the nearest K peers (for example 30) with their companions.
  - Draw the next ring as a simpler figure with no companion and a lower update rate.
  - Hide anyone farther away.
- **Phone checks:** test on a real phone, not only desktop.

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

### SC-4 — Interest management *(open)*
- **Grid:** a spatial grid inside each world (or instance).
- **Nearby only:** each player's bundle holds only the entities in nearby cells.
- **How to build it:**
  - Start simple: the world process builds the per-player bundles itself.
  - If one process becomes the bottleneck, move to per-cell PubSub topics. Each client then follows
    the 3×3 block of cells around it.
- **Shared things:** Ruin wards, flares, world events and the like should also only reach nearby
  players, or the whole instance when it's a world-wide event.

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

One item at a time. SC-0 is decided, SC-1 has run, and SC-3 is built: one world went from about 75
players to about 500. Next is SC-4 (interest management), then SC-5 (splitting a world by area),
re-running the load test after each.
