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
```

Logs and per-step JSON land in `tools/loadtest/results/`, which is git-ignored.

Notes:
- **Accounts.** Bots log in with tokens `lt-bot-<n>`, so each run reuses the same accounts. They're
  ordinary rows in whatever database the server uses, so **don't point this at production**
  casually.
- **Bot CPU.** On one machine the bots compete with the server for CPU. Watch the bots' own load. For
  the server's true ceiling, run the bots from a different machine than the server.
