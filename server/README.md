# pokepals relay — Rung 4, step 1

A **minimal authoritative server** for the shared world: it assigns each connected client an id,
holds the roster, and relays presentation state (avatar + companion transforms and identity)
between clients over raw WebSockets + JSON. That's the whole job for this step.

It deliberately does **not** have a database, accounts, Phoenix Presence, proximity chat, or any
server-side game simulation. Those are later Rung-4 steps. The runtime stack here
(**Bandit + WebSock + Phoenix.PubSub**) is the same one Phoenix Channels ride on, so growing into
Channels/Presence later is additive.

## Run it

Requires [Elixir](https://elixir-lang.org/install.html) (1.15+) and Erlang/OTP.

```sh
cd server
mix deps.get
mix run --no-halt        # start the relay
# …or, for an interactive shell you can poke at:
iex -S mix
```

It listens on `:4000` (override with `PORT=...`). Clients connect to `ws://<this-machine-ip>:4000/ws`
— use `127.0.0.1` if Godot runs on the same machine, or the LAN IP printed by the lobby's host for
a friend on the same network. `GET /health` returns `ok` for a quick liveness check.

## Run the tests

```sh
mix test
```

Covers the Hub's id assignment + roster (the server-authoritative core). End-to-end relay
behaviour is verified by running two Godot clients against the server (see the repo `CLAUDE.md`).

## Shape

```
lib/server/
  application.ex     supervision tree: PubSub + Hub + Bandit(:4000)
  router.ex          GET /ws (WebSocket upgrade) + /health
  hub.ex             id assignment + roster (the only shared state)
  presence_relay.ex  one WebSock process per client: welcome / join / identity / state / leave
```

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
