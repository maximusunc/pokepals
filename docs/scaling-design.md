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

### SC-1 — Measure first: a load test with bot players *(open)*
Before changing the architecture, find where today's code actually breaks:
- **Bots:** a small bot client (an Elixir mix task speaking the real WebSocket protocol) that joins a
  world and walks around at 20 Hz. Run 10, 50, 100, 300, 1,000 of them.
- **Server measurements:** CPU and scheduler use, the world process's mailbox length (a growing
  mailbox means it can't keep up), bytes out per second, and update delay at the client.
- **Client measurements:** one real client in the crowd, measuring its frame rate and draw calls. The
  `perf` harness used for the Bazaar can be kept as a tool for this.
- **Output:** a short table of where it breaks and which resource runs out first. That table decides
  what SC-2 to SC-6 need to look like.

### SC-2 — A client drawing budget *(open)*
This is what you actually felt.
- **Per-world budget:** a draw-call and frame-time budget per world, checked by the perf harness.
- **Limit on drawn people:**
  - Fully draw the nearest K peers (for example 30) with their companions.
  - Draw the next ring as a simpler figure with no companion and a lower update rate.
  - Hide anyone farther away.
- **Phone checks:** test on a real phone, not only desktop.

### SC-3 — Batched, compact world ticks *(open)*
- **One bundle per tick:** the world process keeps the latest transform per player and, on a fixed
  tick (10–20 Hz), sends one bundle per client. It does not rebroadcast every incoming message. The
  ambient pals join that same tick.
- **Encode once:** encode each bundle a single time, not once per socket.
- **Smaller messages:** round positions to whole numbers, and drop fields that haven't changed.
- **Effect:** each client gets about 20 messages a second whatever the crowd size. Messages still grow
  with the number of nearby players, which is SC-4's job.

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

One item at a time. SC-0 is decided (above). SC-1 (the load test) should come before any
architecture change, so we build what the numbers say rather than what we guess.
