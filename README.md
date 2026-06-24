# Kithbound

A cozy, 2D, companion-centered world game built in **Godot 4.6** with **GDScript**,
mobile-friendly from the start.

> **Status — Rung 4 in progress:** two players share a space and see each other’s bonded companion
> (WebSockets + an authoritative Elixir/Phoenix server, with a Phoenix.Presence roster). The
> companion’s grown self + wardrobe now live **server-side** (PostgreSQL), keyed by a local identity
> token — so the game is **online-only** (no offline/solo mode; connecting to a server is required).
> Remaining Rung-4 step: proximity text chat. Still a test of FEEL, not features.
> See [`CLAUDE.md`](CLAUDE.md) for the full vision and the staged roadmap.

The Godot project lives in the [`pokepals/`](pokepals/) subdirectory. (An earlier
turn-based battle prototype still lives under `scripts/battle/` + `scripts/ui/` +
`scenes/battle.tscn`; it predates the pivot to Kithbound and is kept for reference.)

## Architecture

Two disciplines held from day one:

1. **Separate logic from presentation.** The companion's *mind* —
   [`scripts/world/companion_brain.gd`](pokepals/scripts/world/companion_brain.gd) —
   is pure behavior logic: a `RefCounted` that takes positions and world events in
   and returns *intent* out (where it wants to go, what it's looking at, how it
   feels). It references no nodes, UI, or rendering.
2. **Keep the world layer presentation-agnostic.** The brain works in abstract
   geometry (`Vector2`), so it isn't welded to 2D and could later run under a
   different presentation or on a server. The presentation layer
   ([`scripts/presentation/`](pokepals/scripts/presentation)) reads that intent and
   makes it look alive — easing, eyes that turn toward what it's attending to, bobs
   and hops.

```
pokepals/
  scripts/world/         PURE world/companion logic (companion_brain, world_data) — no UI refs
  scripts/presentation/  player, companion view, world art, camera, joystick, world controller
  scenes/                world.tscn (main scene) + player.tscn + companion.tscn
  data/                  companion.json (feel tunables), world.json (hand-placed clearing)
  tests/                 headless tests for the pure logic + scene smoke tests
```

## Play it

The game is **online-only**: your companion lives on the server, so you connect to one to play
(there's no offline/solo mode). For local play that's a one-command server on your own machine.

1. **Start a server** (needs Docker): `cd server && docker compose up -d --build` — this runs the
   relay on `:4000` plus its PostgreSQL. (Other ways to run it — including no-Docker — are in
   [`server/DEPLOYMENT.md`](server/DEPLOYMENT.md).)
2. Install [Godot 4.6](https://godotengine.org/download) (standard build, no C#).
3. Open the project: `godot --path pokepals` (or open `pokepals/project.godot` in the editor) and
   press **Play** (main scene `scenes/world.tscn`). At the gate, enter `ws://127.0.0.1:4000/ws`
   (or a friend's server IP) and press **Connect** — your companion loads from the server.
4. Wander with **arrow keys / WASD** (or the on-screen thumbstick on touch). Your companion trails
   behind, idles and glances back when you stop, and perks up to investigate when you press **Space**
   to examine a prop. A second person who connects to the same server appears beside you, with their
   own companion.

To play it on a phone (where the touch feel actually lives), see
[`docs/mobile-testing.md`](docs/mobile-testing.md) — iOS (needs a Mac) and
Android (no Mac, fastest) walkthroughs. Export presets for both ship in
[`pokepals/export_presets.cfg`](pokepals/export_presets.cfg).

## The server

Everything shared — the roster, presence relay, and the **server-canonical companion + wardrobe**
(PostgreSQL) — lives in [`server/`](server/), an Elixir/Phoenix app. Each player is keyed by a
local identity token (`user://player_id.json`); there are no accounts yet. See
[`server/README.md`](server/README.md) for how it works and [`server/DEPLOYMENT.md`](server/DEPLOYMENT.md)
to host it persistently on a real box (Docker or systemd; includes a Proxmox LXC walkthrough).

## Run the tests

Fast, dependency-free headless tests cover the pure logic; smoke tests drive the
real scenes end to end.

```sh
# One-time per fresh checkout: import the project so class_name globals register.
godot --headless --path pokepals --import

# Pure-logic tests (companion brain + the legacy battle core):
godot --headless --path pokepals --script res://tests/run_tests.gd

# Scene smoke tests (drive the real scenes; verify wiring runs without errors):
godot --headless --path pokepals --script res://tests/smoke_world.gd
godot --headless --path pokepals --script res://tests/smoke_ui.gd
```

Opening the project in the Godot editor once does the same import as the first
command. (CI-friendly: the test runner's exit code is the number of failures.)

## Tune the feel

The companion's whole personality is data. Edit
[`pokepals/data/companion.json`](pokepals/data/companion.json) — follow distances,
walk/run speed, idle rhythm, curiosity, clinginess — and replay to feel the
difference, no code changes. Reshape the clearing in
[`pokepals/data/world.json`](pokepals/data/world.json).
