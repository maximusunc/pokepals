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

That writes `index.html`, `index.js`, `index.wasm`, `index.pck`, and friends into
`server/priv/static/`. These are build artifacts — **gitignored**, not committed.

Then just run the server as usual (`mix phx.server` / your release). It now answers:

- `GET /` → the game shell (`priv/static/index.html`)
- `GET /index.wasm`, `/index.pck`, … → the export assets (`Plug.Static`, files starting `index`)
- `GET /ws/websocket` → the game socket (unchanged)
- `GET /health`, `/worlds` → unchanged

Until you've exported, `GET /` returns a plain 503 telling you to export — the socket and
JSON routes work regardless.

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
`https://…ts.net`, it offers `wss://…ts.net/ws` automatically. Nothing is hardcoded, and the
lobby's address field stays editable for anything unusual.

---

## Notes / gotchas

- **First-load size.** The `.wasm` + `.pck` are the whole game up front — tens of MB. Fine
  functionally; just the thing to watch on a phone. `Plug.Static` already serves a pre-gzipped
  `*.gz` sibling if one exists (`gzip: true`), so you can shrink first load by gzipping the export
  outputs later.
- **`check_origin`.** Currently `false` (the native client sends no Origin; browsers do, and are
  accepted). Once the public origin is stable, consider tightening it in
  [`config/config.exs`](../server/config/config.exs), e.g.
  `check_origin: ["https://your-box.ts.net"]`.
- **Native builds are unaffected.** iOS/Android/desktop still use the editable LAN default
  (`Net.DEFAULT_SERVER_URL`); only the web build reads the page origin.
