# pokepals relay — Rung 4 / MMO foundation (P1)

The **authoritative server** for the shared world. It authenticates each connection by its identity
token (resolving it to an internal `user_id`, which is also the peer id), tracks the roster with
**Phoenix.Presence**, relays presentation state (avatar + companion transforms and identity) between
clients, and is the **sole store** of each player's companion + wardrobe (**PostgreSQL** via Ecto),
keyed by `user_id`. The game is online-only: there is no local game save.

Runtime stack: **Phoenix Channels** (over **Bandit**, via `Bandit.PhoenixAdapter`) + **Phoenix.PubSub**
+ **Phoenix.Presence** + **Ecto** — a socket-only Phoenix endpoint (no HTML). Clients are Phoenix
Channel clients on a single `"world"` topic; Presence and the DB are internal details they never see.

## Identity model (P1)

The client still holds an anonymous 128-bit bearer **token**, but it's now just a lookup: at connect
the token resolves to (or mints) an **`accounts`** row whose **`user_id` UUID** is the internal anchor
every other table is keyed by. `email` / `username` / `password_hash` are nullable upgrade-path
columns — a player can claim an account later without `user_id` ever changing. The companion and
appearance are **client-owned opaque jsonb blobs** the server stores but never interprets.

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
(The Godot client rewrites that into the full Phoenix socket URL — `…/ws/websocket?vsn=2.0.0&token=…`
— so you only ever type the host.) `GET /health` returns `ok` for a quick liveness check.

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

Covers token→user_id resolution (`Accounts`), the `Saves` store/load round-trip keyed by user_id,
the Presence diff→frame adapter (`PresenceFrames`), the world process (`World`: store/snapshot/forget
+ fan-out), and the full channel flow (`WorldChannel` via `Phoenix.ChannelTest`: connect auth,
welcome+load on join, save persistence, presence join/leave/identity, state relay + snapshot replay),
plus the economy: `Economy` (grant/sink, the ledger==balance invariant, equip), `Trade` (atomic swap
with one correlation_id, roll-back on insufficient funds, re-verify prevents a double-spend), and
`TradeSession` (offer/confirm → execute). The `test` alias creates + migrates a `pokepals_test` DB first.
End-to-end behaviour is verified by running Godot clients against the server (see the repo `CLAUDE.md`).

## Shape

```
lib/server/
  application.ex     supervision tree: Repo + PubSub + Presence + World + Endpoint
  endpoint.ex        Phoenix endpoint: UserSocket at /ws (over Bandit) + /health router
  user_socket.ex     connect/3 — resolves the token → user_id into the socket assigns
  world_channel.ex   the "world" channel: join/welcome/load, identity/state/save, presence diffs
  world.ex           the shared world as a process: owns live transforms, fans them out + snapshot
  presence_frames.ex pure presence-diff → wire-frame translation (unit-tested)
  router.ex          Plug router for /health + 404 (the socket handles /ws)
  presence.ex        the roster, as a Phoenix.Presence (CRDT over PubSub), keyed by user_id
  accounts.ex        resolve a token → account (the token → user_id indirection)
  account.ex         schema for accounts (user_id PK, token UNIQUE, nullable claim cols)
  companion.ex       schema for companions (companion_id PK, user_id UNIQUE, opaque data jsonb)
  appearance.ex      schema for player_appearances (user_id PK, opaque data jsonb)
  saves.ex           load/store a player's blobs by user_id (the persistence boundary)
  economy.ex         the §0 WALL: sole gateway for currency/items, ledger-in-same-txn, equip, trade
  trade_session.ex   short-lived coordination GenServer (offer/confirm → Economy.execute_trade)
  item_definition.ex / player_currency.ex / inventory_item.ex / equipped_item.ex /
  wardrobe.ex / companion_inventory.ex / ledger_entry.ex   the typed economy schemas
  repo.ex            the Ecto/Postgres repo;  release.ex  runs migrations in the packaged release
priv/repo/migrations accounts + companions + player_appearances + economy tables
priv/repo/seeds.exs  item definitions + a demo account (mix run priv/repo/seeds.exs)
```

The roster lives in `Presence`, so a peer's leave is detected even on a hard crash/disconnect (the
channel process is monitored). `WorldChannel` translates Presence diffs into the client's frames in
`handle_out("presence_diff", ...)`.

Live transforms flow through **`Server.World`**, a single supervised process that owns "where is
everyone right now": a channel `cast`s each `state` frame to it; it stores the latest and fans it out
over PubSub (`world:state`) to every channel, which pushes to its client (dropping its own echo). On
join, the world's `snapshot` is replayed to the newcomer so existing peers appear at their real
positions immediately. The state is transient and in-memory — if the world process crashes, the
supervisor restarts it empty and clients re-sync on the next tick (no player is harmed).

**Deferred (scale) seams — intentionally NOT built yet, flagged in `Server.World`:** write-behind
persistence of transient state (Oban), one world process per `world_id` (DynamicSupervisor +
registry; cluster-aware Horde beyond that), and any Redis. These land when a real need arises, not
before.

## Economy (the §0 wall)

`Server.Economy` is the SOLE gateway for mutating currency, inventory, equipped items, and the
wardrobe — strict, typed, transactional Postgres tables that creator/UGC code may never touch. It
guarantees two things: every currency/item **movement** writes its `economy_ledger` row(s) inside the
same transaction (the append-only audit trail; one `correlation_id` per event), and a **trade** is a
single transaction that locks the affected rows in a deterministic order (lower `user_id` first) and
**re-verifies** ownership/balances under those locks — so a stale offer can never dupe an asset.
Money is `BIGINT`, never floats; Postgres is always the source of truth. `Server.TradeSession` is the
(non-authoritative) coordination layer that collects offers/confirms and then calls
`Economy.execute_trade/1`.

These tables exist as the destination the game grows into when it introduces money/items; they aren't
wired to the client yet (no economy UI), and the channel handlers that would drive them come then.

**Deferred (scale/abuse) seams — flagged in `Server.Economy`:** a per-node ETS cache for item
definitions (Cachex), and rate-limiting trade confirms / mints (Hammer). The anti-dupe guarantee is
structural and does NOT depend on either; both are added when read volume or an abuse surface is real.

## Wire protocol (Phoenix Channels, v2 serializer)

Every frame is a JSON array `[join_ref, ref, topic, event, payload]` on the `"world"` topic. Auth is
done once via the `token` connect param (in the socket URL), so there's no `hello` round-trip. The
server stamps the sender id onto every relayed frame — clients never send their own id. The `id` is
the player's `user_id` (a UUID string, the Presence roster key) — stable across reconnects.

Presentation (relayed to peers), `event` + `payload`:

- client→server `identity` `{"name":..,"appearance":{..},"companion_look":{..}}` — on join / change
- client→server `state` `{"p":[x,y],"pf":[x,y],"c":[x,y],"cl":[x,y]}` — ~20 Hz
- server→client `welcome` `{"id":"<our user_id>","peers":[{"id":"<user_id>","identity":{..}}, ...]}`
- server→client `join` `{"id":"<user_id>"}` · `identity` `{"id":"<user_id>",..}` · `state` `{"id":"<user_id>",..}` · `leave` `{"id":"<user_id>"}`

Persistence (point-to-point with the server; never relayed — the token is a bearer credential):

- server→client `load` `{"companion":{..}|null,"appearance":{..}|null}` — the canonical save on join (nulls = new player)
- client→server `save` `{"companion":{..},"appearance":{..}}` — periodic + on exit (the canonical write)
