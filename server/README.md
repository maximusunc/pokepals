# pokepals relay — Rung 4 (steps 1–3)

The **authoritative server** for the shared world. It assigns each connected client an id, tracks
the roster with **Phoenix.Presence**, relays presentation state (avatar + companion transforms and
identity) between clients over raw WebSockets + JSON, and is the **sole store** of each player's
companion + wardrobe (**PostgreSQL** via Ecto), keyed by a client-generated identity token. The game
is online-only: there is no local game save.

Runtime stack: **Bandit + WebSock + Phoenix.PubSub + Phoenix.Presence + Ecto** — no Phoenix
Endpoint/HTML. The Godot client speaks a fixed wire protocol (below); Presence and the DB are
internal details it never sees.

## Run it (development)

Requires [Elixir](https://elixir-lang.org/install.html) (1.15+), Erlang/OTP, and a reachable
**PostgreSQL** (the dev default is `ecto://postgres:postgres@localhost/pokepals_dev`; override with
`DATABASE_URL`).

```sh
cd server
mix deps.get
mix ecto.setup           # create + migrate the dev DB (once)
mix run --no-halt        # start the server
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

Covers the id counter, the Presence diff→frame adapter, and the `Saves` store round-trip (the
`test` alias creates + migrates a `pokepals_test` DB first). End-to-end behaviour is verified by
running Godot clients against the server (see the repo `CLAUDE.md`).

## Shape

```
lib/server/
  application.ex     supervision tree: Repo + PubSub + Presence + Hub + Bandit(:4000)
  repo.ex            the Ecto/Postgres repo;  release.ex  runs migrations in the packaged release
  player_save.ex     schema for player_saves (player_id PK + companion/appearance jsonb)
  saves.ex           load/store a player's save (the persistence boundary)
  router.ex          GET /ws (WebSocket upgrade) + /health
  presence.ex        the roster, as a Phoenix.Presence (CRDT over PubSub)
  hub.ex             monotonic id counter (the per-connection / Presence key)
  presence_relay.ex  one WebSock process per client; relays presence + serves load/save
priv/repo/migrations player_saves table
```

The roster lives in `Presence`, so a peer's leave is detected even on a hard crash/disconnect (it
monitors the connection process), and the high-rate `state` relay runs on a separate PubSub topic
(`world:state`) so transforms never mix with presence diffs.

## Wire protocol (JSON text frames)

The server stamps the sender id onto every relayed frame — clients never send their own id.

Presentation (relayed to peers):

- client→server `{"t":"identity","name":..,"appearance":{..},"companion_look":{..}}` — on connect / change
- client→server `{"t":"state","p":[x,y],"pf":[x,y],"c":[x,y],"cl":[x,y]}` — ~20 Hz
- server→client `{"t":"welcome","id":N,"peers":[{"id":M,"identity":{..}}, ...]}`
- server→client `{"t":"join","id":M}` · `{"t":"identity","id":M,..}` · `{"t":"state","id":M,..}` · `{"t":"leave","id":M}`

Persistence (point-to-point with the server; never relayed — the token is a bearer credential):

- client→server `{"t":"hello","player_id":"<token>"}` — on connect, to identify the player
- server→client `{"t":"load","companion":{..}|null,"appearance":{..}|null}` — the canonical save (nulls = new player)
- client→server `{"t":"save","companion":{..},"appearance":{..}}` — periodic + on exit (the canonical write)
