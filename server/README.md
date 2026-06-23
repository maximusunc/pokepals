# pokepals relay — Rung 4 (steps 1–2)

A **minimal authoritative server** for the shared world: it assigns each connected client an id,
tracks the roster with **Phoenix.Presence**, and relays presentation state (avatar + companion
transforms and identity) between clients over raw WebSockets + JSON.

It deliberately does **not** have a database, accounts, proximity chat, or any server-side game
simulation — those are later Rung-4 steps. The runtime stack (**Bandit + WebSock + Phoenix.PubSub +
Phoenix.Presence**) is the same one Phoenix Channels ride on, so growing further is additive.

The Godot client speaks a fixed `welcome / join / identity / state / leave` wire protocol (below);
Phoenix.Presence is an internal implementation detail the client never sees — the server adapts
Presence's diffs into those frames.

## Run it (development)

Requires [Elixir](https://elixir-lang.org/install.html) (1.15+) and Erlang/OTP.

```sh
cd server
mix deps.get
mix run --no-halt        # start the relay
# …or, for an interactive shell you can poke at:
iex -S mix
```

It listens on `:4000` (override with `PORT=...`). Clients connect to `ws://<this-machine-ip>:4000/ws`
— use `127.0.0.1` if Godot runs on the same machine, or the LAN IP for a friend on the same network.
`GET /health` returns `ok` for a quick liveness check.

## Deploy it somewhere

To stand the relay up on a real host (a Proxmox LXC on a home server, a VPS, anything) — via Docker
or a systemd-managed OTP release — see **[DEPLOYMENT.md](DEPLOYMENT.md)**. Quickest path, on a box
with Docker:

```sh
docker compose up -d --build     # builds + runs, published on :4000
```

Common actions are also wrapped in the `Makefile` (`make release`, `make compose-up`, …; `make help`).

## Run the tests

```sh
mix test
```

Covers the Hub's id assignment + roster (the server-authoritative core). End-to-end relay
behaviour is verified by running two Godot clients against the server (see the repo `CLAUDE.md`).

## Shape

```
lib/server/
  application.ex     supervision tree: PubSub + Presence + Hub + Bandit(:4000)
  router.ex          GET /ws (WebSocket upgrade) + /health
  presence.ex        the roster, as a Phoenix.Presence (CRDT over PubSub)
  hub.ex             monotonic id counter (the per-connection / Presence key)
  presence_relay.ex  one WebSock process per client; adapts Presence diffs <-> the wire frames
```

The roster lives in `Presence`, so a peer's leave is detected even on a hard crash/disconnect (it
monitors the connection process), and the high-rate `state` relay runs on a separate PubSub topic
(`world:state`) so transforms never mix with presence diffs.

## Wire protocol (JSON text frames)

The server stamps the sender id onto every relayed frame — clients never send their own id.

Client → server:

- `{"t":"identity","name":..,"appearance":{..},"companion_look":{..}}` — on connect / on change
- `{"t":"state","p":[x,y],"pf":[x,y],"c":[x,y],"cl":[x,y]}` — ~20 Hz

Server → client:

- `{"t":"welcome","id":N,"peers":[{"id":M,"identity":{..}}, ...]}`
- `{"t":"join","id":M}`
- `{"t":"identity","id":M,"name":..,"appearance":..,"companion_look":..}`
- `{"t":"state","id":M,"p":[x,y],...}`
- `{"t":"leave","id":M}`
