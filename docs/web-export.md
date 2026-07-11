# Playing Kithbound in a browser

The game's renderer and input are already web-ready (Compatibility/WebGL2 renderer,
touch + keyboard both wired up), so getting into a browser is a **packaging + hosting**
job, not an engine change. The design here is deliberately boring: **the server serves the
game**, so the browser client and the `/ws` socket share one origin — no CORS, no
mixed-content, no second host to run.

```
  https://your-box.ts.net/         →  the game   (index.html / .wasm / .pck / …)
  wss://your-box.ts.net/ws         →  the socket (same origin, derived automatically)
```

---

## One-time setup

### 1. Godot Web export template

The project ships a **Web** preset (`preset.2`) in
[`export_presets.cfg`](../pokepals/export_presets.cfg). It exports straight into
`server/priv/static/` (where the server serves from) and is configured **threads-off**
(`variant/thread_support=false`).

> **Why threads-off?** Godot's threaded web build needs the page served with
> `Cross-Origin-Opener-Policy`/`Cross-Origin-Embedder-Policy` headers (for `SharedArrayBuffer`).
> Threads-off needs no special headers and runs anywhere — plenty for a 640×360 cozy 2D game.
> Revisit only if it ever feels sluggish.

Install the matching **Web export templates** once (Godot editor →
*Editor → Manage Export Templates → Download and Install*), matching your Godot version (4.6).

### 2. MIME types (once)

The server pins `.wasm → application/wasm` (required for the browser's streaming WASM compile)
and `.pck → application/octet-stream` in [`config/config.exs`](../server/config/config.exs).
Changing `:mime` types needs a one-time dep recompile:

```bash
cd server
mix deps.clean mime --build
```

(Modern `mime` already knows `wasm`, so this is belt-and-suspenders — but do it once to be safe.)

---

## Each build: export → serve

Export the Web preset (editor: *Project → Export → Web → Export Project*, save as
`index.html`), or headless from the client dir:

```bash
cd pokepals
godot --headless --export-release "Web" ../server/priv/static/index.html
```

Or just run the wrapper script in the server dir, which does exactly this export
(override the binary with `GODOT=/path/to/godot` if it isn't on your PATH):

```bash
cd server
./build-web.sh
```

That writes `index.html`, `index.js`, `index.wasm`, `index.pck`, and friends into
`server/priv/static/`. These are build artifacts — **gitignored**, not committed.

Then just run the server as usual (`mix phx.server` / your release). It now answers:

- `GET /` → the game shell (`priv/static/index.html`)
- `GET /index.wasm`, `/index.pck`, … → the export assets (`Plug.Static`, files starting `index`)
- `GET /ws/websocket` → the game socket (unchanged)
- `GET /health`, `/worlds` → unchanged

Until you've exported, `GET /` returns a plain 503 telling you to export — the socket and
JSON routes work regardless.

### Running under Docker Compose

`docker compose up -d --build` serves the browser client too — there's **no separate web
server**, and the exposed port 4000 carries both the game files and `/ws` (so one Tailscale
Funnel → 4000 covers everything). One ordering rule, because Docker differs from a bare
`mix phx.server`:

> **Export before you build.** A bare server reads `priv/static/` from disk live; the Docker
> image **bakes `priv/` in at build time** (`COPY priv priv` → `mix release`). So the export
> must already be in `server/priv/static/` when you run `--build`. The files are gitignored but
> **not** dockerignored, so Docker copies them in. Rebuild the client → re-run
> `docker compose up -d --build` to bake the new export; a plain restart won't pick it up.

```bash
cd pokepals
godot --headless --export-release "Web" ../server/priv/static/index.html   # 1. export first
cd ../server
docker compose up -d --build                                               # 2. then build+serve
```

A fresh `git clone` has no export (it's gitignored), so `docker compose up --build` on a clean
checkout starts fine but `GET /` returns the 503 until you export and rebuild.

---

## Reaching it over TLS (Tailscale Funnel)

Browsers block a plaintext `ws://` socket from an `https://` page, so the server needs public
TLS. A **Tailscale Funnel** gives you that (a `*.ts.net` hostname + TLS termination) with no certs
to manage. Point the Funnel at the server's local port (default `4000`):

```bash
tailscale funnel 4000
```

Confirm: the node has Funnel enabled in your tailnet ACLs (`nodeAttrs` → `"funnel"`), and that
**WebSockets upgrade cleanly** through the Funnel (open the game, hit Connect, watch for the
companion to load — a quick sanity check before assuming).

The client's web build **derives its server URL from the page origin** (see
`Net.default_server_url` in [`net.gd`](../pokepals/scripts/net/net.gd)): reached over
`https://…ts.net`, it offers `wss://…ts.net/ws` automatically. Nothing is hardcoded.

---

## How the client picks its server URL

There is **no address-entry screen** — the connection gate auto-connects to a URL resolved per
platform, and only shows a **Retry** button if the connection can't be made:

- **Web:** derived from the page origin (above). Served over `https://…ts.net` → `wss://…ts.net/ws`.
- **Native (iOS / Android / desktop):** read at startup from **`pokepals/server_config.json`** —
  a file that is **gitignored but baked into the exported package** (it lives under `res://`), so
  the real address ships in the installable without ever living in the repo. Copy the committed
  [`server_config.example.json`](../pokepals/server_config.example.json) to `server_config.json`
  and set `server_url`, then export. If the file is absent, native falls back to
  `Net.DEFAULT_SERVER_URL` (a harmless LAN default).

```jsonc
// pokepals/server_config.json  (gitignored; create from server_config.example.json)
{ "server_url": "wss://your-host.ts.net/ws" }
```

---

## Landscape on mobile web

The game is designed for a wide 640×360 viewport and doesn't read well in a tall
portrait phone window, so the Web preset's `html/head_include` (in
[`export_presets.cfg`](../pokepals/export_presets.cfg)) injects a small CSS+JS
snippet into the exported `index.html` that enforces landscape on **mobile
browsers only**:

- It attempts `screen.orientation.lock('landscape')` where the browser allows it
  (Android Chrome, etc. — needs the game to be fullscreen; harmless no-op otherwise).
- Because iOS Safari can't lock orientation from a web page at all, the reliable
  guarantee is a **full-screen "please rotate your device" overlay** shown whenever a
  mobile device is held in portrait. It hides itself the moment the phone is turned to
  landscape. Desktop browsers are unaffected (the overlay never triggers).

This is web-only; native iOS/Android builds get their orientation from the project's
handheld orientation settings, not this snippet. Edit the snippet in the `Web` preset
(Godot editor → *Project → Export → Web → Options → HTML → Head Include*, or the
`html/head_include=` line in the cfg) if you want to tweak the overlay copy or logic.

## Notes / gotchas

- **First-load size.** The `.wasm` + `.pck` are the whole game up front — tens of MB. Fine
  functionally; just the thing to watch on a phone. `Plug.Static` already serves a pre-gzipped
  `*.gz` sibling if one exists (`gzip: true`), so you can shrink first load by gzipping the export
  outputs later.
- **`check_origin`.** Currently `false` (the native client sends no Origin; browsers do, and are
  accepted). Once the public origin is stable, consider tightening it in
  [`config/config.exs`](../server/config/config.exs), e.g.
  `check_origin: ["https://your-box.ts.net"]`.
- **Native URL is baked in at export.** `server_config.json` is read from `res://`, so it's fixed
  when you export the package — change it and re-export to point a build at a different server.
