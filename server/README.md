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
mix ecto.setup                    # create + migrate the dev DB (once)
mix run priv/repo/seeds.exs       # seed the worlds (the client can't enter a world that isn't in the catalog)
mix run --no-halt                 # start the server
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
the Presence diff→frame adapter (`PresenceFrames`), the world catalog (`Worlds`: upsert/get/list +
display-type filter), the per-world process (`World`: store/snapshot/forget/fan-out, one per world_id,
isolated), and the full channel flow (`WorldChannel` via `Phoenix.ChannelTest`: per-world join with
spec delivery + `known_version` skip, welcome+load, save persistence, and per-world scoping of
presence and state — same world sees each other, different worlds don't); plus the economy: `Economy`
(grant/sink, the ledger==balance invariant, equip), `Trade` (atomic swap with one correlation_id,
roll-back on insufficient funds, re-verify prevents a double-spend), and `TradeSession`
(offer/confirm → execute); plus the UGC sandbox (`World.Sandbox`: KV round-trips, optimistic-version
conflict, atomic increment, schema validation, per-value/byte/key quotas, list pagination, and the
§10 cross-world isolation invariant). The `test` alias creates + migrates a `pokepals_test` DB first.
End-to-end behaviour is verified by running Godot clients against the server (see the repo `CLAUDE.md`).

## Shape

```
lib/server/
  application.ex     supervision tree: Repo + PubSub + Presence + World{Registry,Supervisor} + Endpoint
  endpoint.ex        Phoenix endpoint: UserSocket at /ws (over Bandit) + /health + /worlds router
  user_socket.ex     connect/3 — resolves the token → user_id; channel "world:*" (one per world)
  world_channel.ex   per-world channel "world:"<>id: spec delivery, welcome/load, identity/state/save
  world.ex           ONE live process per world_id (registry-addressed): live transforms + snapshot
  worlds.ex          the world CATALOG boundary: get/list/upsert world definitions (specs)
  world_definition.ex schema for world_definitions (world_id PK, slug, display_types, version, spec)
  presence_frames.ex pure presence-diff → wire-frame translation (unit-tested)
  router.ex          Plug router: /health + the world catalog (GET /worlds, /worlds/:id) + 404
  presence.ex        the roster, as a Phoenix.Presence (CRDT over PubSub), per-world topic, keyed by user_id
  accounts.ex        resolve a token → account (the token → user_id indirection)
  account.ex         schema for accounts (user_id PK, token UNIQUE, nullable claim cols)
  companion.ex       schema for companions (companion_id PK, user_id UNIQUE, opaque data jsonb)
  appearance.ex      schema for player_appearances (user_id PK, opaque data jsonb)
  saves.ex           load/store a player's blobs by user_id (the persistence boundary)
  economy.ex         the §0 WALL: sole gateway for currency/items, ledger-in-same-txn, equip, trade
  trade_session.ex   short-lived coordination GenServer (offer/confirm → Economy.execute_trade)
  item_definition.ex / player_currency.ex / inventory_item.ex / equipped_item.ex /
  wardrobe.ex / companion_inventory.ex / ledger_entry.ex   the typed economy schemas
  world/context.ex   the runtime-bound world_id handed to creator code (the isolation anchor)
  world/sandbox.ex   the fenced UGC data-access layer: KV + quota + schema + version + lists
  world/api.ex       the creator-facing World.{Player,Global,Entity,List,Leaderboard} facade (§7)
  world_data.ex / world_quota.ex / world_schema.ex / world_list_item.ex   the sandbox schemas
  repo.ex            the Ecto/Postgres repo;  release.ex  runs migrations in the packaged release
priv/repo/migrations accounts + companions + player_appearances + economy + UGC sandbox + world_definitions
priv/repo/seeds.exs  item definitions + a demo account + the seed worlds (mix run priv/repo/seeds.exs)
priv/world_seeds/    canonical content for the seed worlds (vale.json, riverbank.json)
```

## Multi-world (catalog + per-world routing)

A "world" is three separate things: its **definition** (authored spec — `Server.Worlds` /
`world_definitions`), its **runtime data** (the P4 `world_data` sandbox), and its **live session**
(`Server.World`). Multi-world is built on all three:

- **Catalog.** World specs are server-hosted and versioned. The spec is display-AGNOSTIC —
  `%{"core" => <semantic logic>, "profiles" => %{"2d" => <presentation>}}` — so a world can gain a
  3D/VR profile later without re-authoring its core. Clients fetch a world's spec on join and cache
  it by `version` (sending `known_version` so an unchanged spec isn't re-sent), which is what lets the
  catalog grow to (eventually millions of) worlds without baking them into the client. The seed worlds
  (Vale, Riverbank) now live in the catalog; the Godot client ships their JSON only as an offline
  first-paint fallback.
- **Routing.** Each world is its own channel topic `"world:" <> world_id` with its own
  `Server.World` process (one per `world_id`, started on demand under a `DynamicSupervisor` + a
  `Registry`). Presence (the roster) and the live-transform fan-out (`world:<id>:state`) are scoped
  per world — players in different worlds don't see each other. Live state is transient/in-memory: a
  world crash restarts it empty and its players re-sync next tick.

**Deferred (scale) seams — flagged in code, NOT built:** the `Registry` + `DynamicSupervisor` are
NODE-LOCAL — going multi-node needs a cluster-aware registry (**Horde**) + **libcluster** so each
`world_id` owns one process cluster-wide. Spec docs/assets are Postgres jsonb now; an **object store +
CDN** (and a client disk cache) is the seam for large specs/assets. Plus the earlier Oban / Redis
seams. None are built until a real need arises.

The roster lives in `Presence`, so a peer's leave is detected even on a hard crash/disconnect (the
channel process is monitored). `WorldChannel` translates Presence diffs into the client's frames in
`handle_out("presence_diff", ...)`.

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

## UGC sandbox (the fence)

Creator-world data lives in a FENCED store, separate from the platform's typed tables. Creator code
only ever sees `Server.World.{Player,Global,Entity,List,Leaderboard}` (§7), each call taking a
runtime-bound `Server.World.Context` whose `world_id` it can't supply or forge — so a cross-world
query is unconstructable (§10). `Server.World.Sandbox` injects that `world_id` and, in the same
transaction as each write, enforces: per-value (256 KiB) + per-world byte + key-count **quotas**
(under a locked `world_quota` row), optional **schema validation** (a small JSON-Schema subset when a
`world_schemas` row exists for the key), and **optimistic concurrency** via a `version` column — plus
atomic `increment` and list `append` so creators never read-modify-write and clobber. Values are JSON
objects; the only query surfaces are these KV ops and bounded list pagination — never raw JSONB
queries. The economy wall holds: sandbox code reaches none of the §2/§3 tables.

**Deferred seams:** **leaderboards** (`World.Leaderboard.*`) are spec'd on Redis ZSETs — not built
yet (the facade returns `{:error, :not_implemented}`), to be wired to Redix when ranking is actually
needed. **Full JSON Schema** validation (an ex_json_schema-style lib) replaces the current subset
when richer schemas are required. Neither is built now; both are flagged at their call sites.

## Wire protocol (Phoenix Channels, v2 serializer)

Every frame is a JSON array `[join_ref, ref, topic, event, payload]`. There's ONE socket per client
(auth once via the `token` connect param — no `hello` round-trip), but the player joins ONE WORLD
channel at a time: `topic = "world:" <> world_id`. Travelling = leave the old world channel, join the
new one. The server stamps the sender id (the player's `user_id`, a UUID string, stable across
reconnects) onto every relayed frame — clients never send their own id.

World spec (server → us, on join):

- client→server (in the `phx_join` payload) `{"known_version": <int>}` — the spec version we already cached
- server→client `world_spec` `{"world_id":..,"slug":..,"name":..,"display_types":[..],"version":N,"spec":{"core":{..},"profiles":{"2d":{..}}}}`
- server→client `world_spec_unchanged` `{"world_id":..,"version":N}` — our cache is current, spec omitted

Presentation (relayed to peers IN THE SAME WORLD), `event` + `payload`:

- client→server `identity` `{"name":..,"appearance":{..},"companion_look":{..}}` — on join / change
- client→server `state` `{"p":[x,y],"pf":[x,y],"c":[x,y],"cl":[x,y]}` — ~20 Hz
- server→client `welcome` `{"id":"<our user_id>","peers":[{"id":"<user_id>","identity":{..}}, ...]}`
- server→client `join` `{"id":"<user_id>"}` · `identity` `{"id":"<user_id>",..}` · `state` `{"id":"<user_id>",..}` · `leave` `{"id":"<user_id>"}`

Persistence (point-to-point with the server; per-USER, same in every world; token is a bearer credential):

- server→client `load` `{"companion":{..}|null,"appearance":{..}|null}` — the canonical save on join (nulls = new player)
- client→server `save` `{"companion":{..},"appearance":{..}}` — periodic + on exit (the canonical write)
