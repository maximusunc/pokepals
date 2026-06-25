# Deploying the pokepals relay

The relay is the minimal authoritative server for Rung 4, step 1: it assigns ids, holds the
roster, and relays presentation state between players. It is **very light** — a BEAM (Erlang VM)
process baseline of ~40–90 MB RAM and well under 1% of a CPU core for fewer than ~10 players at
~20 Hz. You can run it on almost anything.

This guide covers two ways to stand it up on a fresh host:

- **[Option A — Docker](#option-a--docker-recommended)** (recommended; most portable — nothing to
  install but Docker).
- **[Option B — OTP release + systemd](#option-b--otp-release--systemd)** (a bare host/LXC with no
  Docker).

Plus a **[Proxmox LXC walkthrough](#proxmox-lxc-walkthrough)**, the **[configuration](#configuration)**
knobs, and **[health/logs](#health-checks--logs)**.

> **Solo play needs none of this.** The server only matters when two or more people want to share a
> space. A single player just presses *Wander solo*.

---

## What to give the box

For development and `<10` players, a container with:

| Resource | Recommended | Bare minimum |
|----------|-------------|--------------|
| vCPU     | 1           | 1 (shared)   |
| RAM      | 768 MB      | 512 MB       |
| Disk     | 6 GB        | ~2 GB        |

The relay's footprint is dominated by the BEAM runtime baseline, not by your players — roughly the
same at 2 players as at 10. **PostgreSQL** (now required — it holds the companions) adds ~100–200 MB
of RAM and the on-disk saves, which is why the figures above are a touch higher than the relay alone;
still very modest for `<10` players on a ThinkCentre.

---

## Option A — Docker (recommended)

Requires only Docker (and the Compose plugin) on the host. From this `server/` directory:

```sh
docker compose up -d --build
```

That builds the relay image (a self-contained OTP release inside a slim Debian base) **and** starts a
PostgreSQL container (with a `pgdata` volume so saves survive restarts). The relay waits for the DB to
be healthy, applies migrations on boot, then serves. Both are set to restart unless you stop them.
Companion/wardrobe saves persist in the `pgdata` volume — `docker compose down` keeps it; `down -v`
wipes it. Verify:

```sh
curl localhost:4000/health        # -> ok
docker compose logs -f relay      # watch the "Running Server.Endpoint ... at 0.0.0.0:4000" line
```

Then point Godot clients at `ws://<this-host-ip>:4000/ws` (use `127.0.0.1` from the same machine).

Common commands:

```sh
docker compose ps                 # status + health
docker compose restart relay      # restart
docker compose down               # stop & remove
docker compose up -d --build      # redeploy after pulling new code
```

To run a different port, set it in `docker-compose.yml` (both the `PORT` env and the published
`"<host>:4000"` mapping), or run the image directly:

```sh
docker build -t pokepals-relay .
docker run -d --restart unless-stopped -p 5000:5000 -e PORT=5000 --name pokepals-relay pokepals-relay
```

(`make compose-up` / `make docker-build` / `make docker-run` wrap these.)

---

## Option B — OTP release + systemd

For a host or LXC where you'd rather not run Docker. You build a self-contained release (no Elixir
needed on the *target*, only on the *build* machine) and run it under systemd.

### 1. Build a release

On any machine with Elixir 1.15+ / Erlang 26+ (your dev box is fine):

```sh
cd server
mix deps.get
MIX_ENV=prod mix release
```

This produces `_build/prod/rel/server/` — a complete, relocatable tree with its own Erlang runtime
and a `bin/server` launcher.

### 2. Ship it to the host

```sh
# create the destination + a service user on the host first (see the unit file header), then:
rsync -a _build/prod/rel/server/ user@host:/opt/pokepals-relay/
```

> The release embeds the Erlang runtime, so the **build** host and the **target** host should have
> compatible OS/libc (e.g. build on Debian, run on Debian). If they differ, build inside a matching
> container — which is exactly what Option A does for you.

### 3. Install the service

On the host (the unit file is `deploy/pokepals-relay.service` in this repo — copy it over too):

```sh
sudo useradd --system --home /opt/pokepals-relay pokepals
sudo chown -R pokepals:pokepals /opt/pokepals-relay
sudo cp pokepals-relay.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now pokepals-relay
```

Verify:

```sh
systemctl status pokepals-relay      # should be active (running)
curl localhost:4000/health           # -> ok
journalctl -u pokepals-relay -f      # follow logs
```

The unit (`deploy/pokepals-relay.service`) restarts on crash and starts on boot. To change the
port, edit `Environment=PORT=...` in the unit and `systemctl daemon-reload && systemctl restart`.

### 4. Provision PostgreSQL (required)

Install Postgres (`sudo apt install postgresql`), create a database and role, then tell the unit
where it is. Add to `deploy/pokepals-relay.service` before installing it:

```ini
Environment=DATABASE_URL=ecto://pokepals:somepassword@localhost/pokepals
```

Apply migrations once (and after each upgrade) using the release's eval task — no Mix needed:

```sh
sudo -u pokepals DATABASE_URL=ecto://pokepals:somepassword@localhost/pokepals \
  /opt/pokepals-relay/bin/server eval "Server.Release.migrate()"
```

The DB itself must already exist (`createdb pokepals`); the release runs `migrate`, not `ecto.create`.

### 5. Upgrade later

Rebuild the release, rsync it over the old tree, run the `migrate` eval above, and
`sudo systemctl restart pokepals-relay`.

---

## Proxmox LXC walkthrough

On the ThinkCentre (or any Proxmox host), an **unprivileged LXC** is the lean choice — no guest
kernel overhead like a full VM.

1. **Create the container** (Proxmox UI → *Create CT*, or `pct create`):
   - Template: Debian 13 (trixie) — matches the Docker image's base, so a release built/run on the
     LXC shares its libc family.
   - Cores: **1**, Memory: **512 MB**, Disk: **4 GB**.
   - Unprivileged: yes. Give it a network interface on your LAN (DHCP or a static IP you'll hand to
     friends).
2. **Start it and get a shell** (`pct enter <vmid>` or the console), then `apt update`.
3. **Pick a path:**
   - **Docker in the LXC:** install Docker (`curl -fsSL https://get.docker.com | sh`), copy this
     `server/` directory in (or `git clone` the repo), then `docker compose up -d --build`.
     *Note:* running Docker inside an unprivileged LXC sometimes needs `nesting=1` and `keyctl=1`
     enabled on the container (Proxmox → CT → Options → Features). If Docker misbehaves, use the
     release path instead.
   - **Release + systemd (no Docker):** install Elixir to *build* (or build elsewhere and copy the
     release in), then follow [Option B](#option-b--otp-release--systemd). This avoids the
     nested-Docker caveat entirely and is the most LXC-native option.
4. **Open the port:** make sure TCP **4000** is reachable on the container's LAN IP (no host
   firewall rule blocking it).
5. **Point the clients:** in each Godot client's launch overlay, enter
   `ws://<container-LAN-ip>:4000/ws` and press **Connect**.

The container survives Proxmox host reboots if you set it to start on boot (CT → Options → *Start
at boot*), and the relay survives container reboots via Docker's `restart: unless-stopped` or the
systemd unit.

---

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `PORT`   | `4000`  | TCP port the server listens on (WebSocket endpoint mounted at `/ws`). |
| `DATABASE_URL` | — (required in prod) | Postgres connection, `ecto://USER:PASS@HOST:PORT/DB`. Compose sets it for you; a bare/systemd deploy must provide it. Dev/test fall back to localhost defaults. |
| `SECRET_KEY_BASE` | — (required in prod) | Phoenix endpoint signing key — a long, stable secret. Generate with `mix phx.gen.secret` (or `bin/server eval "IO.puts(:crypto.strong_rand_bytes(48) \|> Base.encode64())"`). Compose ships a placeholder you must replace; dev/test use a built-in default. |
| `POOL_SIZE` | `10` | DB connection pool size. |

The relay **binds all interfaces** (`0.0.0.0`) so it's reachable across your LAN and from outside a
container. Players are keyed by a client-generated token (no accounts); their companion + wardrobe
are stored in Postgres. The token is a bearer credential sent over plaintext `ws://` on the LAN —
fine for a handful of friends; front it with TLS (`wss://`) before exposing it wider (see below).

Clients connect to `ws://<host>:<PORT>/ws`. The default the Godot gate pre-fills is
`ws://127.0.0.1:4000/ws`; change the host to your relay's LAN IP for a friend on another machine.

---

## Health checks & logs

- **Health:** `GET /health` returns `200 ok`. The Docker image and `docker-compose.yml` both wire
  this into a container `HEALTHCHECK`; use it for any external monitor too.
- **Logs:**
  - Docker: `docker compose logs -f relay` (or `docker logs -f pokepals-relay`).
  - systemd: `journalctl -u pokepals-relay -f`.
  - Foreground dev (`mix run --no-halt`): straight to your terminal.

  At the default `:info` level you'll see the startup listen line and not much else — state frames
  at ~20 Hz are intentionally not logged.

---

## Looking ahead (not built yet)

- **TLS / `wss://`:** this step serves plain `ws://` for LAN use. When you expose the relay beyond a
  trusted network, **don't** open the BEAM port to the internet directly — put a reverse proxy
  (Caddy or Traefik, which do automatic TLS) in front and terminate `wss://` there, forwarding to
  the relay's `:4000`. With Compose, that's an added `caddy`/`traefik` service alongside `relay`.
- **Accounts:** identity is a bearer token today (whoever holds it owns that save). Real accounts /
  auth are a later step; until then, keep the deployment on a trusted network.
- **Backups:** the companion lives only in Postgres now, so it's worth a periodic `pg_dump` of the
  `pokepals` DB (or a volume snapshot) once people have companions they'd miss.
