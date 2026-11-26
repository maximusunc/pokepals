# Load test (SC-1)

Bot players that speak the real client protocol, plus a probe that watches the server from the
inside, so we can see where the shared world stops keeping up. Background and results:
[`docs/scaling-design.md`](../../docs/scaling-design.md) (SC-1).

## Pieces

- **`bots.mjs`** (Node 22+, no npm install). N bots each:
  1. connect over a WebSocket;
  2. join a world (`phx_join` on `world:<uuid>`, just like `scripts/net/net.gd`);
  3. wander near its spawn, sending the client's transform packet at 20 Hz.

  Every packet carries its send time, and the server relays it untouched. So bots on one machine can
  measure **latency**: how old each peer's update is when it arrives. They also report messages and
  kilobytes received per bot per second.
- **`probe.exs`** (Elixir). It joins the running server as a second Erlang node and samples, every
  couple of seconds:
  - scheduler utilisation (how busy the server's cores are);
  - the run queue;
  - each world process's mailbox and work rate;
  - the mailboxes of the per-player relay processes (channel and WebSocket connection);
  - memory.

  A mailbox that keeps growing means that process can't keep up.
- **Bot behaviour** (since SC-4):
  - Like the real client, bots send **only changes**: 20 Hz while their pose changes, otherwise a 1 Hz
    keepalive.
  - `--profile wander` (the default): always walking about within `--radius` of a home.
  - `--profile hangout`: groups (`--clusters`, each within `--cluster-radius`) mostly standing about,
    each standing 4 to 20 s then taking a few steps; a `--strollers` fraction (0.1) strolls anywhere.
  - `--spread S`: homes / group centres are spread over an S px square around the spawn (0 = all at it).
  - They report how many **different peers** each heard about (`peers_avg/max`): in a crowd world, only
    the neighbourhood.
  - `--parse-frac F`: only that fraction of bots parse the live bundles (and so measure latency and
    peers); the rest still receive every byte. With 1000 in one place, parsing everything costs the
    bots more CPU than the server spends.
- **`crowd_world.exs`** makes (or refreshes) a load-test-only **crowd world** on the running server: an
  unlisted world whose spec has a crowd block (`core.crowd.cell`, default 480 px), with its spawn in the
  middle of a cell. Nothing in the repo seeds it, so it never ships or shows in the Gateway.
- **`run.sh`** steps the crowd up (10, 50, 100, 200, 300, 500, 1000 by default) and prints one summary
  line per step. It stops once p95 latency passes 2 s.

## Running it

From `server/`, start the server as a named node with the load-test cookie:

```sh
elixir --sname srv --cookie loadtest -S mix run --no-halt
```

Then from the repo root:

```sh
tools/loadtest/run.sh                                   # the Vale, default steps, 40 s each
tools/loadtest/run.sh 33333333-3333-3333-3333-333333333333 "10 50 100" 30   # the Bazaar, a few steps
URL=wss://your-host/ws SERVER_NODE=srv@host tools/loadtest/run.sh           # a remote server

# SC-4, the crowd world ("crowd" makes it first; CELL sets its cell size):
BOT_ARGS="--profile wander --spread 8000" tools/loadtest/run.sh crowd "500 1000 2000" 130
BOT_ARGS="--profile hangout --spread 0 --parse-frac 0.1" tools/loadtest/run.sh crowd "500 1000 2000" 130   # everyone in one cell
```

`RATE` sets how many bots join per second (default 25); a step must last longer than its join ramp
(N / RATE + 3 s), so big steps need long ones. Joining much faster than 25 a second on a small machine
runs out of database connections (each join reads the account, profile, save, wallet and so on).

Logs and per-step JSON land in `tools/loadtest/results/`, which is git-ignored.

Notes:
- **Accounts.** Bots log in with tokens `lt-bot-<n>`, so each run reuses the same accounts. They're
  ordinary rows in whatever database the server uses, so **don't point this at production**
  casually.
- **Bot CPU.** On one machine the bots compete with the server for CPU. Each bot process reports its
  own event-loop lag (`loop_lag_p99`, and `bot_loop_lag_max_ms` in its summary). If that climbs into
  the hundreds of ms, the bots are reading too slowly and part of the measured latency is theirs. For
  the server's true ceiling, run the bots from a different machine than the server.
