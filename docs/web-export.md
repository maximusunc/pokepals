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

## World packs: every world's own art is its own download

The browser build is split so the first download stays small however many worlds there are.

```
  index.pck               the BASE — the Vale, every player's home, the wardrobe, the companion's
                          animals, the UI, fonts, shaders, portals. Everyone downloads this up front.
  packs/nocthollow.<hash>.pck       Nocthollow's own art, fetched the first time a player goes there
  packs/bobbledown.<hash>.pck       Bobbledown's
  packs/manifest.json               which packs exist and which world needs which (the server reads it)
```

**Building it.** `server/build-web.sh` does everything (it now needs `python3` as well as Godot). The work
is in [`pokepals/tools/packs/build_packs.py`](../pokepals/tools/packs/build_packs.py), on a scratch copy of
the project (so your checkout gets no `.import` churn):

1. **Audit.** Every world is built headless with `godot --verbose` and the `res://assets/` files it
   loads are read off the log. Measured, not guessed. (The home is audited with *every* quality switched
   on, since a real home only shows some of them.)
2. **Plan.** The Vale's and the homes' art, plus the shared things pinned in
   [`tools/packs/packs.json`](../pokepals/tools/packs/packs.json) (fonts, loading screen, wardrobe, the
   player and companion, portals, and every animal the companion can shift into), is the base. What only
   one other world loads is **that world's pack**. What 2–3 other worlds share is one **kit** pack they
   all depend on. Art loaded by more worlds than that is general-purpose, so it joins the base. Anything
   the audit never saw also stays in the base, so a gap makes the download bigger, **never a sprite
   missing**.
3. **Export.** The base is the normal Web preset with the packed files excluded. Each pack is written by
   `make_pack.gd` (Godot's `PCKPacker`) holding only its assets, named by a hash of its contents.
4. **Verify.** Every world is built again from the exported base, getting its packs through the game's
   own client code against a local stand-in server, and must load exactly the art it did from the source.
   If it doesn't, the build fails and says which file went missing.

`./build-web.sh --monolithic` skips all of it (one big pck, no packs); `--skip-verify` skips step 4.
Unit tests for the planner: `python3 -m unittest discover -s pokepals/tools/packs`.

**Today's numbers.** The base pck is 1.6 MB (3.5 MB before the split); Bobbledown's pack is 1.8 MB and
Nocthollow's 0.12 MB. Riverbank, the Ruin, the Maze and the Bazaar use nothing the Vale doesn't, so they
have no pack (and nothing to download). The real saving is the future one: each new world with art of its
own adds a pack that only its visitors ever download, and nothing to the base.

**At runtime.** Before the client *joins* a world it calls `AssetPacks.prepare(world_id)`
([`scripts/net/asset_packs.gd`](../pokepals/scripts/net/asset_packs.gd)):

1. `GET /worlds/<id>/packs` asks the server which packs the world needs (`Server.Packs` reads
   `packs/manifest.json`; one tiny request per world per session).
2. Any pack whose probe file isn't already loadable is fetched, size- and SHA-256-checked, kept in
   `user://packs/` (the browser's own storage on web), and mounted with `ProjectSettings.load_resource_pack`.
   After that `load("res://assets/…")` just works, so none of the drawing code knows packs exist.
3. While that takes more than a moment, `PackLoading` shows the loading screen's wordmark and fox with a
   progress line ("Gathering Nocthollow…"). A pack that arrives quickly shows nothing. If the fetch fails
   the player goes in anyway, with the plainer fallback look the renderers already have.

Pack file names include their hash, so the server sends them with `immutable` caching and a returning
player downloads nothing. The client joins the world only *after* its art is here, because the server
starts talking the moment you join and the world's directors must exist to hear it.

**Only the web build is split.** The editor and the iOS/Android exports bundle all of `res://`, so every
pack's probe file already exists and `AssetPacks.enabled` (true only on web) keeps it from fetching.

**Adding a world.** Nothing to do: add its seed, run `build-web.sh`. If the world has art of its own it
gets a pack automatically; the server finds it by the world's `slug`. If its art overlaps another
world's, they share a kit.

**If a world looks plain after a deploy**, a pack didn't load: check the browser console for
`AssetPacks:` warnings and that `curl https://your-host/worlds/<id>/packs` lists it.

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

- **First-load size.** Up front a player gets the `.wasm` engine (37.7 MB, 9.4 MB gzipped, and by far the
  biggest part) plus the base `.pck` (see "World packs"). Fine
  functionally; just the thing to watch on a phone. `build-web.sh` gzips (`-9`) the `.wasm`,
  `.pck`, `.js` and `.html` after exporting, and `Plug.Static` (`gzip: true`) serves the `.gz`
  sibling to any browser that accepts it (original MIME type kept, so `.wasm` still stream-compiles).
  The originals stay beside them as the fallback. Plug.Static only knows gzip, not brotli; if you
  later put a CDN or reverse proxy in front, brotli there would shave a bit more. Verify with
  `curl -sI -H 'Accept-Encoding: gzip' https://your-host/index.wasm` (expect `content-encoding: gzip`).
- **`check_origin`.** Currently `false` (the native client sends no Origin; browsers do, and are
  accepted). Once the public origin is stable, consider tightening it in
  [`config/config.exs`](../server/config/config.exs), e.g.
  `check_origin: ["https://your-box.ts.net"]`.
- **Native URL is baked in at export.** `server_config.json` is read from `res://`, so it's fixed
  when you export the package — change it and re-export to point a build at a different server.
